module LibPQ

export status,
    reset!,
    execute,
    prepare,
    async_execute,
    cancel,
    PGauthData,
    PGoauthBearerRequest,
    PGpromptOAuthDevice,
    PQAUTHDATA_PROMPT_OAUTH_DEVICE,
    PQAUTHDATA_OAUTH_BEARER_TOKEN,
    set_auth_data_hook!,
    get_auth_data_hook,
    default_auth_data_hook,
    register_oauth_bearer_token_provider!,
    clear_oauth_bearer_token_provider!,
    oauth_bearer_set_token!,
    num_columns,
    num_rows,
    num_params,
    num_affected_rows

using Base: Semaphore, acquire, release
using Base.Iterators: zip, product
using Base.Threads

using Dates
using DocStringExtensions
using Decimals
using FileWatching
using Tables
using Infinity: InfExtendedTime, isposinf, ∞
using Intervals
using IterTools: imap
using LayerDicts
using Memento: Memento, getlogger, warn, info, error, debug
using OffsetArrays
using SQLStrings
using TimeZones
using UTCDateTimes
using DBInterface

const Parameter = Union{String,Missing}
const LOGGER = getlogger(@__MODULE__)

function __init__()
    INTERVAL_REGEX[] = _interval_regex()
    Memento.register(LOGGER)
    return nothing
end

# Docstring template for types using DocStringExtensions
@template TYPES = """
        $(TYPEDEF)

    $(DOCSTRING)

    ## Fields:

    $(TYPEDFIELDS)
    """

include(joinpath(@__DIR__, "utils.jl"))

module libpq_c
    export Oid

    using LibPQ_jll

    include(joinpath(@__DIR__, "headers", "libpq-fe.jl"))
end

using .libpq_c

include("typemaps.jl")
include("authdata.jl")

const DEFAULT_CLIENT_TIME_ZONE = Ref("UTC")

"""
    const LIBPQ_TYPE_MAP::PQTypeMap

The [`PQTypeMap`](@ref) containing LibPQ-level type mappings for LibPQ.jl.
Adding type mappings to this constant will override the default type mappings for all code
using LibPQ.jl.
"""
const LIBPQ_TYPE_MAP = PQTypeMap()

"""
    const LIBPQ_CONVERSIONS::PQConversions

The [`PQConversions`](@ref) containing LibPQ-level conversion functions for LibPQ.jl.
Adding conversions to this constant will override the default conversions for all code using
LibPQ.jl.
"""
const LIBPQ_CONVERSIONS = PQConversions()

const BINARY = true
const TEXT = false

include("connections.jl")
include("results.jl")
include("statements.jl")
include("exceptions.jl")

include("parsing.jl")
include("copy.jl")
include("tables.jl")
include("dbinterface.jl")

include("asyncresults.jl")

include("deprecated.jl")

end
