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
squares(v::V3) = v .^ 2 .+ v .^ 3 .+ v .^ -1 .+ v .^ 5
lifted(v::V3) = exp.(v) .+ 1.0
append!(cases, [Case(coef, A), Case(zer, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0)), Case(fil, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0), 2.5),
                Case(filint, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0)), Case(into, MMatrix{2,2}(1.0, 2.0, 3.0, 4.0), A),
                Case(addI, A), Case(subI, A), Case(rsubI, A), Case(twoI), Case(lt, SVector(1.0, 5.0, 3.0), SVector(2.0, 4.0, 3.0)),
                Case(ge0, SVector(-1.0, 0.0, 1.0)), Case(sel, SVector(true, false, true), SVector(1.0, 2.0, 3.0), SVector(4.0, 5.0, 6.0)),
                Case(both, SVector(true, true, false), SVector(true, false, false)), Case(squares, SVector(1.5, 2.0, -0.5)), Case(lifted, v)])
@testset "array text" begin
    src = csource("arraytext", coef, zer, addI, lt, sel)
    @test occursin("mul_s_2x2(-3.0, A, temp", src) && occursin("mul_s_2x2(2.0, A, temp", src)   # an integer coefficient takes the element type
    @test occursin("memset(A, 0, sizeof(double[2][2]));", src)
    @test occursin("addI_2x2(A, 2.0, out);", src) && occursin("out[i][i] += s;", src)
    @test occursin("ltP_3_3(v, w, out);", src) && occursin("out[i] = a[i] < b[i];", src) && occursin("bool out[restrict 3]", src)
    @test occursin("ifelseP_3B_3F64_3F64(c, a, b, out);", src) && occursin("out[i] = a[i] ? b[i] : c[i];", src)
    sq = csource("squares", squares)
    @test occursin("/// 3-vector element-wise square\n/// out = a .^ 2\nstatic inline void pow2P_3(const double a[3], double out[3]) {\n    for (int i = 0; i < 3; i++) {\n        out[i] = a[i] * a[i];", sq)
    @test occursin("out[i] = 1.0 / a[i];", sq) && occursin("out[i] = powi(a[i], 5);", sq) && occursin("pow2P_3(v, temp", sq)
end
targets = Any[f for f in unique(c.f for c in cases) if !(f in (regmul, regchain, regvec))]
append!(targets, [(regmul, Float64, 2, 3, Float64, 3, 3), (regchain, Float64, 2, 2, Float64), (regvec, Float64, 3, 3, Float64, 3)])
check("array", cases; targets)

# Variables that live in `out` from the start (`outplacement!`): a reassigned parameter's
# working copy made there, a local built there, and the cases that must keep the copies.
const M3 = SMatrix{3,3,Float64,9}
function state(x::V3, v::V3, dt::Float64)          # both halves placed: no copies at the end
    r = norm(x)
    a = -x / r^3
    v = v + dt * a
    x = x + dt * v
    return [x; v]
end
function whole(x::V3, s::Float64)                  # returned whole: placed at 0
    x = x * s
    x = x + x
    return x
end
function grown(a::V3)                              # locals built in out
    b = a .* 2
    c = b .+ 1.0
    return [b; c]
end
function swapped(x::V3, v::V3, flag::Bool)         # two returns disagree on the places: refused
    x = x + v
    flag && return [v; x]
    return [x; v]
end
function scaled(x::V3, v::V3, flag::Bool)          # another return computes into out from a placed variable: refused
    x = x + v
    flag && return [x; v] .* 2.0
    return [x; v]
end
function turned(x::V3, M::M3)                      # a product into itself keeps its temp; the doubled half is copied
    x = M * x
    return [x; x .* 2]
end
function bottom()                                  # `end` on a regular array the transpiler sized itself: folded, as for a static one
    m = [4; 5.0; 4;; 8; 9; 8;; 1; 2; 0]
    return m[2:end, 1:2]
end
function tail(v::SVector{5,Float64})
    w = [v[1]; v[2]; 3.0; 4.0]
    return w[2:end]
end
function stacked(A::SMatrix{2,3,Float64,6}, r::SVector{3,Float64})   # a matrix's rows in out, a row vector copied beside them
    A = A .* 2
    return [A; r']
end
function sliced()                                   # `a = …` as the last line, of a regular array: computed into the parameter, which is `a`
    m = [4; 5.0; 4;; 8; 9; 8;; 1; 2; 0]
    a = m[2, :]
end
function either(v::SVector{3,Float64}, c::Bool)     # `return a` and `a = …` as the last line agree: the parameter is `a`
    if c
        a = v * 2
        return a
    end
    a = v * 3
end
function aliased(v::MVector{3,Float64})             # a second name for one mutable array, then a write through it: a pointer (`names`, below)
    m = v
    m[2] = 77.0
    return v[2]
end
function copied(v::MVector{3,Float64})              # a copy, said so, is a copy in both
    m = copy(v)
    m[2] = 77.0
    return v[2] + m[2]
end
function renamed(v::MVector{3,Float64})             # a second name nobody writes through is harmless
    m = v
    return m[1] + v[2]
end
const K3 = SMatrix{3,3}(1.0, 4.0, 7.0, 2.0, 5.0, 8.0, 3.0, 6.0, 10.0)
function flipself(a::SMatrix{3,3,Float64,9}, n::Int64)   # `a = a'` onto its own storage would read what it has written: through a temp
    for k in 1:n
        a = a'
        a = a .+ Float64(k) .* K3
    end
    return a
end
function literalend(k::Int64)                       # `end` as a plain index, and inside arithmetic, on a regular array
    m = [4.0 8.0 1.0; 5.0 9.0 2.0; 6.0 7.0 3.0]
    r = m[end, :]
    c = m[2:end, end]
    b = m[1:end-1, 2:end]
    return r[k] + 10.0 * c[end] + 100.0 * b[end, 1] + 1000.0 * b[1, end]
end
lastof(v::SVector{3,Float64}) = v[end] + v[end-1] * 10.0
function resized()                                  # one size per variable, as one type
    a = [1.0; 2.0]
    a = [1.0; 2.0; 3.0]
    return a
end
# Index lists, a gather: `[1, 3]` written out is one copy per listed index, in one nest
# where they share loops; a list held at run time is a loop reading `idx[i] - 1`.
function selected()
    m = [4; 5.0; 4;; 8; 9; 8;; 1; 2; 0]
    a = m[2:end, [1, 3]]
end
reorder(v::SVector{3,Float64}) = v[[3, 1, 2]]
chosen(v::SVector{5,Float64}, idx::SVector{3,Int64}) = v[idx]
function placed(A::MMatrix{2,4,Float64,8}, B::SMatrix{2,2,Float64,4}); A[:, [1, 3]] = B; return A; end
function spread!(v::MVector{5,Float64}, w::SVector{2,Float64}, idx::SVector{2,Int64}); v[idx] = w; return v; end
outside(v::SVector{3,Float64}) = v[[1, 4]]
check("gather", [Case(selected), Case(reorder, SVector(1.0, 2.0, 3.0)), Case(chosen, SVector(1.0, 2.0, 3.0, 4.0, 5.0), SVector(5, 1, 3)),
                 Case(placed, MMatrix{2,4}(1.0:8...), SMatrix{2,2}(10.0, 20.0, 30.0, 40.0)),
                 Case(spread!, MVector(1.0, 2.0, 3.0, 4.0, 5.0), SVector(9.0, 8.0), SVector(4, 2))])
@testset "gather" begin
    src = csource("gather", selected, reorder, chosen, placed, spread!)
    @test occursin("for (int i = 0; i < 2; i++) {\n        a[i][0] = m[1 + i][0];\n        a[i][1] = m[1 + i][2];\n    }", src) && !occursin("int64_t temp", src)   # the list is never built
    @test occursin("out[0] = v[2];\n    out[1] = v[0];\n    out[2] = v[1];", src)
    @test occursin("out[i] = v[idx[i] - 1];", src)
    @test occursin("A[i][0] = B[i][0];\n        A[i][2] = B[i][1];", src)
    @test occursin("v[idx[i] - 1] = w[i];", src)
    @test_throws ArgumentError csource("outside", outside)   # a listed index beyond the dimension, refused at transpile time
end

check("outplaced", [Case(state, SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0), 0.1), Case(whole, SVector(1.0, 2.0, 3.0), 2.0), Case(grown, SVector(1.0, 2.0, 3.0)),
                    Case(swapped, SVector(1.0, 2.0, 3.0), SVector(4.0, 5.0, 6.0), true), Case(swapped, SVector(1.0, 2.0, 3.0), SVector(4.0, 5.0, 6.0), false),
                    Case(scaled, SVector(1.0, 2.0, 3.0), SVector(4.0, 5.0, 6.0), true), Case(scaled, SVector(1.0, 2.0, 3.0), SVector(4.0, 5.0, 6.0), false),
                    Case(turned, SVector(1.0, 2.0, 3.0), SMatrix{3,3}(1.0:9...)), Case(stacked, SMatrix{2,3}(1.0:6...), SVector(7.0, 8.0, 9.0)),
                    Case(bottom), Case(tail, SVector(1.0, 2.0, 3.0, 4.0, 5.0)), Case(sliced), Case(either, SVector(1.0, 2.0, 3.0), true), Case(either, SVector(1.0, 2.0, 3.0), false),
                    Case(copied, MVector(1.0, 2.0, 3.0)), Case(renamed, MVector(1.0, 2.0, 3.0)),
                    Case(flipself, SMatrix{3,3}(2.0, -1.0, 0.5, 3.0, 1.5, -2.0, 0.25, 4.0, 1.0), 2),
                    Case(literalend, 2), Case(lastof, SVector(1.0, 2.0, 3.0))])
@testset "outplaced" begin
    src = csource("outplaced", state, whole, grown, swapped, scaled, turned, stacked, sliced, either)
    fn(name) = (i = findfirst("void $name(", src)[1]; src[i:findnext("\n}", src, i)[end]])
    @test occursin("// copy x and v into out, where the function works on them and returns them\n    memcpy(out, x, sizeof(double[3]));\n    double *x_local = out;\n    memcpy(&out[3], v, sizeof(double[3]));\n    double *v_local = &out[3];", src)
    @test occursin("add_3(x_local, temp2_dt_v, x_local);  // x_local += temp2_dt_v", fn("state")) && !occursin("memcpy(out, x_local", fn("state")) && !occursin("memcpy(&out[3], v_local", fn("state"))
    @test occursin("// copy x into out, where the function works on it and returns it\n    memcpy(out, x, sizeof(double[3]));\n    double *x_local = out;", src) && occursin("mul_3_s(x_local, s, x_local);", src)
    @test occursin("// b and c are built in out, where the function returns them\n    double *b = out;\n    double *c = &out[3];", src) && occursin("mulP_3F64_sI64(a, 2, b);", src) && occursin("addP_3_s(b, 1.0, c);", src)
    @test occursin("double x_local[3];\n    memcpy(x_local, x, sizeof x_local);", src)          # swapped and scaled: the copy stays
    @test occursin("mul_3x3_3(M, x_local, temp1_M_x);", src) && occursin("memcpy(x_local, temp1_M_x, sizeof temp1_M_x);", src)   # turned: through a temp, into place
    @test occursin("memcpy(out, A, sizeof(double[2][3]));\n    double (*A_local)[3] = out;", src) && occursin("mulP_2x3F64_sI64(A_local, 2, A_local);", src) && occursin("memcpy(out[2], r, sizeof(double[3]));", src)   # stacked
    @test occursin("void sliced(double a[restrict 3])", src) && occursin("a = m[2, :]\n    memcpy(a, m[1], sizeof(double[3]));\n}", src)   # one copy, into the parameter
    @test occursin("double m[3][3] = {\n        {4, 8, 1},\n        {5.0, 9, 2},\n        {4, 8, 0},\n    };", src)   # a literal is declared with its initializer, a row per line
    @test occursin("void either(const double v[3], bool c, double a[restrict 3])", src) && occursin("mul_3_s(v, 2.0, a);\n\n        // @", src) && occursin("mul_3_s(v, 3.0, a);\n}", src) && !occursin("double *a = out", src)
    @test_throws ArgumentError csource("resized", resized)
end

# One array under two names (`src/storage.jl`). Julia's mutable arrays keep a name and its
# storage apart; C's array variable is both at once. A variable that is given another's array
# is a pointer: a second name if that happens once, a moving name if it happens again.
function namezero!(v::MVector{3,Float64})
    m = v
    m[1] = 0.0
    return nothing
end
function namecaller()                                # the caller sees a write made through a second name of a parameter
    a = MVector(1.0, 2.0, 3.0)
    namezero!(a)
    return a[1] + 10.0 * a[2]
end
function namechain(v::MVector{3,Float64})
    m = v
    k = m
    k[3] = 9.0
    m[2] = 8.0
    return v[1] + v[2] + v[3]
end
function namejacobi(A::SMatrix{3,3,Float64,9}, b::SVector{3,Float64}, n::Int64)   # two buffers, swapped each pass: no copy
    x = zeros(MVector{3,Float64})
    xnew = zeros(MVector{3,Float64})
    for k in 1:n
        for i in 1:3
            s = b[i]
            for j in 1:3
                j != i && (s -= A[i, j] * x[j])
            end
            xnew[i] = s / A[i, i]
        end
        x, xnew = xnew, x
    end
    return x[1] + 10.0 * x[2] + 100.0 * x[3]
end
function nameswap!(a::MVector{3,Float64}, b::MVector{3,Float64})     # parameters are pointers already
    a, b = b, a
    a[1] = 0.0
    return b[1]
end
function nameswapcaller()
    a = MVector(1.0, 2.0, 3.0)
    b = MVector(4.0, 5.0, 6.0)
    r = nameswap!(a, b)
    return r + 10.0 * a[1] + 100.0 * b[1]
end
function nameinplace(v::MVector{3,Float64})
    m = v
    v .= m .* 2.0
    m[1] += 1.0
    return v[1] + v[2] + m[3]
end
function namematrix(A::MMatrix{2,3,Float64,6})
    M = A
    M[1, 2] = 9.0
    return A[1, 2] + M[2, 3]
end
function nameeither(c::Bool, u::MVector{3,Float64}, w::MVector{3,Float64})
    best = u
    if c
        best = w
    end
    best[2] = -1.0
    return u[2] + 10.0 * w[2]
end
function namebyhand(n::Int64)
    x = MVector(1.0, 2.0, 3.0)
    y = MVector(4.0, 5.0, 6.0)
    for k in 1:n
        y[1] = x[1] + k
        t = x
        x = y
        y = t
    end
    return x[1] + 10.0 * y[1]
end
function namereturned(n::Int64)
    x = MVector(1.0, 2.0, 3.0)
    y = MVector(4.0, 5.0, 6.0)
    for k in 1:n
        y[2] = x[2] * 2.0
        x, y = y, x
    end
    return x
end
function nameworking(a::MVector{3,Float64})          # a parameter's working copy given a new array stays a copy
    a = a .+ 1.0
    a[1] = 0.0
    return a[1] + a[2]
end
function nameworkingcaller()
    a = MVector(1.0, 2.0, 3.0)
    r = nameworking(a)
    return r + 10.0 * a[1]
end
function namebump!(v::MVector{3,Float64})
    v[2] += 100.0
    return nothing
end
function namehanded(v::MVector{3,Float64})           # a second name handed to a function that writes
    m = v
    namebump!(m)
    return v[2]
end
mutable struct NameHolder
    v::MVector{3,Float64}
    k::Int64
end
struct NameFrozen
    v::MVector{3,Float64}
    k::Int64
end
function namefield(h::NameHolder)                    # a second name for the array a mutable struct holds
    m = h.v
    m[1] = 42.0
    return h.v[1]
end
function namefrozen(p::NameFrozen)                   # a struct passed by value, its array with it: the write would reach a copy
    p.v[1] = 42.0
    return nothing
end
function namefrozenfield(p::NameFrozen)
    m = p.v
    m[2] = 7.0
    return p.v[2]
end
function nameregular(v::Vector{Float64})
    m = v
    m[2] = 5.0
    return v[2] + m[1]
end
function nameregularmatrix(A::Matrix{Float64})
    M = A
    M[2, 1] = -3.0
    return A[2, 1] + M[1, 2]
end
function nameregularswap(n::Int64)
    x = zeros(3)
    y = zeros(3)
    for k in 1:n
        y[1] = x[1] + 1.0
        y[3] = x[3] + k
        x, y = y, x
    end
    return x[1] + 10.0 * x[3]
end
function namerotate(n::Int64)
    a = MVector(1.0, 0.0, 0.0)
    b = MVector(2.0, 0.0, 0.0)
    c = MVector(3.0, 0.0, 0.0)
    for k in 1:n
        a[2] += 1.0
        a, b, c = b, c, a
    end
    return a[1] + 10.0 * b[1] + 100.0 * c[1] + 1000.0 * (a[2] + 2.0 * b[2] + 4.0 * c[2])
end
function namestale(v::MVector{3,Float64})            # a new array while another name still holds the old one: refused
    w = zeros(MVector{3,Float64})
    m = w
    w = zeros(MVector{3,Float64})
    w[1] = 1.0
    return m[1] + w[1]
end
@testset "names" begin
    A = SMatrix{3,3}(4.0, 1.0, 0.0, 1.0, 5.0, 1.0, 0.0, 1.0, 6.0)
    src = check("names", [Case(aliased, MVector(1.0, 2.0, 3.0)), Case(namecaller), Case(namechain, MVector(1.0, 2.0, 3.0)),
        Case(namejacobi, A, SVector(1.0, 2.0, 3.0), 1), Case(namejacobi, A, SVector(1.0, 2.0, 3.0), 4), Case(namejacobi, A, SVector(1.0, 2.0, 3.0), 7),
        Case(nameswapcaller), Case(nameinplace, MVector(1.0, 2.0, 3.0)), Case(namematrix, MMatrix{2,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)),
        Case(nameeither, true, MVector(1.0, 2.0, 3.0), MVector(4.0, 5.0, 6.0)), Case(nameeither, false, MVector(1.0, 2.0, 3.0), MVector(4.0, 5.0, 6.0)),
        Case(namebyhand, 1), Case(namebyhand, 2), Case(namebyhand, 5), Case(namereturned, 0), Case(namereturned, 3),
        Case(nameworkingcaller), Case(namehanded, MVector(1.0, 2.0, 3.0))])
    @test occursin("double aliased(double v[3]) {", src) && occursin("double *const m = v;\n", src)             # written through: the parameter is not `const`
    @test occursin("double *const k = m;", src)
    @test occursin("double x_data[3];\n    memset(x_data, 0, sizeof(double[3]));\n    double *x = x_data;", src) && occursin("double *xnew = xnew_data;", src)
    @test occursin("double x_data[3] = {1.0, 2.0, 3.0};\n    double *x = x_data;", src)                                # built in its own storage, as any array is
    @test occursin("double *temp1_x = x;\n        x = xnew;\n        xnew = temp1_x;", src)                       # the swap: three pointers, no copy
    @test occursin("double *temp1_a = a;\n    a = b;\n    b = temp1_a;", src)                                   # two parameters swapped: no declaration at all
    @test occursin("double (*const M)[3] = A;", src)
    @test occursin("double *best = u;", src) && occursin("best = w;", src)
    @test occursin("double a_local[3];", src)                                                                   # the working copy that stays one
    @test_throws ArgumentError csource("namestale", namestale)
    src = check("namesmore", [Case(namefield, NameHolder(MVector(1.0, 2.0, 3.0), 1)), Case(nameregular, [1.0, 2.0, 3.0]), Case(nameregularmatrix, [1.0 2.0; 3.0 4.0]),
        Case(nameregularswap, 3), Case(namerotate, 1), Case(namerotate, 2), Case(namerotate, 4)];
        targets=[namefield, (nameregular, Float64, 3), (nameregularmatrix, Float64, 2, 2), nameregularswap, namerotate])
    @test occursin("double *const m = h->v;", src) && occursin("double (*const M)[2] = A;", src)
    @test_throws ArgumentError csource("namefrozen", namefrozen)
    @test_throws ArgumentError csource("namefrozenfield", namefrozenfield)
    @test_throws ArgumentError csource("nameunsized", nameregular)                    # a refusal, not a fault
end
# One index into a matrix: Julia counts through the whole array down its columns, the C is
# stored by rows, so the index is taken apart into one for each dimension. It is written
# once for each, so it is never an expression written in place. `(undef)` is the declaration.
fixedlinear(A::SMatrix{2,3,Float64,6}) = A[5] + 10.0 * A[2] + 100.0 * A[6]
movinglinear(A::SMatrix{2,3,Float64,6}, k::Int64) = A[k] + A[k + 1]
cubelinear(T::SArray{Tuple{2,3,2},Float64,3,12}, k::Int64) = T[k] + T[11]
function storedlinear(k::Int64)
    M = MMatrix{2,3,Float64}(undef)
    fill!(M, 0.0)
    M[k] = 7.0
    M[4] = 2.0
    return M[1, 2] + 10.0 * M[2, 2] + 100.0 * M[k]
end
@testset "linear index" begin
    A23 = SMatrix{2,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
    T232 = SArray{Tuple{2,3,2}}(collect(1.0:12.0)...)
    check("linearindex", [Case(fixedlinear, A23); [Case(movinglinear, A23, k) for k in 1:5];
                          [Case(cubelinear, T232, k) for k in (1, 2, 3, 7, 12)]; [Case(storedlinear, k) for k in (1, 3, 6)]])
    src = csource("linearindextext", fixedlinear, movinglinear, cubelinear, storedlinear)
    @test occursin("return A[0][2] + 10.0 * A[1][0] + 100.0 * A[1][2];", src)
    @test occursin("int64_t temp1_k = k + 1;", src) && occursin("A[(k - 1) % 2][(k - 1) / 2]", src)
    @test occursin("T[(k - 1) % 2][((k - 1) / 2) % 3][(k - 1) / 6] + T[0][2][1]", src)
    @test occursin("double M[2][3];\n", src) && occursin("M[(k - 1) % 2][(k - 1) / 2] = 7.0;", src) && occursin("M[1][1] = 2.0;", src)
end

# Found on 2026-09-21 by readers who attacked the code on paper and wrote what they expected to break:
# each of these compiled and answered wrongly, or did not compile, or was refused for no reason.
function arraystoreoncetick(c::MVector{2,Int64})
    c[1] += 1
    return c[1]
end
function arraystoreonce(x::Float64)
    c = MVector{2,Int64}(0, 0)
    M = MMatrix{2,2,Float64}(undef)
    fill!(M, 0.0)
    M[arraystoreoncetick(c)] = x
    return M[1] + 10.0 * M[2] + 100.0 * M[3] + 1000.0 * M[4] + 10000.0 * c[1]
end
arraytransposedelement(A::SMatrix{3,3,Float64,9}, i::Int64, j::Int64) = (A')[i, j] + 10.0 * transpose(A)[j, i]
arraynormint(v::SVector{3,Int64}) = norm(v, 1) + 10.0 * norm(v, Inf)
function arrayintsum(a::SVector{3,Int64}, b::SVector{3,Int64}, c::SVector{3,Float64})
    d = a + b
    e = a + b + c
    return e[1] + e[2] + e[3] + d[2]
end
arrayquadratic(v::SVector{3,Float64}, A::SMatrix{3,3,Float64,9}, w::SVector{3,Float64}) = v' * A * w
arrayscaledrowcol(s::Float64, v::SVector{3,Float64}, w::SVector{3,Float64}) = s * v' * w
arrayrowcolmatrix(v::SVector{2,Float64}, w::SVector{2,Float64}, A::SMatrix{2,2,Float64,4}) = v' * w * A
@testset "hunt" begin
    check("huntarray", [Case(arrayquadratic, SVector(1.0, -2.0, 3.5), SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.5), SVector(0.5, 0.25, -1.0)),
        Case(arrayscaledrowcol, 2.5, SVector(1.0, -2.0, 3.5), SVector(0.5, 0.25, -1.0)),
        Case(arrayrowcolmatrix, SVector(0.3, 0.7), SVector(2.0, -1.0), SMatrix{2,2}(1.0, 2.0, 3.0, 4.5)),
        Case(arraystoreonce, 7.0), Case(arraystoreonce, -2.5),
        Case(arraytransposedelement, SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0), 1, 2), Case(arraytransposedelement, SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0), 3, 1), Case(arraytransposedelement, SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0), 2, 2),
        Case(arraynormint, SVector(3, -4, 2)), Case(arraynormint, SVector(-1, 0, -9)),
        Case(arrayintsum, SVector(1, 2, 3), SVector(10, 20, 30), SVector(0.5, 0.25, 0.125))])
end

# Found by the critic who looked for what the other readers had not attacked (2026-09-21).
gapsizedim(A::SMatrix{2,3,Float64,6}, d::Int64) = 10 * size(A, d) + d
# An irrational beside an array (2026-09-30): Julia gives `π` the type it meets, the array's
# floating element type, or Float64 beside integers. It reached the helper's name as
# `Irrational{:π}`, which has no C spelling, and was refused.
piscaled(A::SMatrix{2,2,Float64,4}) = π * A
pishifted(A::SMatrix{2,2,Float64,4}) = π * A .+ SVector(1.0, 2.0)
pidotted(v::SVector{3,Float64}) = π .* v
pidivided(v::SVector{3,Float64}) = v / ℯ
pisingle(v::SVector{3,Float32}) = π * v
piinteger(v::SVector{3,Int64}) = v * π
pibroadcastint(v::SVector{3,Int64}) = v .+ π
@testset "irrational beside an array" begin
    A = SMatrix{2,2}(1.0, 2.0, 3.0, 4.0)
    src = check("irrational", [Case(piscaled, A), Case(pishifted, A), Case(pidotted, SVector(1.0, 2.0, 3.0)), Case(pidivided, SVector(1.0, 2.0, 3.0)),
        Case(pisingle, SVector(1.0f0, 2.0f0, 3.0f0)), Case(piinteger, SVector(1, 2, 3)), Case(pibroadcastint, SVector(1, 2, 3))])
    @test occursin("mul_s_2x2(LEGIBLEC_PI, A, out);", src) && occursin("mulP_s_3(LEGIBLEC_PI, v, out);", src) && occursin("div_3_s(v, LEGIBLEC_E, out);", src)
    @test occursin("mul_sF32_3F32((float)LEGIBLEC_PI, v, out);", src)                       # rounded to the type it meets, as Julia rounds it
    @test occursin("mul_3I64_sF64(v, LEGIBLEC_PI, out);", src) && occursin("addP_3I64_sF64(v, LEGIBLEC_PI, out);", src)   # Float64 beside integers
end
@testset "gap" begin
    @test_throws ArgumentError csource("gapsizedim", gapsizedim)
end
end
