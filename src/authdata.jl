"""
    set_auth_data_hook(hook::Ptr{Cvoid})

Register a raw libpq authdata hook. Most callers should prefer
`register_oauth_bearer_token_provider` to install a safe Julia hook.
"""
function set_auth_data_hook(hook::Ptr{Cvoid})
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
const _oauth_fixed_token = Ref{Union{Nothing, String}}(nothing)
const _oauth_token_store = IdDict{Ptr{libpq_c.PGoauthBearerRequest}, Vector{UInt8}}()
const _oauth_cleanup_cfun_ref = Ref{Any}(nothing)
const _oauth_cleanup_ptr = Ref{Ptr{Cvoid}}(C_NULL)
const _authdata_hook_cfun_ref = Ref{Any}(nothing)
const _authdata_hook_ptr = Ref{Ptr{Cvoid}}(C_NULL)

"""
    _fixed_oauth_bearer_provider(conn, request_ptr)

Internal provider callback that returns the currently configured fixed OAuth
Bearer token, or `nothing` when no fixed token is available.
"""
function _fixed_oauth_bearer_provider(
    conn::Ptr{libpq_c.PGconn},
    request_ptr::Ptr{libpq_c.PGoauthBearerRequest},
)
    tok = _oauth_fixed_token[]
    tok === nothing && return nothing
    isempty(tok) && return nothing
    return tok
end

"""
    _init_authdata_hooks()

Initialize and retain C-callable function pointers for authdata hook and
cleanup callbacks used by libpq.
"""
function _init_authdata_hooks()
    cleanup_cfun = @cfunction(
        $(_oauth_cleanup),
        Cvoid,
        (Ptr{libpq_c.PGconn}, Ptr{libpq_c.PGoauthBearerRequest}),
    )
    _oauth_cleanup_cfun_ref[] = cleanup_cfun
    _oauth_cleanup_ptr[] = Base.unsafe_convert(Ptr{Cvoid}, cleanup_cfun)

    hook_cfun = @cfunction(
        $(_authdata_hook),
        Cint,
        (Cint, Ptr{libpq_c.PGconn}, Ptr{Cvoid}),
    )
    _authdata_hook_cfun_ref[] = hook_cfun
    _authdata_hook_ptr[] = Base.unsafe_convert(Ptr{Cvoid}, hook_cfun)

    return nothing
end

"""
    _oauth_cleanup(conn, request)

Internal cleanup callback invoked by libpq to release Julia-managed token
storage associated with an OAuth bearer request.
"""
function _oauth_cleanup(conn::Ptr{libpq_c.PGconn}, request::Ptr{libpq_c.PGoauthBearerRequest})::Cvoid
    if haskey(_oauth_token_store, request)
        delete!(_oauth_token_store, request)
    end
    return
end

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
        C_NULL,
        _oauth_cleanup_ptr[],
        pointer(token_bytes),
        request.user,
    )
    unsafe_store!(request_ptr, updated)
    return
end

"""
    _authdata_hook(type, conn, data) -> Cint

Internal libpq authdata hook dispatcher. It forwards unsupported authdata
types to libpq defaults, invokes the registered OAuth provider for bearer
requests, and writes provider tokens back to libpq when available.
"""
function _authdata_hook(
    type::Cint,
    conn::Ptr{libpq_c.PGconn},
    data::Ptr{Cvoid},
)::Cint
    try
        provider = _oauth_bearer_provider[]

        if type != Cint(libpq_c.PQAUTHDATA_OAUTH_BEARER_TOKEN)
            if provider !== nothing && type == Cint(libpq_c.PQAUTHDATA_PROMPT_OAUTH_DEVICE)
                return Cint(1)
            end
            return libpq_c.PQdefaultAuthDataHook(libpq_c.PGauthData(type), conn, data)
        end

        if provider === nothing
            return libpq_c.PQdefaultAuthDataHook(libpq_c.PGauthData(type), conn, data)
        end

        request_ptr = Ptr{libpq_c.PGoauthBearerRequest}(data)
        token = provider(conn, request_ptr)
        if token === nothing
            return libpq_c.PQdefaultAuthDataHook(libpq_c.PGauthData(type), conn, data)
        end

        oauth_bearer_set_token!(request_ptr, token)
        return Cint(1)
    catch err
        warn(LOGGER, "Authdata hook error: $(sprint(showerror, err))")
        return Cint(0)
    end
end

"""
    register_oauth_bearer_token_provider(provider)

Register `provider` to supply OAuth Bearer tokens for libpq. The provider is
called with `(conn::Ptr{PGconn}, request_ptr::Ptr{PGoauthBearerRequest})` and
should return a token string or `nothing` on failure.

Keep this callback fast: it runs on libpq's authentication path and may block
nonblocking connection workflows if it performs long-running work.
"""
function register_oauth_bearer_token_provider(provider::Function)
    _oauth_bearer_provider[] = provider
    _authdata_hook_ptr[] == C_NULL && _init_authdata_hooks()
    set_auth_data_hook(_authdata_hook_ptr[])
    return
end

"""
    register_fixed_oauth_bearer_token(token)

Register a fixed OAuth Bearer token provider backed by LibPQ-managed state.
Subsequent OAuth authdata hook invocations will return `token` until the
provider is replaced or cleared.
"""
function register_fixed_oauth_bearer_token(token::AbstractString)
    _oauth_fixed_token[] = String(token)
    register_oauth_bearer_token_provider(_fixed_oauth_bearer_provider)
    return
end

"""
    clear_oauth_bearer_token_provider()

Remove any registered OAuth Bearer token provider.
"""
function clear_oauth_bearer_token_provider()
    _oauth_bearer_provider[] = nothing
    _oauth_fixed_token[] = nothing
    return
end
