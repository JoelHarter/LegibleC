# Complex numbers: C99's `double complex`, its operators and `c` functions; arrays of them
# through the same helpers, with `H` where an adjoint conjugates and `T` where it doesn't.
module Complex_
using Test, StaticArrays, LinearAlgebra
import Main: Case, check, csource

const C = ComplexF64
zsq(z::C) = z * z + conj(z)
parts(z::C) = real(z) + 2imag(z) + z.re - z.im
mag(z::C) = abs(z) + abs2(z) + angle(z)
mk(a::Float64, b::Float64) = (a + b * im) * Complex(b, a) / sqrt(Complex(a, b))
funs(z::C) = exp(z) + log(z) * sin(z) - z^2 + z^C(0.5, 0.25)
realparts(x::Float64) = real(x) + imag(x) + conj(x)
cadd(x::SVector{3,C}, y::SVector{3,C}) = x + 2y
cdot(x::SVector{3,C}, y::SVector{3,C}) = dot(x, y)
cnorm(x::SVector{3,C}) = norm(x)
crow(x::SVector{3,C}, y::SVector{3,C}) = x' * y
cgram(A::SMatrix{3,2,C,6}) = A' * A
ctr(A::SMatrix{3,2,C,6}) = transpose(A) * conj.(A)
crossgram(A::SMatrix{3,2,C,6}, B::SMatrix{3,2,C,6}) = A * B'
csolve(A::SMatrix{2,2,C,4}, b::SVector{2,C}) = A \ b
csolve4(A::SMatrix{4,4,C,16}, b::SVector{4,C}) = A \ b
cinv3(A::SMatrix{3,3,C,9}) = inv(A)
cdet(A::SMatrix{3,3,C,9}) = det(A)
cchol(A::SMatrix{3,3,C,9}, b::SVector{3,C}) = cholesky(A) \ b
cchol4(A::SMatrix{4,4,C,16}, b::SVector{4,C}) = cholesky(A) \ b
cabsv(v::SVector{3,C}) = abs.(v)
cparts(v::SVector{3,C}) = real.(v) .+ imag.(v)
csum(v::SVector{3,C}) = sum(v) * prod(v)
printed(z::C) = println(z)

z = C(1.5, -0.5); w = C(-2.0, 3.0)
x = SVector(C(1, 2), C(-1, 0.5), C(0, -3)); y = SVector(C(2, -1), C(1.5, 1), C(-0.5, 0.5))
A = SMatrix{3,2}(C(1, 1), C(2, -1), C(0, 1), C(1, 0), C(-1, 2), C(3, 1))
M3 = SMatrix{3,3}(C(2, 1), C(0, -1), C(1, 1), C(1, 0), C(3, 1), C(0, 2), C(-1, 1), C(1, 0), C(2, -2))
M4 = SMatrix{4,4}(C.(reshape(1.0:16, 4, 4), reshape(16.0:-1:1, 4, 4)) + 4I)
H3 = M3' * M3 + 3I
H4 = M4' * M4 + 5I
check("cx", [Case(zsq, z), Case(parts, z), Case(mag, w), Case(mk, 1.5, -2.0), Case(funs, z), Case(realparts, 2.5),
                  Case(cadd, x, y), Case(cdot, x, y), Case(cnorm, x), Case(crow, x, y), Case(cgram, A), Case(ctr, A), Case(crossgram, A, A),
                  Case(csolve, SMatrix{2,2}(z, w, C(1, 0), C(0, 2)), SVector(z, w)), Case(csolve4, M4, SVector(z, w, C(1, 1), C(-1, 2))),
                  Case(cinv3, M3), Case(cdet, M3), Case(cchol, H3, SVector(z, w, C(1, 1))), Case(cchol4, H4, SVector(z, w, C(1, 1), C(0, -1))),
                  Case(cabsv, x), Case(cparts, x), Case(csum, x)])
@testset "complex" begin
    src = csource("cx", zsq, parts, mk, cadd, cdot, cnorm, cgram, ctr, cchol, cabsv, printed)
    @test occursin("double complex zsq(double complex z)", src) && occursin("return z * z + conj(z);", src)
    @test occursin("return creal(z) + 2 * cimag(z) + creal(z) - cimag(z);", src)
    @test occursin("return (a + b * I) * CMPLX(b, a) / csqrt(CMPLX(a, b));", src) && occursin("#ifndef CMPLX", src) && occursin("#include <complex.h>", src)
    # Arrays: the same helpers with `C64` in the name; `2y` a real coefficient.
    @test occursin("mul_s_C3(2.0, y, temp1_y);", src) && occursin("add_C3(x, temp1_y, out);", src)
    # `dot` conjugates its first argument; `norm` sums squared magnitudes into a real.
    @test occursin("sum += conj(a[k]) * b[k];", src) && occursin("double norm_C3(const double complex a[3])", src) && occursin("sum += creal(a[i]) * creal(a[i]) + cimag(a[i]) * cimag(a[i]);", src)
    # `A' * A` is `H`, read conjugated; `transpose(A)` stays `T`.
    @test occursin("mul_CH3x2_C3x2(A, A, out);", src) && occursin("out[i][j] += conj(A[k][i]) * B[k][j];", src) && occursin("/// out = Aᴴ * B", src) && occursin("adjoint complex 3×2-matrix", src)
    @test occursin("mul_CT3x2_C3x2(A, temp1, out);  // out = Aᵀ * temp1", src) && occursin("conjP_C3x2(A, temp1);  // temp1 = conj.(A)", src)
    # Cholesky is L Lᴴ: conjugates in the products, real pivots.
    @test occursin("L[1][0] = A[1][0] / L[0][0];", src) && occursin("conj(L[1][0])", src) && occursin("L[1][1] = creal(", src) && occursin("/// A = L Lᴴ", src)
    @test occursin("void absP_C3(const double complex a[3], double out[restrict 3])", src) && occursin("out[i] = cabs(a[i]);", src)
    @test occursin("printf(\"%g%+gim\\n\", creal(z), cimag(z));", src)
    @test_throws ArgumentError csource("mixed", (A -> transpose(A'), Float64, 2, 3))
    @test_throws ArgumentError csource("complex", zsq)     # the file would shadow <complex.h>
end
end
