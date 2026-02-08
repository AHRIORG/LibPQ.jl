"""
    set_auth_data_hook!(hook::Ptr{Cvoid})

Register a raw libpq authdata hook. Most callers should prefer
`register_oauth_bearer_token_provider!` to install a safe Julia hook.
"""
function set_auth_data_hook!(hook::Ptr{Cvoid})
    _authdata_hook_ref[] = hook
    libpq_c.PQsetAuthDataHook(hook)
    return
end

const PGauthData = libpq_c.PGauthData
const PGoauthBearerRequest = libpq_c.PGoauthBearerRequest
const PGpromptOAuthDevice = libpq_c.PGpromptOAuthDevice
const PQAUTHDATA_PROMPT_OAUTH_DEVICE = libpq_c.PQAUTHDATA_PROMPT_OAUTH_DEVICE
const PQAUTHDATA_OAUTH_BEARER_TOKEN = libpq_c.PQAUTHDATA_OAUTH_BEARER_TOKEN

"""
    get_auth_data_hook() -> Ptr{Cvoid}

Return the currently registered libpq authdata hook.
"""
function get_auth_data_hook()
    return libpq_c.PQgetAuthDataHook()
end

"""
    default_auth_data_hook(type, conn, data) -> Cint

Invoke libpq's default authdata hook.
"""
function default_auth_data_hook(type::libpq_c.PGauthData, conn::Ptr{libpq_c.PGconn}, data::Ptr{Cvoid})
    return libpq_c.PQdefaultAuthDataHook(type, conn, data)
end

const _authdata_hook_ref = Ref{Ptr{Cvoid}}(C_NULL)
const _oauth_bearer_provider = Ref{Union{Nothing, Function}}(nothing)
const _oauth_token_store = IdDict{Ptr{libpq_c.PGoauthBearerRequest}, Vector{UInt8}}()

function _oauth_cleanup(conn::Ptr{libpq_c.PGconn}, request::Ptr{libpq_c.PGoauthBearerRequest})::Cvoid
    if haskey(_oauth_token_store, request)
        delete!(_oauth_token_store, request)
    end
    return
end

const _oauth_cleanup_ptr = @cfunction(
    _oauth_cleanup,
    Cvoid,
    (Ptr{libpq_c.PGconn}, Ptr{libpq_c.PGoauthBearerRequest}),
)

"""
    oauth_bearer_set_token!(request_ptr, token)

Store `token` in `request_ptr` and register a cleanup callback that releases the
Julia-owned token once libpq signals cleanup.
"""
function oauth_bearer_set_token!(
    request_ptr::Ptr{libpq_c.PGoauthBearerRequest},
    token::AbstractString,
)
    token_bytes = Vector{UInt8}(codeunits(token))
    push!(token_bytes, 0x00)
    _oauth_token_store[request_ptr] = token_bytes

    request = unsafe_load(request_ptr)
    updated = libpq_c.PGoauthBearerRequest(
        request.openid_configuration,
        request.scope,
        request.async,
        _oauth_cleanup_ptr,
        pointer(token_bytes),
        request.user,
    )
    unsafe_store!(request_ptr, updated)
    return
end

function _authdata_hook(
    type::libpq_c.PGauthData,
    conn::Ptr{libpq_c.PGconn},
    data::Ptr{Cvoid},
)::Cint
    try
        if type != libpq_c.PQAUTHDATA_OAUTH_BEARER_TOKEN
            return libpq_c.PQdefaultAuthDataHook(type, conn, data)
        end

        provider = _oauth_bearer_provider[]
        if provider === nothing
            return libpq_c.PQdefaultAuthDataHook(type, conn, data)
        end

        request_ptr = Ptr{libpq_c.PGoauthBearerRequest}(data)
        token = provider(conn, request_ptr)
        token === nothing && return Cint(0)

        oauth_bearer_set_token!(request_ptr, token)
        return Cint(1)
    catch err
        warn(LOGGER, "Authdata hook error: $(sprint(showerror, err))")
        return Cint(0)
    end
end

const _authdata_hook_ptr = @cfunction(
    _authdata_hook,
    Cint,
    (libpq_c.PGauthData, Ptr{libpq_c.PGconn}, Ptr{Cvoid}),
)

"""
    register_oauth_bearer_token_provider!(provider)

Register `provider` to supply OAuth Bearer tokens for libpq. The provider is
called with `(conn::Ptr{PGconn}, request_ptr::Ptr{PGoauthBearerRequest})` and
should return a token string or `nothing` on failure.

Keep this callback fast: it runs on libpq's authentication path and may block
nonblocking connection workflows if it performs long-running work.
"""
function register_oauth_bearer_token_provider!(provider::Function)
    _oauth_bearer_provider[] = provider
    set_auth_data_hook!(_authdata_hook_ptr)
    return
end

"""
    clear_oauth_bearer_token_provider!()

Remove any registered OAuth Bearer token provider.
"""
function clear_oauth_bearer_token_provider!()
    _oauth_bearer_provider[] = nothing
    return
end
