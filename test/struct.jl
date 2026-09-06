# Structs by value, mutable structs through a pointer, parametric structs, and tuples.
module Struct
using Test, StaticArrays
import Main: Case, check, csource

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
"A quaternion `w + xi + yj + zk`."
struct Quaternion
    w::Float64
    x::Float64
    y::Float64
    z::Float64
end
"The Hamilton product."
Base.:*(a::Quaternion, b::Quaternion) = Quaternion(
    a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
Base.adjoint(q::Quaternion) = Quaternion(q.w, -q.x, -q.y, -q.z)
function rotated(q::Quaternion, v::SVector{3,Float64})
    p = q * Quaternion(0.0, v[1], v[2], v[3]) * q'
    return SVector(p.x, p.y, p.z)
end
third(t::NTuple{3,Float64}) = t[1] + t[3]
viathird(a::Float64) = third((a, 2a, 3a))
function step(x::Float64, ẋ::Float64, dt::Float64)
    ẋ += dt * -x
    x += dt * ẋ
    return x, ẋ
end
function twice(x::Float64, ẋ::Float64, dt::Float64)
    x, ẋ = step(x, ẋ, dt)
    return step(x, ẋ, dt)
end
kept(x::Float64, dt::Float64) = (t = step(x, 0.0, dt); t[1] * t[2])

p = Point(3.0, 4.0); q = Point(1.0, 2.0); b = Body(SVector(1.0, 2.0, 3.0), 2.5); v = SVector(1.0, 1.0, 1.0)
check("struct", [Case(norm2, p), Case(make, 5.0, 6.0), Case(midpoint, Segment(p, q)), Case(momentum, b, v), Case(shifted, b, v),
                 Case(same, p, Point(3.0, 4.0)), Case(same, p, q), Case(swap, Pair2(1.0, 2.0)), Case(bump!, Counter(41)),
                 Case(peek, Counter(21)), Case(both, 1.5, 2), Case(untup, SVector(1.5, 2.0)), Case(held, 1.5, 3),
                 Case(tswap, 1.0, 2.0), Case(arrays, SVector(1.0, 2.0, 3.0)), Case(unarrays, SVector(1.0, 2.0, 3.0)),
                 Case(third, (1.0, 2.0, 3.0)), Case(viathird, 1.5), Case(step, 1.0, 0.0, 0.1), Case(twice, 1.0, 0.0, 0.1), Case(kept, 1.0, 0.1),
                 Case(rotated, Quaternion(cos(0.3), 0.0, 0.0, sin(0.3)), SVector(1.0, 0.0, 0.0))])
@testset "operator methods" begin
    # A method of a Julia operator on the user's struct is the user's function, named by
    # the operator's word; `a * b * c` is the two binary calls.
    src = csource("quaternion", rotated)
    @test occursin("Quaternion mul_Quaternion_Quaternion(Quaternion a, Quaternion b)", src) && occursin(" * The Hamilton product.", src)
    @test occursin("mul_Quaternion_Quaternion(mul_Quaternion_Quaternion(q, ", src) && occursin(r"\),\n\s+adjoint_Quaternion\(q\)\);", src)   # wrapped at the argument
    @test occursin("Quaternion adjoint_Quaternion(Quaternion q)", src)
end
@testset "tuple text" begin
    src = csource("tupletext", step, twice, kept, third, viathird, unarrays, tswap)
    # A returned tuple is the function's own struct, fields named after the variables returned.
    @test occursin("typedef struct {\n    double x;\n    double xdot;\n} step_t;", src) && occursin("step_t step(double x, double xdot, double dt)", src)
    @test occursin("return (step_t){x, xdot};", src)
    # Destructured at the call site by name; passed straight on, the callee's struct is inherited.
    @test occursin("step_t temp1_step = step(x, xdot, dt);\n    x = temp1_step.x;\n    xdot = temp1_step.xdot;", src) && occursin("step_t twice(", src) && occursin("return step(x, xdot, dt);", src)
    @test occursin("step_t t = step(x, 0.0, dt);", src) && occursin("return t.x * t.xdot;", src)
    # A tuple parameter is spread; a tuple built for a call goes as its elements.
    @test occursin("double third(double t1, double t2, double t3)", src) && occursin("return t1 + t3;", src) && occursin("return third(a, 2 * a, 3 * a);", src)
    # Variables returned in any order keep their names; an expression returned has none,
    # so `arrays`, returning `(v, 2.0 * v)`, gets the structural struct with positional fields.
    @test occursin("typedef struct {\n    double b;\n    double a;\n} tswap_t;", src) && occursin("return (tswap_t){b, a};", src)
    @test occursin("Tuple_3_3 temp1_arrays = arrays(v);", src)
end
end
