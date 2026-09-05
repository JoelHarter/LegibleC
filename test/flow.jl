# Control flow recovered from the IR: if/elseif/else, &&, ||, ?:, while, for, break,
# continue, early return, and loops over arrays.
module Flow
using Test, StaticArrays
import Main: Case, check

smaller(a::Float64, b::Float64) = (if a < b; x = a; else; x = b; end; x)
sign_(a::Float64) = (if a < 0.0; y = -1.0; elseif a == 0.0; y = 0.0; else; y = 1.0; end; y)
larger(a::Float64, b::Float64) = a > b ? a : b
quadrant(a::Float64, b::Float64) = (if a > 0.0 && b > 0.0; r = 1.0; elseif a < 0.0 || b < 0.0; r = -1.0; else; r = 0.0; end; r)
bothpos(a::Float64, b::Float64) = a > 0.0 && b > 0.0
guard(x::Float64) = (x < 0.0 && return 0.0; sqrt(x))
triangle(n::Int64) = (s = 0; i = 1; while i <= n; s += i; i += 1; end; s)
oddsum(n::Int64) = (s = 0; i = 0; while true; i += 1; i > n && break; i % 2 == 0 && continue; s += i; end; s)
squares(n::Int64) = (s = 0; for i in 1:n; s += i * i; end; s)
stepped(n::Int64) = (s = 0; for i in 2:3:n; s += i; end; s)
skipper(n::Int64) = (s = 0; for i in 1:n; i == 3 && continue; i > 6 && break; s += i; end; s)
total(v::SVector{3,Float64}) = (s = 0.0; for i in eachindex(v); s += v[i]; end; s)
totalvec(v::Vector{Float64}) = (s = 0.0; for i in 1:length(v); s += v[i]; end; s)
trace(A::SMatrix{3,3,Float64,9}) = (t = 0.0; for i in 1:3; t += A[i, i]; end; t)
gridsum(A::SMatrix{2,3,Float64,6}) = (s = 0.0; for i in 1:2, j in 1:3; s += A[i, j]; end; s)
double1(v::MVector{3,Float64}) = (v[1] = 2.0 * v[2]; v)
basis(n::Float64) = (v = zeros(3); v[1] = n; v)
outer(u::SVector{2,Float64}, v::SVector{3,Float64}) = (M = zeros(2, 3); for i in 1:2, j in 1:3; M[i, j] = u[i] * v[j]; end; M)
sizes(v::SVector{3,Float64}, A::SMatrix{2,3,Float64,6}) = length(v) + size(A, 1) + size(A, 2)

v3 = SVector(1.0, 2.0, 3.5)
A3 = SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0)
A23 = SMatrix{2,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
cases = [Case(smaller, 1.0, 2.0), Case(smaller, 3.0, 2.0), Case(sign_, -3.0), Case(sign_, 0.0), Case(sign_, 2.0),
         Case(larger, 1.0, 2.0), Case(quadrant, 1.0, 1.0), Case(quadrant, -1.0, 2.0), Case(quadrant, 0.0, 0.0),
         Case(bothpos, 1.0, -1.0), Case(guard, -4.0), Case(guard, 4.0), Case(triangle, 10), Case(oddsum, 10),
         Case(squares, 5), Case(stepped, 11), Case(skipper, 10), Case(total, v3), Case(totalvec, [1.0, 2.0, 3.0, 4.0]),
         Case(trace, A3), Case(gridsum, A23), Case(double1, MVector(1.0, 2.0, 3.0)), Case(basis, 2.5),
         Case(outer, SVector(1.0, 2.0), v3), Case(sizes, v3, A23)]
check("flow", cases; targets=[smaller, sign_, larger, quadrant, bothpos, guard, triangle, oddsum, squares, stepped, skipper,
                              total, (totalvec, Float64, 4), trace, gridsum, double1, basis, outer, sizes])
end
