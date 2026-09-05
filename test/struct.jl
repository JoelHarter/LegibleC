# Structs by value, mutable structs through a pointer, parametric structs, and tuples.
module Struct
using Test, StaticArrays
import Main: Case, check

struct Point
    x::Float64
    y::Float64
end
struct Segment
    a::Point
    b::Point
end
struct Body
    pos::SVector{3,Float64}
    mass::Float64
end
struct Pair2{T}
    first::T
    second::T
end
mutable struct Counter
    n::Int64
end

norm2(p::Point) = p.x^2 + p.y^2
make(x::Float64, y::Float64) = Point(x, y)
midpoint(s::Segment) = Point((s.a.x + s.b.x) / 2, (s.a.y + s.b.y) / 2)
momentum(b::Body, v::SVector{3,Float64}) = b.mass * v
shifted(b::Body, d::SVector{3,Float64}) = Body(b.pos + d, b.mass)
same(p::Point, q::Point) = p == q
swap(p::Pair2{Float64}) = Pair2(p.second, p.first)
bump!(c::Counter) = (c.n += 1; c)
peek(c::Counter) = c.n * 2
both(a::Float64, b::Int64) = (a * 2, b + 1)
function untup(v::SVector{2,Float64})
    x, y = both(v[1], 2)
    return x + y
end
function held(a::Float64, b::Int64)
    t = (a, b)
    return t[2] * t[1]
end
tswap(a::Float64, b::Float64) = (b, a)
arrays(v::SVector{3,Float64}) = (v, 2.0 * v)
function unarrays(v::SVector{3,Float64})
    p, q = arrays(v)
    return p + q
end
third(t::NTuple{3,Float64}) = t[1] + t[3]

p = Point(3.0, 4.0); q = Point(1.0, 2.0); b = Body(SVector(1.0, 2.0, 3.0), 2.5); v = SVector(1.0, 1.0, 1.0)
check("struct", [Case(norm2, p), Case(make, 5.0, 6.0), Case(midpoint, Segment(p, q)), Case(momentum, b, v), Case(shifted, b, v),
                 Case(same, p, Point(3.0, 4.0)), Case(same, p, q), Case(swap, Pair2(1.0, 2.0)), Case(bump!, Counter(41)),
                 Case(peek, Counter(21)), Case(both, 1.5, 2), Case(untup, SVector(1.5, 2.0)), Case(held, 1.5, 3),
                 Case(tswap, 1.0, 2.0), Case(arrays, SVector(1.0, 2.0, 3.0)), Case(unarrays, SVector(1.0, 2.0, 3.0)),
                 Case(third, (1.0, 2.0, 3.0))])
end
