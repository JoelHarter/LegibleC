# Scalar arithmetic, division rules, powers, integer operations, conversions, math.
module Scalar
using Test, StaticArrays
import Main: Case, check, csource, LegibleC

arith(a::Float64, b::Float64, c::Float64) = (d = (a + b) * c / 2)
unary(x::Int64) = -x + 2 * x
nary(a::Float64, b::Float64, c::Float64, d::Float64) = a + b + c + d
reassign(a::Float64) = (d = a; d = d + 1.0; d = d * d; d - 3.0)
intint(a::Int64, b::Int64) = a / b
literal() = 5 / 2
halfint(a::Int64) = a / 2
mixed(a::Float64, b::Int64) = a / b
narrow(a::Int32, b::Int32) = a / b
single(a::Float32, b::Int32) = a / b
smooth(x::Float64) = sqrt(abs(x)) + x^2 + x^0.5 + max(x, 1.0) + 2 * pi + exp(-x) * sin(x)
intmath(a::Int64, b::Int64) = a ÷ b + a % b + a^3 + mod(a, b) + abs(a) + max(a, b)
convert_(a::Int64, x::Float64) = Float64(a) + Int64(round(x)) + trunc(Int64, x) + round(x)
strictly(a::Float64, b::Float64) = a != b && !(a >= b)
either(a::Bool, b::Bool) = !a || b
ldiv(a::Float64, b::Float64) = a \ b
cube(x::Float64) = x^3 + x^-1
powers(x::Float64) = x^5 + x^-4 + x^7 * x^0 + x^1 + x^-2 + x^13
intpow(a::Int64) = a^5 + a^4 + a^0
pow32(x::Float32) = x^5 + x^-3
math32(x::Float32) = sqrt(x) + abs(-x) + max(x, 1.0f0) + x^0.5f0 + exp(x) + round(x) + rem(x, 0.7f0)
fmod_(a::Float64, b::Float64) = mod(a, b)
fmod32(a::Float32, b::Float32) = mod(a, b)
zeroone(x::Float64, n::Int64) = zero(x) + one(x) * x + one(n) + zero(Float64)
pie(x::Float64) = x * pi + ℯ
Base.@irrational twopi 6.283185307179586 2 * big(π)          # the author's own irrational: a macro like any other
struct Root2 <: AbstractIrrational end                       # the same by the public interface, no Base macro
const root2 = Root2()
Base.BigFloat(::Root2; precision=precision(BigFloat)) = sqrt(BigFloat(2; precision))
Base.Float64(::Root2) = 1.4142135623730951
Base.Float32(::Root2) = 1.4142135f0
Base.:(==)(::Root2, ::Root2) = true
Base.hash(::Root2, h::UInt) = hash(:root2, h)
rooted(x::Float64) = x * root2
irrationals(x::Float64) = x * Base.MathConstants.catalan + Base.MathConstants.γ - twopi
Base.@irrational ϕ 1.5 big"1.5"                              # spells `PHI`, as Base's φ does: the second one met is `PHI_`
phis(x::Float64) = x * Base.MathConstants.φ + ϕ
function sincos_(x::Float64)
    s, c = sincos(x)
    return s * c
end
function sincos32(x::Float32)
    s, c = sincos(2x)
    return s + c
end
picked(x::Float64) = sincos(x)[2]
function kept(x::Float64)
    t = sincos(x)
    return t[1]
end
bits(a::Int64, b::Int64) = (a & b) | (a << 2) ⊻ (b >> 1)
special(x::Float64) = x + NaN + Inf - Inf
special32(x::Float32) = x + NaN32 + Inf32
classify(x::Float64) = (isnan(x) ? 1 : 0) + (isinf(x) ? 2 : 0) + (isfinite(x) ? 4 : 0) + (signbit(x) ? 8 : 0)
limits() = Float64(typemax(Int64)) + Float64(typemin(Int32)) + Float64(typemax(UInt8)) + eps(Float64) + Float64(eps(Float32)) + floatmin(Float64)
biggest(x::Float64) = min(floatmax(Float64), x) + (typemax(Float64) == Inf ? 1.0 : 0.0)

check("scalar", [Case(arith, 1.0, 2.0, 3.0), Case(unary, 7), Case(nary, 1.0, 2.0, 3.0, 4.0), Case(reassign, 2.0),
                 Case(intint, 7, 2), Case(literal), Case(halfint, 7), Case(mixed, 7.0, 2), Case(narrow, Int32(7), Int32(2)),
                 Case(single, 7.0f0, Int32(2)), Case(smooth, 1.7), Case(intmath, 7, 3), Case(intmath, -7, 3),
                 Case(convert_, 3, 2.6), Case(strictly, 1.0, 2.0), Case(strictly, 2.0, 1.0), Case(either, true, false),
                 Case(ldiv, 4.0, 1.0), Case(cube, 2.0), Case(powers, 1.3), Case(intpow, 3), Case(pow32, 1.5f0), Case(math32, 1.7f0), Case(fmod_, 7.5, 2.0), Case(fmod_, -7.5, 2.0), Case(fmod_, 7.5, -2.0), Case(fmod_, 4.0, -2.0),
                 Case(fmod32, -7.5f0, 2.0f0), Case(zeroone, 2.5, 3), Case(pie, 2.0), Case(irrationals, 2.0), Case(phis, 2.0), Case(rooted, 2.0), Case(sincos_, 0.7), Case(sincos32, 0.7f0), Case(picked, 0.7), Case(bits, 12, 10),
                 Case(special, 1.0), Case(special32, 1.0f0), Case(classify, NaN), Case(classify, -Inf), Case(classify, -2.5), Case(classify, 3.0),
                 Case(limits), Case(biggest, 7.0)])
@testset "scalar text" begin
    src = csource("scalartext", math32, fmod_, pie, irrationals)
    @test occursin("sqrtf(x) + fabsf(-x) + maxNF32(x, 1.0f) + powf(x, 0.5f) + expf(x) + rintf(x)", src) && occursin("+ fmodf(x, 0.7f);", src)   # float math is the `f` family
    @test occursin("return modulo(a, b);", src) && occursin("static inline double modulo(double x, double y) {", src) && occursin("    double r = fmod(x, y);", src)   # Julia 1.13 puts a rule for an infinite divisor first
    @test occursin("return x * LEGIBLEC_PI + LEGIBLEC_E;", src) && !occursin("M_PI", src)   # π and ℯ are our own macros, defined in the file
    # Every irrational is a macro named after it, to 128-bit precision, in the helper header.
    @test occursin(r"#define LEGIBLEC_E 2\.718281828459045\d+  // ℯ to 128-bit precision\n#define LEGIBLEC_GAMMA 0\.577215664901532\d+  // γ to 128-bit precision\n#define LEGIBLEC_PI 3\.141592653589793\d+  // π to 128-bit precision\n#define LEGIBLEC_TWOPI 6\.283185307179586\d+  // twopi to 128-bit precision\n", src)
    @test occursin("#define LEGIBLEC_CATALAN 0.915965594177219", src) && occursin("return x * LEGIBLEC_CATALAN + LEGIBLEC_GAMMA - LEGIBLEC_TWOPI;", src)
    root = csource("rooted", rooted)
    @test occursin("return x * LEGIBLEC_ROOT2;", root) && occursin("#define LEGIBLEC_ROOT2 1.41421356237309504880168872420969798  // Root2 to 128-bit precision", root) && !occursin("typedef", root)
    phi = csource("phis", phis)
    @test occursin("return x * LEGIBLEC_PHI + LEGIBLEC_PHI_;", phi) && occursin("#define LEGIBLEC_PHI 1.61803398874989484820458683436563816  // φ to 128-bit precision\n#define LEGIBLEC_PHI_ 1.5  // ϕ to 128-bit precision", phi)
    # `posix`: the POSIX names, not ISO C; a file that uses one defines it if <math.h> didn't (glibc under -std=c11).
    posix = csource("posix", pie; posix=true)
    @test occursin("return x * M_PI + M_E;", posix) && occursin("#include <math.h>", posix)
    @test occursin(r"#ifndef M_PI\n#define M_PI 3\.141592653589793\d+  // not in ISO C; absent under a strict -std=c11\n#endif", posix) && occursin("#ifndef M_E\n", posix)
    sc = csource("sincos", sincos_, sincos32, picked)
    @test occursin("    double s = sin(x);\n    double c = cos(x);\n", sc) && occursin("return s * c;", sc)   # exactly as sin and cos written separately
    @test occursin("    float s = sinf(2 * x);\n    float c = cosf(2 * x);", sc) && occursin("return cos(x);", sc)
    @test_throws ArgumentError csource("keptpair", kept)                                  # the pair itself is not a value
end

# One C type per variable (`onetype!`): a union of numbers widens to the one holding
# them all, and anything else is refused by name and line.
accum(v::SVector{3,Float64}) = (s = 0; for x in v; s += x; end; s)
function joined(x::Float64, c::Bool)
    a = 5
    if c
        a = 2.5
    end
    return a * x
end
function widened(c::ComplexF64)
    z = 0
    for i in 1:3
        z = z^2 + c
    end
    return z
end
function reuse(x::Float64)
    a = 5
    b = a + 1
    a = SVector(3.0, 4.0)
    return a[1] * x + b
end
floated(n::Int64, x::Float64) = float(n) + float(x)
zeroed(r::Float64) = r > 0 ? r : 0                   # a union of numbers returned: a double
pick(x::Int64) = 1.0
pick(x::Float64) = 2.0
twice(x) = 2x
function bypath(c::Bool)                              # a widened variable reaching a function: only if the method is the same
    a = 5
    if c
        a = 2.5
    end
    return pick(a)
end
function samepath(c::Bool)
    a = 5
    if c
        a = 2.5
    end
    return twice(a)
end
signs(x::Float64, y::Float64) = x * y > 0 ? x + y : "mixed"   # a number or a string: refused by name and line
check("onetype", [Case(accum, SVector(1.5, 2.5, 3.0)), Case(joined, 2.0, true), Case(joined, 2.0, false), Case(widened, ComplexF64(0.1, 0.2)), Case(floated, 3, 0.5),
                  Case(zeroed, 1.5), Case(zeroed, -1.5), Case(samepath, true), Case(samepath, false)])
@testset "onetype" begin
    src = csource("onetype", accum, joined, widened, floated, zeroed)
    @test occursin("double s = 0.0;", src) && occursin("s += x;", src)
    @test occursin("double a = 5.0;", src) && occursin("a = 2.5;", src)
    @test occursin("double complex z = 0;", src) && occursin("z = z * z + c;", src)
    @test occursin("return (double)n + x;", src)
    @test_throws ArgumentError csource("reuse", reuse)
    @test occursin("`a` is assigned values of different types (Int64 at line", sprint(showerror, try csource("reuse", reuse) catch e; e end))
    @test occursin("double zeroed(double r)", src) && occursin("return 0;", src)
    msg = sprint(showerror, try csource("bypath", bypath) catch e; e end)
    @test occursin("`a` is a ", msg) && occursin("on one path and a ", msg) && occursin("which method of `pick` runs depends on which", msg)
    msg = sprint(showerror, try csource("signs", signs) catch e; e end)
    @test occursin("`signs` returns values of different types from the same argument types (Float64 at line", msg) && occursin("String at line", msg) && occursin("one return type", msg)
end
# Scalar functions that are one C expression of their arguments, each a row of one table
# (`src/idiom.jl`), and the few that are a small helper reached through it.
parity(k::Int64) = (isodd(k) ? 1 : 0) + (iseven(k + 1) ? 10 : 0) + (isodd(k * 3) ? 100 : 0)
parity32(k::Int32) = isodd(k) && !iseven(k)
recip(x::Float64, k::Int64) = inv(x) + inv(k) + inv(x + 1.0)
recip32(x::Float32) = inv(x)
angles(d::Float64) = deg2rad(d) + rad2deg(d / 100) + deg2rad(d + 1.0)
shifts(a::Int64, n::Int64) = (a >>> n) + (a >>> 3)
ushifts(a::UInt32, n::Int64) = a >>> n
gap(x::Float64) = eps(x) + eps(2.0x) + eps(x * x + 1.0)
gap32(x::Float32) = eps(x)
gapmax(x::Float64) = eps(x)                                       # finite at the largest float, where the next one up is Inf
choose(c::Bool, a::Int64, b::Int64) = ifelse(c, a, b) + ifelse(a > b, a - b, b - a)
divisors(a::Int64, b::Int64) = gcd(a, b) + 1000 * lcm(a, b)
divisors32(a::Int32, b::Int32) = gcd(a, b) + lcm(a, b)
gcdonly(a::Int64, b::Int64) = gcd(a, b)                           # the one value with no negative
roots(n::Int64) = isqrt(n) + isqrt(n + 1)
degrees(x::Float64) = sind(x) + 10.0 * cosd(x) + 100.0 * tand(x / 4)
# Julia's are exact at the multiples of 90, which `sin(x * π / 180)` is not.
exact(x::Float64) = (sind(x) == 0.0 ? 1 : 0) + (cosd(x) == 0.0 ? 10 : 0) + (sind(x) == 1.0 ? 100 : 0) + (cosd(x) == -1.0 ? 1000 : 0)
least() = typemin(Int64) + 1                                      # C has no negative literals
function ordered(a::Float64, b::Float64); lo, hi = minmax(a, b); return hi - 2.0 * lo; end
function orderedexpr(a::Int64, b::Int64); lo, hi = minmax(a * 2, b + 1); return hi - 2 * lo; end   # each argument is written twice: never in place
keptpair(a::Int64, b::Int64) = (t = minmax(a, b); t[2] - t[1])
consts(x::Float64) = (ℯ, x * π, π)                               # an irrational held as a value is the double it is a macro for
# `throw`, `error`, `@assert`: the exception's name and what it was made from on `stderr`, and
# `abort()`. Only inputs that don't throw are compared with Julia: Julia that throws never reaches C.
function guarded(n::Int64, x::Float64)
    n < 0 && throw(ArgumentError("n must not be negative"))
    x < 0.0 && throw(DomainError(x, "needs a nonnegative number"))
    n > 50 && error("much too big: $n for $x")
    @assert n != 7 "seven"
    @assert x != 7.0
    return n + sqrt(x)
end
@testset "idiom" begin
    cases = [[Case(parity, k) for k in (-3, -2, 0, 1, 8)]; Case(parity32, Int32(-3)); Case(parity32, Int32(4));
             Case(recip, 4.0, 8); Case(recip, -0.5, -3); Case(recip32, 4.0f0);
             [Case(angles, d) for d in (0.0, 90.0, 180.0, -37.5)];
             [Case(shifts, a, n) for a in (-16, 1024, -1) for n in (0, 2, 63)]; Case(ushifts, 0xf0000000, 4);
             [Case(gap, x) for x in (0.0, 1.0, -3.7, 1e300, 5e-324, 2.0^-1040)]; Case(gapmax, floatmax(Float64)); Case(gapmax, -floatmax(Float64)); Case(gap32, 1.5f0);
             [Case(choose, c, a, b) for c in (true, false) for (a, b) in ((3, 9), (9, 3))];
             [Case(divisors, a, b) for (a, b) in ((12, 18), (-12, 18), (12, -18), (0, 5), (5, 0), (0, 0), (17, 5), (-7, -21))];
             Case(divisors32, Int32(12), Int32(-18)); Case(gcdonly, typemin(Int64), -1); Case(gcdonly, 6, typemin(Int64));
             [Case(roots, n) for n in (0, 1, 15, 16, 17, 4503599761588224, 9223372030926249000, 9223372036854775806)];
             [Case(degrees, x) for x in (0.0, 30.0, 45.0, 60.0, 135.0, 180.0, 200.0, 225.0, 300.0, 315.0, 350.0, 720.5, -30.0, -200.0, -300.0, 1e6 + 0.25)];
             [Case(exact, x) for x in (0.0, 90.0, 180.0, 270.0, 360.0, -90.0, -180.0, 450.0, 30.0)]; Case(least);
             Case(ordered, 3.0, 1.0); Case(ordered, 1.0, 3.0); Case(orderedexpr, 3, 1); Case(orderedexpr, 1, 9);
             Case(consts, 2.0); Case(guarded, 4, 9.0)]
    check("idiom", cases)
    src = csource("idiomtext", parity, recip, angles, shifts, gap, choose, least)
    @test occursin("(k % 2 != 0 ? 1 : 0) + ((k + 1) % 2 == 0 ? 10 : 0)", src)
    @test occursin("return 1.0 / x + 1.0 / k + 1.0 / (x + 1.0);", src)
    @test occursin("d * (LEGIBLEC_PI / 180)", src) && occursin("* (180 / LEGIBLEC_PI)", src)
    @test occursin("shru(a, n) + (int64_t)((uint64_t)a >> 3)", src)      # a count that could be anything goes through Julia's rule; a literal in range is C's shift
    @test occursin("return ulp(x) + ulp(2.0 * x) + ulp(x * x + 1.0);", src)      # a helper: the gap is still finite at the largest float
    @test occursin("(c ? a : b) + (a > b ? a - b : b - a)", src)
    @test occursin("return INT64_MIN + 1;", src)
    src = csource("guardedtext", guarded, consts)
    @test occursin("if (n < 0) {\n        fprintf(stderr, \"ArgumentError: n must not be negative\\n\");\n        abort();\n    }", src)
    @test occursin("fprintf(stderr, \"DomainError: %g, needs a nonnegative number\\n\", x);", src)
    @test occursin("fprintf(stderr, \"ERROR: much too big: %lld for %g\\n\", (long long)n, x);", src)
    @test occursin("if (n == 7) {\n        fprintf(stderr, \"AssertionError: seven\\n\");", src)      # `@assert c`: the opposite test, no empty branch
    @test occursin("if (x == 7.0) {\n        fprintf(stderr, \"AssertionError: x != 7.0\\n\");", src)
    @test occursin("LEGIBLEC_E", src) && occursin("x * LEGIBLEC_PI", src)
    @test occursin("is only available destructured", sprint(showerror, try csource("keptpair", keptpair) catch e; e end))
end
# Every refusal leaves the same way: what it is, then the function, the file and line, and
# the Julia line itself. A statement's number, which is the transpiler's, never shows.
nocode(x::Float64, k::Int64) = x * exp10(k)
@testset "refusal" begin
    msg = sprint(showerror, try csource("nocode", nocode) catch e; e end)
    @test occursin("`exp10(::Int64)` has no C yet", msg) && !occursin("statement", msg)
    @test occursin("in `nocode`, scalar.jl:", msg) && occursin("nocode(x::Float64, k::Int64) = x * exp10(k)", msg)
    # A mistake of the transpiler's own says so, names where it was, and keeps the error underneath.
    mi = Base.method_instance(nocode, (Float64, Int64))
    fault = LegibleC.explained(KeyError(:gone), mi, nothing)
    @test fault isa LegibleC.Fault && occursin("the transpiler went wrong in `nocode`, scalar.jl:", fault.msg) && occursin("KeyError", fault.msg)
    @test LegibleC.explained(fault, mi, nothing) === fault
end

# Found on 2026-09-21 by readers who attacked the code on paper and wrote what they expected to break:
# each of these compiled and answered wrongly, or did not compile, or was refused for no reason.
idiommaxthree(a::Int64, b::Int64, c::Int64) = max(a, b, c) + 100 * min(a, b, c)
idiomminthreefloat(a::Float64, b::Float64, c::Float64) = min(a, b, c)
idiommaxmixed(x::Float32, y::Float64) = max(x, y)
idiompowmixed(x::Float32, y::Float64) = x ^ y
idiomdivfloat(x::Float64, y::Float64) = div(x, y)
idiommodunsigned(a::UInt64, b::UInt64) = mod(a, b)
idiomnarrownot(a::UInt8) = (~a) >>> 2
idiomnarrowshift(a::UInt8, b::UInt8) = (a + b) >>> 1
idiomstore!(v::MVector{3,Float64}, k::Float64) = (v[1] = k; k)
function idiomifelseeffect(c::Bool, v::MVector{3,Float64})
    x = ifelse(c, idiomstore!(v, 7.0), 1.0)
    return x + v[1]
end
idiomisqrtwrap(n::UInt32) = isqrt(n)
function idiomminmaxself(a::Float64, b::Float64)
    a, b = minmax(a, b)
    return a + 10.0 * b
end
function idiomminmaxlocal(p::Int64, q::Int64)
    lo = p * 2
    hi = q + 1
    lo, hi = minmax(lo, hi)
    return hi - 3 * lo
end
function lowerhalf(n::Int64)
    n = n / 2
    return n + 1
end
idiomdivsigned(a::Int64, b::UInt64) = div(a, b)
idiomsigncompare(a::Int64, b::UInt64) = a < b
function choicesignmix(c::Bool, a::Int64, u::UInt64)
    return Float64(c ? a : u)
end
@testset "hunt" begin
    check("huntscalar", [Case(idiommaxthree, 1, 2, 9), Case(idiommaxthree, 5, 4, -3), Case(idiommaxthree, 9, 2, 1),
        Case(idiomminthreefloat, 3.0, 2.0, 1.0), Case(idiomminthreefloat, 1.0, 2.0, 3.0),
        Case(idiommaxmixed, 1.0f0, 2.123456789), Case(idiommaxmixed, 3.0f0, 2.123456789), Case(idiommaxmixed, -1.0f0, -0.3333333333333333),
        Case(idiompowmixed, 1.5f0, 2.123456789), Case(idiompowmixed, 2.0f0, 0.3333333333333333),
        Case(idiomdivfloat, 7.5, 2.0), Case(idiomdivfloat, -7.5, 2.0), Case(idiomdivfloat, 8.0, 2.0), Case(idiomdivfloat, 1.0, 3.0),
        Case(idiommodunsigned, 0x8000000000000004, 0x8000000000000005), Case(idiommodunsigned, UInt64(7), UInt64(3)), Case(idiommodunsigned, 0xfffffffffffffffe, 0xffffffffffffffff),
        Case(idiomnarrownot, UInt8(15)), Case(idiomnarrownot, UInt8(0)), Case(idiomnarrownot, UInt8(255)),
        Case(idiomnarrowshift, UInt8(200), UInt8(100)), Case(idiomnarrowshift, UInt8(3), UInt8(4)), Case(idiomnarrowshift, UInt8(255), UInt8(255)),
        Case(idiomifelseeffect, false, MVector(0.5, 0.0, 0.0)), Case(idiomifelseeffect, true, MVector(0.5, 0.0, 0.0)),
        Case(idiomisqrtwrap, 0xfffe0001), Case(idiomisqrtwrap, 0xfffe0000), Case(idiomisqrtwrap, UInt32(17)),
        Case(idiomminmaxself, 5.0, 3.0), Case(idiomminmaxself, 1.0, 2.0), Case(idiomminmaxself, -4.0, -9.0),
        Case(idiomminmaxlocal, 5, 2), Case(idiomminmaxlocal, 1, 7), Case(idiomminmaxlocal, 3, 5),
        Case(lowerhalf, 5), Case(lowerhalf, -3), Case(lowerhalf, 4)])
    @test_throws ArgumentError csource("idiomdivsigned", idiomdivsigned)
    @test_throws ArgumentError csource("idiomsigncompare", idiomsigncompare)
    @test_throws ArgumentError csource("choicesignmix", choicesignmix)
end

# What a declared type puts in, and what Julia has already decided: `x::Float64 = 1` converts, which is a
# cast; `(x * 2.0)::Float64` asserts, which is nothing; `n isa Int64` on an `Int64` is no test at all, and the
# `else` that can't run is no part of the C. `@fastmath x^2` is still `x * x`.
asserted(x::Float64) = (x * 2.0)::Float64 + 1.0
declared(n::Int64)::Float64 = n + 1
converted(n::Int64, x::Float64) = convert(Float64, n) / 2 + convert(Int64, x * 4.0)
fastsq(x::Float64) = @fastmath x^2 + 1.0
function staticn(v::SVector{3,Float64})
    s = 0.0
    for k in 1:3
        s += v[k] * k
    end
    return s / 3
end
pickT(x::Float64) = x / 2
absu(a::UInt8, b::Int16) = abs(a) + abs(b)
bigroot(n::UInt64) = isqrt(n)
bigroot32(n::UInt32) = isqrt(n)
function lowerlocalint(x::Float64, n::Int64)
    local acc::Float64 = 0
    for k in 1:n
        acc = acc + x * k
    end
    return acc
end
lowerintlevel::Float64 = 0.0
function lowerglobalint(n::Int64)
    global lowerintlevel = n
    global lowerintlevel += 0.5
    return lowerintlevel
end
function lowerstaticmean(v::SVector{N,Float64}) where {N}
    s = 0.0
    for k in 1:N
        s += v[k]
    end
    return s / N
end
lowerstaticn(v::SVector{3,Float64}) = lowerstaticmean(v) + 1.0
function lowerisabreak(x::Float64, n::Int64)
    s = 0.0
    for k in 1:n
        s += x
        if s > 2.5
            s += 100.0
            x isa Float64 && break
        end
    end
    return s
end
function treeisaelse(x::Float64, n::Int64)
    if n isa Int64
        y = x + n
    else
        y = x
    end
    return 2.0 * y
end
function treelocalint(n::Int64)
    local acc::Float64 = 0
    for k in 1:n
        acc = acc + k / 2
    end
    return acc
end
@testset "declared" begin
    check("declared", [Case(asserted, 1.5), Case(declared, 3), Case(converted, 3, 2.5), Case(fastsq, 3.0), Case(staticn, SVector(1.0, 2.0, 3.0)),
                 Case(pickT, 3.0), Case(absu, 0xf0, Int16(-300)), Case(bigroot, typemax(UInt64)), Case(bigroot, 0xfffffffe00000001), Case(bigroot, 0xfffffffe00000000),
                 Case(bigroot32, typemax(UInt32)), Case(bigroot32, 0xfffe0001),
        Case(lowerlocalint, 1.5, 3), Case(lowerlocalint, 2.0, 0),
        Case(lowerglobalint, 3), Case(lowerglobalint, -2),
        Case(lowerstaticn, SVector(1.0, 2.0, 6.0)), Case(lowerstaticn, SVector(-1.0, 0.5, 0.0)),
        Case(lowerisabreak, 1.0, 5), Case(lowerisabreak, 1.0, 2), Case(lowerisabreak, 3.0, 1),
        Case(treeisaelse, 1.5, 2), Case(treeisaelse, -3.0, 0),
        Case(treelocalint, 4), Case(treelocalint, 0)])
end

# Found by the critic who looked for what the other readers had not attacked (2026-09-21).
gapboolnot(a::Bool, b::Bool) = (~a | b) ? 1 : 2
gapclassify32(x::Float32) = (isnan(x) ? 1 : 0) + (isfinite(x) ? 4 : 0) + (signbit(x) ? 8 : 0)
gapifelsebit(n::Int64, m::Int64, x::Float64, y::Float64) = ifelse((n > 0) | (m > 0), x, y) + 1.0
gapshiftlit(k::Int64) = 1 << k
function gapsincosexpr(x::Float64)
    x, c = sincos(2.0x)
    return x + 10.0c
end
gapwidenlit(ms::UInt32) = ms * 1000 + 1
gapfastpow(x::Float64) = @fastmath x^2 + 1.0
gapifelsesign(c::Bool, a::Int64, u::UInt64) = Float64(ifelse(c, a, u))
function gapsignvar(c::Bool, u::UInt64)
    best = -1
    if c
        best = u
    end
    return Float64(best)
end
@testset "gap" begin
    check("gapscalar", [Case(gapboolnot, true, false), Case(gapboolnot, false, false), Case(gapboolnot, true, true),
        Case(gapclassify32, 1.5f0), Case(gapclassify32, -2.0f0), Case(gapclassify32, NaN32), Case(gapclassify32, Inf32),
        Case(gapifelsebit, 1, 0, 2.0, 5.0), Case(gapifelsebit, 0, 1, 2.0, 5.0), Case(gapifelsebit, 0, 0, 2.0, 5.0),
        Case(gapshiftlit, 3), Case(gapshiftlit, 31), Case(gapshiftlit, 40), Case(gapshiftlit, 62),
        Case(gapsincosexpr, 0.7), Case(gapsincosexpr, -1.2), Case(gapsincosexpr, 0.0),
        Case(gapwidenlit, UInt32(5000000)), Case(gapwidenlit, UInt32(7)), Case(gapwidenlit, 0xffffffff),
        Case(gapfastpow, 3.0), Case(gapfastpow, -1.5)])
    @test_throws ArgumentError csource("gapifelsesign", gapifelsesign)
    @test_throws ArgumentError csource("gapsignvar", gapsignvar)
end

# An expression has two types, Julia's and the one C computes it in (`src/term.jl`). These are
# the places where the two differ and a value can tell, each one step to the side of a rule
# that looked at Julia's type alone (2026-09-21).
twoinner(a::UInt8) = (a + 1) * 100000000                   # `a + 1` is an `int` in C, and the product outgrows it
twochain(a::UInt8, b::UInt8, n::Int64) = a + b + n         # two `UInt8` wrap at 256 before the `Int64` is added
twoproduct(a::Int32, b::Int32) = a * b * 1000              # the `Int32` product wraps before it is widened
twomod(a::Int8) = mod(a, 3) * 2000000000                   # the `mod` idiom is an `int` in C
twopick(c::Bool) = ifelse(c, 1, 2) * 2000000000            # so is a choice between two literals
twoabove(u::UInt32) = u > -1                               # C's `-1` is an `int`, converted to unsigned beside a `uint32_t`
twosame(u::UInt32) = u == -1
twounder(u::UInt32, k::Int32) = k < u                      # a type that holds both: `int64_t`
twoleast(u::UInt32) = max(u, -1)
twoover(u::UInt32, m::Int8) = u > m                        # `m` is promoted to `int`, then converted to unsigned: `(int64_t)u > m`
twomost(u::UInt32, k::Int32) = max(u, k)                   # Julia converts both to `UInt32`, and so does the C, said out loud
twoquot(a::Int32) = div(a, -1)                             # the least `Int32` by -1 fits Julia's `Int64`, and overflows C's `int`
twofloat(n::Int32, x::Float32) = (n == x) + 2 * (n < x)    # beside a `float` an integer is exact to 2^24 only
twobits(a::Int8, b::UInt8) = (a | b) + 1000                # `Int8(-1) | 0x03` is `0xff` in Julia and -1 in C's `int`
twonot(a::UInt8) = ~a + 1000
twoindex(v::SVector{4, Float64}, i::Int64) = v[i + 1] + v[i - 1]
twowide(u::UInt64, k::Int64) = k < u
function twobound(n::Int32)
    s = 0
    for k in 1:Int64(n)                                    # a cast is not a call: it stays in the header
        s += k
    end
    return s
end
@testset "two types" begin
    src = check("twotypes", [Case(twoinner, 0xff), Case(twoinner, 0x30), Case(twochain, 0xff, 0xff, 5), Case(twochain, 0x01, 0x02, -5),
        Case(twoproduct, Int32(100000), Int32(100000)), Case(twoproduct, Int32(3), Int32(-4)),
        Case(twomod, Int8(5)), Case(twomod, Int8(-5)), Case(twopick, true), Case(twopick, false),
        Case(twoabove, 0x00000005), Case(twoabove, 0xffffffff), Case(twosame, 0xffffffff), Case(twosame, 0x00000001),
        Case(twounder, 0x00000005, Int32(-1)), Case(twounder, 0xffffffff, Int32(7)), Case(twounder, 0x00000003, Int32(7)),
        Case(twoleast, 0x00000005), Case(twoleast, 0xffffffff), Case(twoover, 0x00000005, Int8(-1)), Case(twoover, 0x00000005, Int8(9)), Case(twomost, 0x00000005, Int32(9)), Case(twomost, 0xfffffff0, Int32(9)),
        Case(twoquot, typemin(Int32)), Case(twoquot, Int32(7)),
        Case(twofloat, Int32(16777217), 16777216f0), Case(twofloat, Int32(3), 3f0), Case(twofloat, Int32(-16777217), -16777216f0),
        Case(twobits, Int8(-1), 0x03), Case(twobits, Int8(5), 0x03), Case(twonot, 0x00), Case(twonot, 0xff),
        Case(twoindex, SVector(1.0, 2.0, 3.0, 4.0), 2), Case(twobound, Int32(10))])
    @test occursin("return (int64_t)(a + 1) * 100000000;", src)
    @test occursin("return (uint8_t)(a + b) + n;", src)
    @test occursin("return (int64_t)(a * b) * 1000;", src)
    @test occursin("return (int64_t)(((a % 3) + 3) % 3) * 2000000000;", src)
    @test occursin("return (int64_t)(c ? 1 : 2) * 2000000000;", src)
    @test occursin("bool twoabove(uint32_t u) {\n    // @scalar.jl", src) && occursin("return true;", src) && occursin("return false;", src)   # what the types alone decide
    @test occursin("return k < (int64_t)u;", src) && occursin("return (int64_t)u > m;", src)
    @test occursin("int64_t twoleast(uint32_t u) {", src) && occursin("return (int64_t)u;", src)
    @test occursin("return (u > (uint32_t)k ? u : (uint32_t)k);", src)
    @test occursin("return (int64_t)a / -1;", src)
    @test occursin("((double)n == x) + 2 * ((double)n < x)", src)
    @test occursin("return (uint8_t)(a | b) + 1000;", src) && occursin("return (uint8_t)~a + 1000;", src)
    @test occursin("return v[i] + v[i - 2];", src)                        # the shift folds into the literal the index has
    @test occursin("for (int64_t k = 1; k <= (int64_t)n; k++) {", src)
    # No type holds both a `UInt64` and a negative number: refused, as it was.
    @test_throws ArgumentError csource("twowide", twowide)
end

# `factorial` of an integer is a table, as Julia's is, and `gamma` is `math.h`'s `tgamma`
# (2026-10-04). `gamma` is `SpecialFunctions`', known to the transpiler by name.
fact(n::Int64) = factorial(n)
factsmall(n::UInt8) = factorial(n) + 1
factwide(n::UInt64) = factorial(n)
binomial5(k::Int64) = div(factorial(5), factorial(k) * factorial(5 - k))
gammaof(x::Float64) = Main.SpecialFunctions.gamma(x)
gammasingle(x::Float32) = Main.SpecialFunctions.gamma(x)
gammaint(n::Int64) = Main.SpecialFunctions.gamma(n)
errors(x::Float64) = Main.SpecialFunctions.erf(x) + 2.0 * Main.SpecialFunctions.erfc(x) + Main.SpecialFunctions.loggamma(x + 3.0)
@testset "factorial and gamma" begin
    src = check("factorial", [(Case(fact, n) for n in (0, 1, 2, 5, 12, 13, 19, 20))..., Case(factsmall, 0x05), Case(factwide, UInt64(20)),
                              (Case(binomial5, k) for k in 0:5)...,
                              (Case(gammaof, x) for x in (0.5, 1.0, 4.5, 10.0, -1.5, 170.0))..., Case(gammasingle, 4.5f0), Case(gammaint, 6),
                              Case(errors, 0.3), Case(errors, -1.2)])
    @test occursin("return factorial(n);", src) && occursin("return factorial(n) + 1;", src) && occursin("return factorialU64(n);", src)
    @test occursin("return tgamma(x);", src) && occursin("return tgammaf(x);", src) && occursin("return tgamma(n);", src)
    @test occursin("erf(x) + 2.0 * erfc(x) + lgamma(x + 3.0)", src)
    helper = csource("factorialtext", fact)
    @test occursin("static const int64_t table[] = {\n                          1,    // 0!\n                          1,    // 1!\n                          2,    // 2!", helper)     # a line each, lined up on the units
    @test occursin("        121645100408832000,    // 19!\n        2432902008176640000     // 20!\n    };", helper)
    @test occursin("if (n > 20) {", helper) && occursin("return table[n];", helper)
end

# An integer power by squaring, for every kind of number (2026-10-04): one definition, in
# Julia, translated for the type. An integer to a power known only at run time was refused.
powint(n::Int64, m::Int64) = n^m
powtwo(n::Int64) = 2^n
powsmall(n::Int32, m::Int64) = n^m
powunsigned(n::UInt64, m::Int64) = n^m
powcomplex(z::ComplexF64, n::Int64) = Base.power_by_squaring(z, n)
powliteral(x::Float64) = x^13 + x^-5
powliteral32(x::Float32) = x^7
@testset "integer power" begin
    src = check("powi", [(Case(powint, b, e) for (b, e) in ((3, 0), (3, 1), (3, 13), (-2, 5), (-2, 62), (7, 22), (1, -4), (-1, -3)))...,
                         (Case(powtwo, e) for e in (0, 1, 10, 62, 63))..., Case(powsmall, Int32(3), 20), Case(powsmall, Int32(-7), 3),
                         Case(powunsigned, UInt64(3), 40), Case(powcomplex, 0.6 + 0.8im, 5), Case(powcomplex, 1.5 - 0.5im, 0),
                         Case(powliteral, 1.3), Case(powliteral, -0.7), Case(powliteral32, 1.3f0)])
    @test occursin("return powiI64(n, m);", src) && occursin("return powiI64(2, n);", src) && occursin("return powiI32(n, m);", src) && occursin("return powiU64(n, m);", src)
    @test occursin("return powiC64(z, n);", src) && occursin("powi(x, 13) + powi(x, -5)", src) && occursin("powiF32(x, 7)", src)
    helper = csource("powitext", powliteral, powint)
    @test occursin("static inline double powi(double x, int64_t n) {\n    if (n < 0) {\n        x = 1.0 / x;\n        n = -n;\n    }\n    if (n == 0) {\n        return 1.0;\n    }", helper)
    @test occursin("static inline int64_t powiI64(int64_t x, int64_t n) {\n    if (n == 0) {\n        return 1;\n    }", helper)       # no inverse for an integer, as in Julia
    @test occursin("    while (n % 2 == 0) {\n        x *= x;\n        n >>= 1;\n    }\n    double y = x;", helper)
end

# A cast is never applied to a number written out (2026-10-04): the number is written as the
# type instead, `2.0` and not `(double)2`. One rule, in `cast`, whoever asked for the conversion.
litdivide(n::Int64) = n / 2 + 2 / n
function litdeclared(x::Float64)
    y::Float64 = 3
    return x * y
end
litwritten(x::Float64) = x + Float64(2)
litfloat(x::Float64) = x - float(2)
litsingle(y::Float32) = y * Float32(3)
littruth(x::Float64) = x + Float64(true)
litvariable(n::Int64) = Float64(n) + 1          # a variable is cast, as it was
function litfixed(x::Float64)
    v = @MVector [1.0, 2.0, 3.0]                # written below: an ordinary array
    v[1] = x
    w = SVector(1.0, x, 3.0)                    # holds a variable: built each time
    u = SVector(1.0, 2.0, 3.0)                  # numbers, never written: fixed
    return v[1] + w[2] + u[3]
end
litreturn(n::Int64)::Float64 = n + 1
@testset "literal as its type" begin
    src = check("literal", [Case(litdivide, 3), Case(litdeclared, 1.5), Case(litwritten, 1.5), Case(litfloat, 1.5), Case(litsingle, 1.5f0), Case(littruth, 1.5), Case(litvariable, 4)])
    @test occursin("return (double)n / 2.0 + 2.0 / (double)n;", src) && occursin("    double y = 3.0;\n", src) && !occursin("temp1", src)             # one line for one line
    @test occursin("return x + 2.0;", src) && occursin("return x - 2.0;", src) && occursin("return y * 3.0f;", src) && occursin("return x + 1.0;", src)
    @test occursin("return (double)n + 1;", src)
    @test !occursin(r"\((double|float)\)-?[0-9]", src) && !occursin("(double)true", src)                # no cast of a literal anywhere
    # An array of numbers written out and never written again is `static const`, whatever its size.
    src = csource("fixed", litfixed)
    @test occursin("static const double u[3] = {1.0, 2.0, 3.0};", src) && occursin("    double v[3] = {1.0, 2.0, 3.0};", src) && occursin("    double w[3] = {1.0, x, 3.0};", src)
    @test occursin("return (double)(n + 1);", csource("declaredreturn", litreturn))            # a declared return type: one line too
end
# The everyday functions that are one C expression or a few lines: each is a row of the table in
# `src/idiom.jl`, which the grid tries on every type. Here, how they read, and the ones that
# take what the grid has no values for: a rounding mode, a type, a tuple, two values at once.
udivrem(a::Int, b::Int) = ((q, r) = divrem(a, b); 10q + r)
ufldmod(a::Int, b::Int) = ((q, r) = fldmod(a, b); 10q + r)
usincosd(x::Float64) = ((s, c) = sincosd(x); s + 2c)
umodf(x::Float64) = ((f, i) = modf(x); f + 10i)
umodfof(x::Float64, y::Float64) = ((f, i) = modf(x * y + 1); f - i)
ufrexp(x::Float64) = ((m, e) = frexp(x); m + e)
ufrexp32(x::Float32) = ((m, e) = frexp(x); m + e)
uhorner(x::Float64) = evalpoly(x, (1.0, 2.0, 3.0))
uhornerof(x::Float64, a::Float64, b::Float64) = evalpoly(x + 1, (a, b - 1, 2.0, a * b))
utrunc(x::Float64) = unsafe_trunc(Int64, x)
uorder(a::Int, b::Int) = isless(a, b) + 2 * isequal(a, b)
urounded(x::Float64) = round(x, RoundUp) + round(x, RoundDown) * 10 + round(x, RoundToZero) * 100 + round(x, RoundNearestTiesAway) * 1000
ulogbase(x::Float64) = log(2.0, x) + log(10, x)
ulogfactorial(n::Int) = Main.SpecialFunctions.logfactorial(n)
uclamp(x::Float64) = clamp(x, 0.0, 1.0)
uclampint(n::Int) = clamp(n, -3, 3)
uapprox(x::Float64, y::Float64) = x ≈ y
usign(x::Float64) = sign(x) + abs2(x)
uexponent(x::Float64) = exponent(x) + significand(x)
ubits(n::Int) = count_ones(n) + 100 * leading_zeros(n) + 10000 * trailing_zeros(n)
unumber(n::Int, k::Int) = binomial(n, k) + powermod(n, k, 1000) + nextpow(2, n) + prevpow(3, n)
uhyperbolic(x::Float64) = asinh(x) + acosh(x + 2) + atanh(x / 4) + sec(x) + coth(x) + asec(x + 2)
ufused(x::Float64, y::Float64) = fma(x, y, 1.0) + muladd(x, y, 2.0) + hypot(x, y, 3.0) + ldexp(x, 3) + nextfloat(x) - prevfloat(x)
udegrees(x::Float64) = asind(x / 40) + atand(x, 2.0) + secd(x)
ufloor(a::Int, b::Int) = fld(a, b) + 10 * cld(a, b) + 100 * mod1(a, b) + 1000 * fld1(a, b)
@testset "everyday functions" begin
    src = check("everyday", [Case(udivrem, 17, 5), Case(udivrem, -17, 5), Case(ufldmod, -17, 5), Case(usincosd, 30.0), Case(umodf, 2.75), Case(umodf, -2.75), Case(umodf, Inf),
                             Case(umodfof, 1.5, 2.5), Case(ufrexp, 12.0), Case(ufrexp, 0.0), Case(ufrexp, Inf), Case(ufrexp32, 12f0), Case(uhorner, 2.0), Case(uhornerof, 1.5, 2.0, 3.0),
                             Case(utrunc, -2.7), Case(uorder, 1, 2), Case(uorder, 2, 2), Case(urounded, 2.5), Case(urounded, -2.5), Case(ulogbase, 8.0), Case(ulogfactorial, 10),
                             Case(uclamp, 1.5), Case(uclamp, -0.5), Case(uclamp, 0.25), Case(uclampint, 7), Case(uapprox, 1.0, 1.0 + 1e-10), Case(uapprox, 1.0, 1.1),
                             Case(usign, -2.5), Case(uexponent, 12.0), Case(ubits, 40), Case(unumber, 10, 3), Case(uhyperbolic, 0.5), Case(ufused, 1.5, 2.5),
                             Case(udegrees, 30.0), Case(ufloor, -17, 5), Case(ufloor, 17, -5), Case(ufloor, 15, 5)])
    # Two values at once: each is written where it is read, from what Julia's own two functions give.
    @test occursin("int64_t q = (a / b);", src) && occursin("int64_t q = fld(a, b);", src) && occursin("double s = sind(x);\n    double c = cosd(x);", src)
    @test occursin("double f = copysign(isinf(x) ? 0 : x - trunc(x), x);\n    double i = trunc(x);", src)
    @test occursin(r"double (temp\d+) = x \* y \+ 1;\n    double f = copysign\(isinf\(\1\)", src)          # what is read three times is worked out once
    @test occursin(r"int (temp\d+);\n    double (temp\d+) = frexp\(x, &\1\);", src) && occursin("frexpf(x, &", src)
    # Horner's rule, written out; the point it is evaluated at worked out once.
    @test occursin("return 1.0 + x * (2.0 + x * 3.0);", src) && occursin(r"return a \+ (temp\d+) \* \(b - 1 \+ \1 \* \(2\.0 \+ \1 \* \(a \* b\)\)\);", src)
    @test occursin("return (int64_t)x;", src) && occursin("return (a < b) + 2 * (a == b);", src)
    @test occursin("return ceil(x) + floor(x) * 10 + trunc(x) * 100 + round(x) * 1000;", src)
    @test occursin("return log(x) / log(2.0) + log(x) / log(10);", src) && occursin("return lgamma((double)(n + 1));", src)
    @test occursin("return x > 1.0 ? 1.0 : x < 0.0 ? 0.0 : x;", src) && occursin("return n > 3 ? 3 : n < -3 ? -3 : n;", src)
    @test occursin("isfinite(x) && isfinite(y) && fabs(x - y) <= 1.4901161193847656e-8 * fmax(fabs(x), fabs(y))", src)
    @test occursin("(x > 0 ? 1.0 : x < 0 ? -1.0 : x) + x * x", src) && occursin("return (int64_t)ilogb(x) + mantissa(x);", src)
    @test occursin("1.0 / cos(x)", src) && occursin("acos(1.0 / (x + 2))", src) && occursin("fma(x, y, 1.0) + (x * y + 2.0) + hypot3(x, y, 3.0)", src) && occursin("ldexp(x, 3)", src)
    @test occursin("nextafter(x, INFINITY)", src) && occursin("nextafter(x, -INFINITY)", src) && occursin("asin(x / 40) * (180 / LEGIBLEC_PI)", src) && occursin("1.0 / cosd(x)", src)
end

# `sinpi` and its kin: written as `sin(π * x)` the product is rounded before the sine sees it,
# so the argument is brought to within a quarter of zero first, as Julia does. Exact at the
# whole and half numbers, and to the last digit at a million and a hair off one, where the
# plain product loses six.
vsinpi(x::Float64) = sinpi(x)
vcospi(x::Float64) = cospi(x)
vtanpi(x::Float64) = tanpi(x)
vsinc(x::Float64) = sinc(x)
vsinpi32(x::Float32) = sinpi(x) + cospi(x)
@testset "sine of pi times" begin
    xs = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, -0.25, -0.5, -1.0, -1.5, 0.1, 7.7, 1000000.25, 1.0000000001, 0.9999999999,
          123456.789, -98765.4321, 1e-8, 1e15 + 0.5, 4.5e15, 1e300, NaN]
    src = check("sinepi", [[Case(g, x) for g in (vsinpi, vcospi, vtanpi, vsinc) for x in xs]; [Case(vsinpi32, x) for x in (0.5f0, 1f0, 0.3f0, 1000.25f0)]])
    @test occursin("return sin_pi(x);", src) && occursin("return tan_pi(x);", src) && occursin("return sinc(x);", src) && occursin("sin_piF32(x) + cos_piF32(x)", src)
    # The harness lets a tiny answer be a little off; these are held to the last digits.
    dir = mktempdir()
    path = Main.LegibleC.transpile(vsinpi, vcospi; outfile="tight", outpath=dir, scope=@__MODULE__)
    out = dirname(path)
    tight = [1000000.25, 1.0000000001, 0.9999999999, 123456.789, 0.1, 7.7, 1e-8]
    write(joinpath(dir, "main.c"), "#include <stdio.h>\n#include \"tight.h\"\nint main(void) { double xs[] = {" * join(repr.(tight), ", ") *
          "}; for (int i = 0; i < $(length(tight)); i++) { printf(\"%.17g %.17g\\n\", vsinpi(xs[i]), vcospi(xs[i])); } return 0; }\n")
    run(`$(Main.cc) $(Main.flags) -I$out $(joinpath(dir, "main.c")) $([joinpath(out, f) for f in readdir(out) if endswith(f, ".c")]) -o $(joinpath(dir, "main")) -lm`)
    for (x, line) in zip(tight, readlines(`$(joinpath(dir, "main"))`))
        s, c = parse.(Float64, split(line))
        @test isapprox(s, sinpi(x); rtol=1e-14) && isapprox(c, cospi(x); rtol=1e-14)
    end
end

end
