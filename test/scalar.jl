# Scalar arithmetic, division rules, powers, integer operations, conversions, math.
module Scalar
using Test, StaticArrays
import Main: Case, check, csource

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
irrationals(x::Float64) = x * Base.MathConstants.catalan + Base.MathConstants.γ - twopi
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
                 Case(fmod32, -7.5f0, 2.0f0), Case(zeroone, 2.5, 3), Case(pie, 2.0), Case(irrationals, 2.0), Case(sincos_, 0.7), Case(sincos32, 0.7f0), Case(picked, 0.7), Case(bits, 12, 10),
                 Case(special, 1.0), Case(special32, 1.0f0), Case(classify, NaN), Case(classify, -Inf), Case(classify, -2.5), Case(classify, 3.0),
                 Case(limits), Case(biggest, 7.0)])
@testset "scalar text" begin
    src = csource("scalartext", math32, fmod_, pie, irrationals)
    @test occursin("sqrtf(x) + fabsf(-x) + fmaxf(x, 1.0f) + powf(x, 0.5f) + expf(x) + rintf(x)", src) && occursin("+ fmodf(x, 0.7f);", src)   # float math is the `f` family
    @test occursin("return modulo(a, b);", src) && occursin("static inline double modulo(double x, double y) {\n    double r = fmod(x, y);", src)
    @test occursin("return x * LEGIBLEC_PI + LEGIBLEC_E;", src) && !occursin("M_PI", src)   # π and ℯ are our own macros, defined in the file
    # Every irrational is a macro named after it, to 128-bit precision, in the helper header.
    @test occursin(r"#define LEGIBLEC_E 2\.718281828459045\d+  // ℯ to 128-bit precision\n#define LEGIBLEC_GAMMA 0\.577215664901532\d+  // γ to 128-bit precision\n#define LEGIBLEC_PI 3\.141592653589793\d+  // π to 128-bit precision\n#define LEGIBLEC_TWOPI 6\.283185307179586\d+  // twopi to 128-bit precision\n", src)
    @test occursin("#define LEGIBLEC_CATALAN 0.915965594177219", src) && occursin("return x * LEGIBLEC_CATALAN + LEGIBLEC_GAMMA - LEGIBLEC_TWOPI;", src)
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
end
