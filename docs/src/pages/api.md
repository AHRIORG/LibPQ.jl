# LibPQ API

## Public

### Connections

```@docs
LibPQ.Connection
execute
prepare
status(::LibPQ.Connection)
Base.close(::LibPQ.Connection)
Base.isopen(::LibPQ.Connection)
reset!(::LibPQ.Connection)
Base.show(::IO, ::LibPQ.Connection)
```

### Results

```@docs
LibPQ.Result
status(::LibPQ.Result)
Base.close(::LibPQ.Result)
Base.isopen(::LibPQ.Result)
num_rows(::LibPQ.Result)
num_columns(::LibPQ.Result)
num_affected_rows(::LibPQ.Result)
Base.show(::IO, ::LibPQ.Result)
```

### Statements

```@docs
LibPQ.Statement
num_columns(::LibPQ.Statement)
num_params(::LibPQ.Statement)
Base.show(::IO, ::LibPQ.Statement)
LibPQ.load!
```

### Copy

```@docs
LibPQ.CopyIn
execute(::LibPQ.Connection, ::LibPQ.CopyIn)
```

### Asynchronous

```@docs
async_execute
LibPQ.AsyncResult
cancel
```

## Internals

### Connections

```@docs
LibPQ.handle_new_connection
LibPQ.server_version
LibPQ.encoding
LibPQ.set_encoding!
LibPQ.reset_encoding!
LibPQ.transaction_status
LibPQ.unique_id
LibPQ.error_message(::LibPQ.Connection)
```

### Connection Info

```@docs
LibPQ.ConnectionOption
LibPQ.conninfo
LibPQ.ConninfoDisplay
Base.parse(::Type{LibPQ.ConninfoDisplay}, ::AbstractString)
```

### Results and Statements

```@docs
LibPQ.handle_result
LibPQ.column_name
LibPQ.column_names
LibPQ.column_number
LibPQ.column_oids
LibPQ.column_types
LibPQ.num_params(::LibPQ.Result)
LibPQ.error_message(::LibPQ.Result)
```

### Errors

```@eval
using InteractiveUtils
using TikzGraphs
using TikzPictures
using Graphs
using LibPQ

function dograph()
    g = SimpleDiGraph()
    types = Any[LibPQ.Errors.LibPQException]

    i = 1
    add_vertex!(g)
    while i <= length(types)
        curr_length = length(types)
        typ = types[i]
        subtyps = subtypes(typ)
        for (j, subtyp) in enumerate(subtyps)
            push!(types, subtyp)
            add_vertex!(g)
            add_edge!(g, i, curr_length + j)
        end
        i += 1
    end

    TikzGraphs.plot(
        g,
        map(String∘nameof, types),
        node_style="draw, rounded corners",
        node_styles=Dict(enumerate((isabstracttype(t) ? "fill=blue!10" : "fill=green!10") for t in types)),
    )
end

TikzPictures.save(SVG("error_types"), dograph())

nothing
```

```@raw html
<div style="text-align:center; padding-bottom:20px">
    <figure>
        <img src="../error_types.svg" alt="Exception Type Hierarchy">
        <figcaption>LibPQ Exception Type Hierarchy<figcaption>
    </figure>
</div>
```

```@docs
LibPQ.Errors.LibPQException
LibPQ.Errors.JLClientException
LibPQ.Errors.PostgreSQLException
LibPQ.Errors.JLConnectionError
LibPQ.Errors.JLResultError
LibPQ.Errors.ConninfoParseError
LibPQ.Errors.PQConnectionError
LibPQ.Errors.PQResultError
```

### Type Conversions

```@docs
LibPQ.oid
LibPQ.PQChar
LibPQ.PQ_SYSTEM_TYPES
LibPQ.PQTypeMap
Base.getindex(::LibPQ.PQTypeMap, typ)
Base.setindex!(::LibPQ.PQTypeMap, ::Type, typ)
LibPQ._DEFAULT_TYPE_MAP
LibPQ.LIBPQ_TYPE_MAP
LibPQ.PQConversions
Base.getindex(::LibPQ.PQConversions, oid_typ::Tuple{Any, Type})
Base.setindex!(::LibPQ.PQConversions, ::Base.Callable, oid_typ::Tuple{Any, Type})
LibPQ._DEFAULT_CONVERSIONS
LibPQ.LIBPQ_CONVERSIONS
LibPQ._FALLBACK_CONVERSION
```

### Parsing

```@docs
LibPQ.PQValue
LibPQ.data_pointer
LibPQ.num_bytes
Base.unsafe_string(::LibPQ.PQValue)
LibPQ.string_view
LibPQ.bytes_view
Base.parse(::Type{Any}, pqv::LibPQ.PQValue)
```

### Authdata Hook

LibPQ exposes the libpq authdata hook API so you can supply OAuth Bearer tokens
from Julia. The hook runs during authentication, so keep it fast and preferably
return a cached token. Blocking work in this callback can interfere with
nonblocking connection flows.

```julia
using LibPQ

LibPQ.register_oauth_bearer_token_provider() do conn, request_ptr
    # Return a cached token string (or `nothing` on failure).
    return get(ENV, "PG_OAUTH_TOKEN", nothing)
end

conn = LibPQ.Connection("host=localhost dbname=postgres")
LibPQ.close(conn)
```

### Testing OAuth/Authdata

Run only the OAuth/authdata tests:

```bash
julia --project=. -e 'using LibPQ, Test; include("test/test_oauth_authdata.jl"); run_oauth_authdata_tests()'
```

Run the full LibPQ test suite against a running PostgreSQL instance:

```bash
PGHOST=tre-postgres \
PGPORT=5432 \
PGDATABASE=postgres \
PGUSER=postgres \
PGPASSWORD=postgres \
LIBPQJL_DATABASE_USER=postgres \
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Miscellaneous

```@docs
LibPQ.@pqv_str
LibPQ.string_parameters
LibPQ.parameter_pointers
LibPQ.unsafe_string_or_null
LibPQ.PGauthData
LibPQ.PGoauthBearerRequest
LibPQ.PGpromptOAuthDevice
LibPQ.PQAUTHDATA_PROMPT_OAUTH_DEVICE
LibPQ.PQAUTHDATA_OAUTH_BEARER_TOKEN
LibPQ.set_auth_data_hook
LibPQ.get_auth_data_hook
LibPQ.default_auth_data_hook
LibPQ.register_oauth_bearer_token_provider
LibPQ.clear_oauth_bearer_token_provider
LibPQ.oauth_bearer_set_token!
```

```@meta
DocTestSetup = nothing
```
