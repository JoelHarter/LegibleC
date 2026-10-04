# The grid: every scalar function the transpiler knows, on every combination of number
# types, at the values where the two languages part ways. Julia computes each answer and the
# C must match. Where Julia throws, the case is left out: Julia that throws never reaches C.
# A refusal is fine. A wrong answer, C that doesn't compile, or a fault inside the transpiler
# is a failure.
#
# It exists because a test written by hand tries the types its author thought of. The bugs of
# 2026-09-21 sat one step to the side: `max(a, b, c)`, `1 << k`, a `UInt8` sum used inside a
# larger expression, `-1 < u`. Nobody thought of them; the grid doesn't have to.
#
# It is part of the suite (under a minute). `GRID_ONLY=max,min` runs some functions only.
module Grid
using Test, LegibleC
import Main: cc, flags, snap
using LegibleC: ctype

const only = filter(!isempty, split(get(ENV, "GRID_ONLY", ""), ","))
const ints = (Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64)
const floats = (Float32, Float64)
const numbers = (Bool, ints..., floats...)

# The values where the languages part ways: zero and its sign, one, a negative, the ends of the
# range and their neighbours, what doesn't fit the next type down, NaN and the infinities.
values(::Type{Bool}) = [false, true]
values(T::Type{<:Signed}) = T[0, 1, -1, 2, 7, -7, 100, typemin(T), typemin(T) + 1, typemax(T), typemax(T) - 1]
values(T::Type{<:Unsigned}) = T[0, 1, 2, 7, 100, 200, typemax(T) ÷ 2 + 1, typemax(T) - 1, typemax(T)]
values(::Type{Char}) = Char.(0:127)             # every character a C `char` holds for sure
values(T::Type{<:AbstractFloat}) = T[0.0, -0.0, 1.0, -1.0, 0.5, 2.5, -2.5, 3.0, 180.0, 1e6, floatmin(T), floatmax(T), -floatmax(T), NaN, Inf, -Inf]

one_ = [(:neg, :(-a), numbers), (:abs, :(abs(a)), numbers), (:not, :(~a), ints), (:lnot, :(!a), (Bool,)), (:zero, :(zero(a)), numbers), (:one, :(one(a)), numbers),
        (:float, :(float(a)), numbers), (:inv, :(inv(a)), numbers), (:isodd, :(isodd(a)), ints), (:iseven, :(iseven(a)), ints), (:isqrt, :(isqrt(a)), ints),
        (:sq, :(a^2), numbers), (:cube, :(a^3), numbers), (:recip, :(a^-1), floats), (:abs2, :(abs2(a)), numbers),
        (:isnan, :(isnan(a)), floats), (:isinf, :(isinf(a)), floats), (:isfinite, :(isfinite(a)), floats), (:signbit, :(signbit(a)), floats),
        (:eps, :(eps(a)), floats), (:deg2rad, :(deg2rad(a)), floats), (:rad2deg, :(rad2deg(a)), floats), (:sind, :(sind(a)), (Float64,)), (:cosd, :(cosd(a)), (Float64,)),
        [(f, :($f(a)), floats) for f in (:sqrt, :cbrt, :sin, :cos, :tan, :asin, :acos, :atan, :sinh, :cosh, :tanh, :exp, :exp2, :expm1, :log, :log2, :log10, :log1p,
                                         :floor, :ceil, :trunc, :round)]...,
        [(Symbol(:to, T), :($T(a)), numbers) for T in (:Float64, :Float32, :Int64, :Int32, :UInt8, :UInt64, :Bool)]...,
        [(Symbol(:round, m), :(round(a, $m)), floats) for m in (:RoundNearest, :RoundUp, :RoundDown, :RoundToZero, :RoundNearestTiesAway)]...,
        (:roundint, :(round(Int64, a)), floats), (:floorint, :(floor(Int64, a)), floats), (:ceilint, :(ceil(Int64, a)), floats), (:truncint, :(trunc(Int64, a)), floats)]
two = [(:add, :(a + b), numbers, numbers), (:sub, :(a - b), numbers, numbers), (:mul, :(a * b), numbers, numbers), (:div, :(a / b), numbers, numbers),
       (:ldiv, :(a \ b), numbers, numbers), (:idiv, :(div(a, b)), numbers, numbers), (:rem, :(rem(a, b)), numbers, numbers), (:mod, :(mod(a, b)), numbers, numbers),
       (:lt, :(a < b), numbers, numbers), (:le, :(a <= b), numbers, numbers), (:gt, :(a > b), numbers, numbers), (:ge, :(a >= b), numbers, numbers),
       (:eq, :(a == b), numbers, numbers), (:ne, :(a != b), numbers, numbers), (:min, :(min(a, b)), numbers, numbers), (:max, :(max(a, b)), numbers, numbers),
       (:and, :(a & b), (Bool, ints...), (Bool, ints...)), (:or, :(a | b), (Bool, ints...), (Bool, ints...)), (:xor, :(xor(a, b)), (Bool, ints...), (Bool, ints...)),
       (:shl, :(a << b), ints, ints), (:shr, :(a >> b), ints, ints), (:lshr, :(a >>> b), ints, ints), (:shl3, :(a << 3), ints, (Bool,)), (:shr3, :(a >> 3), ints, (Bool,)),
       (:one_shl, :(1 << b), (Bool,), ints), (:gcd, :(gcd(a, b)), ints, ints), (:lcm, :(lcm(a, b)), ints, ints),
       (:remnear, :(rem(a, b, RoundNearest)), floats, floats),
       (:hypot, :(hypot(a, b)), floats, floats), (:copysign, :(copysign(a, b)), floats, floats), (:atan2, :(atan(a, b)), floats, floats), (:pow, :(a^b), floats, floats),
       (:ifelse, :(ifelse(a < b, a, b)), numbers, numbers), (:minmax, :((lo, hi) = minmax(a, b); hi - lo), numbers, numbers),
       (:inside, :((a + b) * 2 > 100), numbers, numbers), (:mixed, :(Float64(a + b) + a * b), numbers, numbers)]

# What the compiler setting is allowed to change is left out, by saying what it is. A product
# that overflows on its own and not inside a fused multiply-add: `-max * -max + (-max + -max)`
# is `Inf - Inf` in Julia and `-Inf` under `-ffp-contract=fast`, which keeps the product exact.
# And the sign of a zero, which the setting lets go (`-fno-signed-zeros` is part of fast math):
# GCC answers `signbit(-0.0)` with 0.
# And a `nextpow` whose answer doesn't fit 64 bits: Julia notices some of those and throws, and
# for the rest returns a power that has wrapped round. The C stops with the error for all of them.
allowed(name, combo) = !(startswith(name, "mixed") && any(x -> x isa AbstractFloat && abs(x) == floatmax(typeof(x)), combo)) &&
                       !(occursin("signbit", name) && iszero(combo[1])) &&
                       !(startswith(name, "row_nextpow") && combo[2] > 1 && combo[1] > 0 && nextpow(big(combo[2]), big(combo[1])) > typemax(Int64))    # the arguments come last first

# One function of the grid: its Julia, its types, and what Julia answers on every combination of values.
struct Item
    name::String
    f::Function
    types::Tuple
    inputs::Vector{Any}              # one list of values for each argument
    answers::Vector{Any}             # Julia's, in the order the C prints them; `nothing` where Julia throws
end

supported(x) = x isa Union{Bool, Char, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64}

# One function with what Julia answers on every combination of its inputs, or `nothing` if Julia
# never answers, or answers with more than one type.
function item(name, f, types, inputs)
    answers = Any[]
    for combo in Iterators.product(reverse(inputs)...)                # the last argument fastest, as the C loops run
        r = allowed(name, combo) ? (try Base.invokelatest(f, reverse(combo)...) catch; nothing end) : nothing
        push!(answers, supported(r) ? r : nothing)
    end
    kinds = unique(typeof(r) for r in answers if r !== nothing)
    return length(kinds) == 1 ? Item(name, f, Tuple(types), inputs, answers) : nothing
end

function items()
    out = Item[]
    add(name, body, types) = begin
        isempty(only) || any(o -> startswith(name, o), only) || return
        args = [Expr(:(::), s, T) for (s, T) in zip((:a, :b, :c), types)]
        f = Core.eval(Grid, Expr(:function, Expr(:call, Symbol(name), args...), body))
        it = item(name, f, types, Any[values(T) for T in types])
        it === nothing || push!(out, it)
    end
    for (name, body, ts) in one_, T in ts
        add("$(name)_$T", body, (T,))
    end
    for (name, body, as, bs) in two, A in as, B in bs
        add("$(name)_$(A)_$B", body, (A, B))
    end
    # And the transpiler's own table of scalar functions (`src/idiom.jl`), every row on every
    # combination of types it says it applies to: a row is tried the day it is added, on types
    # its author didn't think of.
    for r in LegibleC.idioms
        n = count(p -> occursin(p, r.c), ("{a}", "{b}", "{c}"))
        occursin("{-", r.c) && continue          # takes an argument that is no number, a rounding mode: tried by name above
        # A row for a package's function, known to the transpiler by name: tried when the package is here.
        f = r.f isa Pair ? (isdefined(Main, r.f[1]) ? getfield(getfield(Main, r.f[1]), r.f[2]) : continue) : r.f
        for A in Iterators.product(fill((numbers..., Char), n)...)
            T = Base.promote_op(f, A...)
            T isa DataType && isconcretetype(T) && r.applies(T, collect(A)) || continue
            add("row_$(nameof(f))_$(join(A, "_"))", Expr(:call, f, (:a, :b, :c)[1:n]...), A)
        end
    end
    return out
end

literal(x::Bool) = x ? "true" : "false"
literal(x::Char) = LegibleC.charliteral(x)
literal(x::Integer) = LegibleC.integer(x)
literal(x::AbstractFloat) = isnan(x) ? "NAN" : isinf(x) ? (x > 0 ? "INFINITY" : "-INFINITY") : x isa Float32 ? repr(Float64(x)) * "f" : repr(x)
printer(T) = T === Bool || T === Char ? ("%d", "(int)") : T <: Unsigned ? ("%llu", "(unsigned long long)") : T <: Integer ? ("%lld", "(long long)") : ("%.17g", "(double)")

# Does the C's answer agree with Julia's? Integers and truth values exactly. Floats exactly, or to
# rounding: the C's math library is not Julia's, and the compiler setting lets rounding move.
function agrees(want, got::AbstractString)
    want isa Bool && return got == (want ? "1" : "0")
    want isa Char && return got == string(Int(want))
    want isa Integer && return got == string(want)
    g = got in ("nan", "-nan") ? NaN : got == "inf" ? Inf : got == "-inf" ? -Inf : parse(Float64, got)
    isnan(want) && return isnan(g)
    return g == want || isapprox(g, Float64(want); rtol=want isa Float32 ? 2e-6 : 1e-9, atol=want isa Float32 ? 1e-30 : 1e-300)
end

function run(todo, scope::Module)
    dir = mktempdir()
    refused, faults, broken, wrong, right = String[], String[], String[], String[], 0
    main = ["#include <stdio.h>", "#include <stdint.h>", "#include <stdbool.h>", "#include <math.h>"]
    body = String[]
    objects = String[]
    ok = Item[]
    # Each function is first tried on its own, in memory: a refusal or a fault is found there and
    # costs little. What is left is transpiled a hundred functions to a file, which is where
    # the time goes otherwise (a file's worth of bookkeeping for every call to `transpile`).
    accepted = filter(todo) do it
        mi = Base.method_instance(it.f, it.types)
        try
            LegibleC.compose(it.name, mi, Type[it.types...], LegibleC.Program(), 40, false)
            return true
        catch e
            e isa ArgumentError ? push!(refused, it.name) : push!(faults, it.name * ": " * first(sprint(showerror, e), 160))
            return false
        end
    end
    log = joinpath(dir, "cc.log")
    function build(batch, tag)
        path = LegibleC.transpile([(it.f, it.types...) for it in batch]...; outpath=joinpath(dir, "src"), outfile="g$tag", helper="h$tag", source=false, scope)
        path isa AbstractString || (path = path[1])
        object = joinpath(dir, "g$tag.o")
        if success(pipeline(`$cc $flags -c $(joinpath(dirname(path), "g$tag.c")) -o $object`; stderr=log, stdout=devnull))
            snap("g$tag", read(joinpath(dirname(path), "g$tag.c"), String))
            append!(ok, batch)
            push!(objects, object)
        elseif length(batch) == 1
            push!(broken, batch[1].name * ": " * first(replace(read(log, String), r"^.*?error: "s => ""), 160))
        else                                     # one of them doesn't compile: halve until it is found
            h = length(batch) ÷ 2
            build(batch[1:h], tag * "a")
            build(batch[h+1:end], tag * "b")
        end
    end
    for (n, batch) in enumerate(Iterators.partition(accepted, 100))
        build(collect(batch), string(n))
    end
    for it in ok
        R = typeof(first(r for r in it.answers if r !== nothing))
        push!(main, "$(ctype(R)) $(it.name)($(join((ctype(T) for T in it.types), ", ")));")
        fmt, cast = printer(R)
        push!(body, "    {")
        for (j, (T, vs)) in enumerate(zip(it.types, it.inputs))
            push!(body, "        $(ctype(T)) x$j[] = {$(join(literal.(vs), ", "))};")
        end
        push!(body, "        static const char run[] = {$(join((r === nothing ? "0" : "1" for r in it.answers), ", "))};")
        n = length.(it.inputs)
        idx = ["i$j" for j in eachindex(n)]
        flat = join((idx[j] * join((" * $(n[k])" for k in j+1:length(n))) for j in eachindex(n)), " + ")       # the last argument fastest
        loops = join(("for (int $(idx[j]) = 0; $(idx[j]) < $(n[j]); $(idx[j])++) " for j in eachindex(n)))
        call = "$(it.name)($(join(("x$j[$(idx[j])]" for j in eachindex(n)), ", ")))"
        push!(body, "        $(loops)if (run[$flat]) printf(\"$fmt\\n\", $cast$call);")
        push!(body, "    }")
    end
    write(joinpath(dir, "main.c"), join([main; "int main(void) {"; body; "    return 0;"; "}"], "\n"))
    exe = joinpath(dir, "grid")
    Base.run(`$cc -std=c11 -O0 -w $(joinpath(dir, "main.c")) $objects -o $exe -lm`)
    lines = split(read(`$exe`, String), '\n'; keepempty=false)
    at = 0
    for it in ok
        combos = collect(Iterators.product(reverse(it.inputs)...))
        for (r, combo) in zip(it.answers, combos)
            r === nothing && continue
            at += 1
            agrees(r, lines[at]) ? (right += 1) : push!(wrong, "$(it.name)$(reverse(combo)): C gave $(lines[at]), Julia $(r)")
        end
    end
    return (; functions=length(todo), refused, faults, broken, wrong, right)
end

function report(title, todo, scope::Module)
    r = run(todo, scope)
    println("$title: $(r.functions) functions, $(r.right) answers right, $(length(r.wrong)) wrong, $(length(r.broken)) don't compile, $(length(r.faults)) faults, $(length(r.refused)) refused")
    # By function first, so that one broken rule with a thousand wrong answers doesn't bury another with three.
    byfunction = Dict{String, Vector{String}}()
    foreach(x -> push!(get!(byfunction, first(split(x, "(")), String[]), x), r.wrong)
    for name in sort!(collect(keys(byfunction)))
        println("  WRONG   $(length(byfunction[name])) × ", byfunction[name][1], length(byfunction[name]) > 1 ? "   and e.g. " * replace(byfunction[name][end], r"^[^(]*" => "") : "")
    end
    foreach(x -> println("  BROKEN  ", x), first(r.broken, 40))
    foreach(x -> println("  FAULT   ", x), first(r.faults, 40))
    return r
end

@testset "grid" begin
    r = report("grid", items(), Grid)
    @test isempty(r.wrong)
    @test isempty(r.broken)
    @test isempty(r.faults)
end
end
