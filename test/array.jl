# Static arrays: arithmetic, products, transposes, broadcasting, construction, blocks,
# literals, odd shapes, regular arrays given a size.
module Array_
using Test, StaticArrays, LinearAlgebra
import Main: Case, check, csource

const M2 = SMatrix{2,2,Float64,4}
const V3 = SVector{3,Float64}

add(A::M2, B::M2) = A + B
mulmv(A::M2, v::SVector{2,Float64}) = A * v
mulmm(A::M2, B::SMatrix{2,3,Float64,6}) = A * B
negcopy(A::M2) = (B = -A; C = copy(B); C - A)
scale(A::M2, s::Float64) = 2.0 * A + A * s
selfmul(A::MMatrix{2,2,Float64,4}) = (A = A * A; A)
mixedarray(A::M2, B::SMatrix{2,2,Float32,4}) = A + B
vec3(u::V3, v::V3, w::V3) = u + v + w
cube(A::SArray{Tuple{2,2,2},Float64,3,8}, B::SArray{Tuple{2,2,2},Float64,3,8}) = A - B
namedarray(A::M2, B::M2) = (C = A + B; return C)
regmul(A::Matrix{Float64}, B::Matrix{Float64}) = A * B
regchain(A::Matrix{Float64}, s::Float64) = (B = 2.0 * A; C = B + A; C = C * s; C)
regvec(A::Matrix{Float64}, v::Vector{Float64}) = A * v + v
blocks(A::M2, B::M2, C::M2, D::M2) = [A B; C D]
columns(A::M2, B::M2, C::M2, D::M2) = [A; B;; C; D]                 # the same grid, listed down each column
beside2(A::M2, B::M2) = [A;; B]
cube3(A::M2, B::M2, C::M2, D::M2) = [A;; B;;; C;; D]                 # 2×4×2
stack3(u::V3, v::V3) = [u;;; v]                                      # 3×1×2
ragged(A::M2, B::M2, C::SMatrix{2,4,Float64,8}) = [A B; C]
mixedcols(a::Int64, b::SVector{2,Int64}) = [a; b;; b; a]                 # 3×2: columns of different-height pieces
mixedrows(a::Int64, b::SMatrix{1,2,Int64,2}) = [a b; b a]               # 2×3: rows of different-width pieces
stack(u::V3, v::V3) = [u; v]
beside(u::V3, v::V3) = [u v]
literal() = [1.0 2.0; 3.0 4.0]
vlit() = [1.0, 2.0, 3.0]
svec() = SVector(1.0, 2.0, 3.0)
smat() = @SMatrix [1.0 2.0; 3.0 4.0]
scalerows(v::V3, M::SMatrix{3,3,Float64,9}) = v .* M
elementwise(v::V3, w::V3) = v .+ w
shifted(v::V3) = exp.(v) .+ 2.0
outer(v::V3, w::V3) = v .* w'
asrow(v::V3) = v'
rowtimes(v::V3, M::SMatrix{3,2,Float64,6}) = v' * M
rowdot(v::V3, w::V3) = v' * w
dotted(v::V3, w::V3) = dot(v, w)
crossed(v::V3, w::V3) = cross(v, w)
flipped(M::SMatrix{2,3,Float64,6}) = transpose(M)
scalecols(v::V3, M::SMatrix{3,2,Float64,6}) = v .* M
byscalar(M::SMatrix{3,2,Float64,6}) = 2.0 .* M
pmixed(A::SMatrix{3,2,Float64,6}, B::SMatrix{3,2,Float32,6}) = A .* B
thin(a::SArray{Tuple{1,1,3},Float64,3,3}, b::SMatrix{2,1,Float64,2}) = a .* b
deep(a::SArray{Tuple{3,1,3},Float64,3,9}, b::SArray{Tuple{1,1,1,1,3,1,1},Float64,7,3}) = a .* b
four(a::SArray{Tuple{2,2,2,2},Float64,4,16}, b::SArray{Tuple{2,2,2,2},Float64,4,16}) = a .+ b
rowplus(u::V3, v::SVector{2,Float64}) = u .+ v'
abt(A::SMatrix{2,3,Float64,6}, B::SMatrix{2,3,Float64,6}) = A * B'
atb(A::SMatrix{3,2,Float64,6}, B::SMatrix{3,2,Float64,6}) = A' * B
atbt(A::SMatrix{2,3,Float64,6}, B::SMatrix{3,2,Float64,6}) = A' * B'
tr(A::SMatrix{2,3,Float64,6}) = A'
atv(A::SMatrix{3,2,Float64,6}, v::V3) = A' * v
addt(A::SMatrix{2,3,Float64,6}, B::SMatrix{3,2,Float64,6}) = A + B'
pt(A::SMatrix{2,3,Float64,6}, B::SMatrix{3,2,Float64,6}) = A .* B'
stored(A::SMatrix{2,3,Float64,6}) = (B = A'; B * A)
rowstored(v::V3, M::SMatrix{3,2,Float64,6}) = (r = v'; r * M)
zeroed(A::SMatrix{3,4,Float64,12}) = zero(A)
zeroes() = zeros(SMatrix{3,4,Float64,12})
zeroint() = zeros(SMatrix{2,2,Int64,4})
oned(A::SMatrix{3,3,Float64,9}) = one(A)
eye() = SMatrix{3,3,Float64,9}(I)
tallI() = SMatrix{3,2,Float64,6}(I)
ones34() = ones(SMatrix{3,4,Float64,12})
filled(x::Float64) = fill(x, SMatrix{2,2,Float64,4})
divs(A::M2, s::Float64) = A / s
sdiv(s::Float64, A::M2) = s \ A
permute(v::MVector{3,Float64}) = (v = [v[3], v[1] + v[2], 0.0]; v)      # reads v while writing it: through a temp

A = SMatrix{2,2}(1.0, 2.0, 3.0, 4.0); B = SMatrix{2,2}(5.0, 6.0, 7.0, 8.0)
A23 = SMatrix{2,3}(1.0, 4.0, 2.0, 5.0, 3.0, 6.0); B23 = SMatrix{2,3}(7.0, 10.0, 8.0, 11.0, 9.0, 12.0)
A32 = SMatrix{3,2}(1.0, 3.0, 5.0, 2.0, 4.0, 6.0); B32 = SMatrix{3,2}(7.0, 9.0, 11.0, 8.0, 10.0, 12.0)
A33 = SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0)
u = SVector(1.0, 2.0, 3.0); v = SVector(4.0, 5.0, 6.0); w = SVector(-1.0, 0.5, 2.0)
C3 = SArray{Tuple{2,2,2}}(1.0:8.0...); D3 = SArray{Tuple{2,2,2}}(8.0:-1.0:1.0...)
cases = [Case(add, A, B), Case(mulmv, A, SVector(1.0, 2.0)), Case(mulmm, A, A23), Case(negcopy, A), Case(scale, A, 3.0),
         Case(selfmul, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0)), Case(mixedarray, A, SMatrix{2,2,Float32}(1, 2, 3, 4)),
         Case(vec3, u, v, w), Case(cube, C3, D3), Case(namedarray, A, B),
         Case(regmul, [1.0 2.0 3.0; 4.0 5.0 6.0], [1.0 0.0 2.0; 0.0 1.0 0.0; 3.0 0.0 1.0]), Case(regchain, [1.0 2.0; 3.0 4.0], 0.5),
         Case(regvec, [1.0 2.0 3.0; 4.0 5.0 6.0; 7.0 8.0 9.0], [1.0, 2.0, 3.0]),
         Case(blocks, A, B, B, A), Case(columns, A, B, B, A), Case(beside2, A, B), Case(cube3, A, B, B, A), Case(stack3, u, v),
         Case(ragged, A, B, SMatrix{2,4}(1.0:8.0...)), Case(mixedcols, 1, SVector(2, 3)), Case(mixedrows, 1, SMatrix{1,2}(2, 3)),
         Case(stack, u, v), Case(beside, u, v), Case(literal), Case(vlit), Case(svec), Case(smat),
         Case(scalerows, u, A33), Case(elementwise, u, v), Case(shifted, u), Case(outer, u, v), Case(asrow, u),
         Case(rowtimes, u, A32), Case(rowdot, u, v), Case(dotted, u, v), Case(crossed, u, v), Case(flipped, A23),
         Case(scalecols, u, A32), Case(byscalar, A32), Case(pmixed, A32, SMatrix{3,2,Float32}(1, 2, 3, 4, 5, 6)),
         Case(thin, SArray{Tuple{1,1,3}}(1.0, 2.0, 3.0), SMatrix{2,1}(4.0, 5.0)),
         Case(deep, SArray{Tuple{3,1,3}}(1.0:9.0...), SArray{Tuple{1,1,1,1,3,1,1}}(2.0, 3.0, 4.0)),
         Case(four, SArray{Tuple{2,2,2,2}}(1.0:16.0...), SArray{Tuple{2,2,2,2}}(16.0:-1.0:1.0...)), Case(rowplus, u, SVector(10.0, 20.0)),
         Case(abt, A23, B23), Case(atb, A32, B32), Case(atbt, A23, B32), Case(tr, A23), Case(atv, A32, u), Case(addt, A23, B32),
         Case(pt, A23, B32), Case(stored, A23), Case(rowstored, u, A32),
         Case(zeroed, SMatrix{3,4}(1.0:12.0...)), Case(zeroes), Case(zeroint), Case(oned, A33), Case(eye), Case(tallI), Case(ones34),
         Case(filled, 2.5), Case(divs, A, 4.0), Case(sdiv, 4.0, A), Case(permute, MVector(1.0, 2.0, 3.0))]
coef(A::M2) = -3A + 2 * A
zer(A::MMatrix{2,2,Float64,4}) = (A .= 0; A)
fil(A::MMatrix{2,2,Float64,4}, x::Float64) = (fill!(A, x); A)
filint(A::MMatrix{2,2,Float64,4}) = (A .= 1; A)
into(A::MMatrix{2,2,Float64,4}, B::M2) = (A .= B .* 2.0 .+ A; A)
addI(A::M2) = A + 2I
subI(A::M2) = A - I
rsubI(A::M2) = 2I - A
twoI() = SMatrix{2,2}(2I)
lt(v::V3, w::V3) = v .< w
ge0(v::V3) = v .>= 0.0
sel(c::SVector{3,Bool}, a::V3, b::V3) = ifelse.(c, a, b)
both(c::SVector{3,Bool}, d::SVector{3,Bool}) = c .& .!d
append!(cases, [Case(coef, A), Case(zer, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0)), Case(fil, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0), 2.5),
                Case(filint, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0)), Case(into, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0), A),
                Case(addI, A), Case(subI, A), Case(rsubI, A), Case(twoI), Case(lt, SVector(1.0, 5.0, 3.0), SVector(2.0, 4.0, 3.0)),
                Case(ge0, SVector(-1.0, 0.0, 1.0)), Case(sel, SVector(true, false, true), SVector(1.0, 2.0, 3.0), SVector(4.0, 5.0, 6.0)),
                Case(both, SVector(true, true, false), SVector(true, false, false))])
@testset "array text" begin
    src = csource("arraytext", coef, zer, addI, lt, sel)
    @test occursin("mul_s_2x2(-3.0, A, temp", src) && occursin("mul_s_2x2(2.0, A, temp", src)   # an integer coefficient takes the element type
    @test occursin("memset(A, 0, sizeof(double[2][2]));", src)
    @test occursin("addI_2x2(A, 2.0, out);", src) && occursin("out[i][i] += s;", src)
    @test occursin("ltP_3_3(v, w, out);", src) && occursin("out[i] = a[i] < b[i];", src) && occursin("bool out[restrict 3]", src)
    @test occursin("ifelseP_3B_3F64_3F64(c, a, b, out);", src) && occursin("out[i] = a[i] ? b[i] : c[i];", src)
end
targets = Any[f for f in unique(c.f for c in cases) if !(f in (regmul, regchain, regvec))]
append!(targets, [(regmul, Float64, 2, 3, Float64, 3, 3), (regchain, Float64, 2, 2, Float64), (regvec, Float64, 3, 3, Float64, 3)])
check("array", cases; targets)
end
