# The machinery behind every test: transpile the functions under test, build a C program
# that calls each of them on the test's inputs and prints the results, compile and run
# it, and compare what C printed with what Julia computes for the same call. Julia's
# value is the reference; the C has to agree to rounding. Any function whose C won't
# compile, or whose result differs, fails its test with both values shown.
using Test, StaticArrays, LinearAlgebra
include(joinpath(@__DIR__, "..", "src", "transpile.jl"))
# The internals the harness needs to build a `main` around the generated C.
using .LegibleC: identifier, identifiers, isarray, isstruct, istuple, structname, declare, normalize, shape, shaped, ctype, arrow, fieldcnames, charliteral

const flags = ["-std=c11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-but-set-variable"]

# One call to check: a function and the values to call it with.
struct Case
    f
    args::Tuple
    Case(f, args...) = new(f, args)
end

# ---- Julia values as C initializers ----------------------------------------------------

cliteral(x::Bool) = x ? "true" : "false"
cliteral(x::Char) = charliteral(x)
cliteral(x::AbstractString) = "\"" * replace(x, "\\" => "\\\\", "\"" => "\\\"") * "\""
cliteral(x::Integer) = string(x)
cliteral(x::AbstractFloat) = isinf(x) ? (x > 0 ? "INFINITY" : "-INFINITY") : isnan(x) ? "NAN" : repr(Float64(x))
cliteral(x::Union{Adjoint{<:Any, <:AbstractVector}, Transpose{<:Any, <:AbstractVector}}) = cliteral(parent(x))
cliteral(x::AbstractVector) = "{" * join(cliteral.(x), ", ") * "}"
cliteral(x::AbstractArray) = "{" * join((cliteral(selectdim(x, 1, i)) for i in 1:size(x, 1)), ", ") * "}"   # row-major nesting
cliteral(x::Tuple) = "{" * join(cliteral.(x), ", ") * "}"
cliteral(x) = "{" * join((cliteral(getfield(x, k)) for k in 1:fieldcount(typeof(x))), ", ") * "}"       # a struct

# ---- Julia results as flat lists, in the order the C prints them ----------------------

flat(::Nothing) = Float64[]
flat(x::Number) = [Float64(x)]
flat(x::Char) = [Float64(codepoint(x))]
flat(x::Union{Adjoint{<:Any, <:AbstractVector}, Transpose{<:Any, <:AbstractVector}}) = flat(parent(x))
flat(x::AbstractArray) = Float64.(vec(permutedims(collect(x), ndims(x):-1:1)))                          # row-major
flat(x::Tuple) = reduce(vcat, flat.(x); init=Float64[])
flat(x) = reduce(vcat, (flat(getfield(x, k)) for k in 1:fieldcount(typeof(x))); init=Float64[])

# The C type the transpiler gives a value: its own, with a regular array's size filled in.
function ctypeof(x)
    T = normalize(typeof(x))
    isarray(T) && shape(T) === nothing && return shaped(eltype(T), size(x))
    return T
end

# C lines printing the value `x` of type `T`, every number as `%.17g` and a space.
function cprint(T::Type, x)
    (T <: Number || T === Char) && return ["printf(\"%.17g \", (double)$x);"]
    if T <: AbstractArray
        return ["for (int k = 0; k < $(prod(shape(T))); k++) {",
                "    printf(\"%.17g \", (double)((const $(ctype(eltype(T))) *)$x)[k]);",
                "}"]
    end
    fields = istuple(T) ? collect(T.parameters) : [fieldtype(T, k) for k in 1:fieldcount(T)]
    return reduce(vcat, (cprint(F, "$x$(arrow(T))$c") for (F, c) in zip(fields, fieldcnames(T))); init=String[])
end

# Do two flat results agree? To rounding, with NaN equal to NaN.
agree(got, want) = length(got) == length(want) &&
                   all(isapprox(g, w; rtol=1e-9, atol=1e-12) || (isnan(g) && isnan(w)) for (g, w) in zip(got, want))

"""
    check(name, cases; targets=functions of the cases, extra="") -> C source

Transpile the functions of `cases` (or `targets`, in `transpile`'s own forms, when a
function needs its types spelled out) into `name.c`, run every case in C, and test that
each result agrees with Julia's. `extra` is C text placed before `main`, for a function
a `ccall` needs to exist. Returns the generated C, for tests that look at the text.
"""
function check(name::AbstractString, cases::Vector{Case}; targets=nothing, extra::AbstractString="")
    dir = mktempdir()
    fs = unique(c.f for c in cases)
    path = transpile((targets === nothing ? fs : targets)...; outpath=dir, outfile=name)
    cnames = Dict(zip(fs, identifiers([identifier(string(nameof(f))) for f in fs])))
    main = ["#include <stdio.h>", "#include \"$name.c\"", extra, "int main(void) {"]
    references = Any[]
    for (k, c) in enumerate(cases)
        passes = String[]
        for (j, x) in enumerate(c.args)
            T = ctypeof(x)
            n = "a$(k)_$j"
            if isstruct(T) && ismutabletype(T)
                push!(main, "    $(structname(T)) $n = $(cliteral(x));")
                push!(passes, "&" * n)
            else
                push!(main, "    $(declare(T, n)) = $(cliteral(x));")
                push!(passes, n)
            end
        end
        r = c.f(c.args...)                    # Julia's answer, after the C literals were taken
        push!(references, r)
        R = ctypeof(r)
        call = "$(cnames[c.f])($(join(passes, ", ")))"
        if R === Nothing
            push!(main, "    $call;")
        elseif isarray(R)
            push!(main, "    $(declare(R, "r$k"));", "    $(cnames[c.f])($(join([passes; "r$k"], ", ")));")
            append!(main, "    " .* cprint(R, "r$k"))
        else
            push!(main, "    $(declare(R, "r$k")) = $call;")
            append!(main, "    " .* cprint(R, "r$k"))
        end
        push!(main, "    printf(\"\\n\");")
    end
    push!(main, "    return 0;", "}")
    write(joinpath(dir, "main.c"), join(main, "\n") * "\n")
    exe = joinpath(dir, "main")
    run(`cc $flags -I$dir $(joinpath(dir, "main.c")) -o $exe`)
    lines = split(read(`$exe`, String), "\n")
    @testset "$name" begin
        @test length(lines) == length(cases) + 1
        for (k, c) in enumerate(cases)
            got = parse.(Float64, split(lines[k]))
            want = flat(references[k])
            @test agree(got, want) || (println("$(nameof(c.f))$(c.args): C gave $got, Julia $want"); false)
        end
    end
    return read(path, String)
end

# Transpile and compile only, for a test that checks the text of the C.
function csource(name::AbstractString, targets...; kw...)
    dir = mktempdir()
    path = transpile(targets...; outpath=dir, outfile=name, kw...)
    run(`cc $flags -c $path -o $(joinpath(dir, "out.o"))`)
    return read(path, String)
end
