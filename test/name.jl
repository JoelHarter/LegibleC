# Naming rules, read off the generated C: identifiers, temps, results, reserved words,
# helper names, collisions.
module Name
using Test, StaticArrays, LinearAlgebra
import Main: csource, check, Case

square(a::Float64) = a * a + 1.0
bare(a::Float64) = (2 * 3) + a
chain(a::Float64, b::Float64) = (a * a) + b
function blocked(a::Float64, b::Float64)
    temp3 = a - b
    temp4_joelwashere = a * b
    temp1001 = 1.0
    (a + b)^2 * (b + a)^2 * (a + 1.0)^2 + temp3 + temp4_joelwashere + temp1001
end
letter(ω::Float64, Ω::Float64, Δt::Float64) = ω * Ω + Δt
marks(x̂::Float64, ẍ::Float64, x⃗::Float64, x′::Float64) = x̂ + ẍ + x⃗ + x′
scripts(x₁::Float64, x²::Float64) = x₁ * x²
fallback(🤠::Float64, µ::Float64) = 🤠 * µ
omega(x::Float64, y::Float64) = (ω = x + y; ω)
sqomega(x::Float64, y::Float64) = omega(x, y)^2
twiced(v::SVector{3,Float64}) = (w = 2.0 * v; w)
quad(v::SVector{3,Float64}) = twiced(twiced(v))
pairnamed(y::Float64, z::Float64) = (x = (y, z); return x)
unpairnamed(y::Float64, z::Float64) = ((p, q) = pairnamed(y, z); p * q)
pairbare(y::Float64, z::Float64) = (y, z)
unpairbare(y::Float64, z::Float64) = ((p, q) = pairbare(y, z); p * q)
toolong(thisisahugelongvariablenameanditsreallyannoyingtoread::SVector{3,Float64}, andanotherreallylongnamewhywouldanyonedothis::SVector{3,Float64}) =
    (thisisahugelongvariablenameanditsreallyannoyingtoread + andanotherreallylongnamewhywouldanyonedothis) * 2.0
physics(ħ::Float64, ∂::Float64, ∇::Float64, ε::Float64, ϵ::Float64, φ::Float64, ℓ::Float64, ∞::Float64, ð::Float64) = ħ + ∂ + ∇ + ε + ϵ + φ + ℓ + ∞ + ð
function keyword(exp::Float64, long::Float64)
    omega = exp + long
    ω = omega * 2.0
    ω
end
long(a::Float64) = a * 2.0
select(a::Float64) = a * 3.0          # libc's `select`: never included, but a symbol the author's function would replace
named(a::Float64, c::Float64) = (x = a + c * c; return x)
fun45(a::Float64, c::Float64) = a + c * c
resulttaken(a::Float64, result::Float64) = ccall(:fabs, Float64, (Float64,), a * result)   # a ccall's value can't be inlined
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
rk_4(h::Float64) = h / 6.0
mul_3x3_3x3(x::Float64) = 2x
scaled32(s::Float32, A::SMatrix{2,2,Float64,4}) = s * A
crossed(u::SVector{3,Float64}, v::SVector{3,Float64}) = cross(u, v)
crossed32(u::SVector{3,Float32}, v::SVector{3,Float32}) = cross(u, v)
crossmixed(u::SVector{3,Float64}, v::SVector{3,Float32}) = cross(u, v)
dotted(u::SVector{3,Float64}, v::SVector{3,Float64}) = dot(u, v)
solve4(A::SMatrix{4,4,Float64,16}, b::SVector{4,Float64}) = A \ b
inv3(A::SMatrix{3,3,Float64,9}) = inv(A)

looped(x::SVector{3,Float64}, n::Int64) = (for i in 1:n; x = x * 2.0; end; x)
rebound(x::SVector{3,Float64}, v::SVector{3,Float64}, dt::Float64) = (v = v + dt * x; x = x + dt * v; x = x / 2.0; [x; v])
squared(A::SMatrix{2,2,Float64,4}) = (A = A * A; A = A + A; A)
branched(a::Float64, b::Float64) = (if a > b; c = a - b; a = c * 2.0; else; c = b - a; end; a + c)

src = csource("name", looped, rebound, squared, branched, square, bare, chain, blocked, letter, marks, scripts, fallback, keyword, long, named, fun45,
              resulttaken, outtaken, helpertaken, underscored, borrowed, short, bump!, (poly, Float64, Float64), (poly, Int64, Int64),
              mixedarray, outer, nine, scaled32, crossed, crossed32, crossmixed, dotted, physics; tempsuffix=true)      # the suffixes are what is tested here
@testset "name" begin
    # A reassigned array parameter is worked on as a copy `x_` made at the top under a
    # comment — in `out`, when that is where it ends up (`outplacement!`); elementwise
    # helpers then write it in place. A reassigned scalar is the parameter.
    @test occursin("    // copy x and v into out, where the function works on them and returns them\n    memcpy(out, x, sizeof(double[3]));\n    double *x_local = out;\n    memcpy(&out[3], v, sizeof(double[3]));\n    double *v_local = &out[3];\n\n    // @name.jl", src)
    @test occursin("mul_s_3(dt, x_local, temp1_dt_x);", src) && occursin("add_3(v_local, temp1_dt_x, v_local);", src) && occursin("div_3_s(x_local, 2.0, x_local);", src)   # temps are named from the Julia, not the copy
    @test occursin("    // copy x into out, where the function works on it and returns it\n    memcpy(out, x, sizeof(double[3]));\n    double *x_local = out;\n\n", src) && occursin("mul_3_s(x_local, 2.0, x_local);", src)
    @test occursin("mul_2x2_2x2(A_local, A_local, temp", src) && occursin("add_2x2(A_local, A_local, A_local);", src)
    @test occursin("a = c * 2.0;", src) && !occursin(r"\ba_\b", src)   # scalar: reassign the parameter itself
    @test occursin("double out[2][2]) {", src) && occursin("double out[restrict 2][2]) {", src)   # elementwise helpers plain, products restrict
    # Scalar work the author didn't name gets no name here either (inline.jl); a
    # power's base does, and shows the temp naming.
    @test occursin("return a * a + 1.0;", src)
    @test occursin("return 2 * 3 + a;", src)
    @test occursin("return a * a + b;", src)
    @test occursin("double temp1_a_b = a + b;", src) && occursin("double temp5_a = a + 1.0;", src) && !occursin(r"temp[34]_[ab]\b", src)   # user's temp3/temp4 block those numbers; a literal contributes nothing
    @test occursin("double temp3 = a - b;", src) && occursin("temp1_a_b * temp1_a_b * (temp2_b_a * temp2_b_a) * (temp5_a * temp5_a) + temp3", src)
    # A call's temp: the callee's returned variable when it has one; the callee's name for
    # an unnamed tuple being unpacked; otherwise the operands.
    calls = csource("calls", sqomega, quad, unpairnamed, unpairbare; tempsuffix=true)
    @test occursin("double temp1_omega = omega(x, y);", calls) && occursin("return temp1_omega * temp1_omega;", calls)
    @test occursin("double temp1_w[3];\n    twiced(v, temp1_w);", calls) && occursin("twiced(temp1_w, out);", calls)
    @test occursin("pairnamed_t temp1_x = pairnamed(y, z);", calls) && occursin("pairbare_t temp1_pairbare = pairbare(y, z);", calls)
    @test occursin("pairnamed_t x = (pairnamed_t){y, z};\n    return x;", calls)
    plain = csource("plain", sqomega, quad, physics)                              # off unless asked for
    @test occursin("double temp1 = omega(x, y);", plain) && occursin("twiced(v, temp1);", plain) && !occursin("temp1_", plain)   # Julia's grouping, exactly
    @test occursin("return omega * Omega + Deltat;", src)
    @test occursin("xhat + xddot + xvec + xprime", src)
    @test occursin("x1 * x2", src)
    @test occursin("facewithcowboyhat * mu", src)   # Julia's own emoji name, one word; µ (micro) decomposes to μ
    # Julia's `\name` table spells the rest: what the author typed to get the character.
    @test occursin("double physics(double hbar, double partial, double nabla, double epsilon, double epsilon_, double phi, double l, double infty, double eth)", src)
    # The user's own spellings sit on top.
    spelt = csource("spelt", physics; spelling=Dict('ħ' => "hred", '∂' => "d", 'ε' => "eps"))
    @test occursin("double physics(double hred, double d, double nabla, double eps, double eps_, double phi, double l, double infty, double eth)", spelt)
    @test_throws ArgumentError csource("bad", physics; spelling=Dict('a' => "x"))          # ASCII is itself
    @test_throws ArgumentError csource("bad", physics; spelling=Dict('×' => "times"))      # not a Julia name character
    @test_throws ArgumentError csource("bad", physics; spelling=Dict('ħ' => "h bar"))      # not C text
    @test_throws ArgumentError csource("bad", physics; spelling=Dict("ħ" => "hbar"))       # not a character
    @test occursin("double keyword(double exp_, double long_)", src) && occursin("omega_", src)   # beside the function `long_`, which `keyword` never mentions
    @test occursin("double long_(double a)", src)
    @test occursin("double select_(double a)", csource("posix", select))
    @test occursin("return x;", src)
    @test occursin("return a + c * c;", src)
    @test occursin("double result_ = fabs(a * result);", src) && occursin("return result_;", src)   # `result` is taken
    long = csource("long", toolong; tempsuffix=true)
    @test occursin("double temp1[3];\n    add_3(", long)                                          # past `templimit`, the suffix is dropped
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
    # A function of the author's named like a helper is renamed, whether or not this program
    # emits that helper: its name can't depend on what else is computed, and `add_3` is the
    # transpiler's word, as `sqrt` is libc's. A name that only looks similar stays.
    clash = csource("clash", add_3, rk_4)
    @test occursin("void add_3_(const double u[3], const double v[3], double out[restrict 3])", clash) && occursin("add_3(u, v, out);", clash)
    @test occursin("double rk_4(double h)", clash)
    @test occursin("double mul_3x3_3x3_(double x)", csource("impostor", mul_3x3_3x3))               # and with no such helper in sight
    # Small helpers are `static inline`, in helper.h; solvers and factorizations are
    # ordinary functions in helper.c, with prototypes in the header.
    big = csource("big", solve4, inv3)
    @test occursin("\nvoid pivot_4x4(", big) && occursin("\nvoid lu_4x4(", big) && occursin("\nvoid solve_4x4_4(", big) && !occursin("static void", big)
    @test occursin("void solve_4x4_4(const double A[4][4], const double b[4], double out[restrict 4]);", big)
    @test occursin("static inline void inv_3x3(", big) && occursin("static inline double det_3x3(", big)
end

# A local may not share a spelling with any file-scope name: Julia keeps `κ` and `kappa`
# apart, C would let the local shadow the global silently, or fail to compile when it
# shadows a function or a struct. Such a local is `kappa_`.
const kappa = 3.0
function localglobal(x::Float64)
    κ = x + 1.0
    return κ * kappa
end
kappa2(x::Float64) = 2x
function localfunction(x::Float64)
    κ2 = x + 1.0
    return κ2 + kappa2(x)
end
struct Kappa; v::Float64; end
function localstruct(o::Kappa, x::Float64)
    Κ = x + o.v
    return Kappa(Κ).v * 2.0
end
check("shadow", [Case(localglobal, 1.0), Case(localfunction, 1.0), Case(localstruct, Kappa(1.0), 2.0)])
@testset "shadow" begin
    src = csource("shadow", localglobal, localfunction, localstruct)
    @test occursin("double kappa_ = x + 1.0;", src) && occursin("return kappa_ * kappa;", src)
    @test occursin("double kappa2_ = x + 1.0;", src) && occursin("return kappa2_ + kappa2(x);", src)
    @test occursin("double Kappa_ = x + o.v;", src) && occursin("(Kappa){Kappa_}", src)
end
end
