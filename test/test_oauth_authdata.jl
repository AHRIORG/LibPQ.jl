function _new_empty_oauth_request()
    return LibPQ.libpq_c.PGoauthBearerRequest(
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
    )
end

function run_oauth_authdata_tests()
    @testset "OAuth/Authdata" begin
        old_hook = LibPQ.get_auth_data_hook()
        old_provider = LibPQ._oauth_bearer_provider[]
        old_fixed_token = LibPQ._oauth_fixed_token[]
        old_token_store = copy(LibPQ._oauth_token_store)

        try
            LibPQ.clear_oauth_bearer_token_provider()

            provider_calls = Ref(0)
            LibPQ.register_oauth_bearer_token_provider() do conn, request_ptr
                provider_calls[] += 1
                return "provider-token"
            end

            @test LibPQ.get_auth_data_hook() != C_NULL

            req_ref = Ref(_new_empty_oauth_request())
            req_ptr = Base.unsafe_convert(Ptr{LibPQ.libpq_c.PGoauthBearerRequest}, req_ref)

            ret = LibPQ._authdata_hook(
                Cint(LibPQ.PQAUTHDATA_OAUTH_BEARER_TOKEN),
                Ptr{LibPQ.libpq_c.PGconn}(C_NULL),
                Ptr{Cvoid}(req_ptr),
            )

            @test ret == Cint(1)
            @test provider_calls[] == 1
            @test req_ref[].token != C_NULL
            @test req_ref[].cleanup != C_NULL
            @test unsafe_string(req_ref[].token) == "provider-token"
            @test haskey(LibPQ._oauth_token_store, req_ptr)

            prompt_ret = LibPQ._authdata_hook(
                Cint(LibPQ.PQAUTHDATA_PROMPT_OAUTH_DEVICE),
                Ptr{LibPQ.libpq_c.PGconn}(C_NULL),
                C_NULL,
            )
            @test prompt_ret == Cint(1)

            LibPQ._oauth_cleanup(Ptr{LibPQ.libpq_c.PGconn}(C_NULL), req_ptr)
            @test !haskey(LibPQ._oauth_token_store, req_ptr)

            LibPQ.register_fixed_oauth_bearer_token("fixed-token")

            fixed_ref = Ref(_new_empty_oauth_request())
            fixed_ptr = Base.unsafe_convert(Ptr{LibPQ.libpq_c.PGoauthBearerRequest}, fixed_ref)

            fixed_ret = LibPQ._authdata_hook(
                Cint(LibPQ.PQAUTHDATA_OAUTH_BEARER_TOKEN),
                Ptr{LibPQ.libpq_c.PGconn}(C_NULL),
                Ptr{Cvoid}(fixed_ptr),
            )

            @test fixed_ret == Cint(1)
            @test fixed_ref[].token != C_NULL
            @test unsafe_string(fixed_ref[].token) == "fixed-token"

            LibPQ.clear_oauth_bearer_token_provider()
            @test isnothing(LibPQ._oauth_bearer_provider[])
            @test isnothing(LibPQ._oauth_fixed_token[])

            LibPQ._oauth_cleanup(Ptr{LibPQ.libpq_c.PGconn}(C_NULL), fixed_ptr)
        finally
            empty!(LibPQ._oauth_token_store)
            for (request_ptr, token_bytes) in old_token_store
                LibPQ._oauth_token_store[request_ptr] = token_bytes
            end
            LibPQ._oauth_bearer_provider[] = old_provider
            LibPQ._oauth_fixed_token[] = old_fixed_token
            LibPQ.set_auth_data_hook(old_hook)
        end
    end

    return nothing
end
