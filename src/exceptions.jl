module Errors

# use Cenum for error codes because it allows overriding show, unlike Base.Enum
using CEnum

using ..LibPQ: Connection, Result, libpq_c, error_message, error_field

"Base abstract type for all custom exceptions thrown by LibPQ.jl"
abstract type LibPQException <: Exception end

"An exception with an error message generated by PostgreSQL"
abstract type PostgreSQLException <: LibPQException end

# PostgreSQL errors have trailing newlines
# https://www.postgresql.org/docs/10/libpq-status.html#LIBPQ-PQERRORMESSAGE
Base.showerror(io::IO, err::PostgreSQLException) = print(io, chomp(err.msg))

"An exception generated by LibPQ.jl"
abstract type JLClientException <: LibPQException end

"An error regarding a connection reported by PostgreSQL"
struct PQConnectionError <: PostgreSQLException
    msg::String
end

function PQConnectionError(jl_conn::Connection)
    return PQConnectionError(error_message(jl_conn))
end

"An error from parsing connection parameter strings reported by PostgreSQL"
struct ConninfoParseError <: PostgreSQLException
    msg::String
end

"An error regarding a connection generated by LibPQ.jl"
struct JLConnectionError <: JLClientException
    msg::String
end

"An error regarding a query result generated by LibPQ.jl"
struct JLResultError <: JLClientException
    msg::String
end

"""
An error regarding a query result generated by PostgreSQL

The `Code` parameter represents the PostgreSQL error code as defined in
[Appendix A. PostgreSQL Error Codes](https://www.postgresql.org/docs/devel/errcodes-appendix.html).
The `Class` parameter is the first two characters of that code, also listed on that page.

For a list of all error aliases, see `src/error_codes.jl`, which was generated using the
PostgreSQL documentation linked above.

```jldoctest
julia> try execute(conn, "SELORCT NUUL;") catch err println(err) end
LibPQ.Errors.SyntaxError("ERROR:  syntax error at or near \\"SELORCT\\"\\nLINE 1: SELORCT NUUL;\\n        ^\\n")

julia> LibPQ.Errors.SyntaxError
LibPQ.Errors.PQResultError{LibPQ.Errors.C42,LibPQ.Errors.E42601}
```
"""
struct PQResultError{Class,Code} <: PostgreSQLException
    msg::String
    verbose_msg::Union{String,Nothing}

    function PQResultError{Class_,Code_}(msg, verbose_msg) where {Class_,Code_}
        return new{Class_::Errors.Class,Code_::Errors.ErrorCode}(
            convert(String, msg), convert(Union{String,Nothing}, verbose_msg)
        )
    end
end

include("error_codes.jl")

# avoid exposing the meaningless integer value of the enum
function Base.show(io::IO, ::MIME"text/plain", class::Class)
    return print(io, class, "::", typeof(class))
end
function Base.show(io::IO, ::MIME"text/plain", code::ErrorCode)
    return print(io, code, "::", typeof(code))
end

Base.parse(::Type{Class}, str::AbstractString) = getfield(Errors, Symbol("C", str))
Base.parse(::Type{ErrorCode}, str::AbstractString) = getfield(Errors, Symbol("E", str))

function PQResultError{Class,Code}(msg::String) where {Class,Code}
    return PQResultError{Class,Code}(msg, nothing)
end

function PQResultError(result::Result; verbose=false)
    msg = error_message(result; verbose=false)
    verbose_msg = verbose ? error_message(result; verbose=true) : nothing
    code_str = something(error_field(result, libpq_c.PG_DIAG_SQLSTATE), "UNOWN")
    class = parse(Class, code_str[1:2])
    code = parse(ErrorCode, code_str)

    return PQResultError{class,code}(msg, verbose_msg)
end

error_class(err::PQResultError{Class_}) where {Class_} = Class_::Class
error_code(err::PQResultError{Class_,Code_}) where {Class_,Code_} = Code_::ErrorCode

function Base.showerror(io::IO, err::T) where {T<:PQResultError}
    msg = err.verbose_msg === nothing ? err.msg : err.verbose_msg

    return print(io, ERROR_NAMES[T], ": ", chomp(msg))
end

function Base.show(io::IO, err::T) where {T<:PQResultError}
    print(io, "LibPQ.Errors.", ERROR_NAMES[T], '(', repr(err.msg))

    if err.verbose_msg !== nothing
        print(io, ", ", repr(err.verbose_msg))
    end

    return print(io, ')')
end

end
