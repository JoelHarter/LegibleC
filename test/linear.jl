# Determinants, solves, inverses, pseudoinverses: sizes 1–3 written out, pivoted LU and
# Cholesky beyond, least squares through the Gram matrix.
module Linear
using Test, StaticArrays, LinearAlgebra
import Main: Case, check

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
                 Case(chol3, A3, b3), Case(chol4, S4, b4), Case(cholinv3, A3), Case(lu4, A4, b4),
                 Case(rdiv, SMatrix{2,3}([1.0 2.0 3.0; 4.0 5.0 6.0]), A3), Case(rowdiv, b3, A3),
                 Case(rdiv4, SMatrix{2,4}([1.0 2.0 3.0 4.0; 5.0 6.0 7.0 8.0]), A4),
                 Case(tall, T43), Case(wide, T43'), Case(square, A3), Case(lsq, T43, b4), Case(minnorm, T43', b3),
                 Case(lsqM, T43, SMatrix{4,2}([1.0 2.0; 3.0 4.0; 5.0 6.0; 7.0 8.0]))])
end
