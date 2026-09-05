# Reductions to a scalar and slices of an array.
module Reduce
using Test, StaticArrays, LinearAlgebra
import Main: Case, check

const V3 = SVector{3,Float64}
const M23 = SMatrix{2,3,Float64,6}

total(v::V3) = sum(v)
product(A::M23) = prod(A)
biggest(A::M23) = maximum(A) - minimum(A)
len(v::V3) = norm(v)
allpos(v::SVector{3,Bool}) = all(v)
anytrue(v::SVector{3,Bool}) = any(v)
row(A::M23, i::Int64) = A[i, :]
col(A::M23) = A[:, 2]
run_(v::SVector{5,Float64}) = v[2:4]
rowsum(A::M23, i::Int64) = sum(A[i, :])
isum(v::SVector{3,Int64}) = sum(v)

v = SVector(1.0, -2.0, 3.0); A = SMatrix{2,3}([1.0 2.0 3.0; 4.0 5.0 6.0])
check("reduce", [Case(total, v), Case(product, A), Case(biggest, A), Case(len, v), Case(allpos, SVector(true, true, false)),
                 Case(allpos, SVector(true, true, true)), Case(anytrue, SVector(false, false, true)), Case(anytrue, SVector(false, false, false)),
                 Case(row, A, 2), Case(col, A), Case(run_, SVector(1.0, 2.0, 3.0, 4.0, 5.0)), Case(rowsum, A, 1), Case(isum, SVector(1, 2, 3))])
end
