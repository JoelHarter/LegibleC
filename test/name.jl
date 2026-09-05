# Naming rules, read off the generated C: identifiers, temps, results, reserved words,
# helper names, collisions.
module Name
using Test, StaticArrays, LinearAlgebra
import Main: csource

square(a::Float64) = a * a + 1.0
bare(a::Float64) = (2 * 3) + a
chain(a::Float64, b::Float64) = (a * a) + b
function blocked(a::Float64, b::Float64)
    temp3 = a - b
    temp4_joelwashere = a * b
    temp1001 = 1.0
    (a + b) * (b + a) * (a + 1.0) + temp3 + temp4_joelwashere + temp1001
end
letter(ω::Float64, Ω::Float64, Δt::Float64) = ω * Ω + Δt
marks(x̂::Float64, ẍ::Float64, x⃗::Float64, x′::Float64) = x̂ + ẍ + x⃗ + x′
scripts(x₁::Float64, x²::Float64) = x₁ * x²
fallback(🤠::Float64, µ::Float64) = 🤠 * µ
function keyword(exp::Float64, long::Float64)
    omega = exp + long
    ω = omega * 2.0
    ω
end
long(a::Float64) = a * 2.0
named(a::Float64, c::Float64) = (x = a + c * c; return x)
fun45(a::Float64, c::Float64) = a + c * c
resulttaken(a::Float64, result::Float64) = a * result
outtaken(out::SVector{3,Float64}, v::SVector{3,Float64}) = out + v
helpertaken(u::SVector{3,Float64}, v::SVector{3,Float64}) = (add_3 = u + v; add_3 .* 2.0)
underscored(_x::Float64, __Y::Float64) = _x + __Y
borrowed(time::Float64, index::Float64, printf::Float64) = time * index + printf
short(a::Float64) = a
bump!(a::Float64) = a + 1.0
poly(a, b) = a * b + a
mixedarray(A::SMatrix{2,2,Float64,4}, B::SMatrix{2,2,Float32,4}) = A + B
outer(v::SVector{3,Float64}, w::SVector{3,Float64}) = v .* w'
nine(a::SVector{3,Float64}, b::SVector{3,Float64}, c::SVector{3,Float64}, d::SVector{3,Float64}, e::SVector{3,Float64},
     f::SVector{3,Float64}, g::SVector{3,Float64}, h::SVector{3,Float64}, i::SVector{3,Float64}) = [a b c d e f g h i]
add_3(u::SVector{3,Float64}, v::SVector{3,Float64}) = u + v
scaled32(s::Float32, A::SMatrix{2,2,Float64,4}) = s * A
crossed(u::SVector{3,Float64}, v::SVector{3,Float64}) = cross(u, v)
crossed32(u::SVector{3,Float32}, v::SVector{3,Float32}) = cross(u, v)
crossmixed(u::SVector{3,Float64}, v::SVector{3,Float32}) = cross(u, v)
dotted(u::SVector{3,Float64}, v::SVector{3,Float64}) = dot(u, v)
solve4(A::SMatrix{4,4,Float64,16}, b::SVector{4,Float64}) = A \ b
inv3(A::SMatrix{3,3,Float64,9}) = inv(A)

src = csource("name", square, bare, chain, blocked, letter, marks, scripts, fallback, keyword, long, named, fun45,
              resulttaken, outtaken, helpertaken, underscored, borrowed, short, bump!, (poly, Float64, Float64), (poly, Int64, Int64),
              mixedarray, outer, nine, scaled32, crossed, crossed32, crossmixed, dotted)
@testset "name" begin
    @test occursin("double temp1_a = a * a;", src)
    @test occursin("int64_t temp1 = 2 * 3;", src) && occursin("double result = temp1 + a;", src)   # a literal contributes nothing
    @test occursin("double temp1_a = a * a;", src) && occursin("double result = temp1_a + b;", src)
    @test occursin("temp5", src) && !occursin("double temp3 =", src) && !occursin("double temp4 =", src)   # user's temp3/temp4 block those numbers
    @test occursin("double temp1_omega_Omega = omega * Omega;", src) && occursin("temp1_omega_Omega + Deltat", src)
    @test occursin("xhat + xddot + xvec + xprime", src)
    @test occursin("x1 * x2", src)
    @test occursin("U1F920 * mu", src)
    @test occursin("double keyword(double exp_, double long_)", src) && occursin("omega_", src)
    @test occursin("double long_(double a)", src)
    @test occursin("return x;", src)
    @test occursin("double result = a + temp1_c;", src)
    @test occursin("double result_ = a * result;", src)
    @test occursin("void outtaken(const double out[3], const double v[3], double out_[restrict 3])", src)
    @test occursin("double add_3_[3];", src) && occursin("add_3(u, v, add_3_);", src)
    @test occursin("double underscored(double x_, double Y__)", src)
    @test occursin("double borrowed(double time_, double index_, double printf_)", src)
    @test occursin("double short_(double a)", src)
    @test occursin("double bump(double a)", src)
    @test occursin("double poly(double a, double b)", src) && occursin("int64_t poly_I64_I64(", src)   # all-Float64 keeps the plain name
    @test occursin("static inline void add_2x2F64F32(", src)                                              # size once, types run together
    @test occursin("static inline void mul_sF32_2x2F64(", src)                                              # a scalar is always `s`
    @test occursin("static inline void cross(", src) && occursin("static inline void cross_F32(", src) && occursin("static inline void cross_F64F32(", src)
    @test occursin("static inline double dot_3(", src)
    @test occursin("static inline void mulP_3_T3(", src)
    @test occursin("for (int i_ = 0; i_ < 3; i_++)", src)                                           # the ninth input is `i`
    @test occursin("/// 3-vector * transposed 3-vector broadcast multiplication", src)
    @test_throws ArgumentError csource("clash", add_3)
    # Small helpers are `static inline`; solvers and factorizations are plain `static`.
    big = csource("big", solve4, inv3)
    @test occursin("static void pivot_4x4(", big) && occursin("static void lu_4x4(", big) && occursin("static void solve_4x4_4(", big)
    @test occursin("static inline void inv_3x3(", big) && occursin("static inline double det_3x3(", big)
end
end
