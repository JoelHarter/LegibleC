# Determinants, solves, inverses, pseudoinverses: sizes 1–3 written out, pivoted LU and
# Cholesky beyond, least squares through the Gram matrix.
module Linear
using Test, StaticArrays, LinearAlgebra
import Main: Case, check, csource

M(n) = SMatrix{n,n,Float64,n*n}
V(n) = SVector{n,Float64}

det1(A::M(1)) = det(A)
det2(A::M(2)) = det(A)
det3(A::M(3)) = det(A)
det4(A::M(4)) = det(A)
det5(A::M(5)) = det(A)
dett(A::M(3)) = det(A')
solve2(A::M(2), b::V(2)) = A \ b
solve3(A::M(3), b::V(3)) = A \ b
solve4(A::M(4), b::V(4)) = A \ b
solve5(A::M(5), b::V(5)) = A \ b
solveM(A::M(3), B::SMatrix{3,2,Float64,6}) = A \ B
inv1(A::M(1)) = inv(A)
inv2(A::M(2)) = inv(A)
inv3(A::M(3)) = inv(A)
inv4(A::M(4)) = inv(A)
chol3(A::M(3), b::V(3)) = cholesky(A) \ b
chol4(A::M(4), b::V(4)) = cholesky(A) \ b
cholinv3(A::M(3)) = inv(cholesky(A))
cholB3(A::M(3), B::SMatrix{3,2,Float64,6}) = cholesky(A) \ B
lu4(A::M(4), b::V(4)) = lu(A) \ b
rdiv(B::SMatrix{2,3,Float64,6}, A::M(3)) = B / A
rowdiv(v::V(3), A::M(3)) = v' / A
rdiv4(B::SMatrix{2,4,Float64,8}, A::M(4)) = B / A
tall(A::SMatrix{4,3,Float64,12}) = pinv(A)
wide(A::SMatrix{3,4,Float64,12}) = pinv(A)
square(A::M(3)) = pinv(A)
lsq(A::SMatrix{4,3,Float64,12}, b::V(4)) = A \ b
minnorm(A::SMatrix{3,4,Float64,12}, b::V(3)) = A \ b
lsqM(A::SMatrix{4,3,Float64,12}, B::SMatrix{4,2,Float64,8}) = A \ B

A1 = SMatrix{1,1}(7.0); A2 = SMatrix{2,2}([4.0 1.0; 2.0 3.0]); A3 = SMatrix{3,3}([4.0 1.0 2.0; 1.0 5.0 3.0; 2.0 3.0 6.0])
A4 = SMatrix{4,4}([0.0 2.0 1.0 3.0; 4.0 1.0 2.0 1.0; 1.0 3.0 5.0 2.0; 2.0 1.0 1.0 6.0])
A5 = SMatrix{5,5}([2.0 1.0 0.0 3.0 1.0; 1.0 4.0 1.0 0.0 2.0; 0.0 1.0 3.0 1.0 1.0; 3.0 0.0 1.0 5.0 2.0; 1.0 2.0 1.0 2.0 4.0])
S4 = SMatrix{4,4}([10.0 2.0 1.0 3.0; 2.0 8.0 2.0 1.0; 1.0 2.0 9.0 2.0; 3.0 1.0 2.0 7.0])
b2 = SVector(1.0, 2.0); b3 = SVector(1.0, 2.0, 3.0); b4 = SVector(1.0, 2.0, 3.0, 4.0); b5 = SVector(1.0, 2.0, 3.0, 4.0, 5.0)
T43 = SMatrix{4,3}([1.0 2.0 0.0; 0.0 1.0 3.0; 2.0 0.0 1.0; 1.0 1.0 1.0])
check("linear", [Case(det1, A1), Case(det2, A2), Case(det3, A3), Case(det4, A4), Case(det5, A5), Case(dett, A3),
                 Case(solve2, A2, b2), Case(solve3, A3, b3), Case(solve4, A4, b4), Case(solve5, A5, b5),
                 Case(solveM, A3, SMatrix{3,2}([1.0 2.0; 3.0 4.0; 5.0 6.0])),
                 Case(inv1, A1), Case(inv2, A2), Case(inv3, A3), Case(inv4, A4),
                 Case(chol3, A3, b3), Case(chol4, S4, b4), Case(cholinv3, A3), Case(cholB3, A3, SMatrix{3,2}(1.0, 2, 3, 4, 5, 6)), Case(lu4, A4, b4),
                 Case(rdiv, SMatrix{2,3}([1.0 2.0 3.0; 4.0 5.0 6.0]), A3), Case(rowdiv, b3, A3),
                 Case(rdiv4, SMatrix{2,4}([1.0 2.0 3.0 4.0; 5.0 6.0 7.0 8.0]), A4),
                 Case(tall, T43), Case(wide, T43'), Case(square, A3), Case(lsq, T43, b4), Case(minnorm, T43', b3),
                 Case(lsqM, T43, SMatrix{4,2}([1.0 2.0; 3.0 4.0; 5.0 6.0; 7.0 8.0]))])

# A chain of products goes through a temp per step, each of its own shape; the temp's
# shape is the step's, not the statement's (A * B * C at 2×3, 3×4, 4×5 has a 2×4 in the
# middle). A product with a transposed operand in a chain, then a sum.
chain3(A::SMatrix{2,3,Float64,6}, B::SMatrix{3,4,Float64,12}, C::SMatrix{4,5,Float64,20}) = A * B * C
sandwich(A::M(3), B::M(3)) = A * B * A' + B
check("chain", [Case(chain3, SMatrix{2,3}(1.0, 2, 3, 4, 5, 6), SMatrix{3,4}(1.0:12...), SMatrix{4,5}(1.0:20...)),
                Case(sandwich, SMatrix{3,3}(2.0, 1, 0, 1, 3, 1, 0, 1, 4), SMatrix{3,3}(1.0:9...))])
@testset "chain" begin
    src = csource("chain", chain3)
    @test occursin("double temp1_A_B[2][4];", src) && occursin("mul_2x3_3x4(A, B, temp1_A_B);", src) && occursin("mul_2x4_4x5(temp1_A_B, C, out);", src)
end
# A product of several factors is grouped as Julia groups it, which Julia is asked (`src/product.jl`):
# `A * B * v` is `A * (B * v)`, three matrices go by cost, a row in front goes first, and `A^5` is
# `A * ((A * A) * (A * A))`. The grouping is the rounding, and with mixed precision more than that.
abv(A::SMatrix{2,2,Float64,4}, B::SMatrix{2,2,Float64,4}, v::SVector{2,Float64}) = A * B * v
mixedprecision(A::SMatrix{2,2,Float32,4}, B::SMatrix{2,2,Float32,4}, v::SVector{2,Float64}) = A * B * v
bycost(A::SMatrix{2,9,Float64,18}, B::SMatrix{9,9,Float64,81}, C::SMatrix{9,1,Float64,9}) = A * B * C
four(A::SMatrix{2,3,Float64,6}, B::SMatrix{3,4,Float64,12}, C::SMatrix{4,5,Float64,20}, D::SMatrix{5,2,Float64,10}) = A * B * C * D
sab(s::Float64, A::SMatrix{2,2,Float64,4}, B::SMatrix{2,2,Float64,4}) = s * A * B
outerthen(u::SVector{2,Float64}, v::SVector{2,Float64}, A::SMatrix{2,2,Float64,4}) = u * v' * A
literal3(A::SMatrix{2,2,Float64,4}) = 3 * A * A
quadin(v::SVector{3,Float64}, A::SMatrix{3,3,Float64,9}) = sqrt(v' * A * v + 1.0)     # a number, whose arrays on the way take lines
squared(A::SMatrix{2,2,Float64,4}) = A^2
cubed(A::SMatrix{3,3,Float64,9}) = A^3 + A
fifth(A::SMatrix{2,2,Float64,4}) = A^5
seventh(A::SMatrix{2,2,Float64,4}) = A^7
first_(A::SMatrix{2,2,Float64,4}) = A^1
@testset "product" begin
    A22 = SMatrix{2,2}(1.0, 2.0, 3.0, 4.5); v2 = SVector(0.3, 0.7); v3 = SVector(1.0, -2.0, 3.5)
    A33 = SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.5)
    check("product", [Case(abv, A22, A22, v2), Case(mixedprecision, SMatrix{2,2}(0.1f0, 0.2f0, 0.3f0, 0.4f0), SMatrix{2,2}(0.7f0, 0.9f0, 1.1f0, 1.3f0), v2),
                      Case(bycost, SMatrix{2,9}((1.0:18.0)...), SMatrix{9,9}((0.1:0.1:8.1)...), SMatrix{9,1}((1.0:9.0)...)),
                      Case(four, SMatrix{2,3}((1.0:6.0)...), SMatrix{3,4}((1.0:12.0)...), SMatrix{4,5}((0.5:0.5:10.0)...), SMatrix{5,2}((1.0:10.0)...)),
                      Case(sab, 2.5, A22, A22), Case(outerthen, v2, SVector(2.0, -1.0), A22), Case(literal3, A22), Case(quadin, v3, A33),
                      Case(squared, A22), Case(cubed, A33), Case(fifth, A22), Case(seventh, A22)])
    src = csource("producttext", abv, bycost, fifth)
    @test occursin("mul_2x2_2(B, v, temp1_B_v);", src) && occursin("mul_2x2_2(A, temp1_B_v, out);", src)             # A * (B * v)
    @test occursin("mul_9x9_9x1(B, C, temp1_B_C);", src) && occursin("mul_2x9_9x1(A, temp1_B_C, out);", src)         # by cost, from the right
    @test occursin("mul_2x2_2x2(A, A, temp1_A);", src) && occursin("mul_2x2_2x2(temp1_A, temp1_A, temp2_A);", src) && occursin("mul_2x2_2x2(A, temp2_A, out);", src)
    check("first_", [Case(first_, A22)])                       # `A^1`: once refused, now the integer power helper
end

# The matrix exponential and a matrix to an integer power (2026-10-03). `exp(A)` is Julia's
# algorithm for a static matrix: `exp` of the element, the closed form two by two, and above
# that a Padé approximant whose order goes by the 1-norm, with scaling and squaring past the
# highest. `A^n` with `n` a variable is by squaring, a negative one through the inverse.
expm1x1(A::M(1)) = exp(A)
expm2(A::M(2)) = exp(A)
expm3(A::M(3)) = exp(A)
expm4(A::M(4)) = exp(A)
expmscaled(A::M(3), s::Float64) = exp(A * s)
expm32(A::SMatrix{3,3,Float32,9}) = exp(A)
expmwritten(A::SMatrix{3,3,Float64}) = exp(A * 2)               # the size without its last parameter, as people write it
powvar(A::M(3), n::Int64) = A^n
powvar2(A::M(2), n::Int64) = A^n
powzero(A::M(3)) = A^0
powneg(A::M(2)) = A^-2
powint(A::SMatrix{2,2,Int64,4}, n::Int64) = A^n
powreal(A::M(2), x::Float64) = A^x
@testset "exponential and power" begin
    A2 = SMatrix{2,2}(1.0, 2.0, 3.0, 4.5)                        # two real eigenvalues
    R2 = SMatrix{2,2}(0.3, 2.0, -2.0, 0.3)                       # a complex pair
    D2 = SMatrix{2,2}(0.7, 0.0, 1.0, 0.7)                        # one eigenvalue twice
    A3 = SMatrix{3,3}(0.1, -0.3, 0.0, 0.2, 0.4, 0.5, 0.0, 0.1, -0.2)
    A4 = SMatrix{4,4}((0.05 * k * (-1)^k for k in 1:16)...)
    # Every order of approximant by the norm, and the scaling past 2.1: norms from 0.006 to 600.
    scales = [0.01, 0.2, 0.8, 2.0, 3.5, 9.0, 40.0, 1000.0]
    src = check("expm", [Case(expm1x1, SMatrix{1,1}(0.7)), Case(expm2, A2), Case(expm2, R2), Case(expm2, D2), Case(expm3, A3), Case(expm4, A4),
                         (Case(expmscaled, A3, s) for s in scales)..., Case(expmscaled, A3, 0.0),
                         Case(expm32, SMatrix{3,3,Float32,9}(A3)), Case(expmwritten, A3)])
    @test occursin("exp_3x3(A, out);", src) && occursin("exp_3x3F32(A, out);", src) && occursin("exp_2x2(A, out);", src)
    @test occursin("powi_3x3(U, (int64_t)1 << squarings, out);", csource("expmtext", expm3))             # the squaring is the integer power
    check("powm", [(Case(powvar, A3, n) for n in (-3, -1, 0, 1, 2, 3, 6, 11))..., (Case(powvar2, A2, n) for n in (-2, 0, 1, 5))...,
                   Case(powzero, A3), Case(powneg, A2), (Case(powint, SMatrix{2,2}(1, 2, 3, 4), n) for n in (0, 1, 2, 7))...])
    e = try csource("powreal", powreal); nothing catch e; e end
    @test e isa ArgumentError && occursin("different types", e.msg)        # real or complex by the eigenvalues: Julia's own type for it is a union
end

# A solve against a matrix (2026-10-04): what depends on `A` alone, the determinant and the
# cofactors or the factorization, is worked out once. A column at a time through the vector
# solve factored `A` again for every column.
solvem1(A::M(1), B::SMatrix{1,3,Float64,3}) = A \ B
solvem2(A::M(2), B::SMatrix{2,3,Float64,6}) = A \ B
solvem3(A::M(3), B::M(3)) = A \ B
solvem3w(A::M(3), B::SMatrix{3,2,Float64,6}) = A \ B
solvem4(A::M(4), B::M(4)) = A \ B
solvem5(A::M(5), B::SMatrix{5,2,Float64,10}) = A \ B
@testset "solve against a matrix" begin
    A3 = SMatrix{3,3}(2.0, -1.0, 0.5, 3.0, 1.5, -2.0, 0.25, 4.0, 1.0)
    A4 = SMatrix{4,4}((sin(1.7k) + (k % 5 == 1 ? 3.0 : 0.0) for k in 1:16)...)
    A5 = SMatrix{5,5}((cos(0.9k) + (k % 6 == 1 ? 4.0 : 0.0) for k in 1:25)...)
    check("solvematrix", [Case(solvem1, SMatrix{1,1}(2.5), SMatrix{1,3}(1.0, 2.0, 3.0)), Case(solvem2, SMatrix{2,2}(1.0, 2.0, 3.0, 4.5), SMatrix{2,3}((1.0:6.0)...)),
                          Case(solvem3, A3, SMatrix{3,3}((1.0:9.0)...)), Case(solvem3w, A3, SMatrix{3,2}((1.0:6.0)...)),
                          Case(solvem4, A4, SMatrix{4,4}((0.5:0.5:8.0)...)), Case(solvem5, A5, SMatrix{5,2}((1.0:10.0)...))])
    src = csource("solvematrixtext", solvem3, solvem4)
    @test occursin("lu_4x4(A, LU, p);        // once, for every column\n    for (int j = 0; j < 4; j++) {", src) && !occursin("solve_4x4_4(A, column, x);", src)
    @test occursin("double d = det_3x3(A);\n    double C[3][3] = {", src) && occursin("out[i][j] = (C[i][0] * B[0][j] + C[i][1] * B[1][j] + C[i][2] * B[2][j]) / d;", src)
end
end
