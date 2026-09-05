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
block(A::SMatrix{3,4,Float64,12}) = A[1:2, 2:3]
tail(A::SMatrix{3,4,Float64,12}) = A[:, 2:end]
function setcols(A::MMatrix{2,4,Float64,8}, B::MMatrix{2,2,Float64,4}); A[:, 3:end] = B; return A; end
function setrow(A::MMatrix{2,4,Float64,8}, v::SVector{4,Float64}); A[2, :] = v; return A; end
function setcol(A::MMatrix{2,4,Float64,8}, v::SVector{2,Float64}); A[:, 1] = v; return A; end
function setblock(A::MMatrix{3,4,Float64,12}, B::SMatrix{2,2,Float64,4}); A[2:3, 1:2] = B; return A; end
function setrun(v::MVector{5,Float64}, w::SVector{2,Float64}); v[2:3] = w; return v; end

v = SVector(1.0, -2.0, 3.0); A = SMatrix{2,3}([1.0 2.0 3.0; 4.0 5.0 6.0])
check("reduce", [Case(total, v), Case(product, A), Case(biggest, A), Case(len, v), Case(allpos, SVector(true, true, false)),
                 Case(allpos, SVector(true, true, true)), Case(anytrue, SVector(false, false, true)), Case(anytrue, SVector(false, false, false)),
                 Case(row, A, 2), Case(col, A), Case(run_, SVector(1.0, 2.0, 3.0, 4.0, 5.0)), Case(rowsum, A, 1), Case(isum, SVector(1, 2, 3)),
                 Case(block, SMatrix{3,4}(1.0:12.0...)), Case(tail, SMatrix{3,4}(1.0:12.0...)),
                 Case(setcols, MMatrix{2,4}(1.0:8.0...), MMatrix{2,2}(9.0:12.0...)), Case(setrow, MMatrix{2,4}(1.0:8.0...), SVector(9.0, 10.0, 11.0, 12.0)),
                 Case(setcol, MMatrix{2,4}(1.0:8.0...), SVector(9.0, 10.0)), Case(setblock, MMatrix{3,4}(1.0:12.0...), SMatrix{2,2}(9.0:12.0...)),
                 Case(setrun, MVector(1.0, 2.0, 3.0, 4.0, 5.0), SVector(9.0, 10.0))])
end
