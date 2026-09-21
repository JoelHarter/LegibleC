# The machinery behind every test: transpile the functions under test, build a C program
# that calls each of them on the test's inputs and prints the results, compile and run
# it, and compare what C printed with what Julia computes for the same call. Julia's
# value is the reference; the C has to agree to rounding. Any function whose C won't
# compile, or whose result differs, fails its test with both values shown.
using Test, StaticArrays, LinearAlgebra
using LegibleC
# The internals the harness needs to build a `main` around the generated C.
using LegibleC: identifier, identifiers, isarray, isstruct, istuple, structname, declare, normalize, shape, shaped, ctype, arrow, fieldcnames, charliteral, returnkind!, Program, initializer

# The setting the C is written for (doc/guide/start.md), so every test checks it holds up there.
# `-fno-cx-limited-range` keeps complex division overflow-safe under fast-math, as Julia's
# is; GCC has it, Apple's clang doesn't, so it is added where the compiler takes it.
# `-fwrapv` makes signed integer overflow wrap, as Julia's does; C leaves it undefined otherwise.
# The compiler is `cc`, or whatever `CC` names: the build server runs the suite under GCC and
# under Clang, the two compilers the C is written for.
const cc = get(ENV, "CC", "cc")
const cxflag = success(pipeline(`$cc -fno-cx-limited-range -x c -c /dev/null -o /dev/null`; stderr=devnull)) ? ["-fno-cx-limited-range"] : String[]
const flags = ["-std=c11", "-O2", "-ffast-math", "-fno-finite-math-only", cxflag..., "-ffp-contract=fast", "-fwrapv", "-march=native",
               "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-but-set-variable"]

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
cliteral(x::Integer) = LegibleC.integer(x)
cliteral(x::AbstractFloat) = isinf(x) ? (x > 0 ? "INFINITY" : "-INFINITY") : isnan(x) ? "NAN" : repr(Float64(x))
cliteral(x::Complex) = "CMPLX($(cliteral(real(x))), $(cliteral(imag(x))))"
cliteral(x::Union{Adjoint{<:Any, <:AbstractVector}, Transpose{<:Any, <:AbstractVector}}) = cliteral(parent(x))
cliteral(x::AbstractVector) = "{" * join(cliteral.(x), ", ") * "}"
cliteral(x::AbstractArray) = "{" * join((cliteral(selectdim(x, 1, i)) for i in 1:size(x, 1)), ", ") * "}"   # row-major nesting
cliteral(x::Tuple) = "{" * join(cliteral.(x), ", ") * "}"
cliteral(x) = "{" * join((cliteral(getfield(x, k)) for k in 1:fieldcount(typeof(x))), ", ") * "}"       # a struct

# ---- Julia results as flat lists, in the order the C prints them ----------------------

flat(::Nothing) = Float64[]
flat(x::Number) = [Float64(x)]
flat(x::Complex) = [Float64(real(x)), Float64(imag(x))]
flat(x::Char) = [Float64(codepoint(x))]
flat(x::Union{Adjoint{<:Any, <:AbstractVector}, Transpose{<:Any, <:AbstractVector}}) = flat(parent(x))
flat(x::AbstractArray) = reduce(vcat, flat.(vec(permutedims(collect(x), ndims(x):-1:1))); init=Float64[])   # row-major; a complex element is its two parts
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
    T <: Complex && return ["printf(\"%.17g %.17g \", creal($x), cimag($x));"]
    (T <: Number || T === Char) && return ["printf(\"%.17g \", (double)$x);"]
    if T <: AbstractArray
        E = eltype(T)
        E <: Complex && return ["for (int k = 0; k < $(prod(shape(T))); k++) {",
                                "    printf(\"%.17g %.17g \", creal(((const $(ctype(E)) *)$x)[k]), cimag(((const $(ctype(E)) *)$x)[k]));",
                                "}"]
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
function check(name, cases::Vector{Case}; targets=nothing, extra::AbstractString="", kw...)
    dir = mktempdir()
    fs = unique(c.f for c in cases)
    scope = parentmodule(fs[1])            # the test module: its names are bare
    path = transpile((targets === nothing ? fs : targets)...; outpath=dir, outfile=name, scope, kw...)
    path isa AbstractString || (path = path[1])
    LegibleC.scope[] = scope               # so the names spelled below match the file's
    LegibleC.booltype[] = get(kw, :bool, Bool)
    cnames = Dict(zip(fs, identifiers([identifier(string(nameof(f))) for f in fs])))
    headers = ["#include \"$h\"" for h in readdir(dirname(path)) if endswith(h, ".h") && h != "helper.h"]
    main = ["#include <stdio.h>", "#include <stdbool.h>", "#include <math.h>", "#include <complex.h>", headers..., extra, "int main(void) {"]
    references = Any[]
    for (k, c) in enumerate(cases)
        passes = String[]
        for (j, x) in enumerate(c.args)
            T = ctypeof(x)
            n = "a$(k)_$j"
            if x isa Tuple
                # A tuple parameter is spread: one C variable per element.
                for (e, y) in enumerate(x)
                    push!(main, "    $(declare(ctypeof(y), "$(n)_$e")) = $(cliteral(y));")
                    push!(passes, "$(n)_$e")
                end
            elseif isstruct(T) && ismutabletype(T)
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
        elseif r isa Tuple
            # The function's own struct, with its field names.
            kind = returnkind!(Program(), Base.method_instance(c.f, Tuple(typeof.(c.args))), cnames[c.f])
            push!(main, "    $(kind.cname) r$k = $call;")
            for (F, f, y) in zip(R.parameters, kind.fields, r)
                append!(main, "    " .* cprint(ctypeof(y), "r$k.$f"))
            end
        else
            push!(main, "    $(declare(R, "r$k")) = $call;")
            append!(main, "    " .* cprint(R, "r$k"))
        end
        push!(main, "    printf(\"\\n\");")
    end
    push!(main, "    return 0;", "}")
    LegibleC.scope[] = Main
    LegibleC.booltype[] = Bool
    write(joinpath(dir, "main.c"), join(main, "\n") * "\n")
    exe = joinpath(dir, "main")
    out = dirname(path)
    sources = [joinpath(out, f) for f in readdir(out) if endswith(f, ".c")]
    run(`$cc $flags -I$out $(joinpath(dir, "main.c")) $sources -o $exe -lm`)   # -lm: Linux doesn't link libm by itself
    lines = split(read(`$exe`, String), "\n")
    @testset "$name" begin
        @test length(lines) == length(cases) + 1
        for (k, c) in enumerate(cases)
            got = parse.(Float64, split(lines[k]))
            want = flat(references[k])
            @test agree(got, want) || (println("$(nameof(c.f))$(c.args): C gave $got, Julia $want"); false)
        end
    end
    return snap(name, read(path, String))
end

# Transpile and compile only, for a test that checks the text of the C: every file
# written, headers first and the functions last, as one string.
# With `LEGIBLEC_SNAP` set to a folder, every C text the tests generate is also written there,
# numbered in order: for comparing the output of two versions of the transpiler byte for byte,
# which is how a change meant to alter nothing is shown to have altered nothing.
const snapped = Ref(0)
function snap(name, text)
    dir = get(ENV, "LEGIBLEC_SNAP", "")
    isempty(dir) && return text
    mkpath(dir)
    snapped[] += 1
    write(joinpath(dir, lpad(snapped[], 4, '0') * "_" * name * ".c"), text)
    return text
end

function csource(name, targets...; kw...)
    dir = mktempdir()
    own(g) = g isa Function && !(nameof(Base.moduleroot(parentmodule(g))) in (:Core, :Base, :LinearAlgebra, :StaticArrays))
    f = findfirst(t -> t isa Function && own(t) || t isa Tuple && own(t[1]), collect(targets))
    scope = f === nothing ? Main : parentmodule(targets[f] isa Tuple ? targets[f][1] : targets[f])
    path = transpile(targets...; outpath=dir, outfile=name, scope, kw...)
    path isa AbstractString || (path = path[1])
    last = basename(path)
    out = dirname(path)
    files = readdir(out)
    for f in files
        endswith(f, ".c") && run(`$cc $flags -c $(joinpath(out, f)) -o $(joinpath(dir, f * ".o"))`)
    end
    ordered = [filter(==("helper.h"), files); filter(f -> endswith(f, ".h") && f != "helper.h", files); filter(f -> endswith(f, ".c") && f != last, files); [last]]
    return snap(name, join((read(joinpath(out, f), String) for f in ordered), "\n"))
end
