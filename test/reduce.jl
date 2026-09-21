# Reductions to a scalar and slices of an array.
module Reduce
using Test, StaticArrays, LinearAlgebra, Statistics
import Main: Case, check, csource

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
colsum(A::M23) = sum(A; dims=1)
rowprod(A::M23) = prod(A; dims=2)
colmax(A::M23) = maximum(A; dims=1)
rowmin(A::M23) = minimum(A; dims=2)
vsum(v::V3) = sum(v; dims=1)
cubesum(A::SArray{Tuple{2,2,2},Float64,3,8}) = sum(A; dims=3)
diffs(v::SVector{5,Float64}) = diff(v)
diff1(A::M23) = diff(A; dims=1)
diff2(A::M23) = diff(A; dims=2)
cums(v::V3) = cumsum(v)
cums2(A::M23) = cumsum(A; dims=2)
cump(v::SVector{4,Int64}) = cumprod(v)
pair(v::SVector{2,Float64}) = diff(v)
cnt(v::SVector{3,Bool}) = count(v)
amax(v::SVector{4,Float64}) = argmax(v)
amin(v::SVector{4,Float64}) = argmin(v)
ext(v::SVector{4,Float64}) = extrema(v)
spread(v::SVector{4,Float64}) = ((lo, hi) = extrema(v); hi - lo)
anyneg(v::V3) = any(v .< 0.0)

v = SVector(1.0, -2.0, 3.0); A = SMatrix{2,3}([1.0 2.0 3.0; 4.0 5.0 6.0])
check("reduce", [Case(total, v), Case(product, A), Case(biggest, A), Case(len, v), Case(allpos, SVector(true, true, false)),
                 Case(allpos, SVector(true, true, true)), Case(anytrue, SVector(false, false, true)), Case(anytrue, SVector(false, false, false)),
                 Case(row, A, 2), Case(col, A), Case(run_, SVector(1.0, 2.0, 3.0, 4.0, 5.0)), Case(rowsum, A, 1), Case(isum, SVector(1, 2, 3)),
                 Case(block, SMatrix{3,4}(1.0:12.0...)), Case(tail, SMatrix{3,4}(1.0:12.0...)),
                 Case(setcols, MMatrix{2,4}(1.0:8.0...), MMatrix{2,2}(9.0:12.0...)), Case(setrow, MMatrix{2,4}(1.0:8.0...), SVector(9.0, 10.0, 11.0, 12.0)),
                 Case(setcol, MMatrix{2,4}(1.0:8.0...), SVector(9.0, 10.0)), Case(setblock, MMatrix{3,4}(1.0:12.0...), SMatrix{2,2}(9.0:12.0...)),
                 Case(setrun, MVector(1.0, 2.0, 3.0, 4.0, 5.0), SVector(9.0, 10.0)),
                 Case(colsum, A), Case(rowprod, A), Case(colmax, A), Case(rowmin, A), Case(vsum, v),
                 Case(cubesum, SArray{Tuple{2,2,2}}(1.0:8.0...)), Case(diffs, SVector(1.0, 4.0, 9.0, 16.0, 25.0)),
                 Case(diff1, A), Case(diff2, A), Case(cums, v), Case(cums2, A), Case(cump, SVector(1, 2, 3, 4)), Case(pair, SVector(1.0, 3.0)),
                 Case(cnt, SVector(true, false, true)), Case(amax, SVector(1.0, 7.0, 7.0, 2.0)), Case(amin, SVector(3.0, -1.0, 5.0, -1.0)),
                 Case(ext, SVector(3.0, -1.0, 5.0, 2.0)), Case(spread, SVector(3.0, -1.0, 5.0, 2.0)), Case(anyneg, v), Case(anyneg, SVector(1.0, 2.0, 3.0))])
@testset "along a dimension" begin
    # The dimension sits on the operation's name; a vector leaves it off, except a
    # reduction, whose plain name is the sum to a scalar.
    src = csource("along", colsum, rowprod, diff2, cums, cums2, vsum, diffs)
    @test occursin("sum1_2x3(A, out);", src) && occursin("prod2_2x3(A, out);", src) && occursin("diff2_2x3(A, out);", src)
    @test occursin("cumsum_3(v, out);", src) && occursin("cumsum2_2x3(A, out);", src) && occursin("sum1_3(v, out);", src) && occursin("diff_5(v, out);", src)
    @test occursin("/// 2×3-matrix sum along dimension 1\n/// out = sum(A; dims=1)\nstatic inline void sum1_2x3(const double A[2][3], double out[1][3]) {\n    for (int j = 0; j < 3; j++) {\n        double sum = 0.0;\n        for (int i = 0; i < 2; i++) {\n            sum += A[i][j];\n        }\n        out[0][j] = sum;\n    }\n}", src)
    @test occursin("/// 5-vector differences\n/// out = diff(a)\nstatic inline void diff_5(const double a[5], double out[4]) {\n    for (int i = 0; i < 4; i++) {\n        out[i] = a[i + 1] - a[i];\n    }\n}", src)
end
# The norms of order 1 and infinity beside the usual one, and `mean`, `var`, `std`: each a
# helper that returns the scalar, like `sum`. `var` and `std` are the corrected ones, as Julia's.
norms(v::SVector{3,Float64}) = norm(v, 1) + 10.0 * norm(v, Inf) + 100.0 * norm(v, 2) + 1000.0 * norm(v)
matnorms(A::SMatrix{2,2,Float64,4}) = norm(A, 1) + norm(A, Inf)
spread(v::SVector{4,Float64}) = mean(v) + 10.0 * std(v) + 100.0 * var(v)
matspread(A::SMatrix{2,2,Float64,4}) = mean(A) + var(A)
centred(v::SVector{4,Float64}) = (m = mean(v); (v[1] - m) / std(v))
single(v::SVector{3,Float32}) = mean(v) + norm(v, 1)
@testset "norms and statistics" begin
    check("spread", [Case(norms, SVector(1.0, -2.0, 3.5)), Case(norms, SVector(0.0, 0.0, 0.0)), Case(matnorms, SMatrix{2,2}(1.0, -2.0, 3.0, -4.5)),
                     Case(spread, SVector(1.0, 2.0, 4.0, 8.0)), Case(matspread, SMatrix{2,2}(1.0, -2.0, 3.0, -4.5)),
                     Case(centred, SVector(1.0, 2.0, 4.0, 8.0)), Case(single, SVector(1.0f0, -2.0f0, 3.5f0))])
    src = csource("spreadtext", norms, spread)
    @test occursin("return norm1_3(v) + 10.0 * normInf_3(v) + 100.0 * norm_3(v) + 1000.0 * norm_3(v);", src)
    @test occursin("return mean_4(v) + 10.0 * std_4(v) + 100.0 * var_4(v);", src)
end
end
