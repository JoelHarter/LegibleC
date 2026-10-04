# Structs by value, mutable structs through a pointer, parametric structs, and tuples.
module Struct
using Test, StaticArrays
using LinearAlgebra: dot, cross
using LinearAlgebra: ⋅, ×
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
"A quaternion as a scalar part and a vector part."
struct Quat
    w::Float64
    v::SVector{3,Float64}
end
Base.:*(a::Quat, b::Quat) = Quat(a.w * b.w - a.v ⋅ b.v, a.w * b.v + b.w * a.v + a.v × b.v)
Base.conj(q::Quat) = Quat(q.w, -q.v)
Base.adjoint(q::Quat) = conj(q)
turned(q::Quat, v::SVector{3,Float64}) = (q * Quat(0.0, v) * q').v
# Placement: an array computed straight into the field it is built into (`placement`).
struct Bag
    v::SVector{3,Float64}
    w::Float64
end
vsum(b::Bag) = sum(b.v) + b.w
function spun(axis::SVector{3,Float64}, θ::Float64)                  # into the returned struct
    s, c = sincos(θ / 2)
    return Quat(c, s * axis)
end
function spun2(axis::SVector{3,Float64}, θ::Float64)                 # into a variable, used on
    s, c = sincos(θ / 2)
    q = Quat(c, s * axis)
    return (q * q).w
end
function rebuilt(q::Quat, s::Float64)                                 # the sibling field reads the destination: refused
    q = Quat(sum(q.v), s * q.v)
    return q.w + q.v[1]
end
function bagged(b::Bag, axis::SVector{3,Float64}, s::Float64)        # a call between receives the destination: refused
    b = Bag(s * axis, vsum(b))
    return vsum(b)
end
function counted(c::Counter, axis::SVector{3,Float64}, s::Float64)   # an effect between with no path to the destination: placed
    b = Bag(s * axis, Float64(peek(bump!(c))))
    return vsum(b)
end
paired(c::Counter, axis::SVector{3,Float64}, s::Float64) = (s * axis, Float64(peek(bump!(c))))   # into the returned tuple's field
struct Bag3
    v::SVector{3,Float64}
    w::Float64
    z::Float64
end
function early(b::Bag3, axis::SVector{3,Float64}, s::Float64, bad::Bool)     # a return between that sees the destination: refused
    b = Bag3(s * axis, 1.0, (bad && return b.z; 2.0))
    return b.v[1] + b.z
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
check("placement", [Case(spun, SVector(0.0, 0.0, 1.0), 0.6), Case(spun2, SVector(0.0, 1.0, 0.0), 0.6), Case(rebuilt, Quat(1.0, SVector(1.0, 2.0, 3.0)), 2.0),
                    Case(bagged, Bag(SVector(1.0, 2.0, 3.0), 4.0), SVector(1.0, 0.0, 0.0), 2.0), Case(counted, Counter(1), SVector(1.0, 0.0, 0.0), 2.0),
                    Case(paired, Counter(1), SVector(1.0, 0.0, 0.0), 2.0),
                    Case(early, Bag3(SVector(1.0, 2.0, 3.0), 4.0, 5.0), SVector(1.0, 0.0, 0.0), 2.0, true), Case(early, Bag3(SVector(1.0, 2.0, 3.0), 4.0, 5.0), SVector(1.0, 0.0, 0.0), 2.0, false)])
# A property the author defines (2026-10-01): `getproperty(q, s) = s === :x ? … : getfield(q, s)` takes
# the name at run time, which C can't pass. Refused with the field it was asked for; it was a
# fault before, and one of Julia's own errors was taken for a refusal and garbled on the way out.
struct Spinner
    w::Float64
    v::SVector{3,Float64}
end
Base.getproperty(s::Spinner, f::Symbol) = f === :x ? getfield(s, :v)[1] : getfield(s, f)
spinx(s::Spinner) = s.x * 2.0
spinw(s::Spinner) = s.w * 2.0
spinfield(s::Spinner) = getfield(s, :v)[1] * 2.0
@testset "property" begin
    e = try csource("spinx", spinx); nothing catch e; e end
    @test e isa ArgumentError && occursin("`s.x` goes through the `getproperty` method of the author's at struct.jl:", e.msg) && occursin("getfield(s, :x)", e.msg)
    @test_throws ArgumentError csource("spinw", spinw)                # the method is asked even where it would fall through
    check("spinfield", [Case(spinfield, Spinner(1.0, SVector(2.0, 3.0, 4.0)))])
    @test Main.LegibleC.refusal(ArgumentError("ours")) && !Main.LegibleC.refusal(ArgumentError(LazyString("invalid index: ", nothing)))
end

# The name of a struct with type parameters (2026-10-03): the parameters run on after the name.
# The innermost list is joined by one `x`, each list around it by one more than the deepest thing
# it holds: what belongs together sits closest. An array's `3x3` is the same rule. No underscore,
# which in a function's name means "next argument".
struct GBody{N}; a::Float64; end
struct GObj{A,B,C}; a::Float64; end
struct GTwo{A,B}; a::Float64; end
struct GInner{A,B}; a::Float64; end
struct GOuter{A,B}; a::Float64; end
gscale(p::Pair2{Float64}, s::Float64) = Pair2(p.first * s, p.second * s)
@testset "name grammar" begin
    Main.LegibleC.scope[] = @__MODULE__                  # this module's names are bare, as in a file transpiled from it
    name(T) = Main.LegibleC.structname(T)
    @test name(Point) == "Point" && name(GBody{3}) == "GBody3" && name(Pair2{Float64}) == "Pair2F64"
    @test name(Tuple{Float64,Int64}) == "TupleF64xI64" && name(Tuple{SVector{3,Float64},SVector{3,Float64}}) == "Tuple3xx3"
    @test name(GObj{Bool,3,3}) == "GObjBx3x3" && name(GTwo{Bool,SMatrix{3,3,Float64,9}}) == "GTwoBxx3x3"      # three parameters, or a truth value and a 3×3
    @test name(GTwo{SVector{3,Float64},3}) == "GTwo3xx3" && name(GBody{SMatrix{3,3,Float64,9}}) == "GBody3x3" && name(GTwo{SMatrix{3,3,Float64,9},3}) == "GTwo3x3xx3"
    @test name(GOuter{GInner{Bool,3},8}) == "GOuterGInnerBx3xx8" && name(GOuter{GInner{Bool,GBody{2}},8}) == "GOuterGInnerBxxGBody2xxx8"
    @test name(GOuter{GBody{Bool},8}) == "GOuterGBodyBxx8" && name(GBody{GInner{Bool,8}}) == "GBodyGInnerBx8"    # one parameter is a level too
    @test name(GTwo{Tuple{Float64,Int64},Char}) == "GTwoTupleF64xI64xxC" && name(GTwo{SMatrix{2,2,Float32,4},ComplexF64}) == "GTwo2x2F32xxC64"
    src = check("grammar", [Case(gscale, Pair2(1.0, 2.0), 3.0), Case(swap, Pair2(1.0, 2.0))])
    @test occursin("Pair2F64 gscale(Pair2F64 p, double s)", src) && !occursin("Pair2_F64", src)
end

# A struct of the author's to an integer power (2026-10-04): by squaring, with their own `*`,
# `one` and `inv`. Nothing about the struct is known to the transpiler; power by squaring is
# written once, in Julia (`src/power.jl`), and translated for the type.
struct Gauss <: Number            # a + b i
    a::Float64
    b::Float64
end
Base.:*(x::Gauss, y::Gauss) = Gauss(x.a * y.a - x.b * y.b, x.a * y.b + x.b * y.a)
Base.one(::Gauss) = Gauss(1.0, 0.0)
Base.inv(x::Gauss) = Gauss(x.a / (x.a^2 + x.b^2), -x.b / (x.a^2 + x.b^2))
gausspow(x::Gauss, n::Int64) = x^n
gausscube(x::Gauss) = x^3
gausssquaring(x::Gauss, n::Int64) = Base.power_by_squaring(x, n)
struct Turn                       # a struct that holds an array, and has no inverse
    w::Float64
    v::SVector{3,Float64}
end
Base.:*(a::Turn, b::Turn) = Turn(a.w * b.w - dot(a.v, b.v), a.w * b.v + b.w * a.v + cross(a.v, b.v))
Base.one(::Turn) = Turn(1.0, SVector(0.0, 0.0, 0.0))
Base.copy(q::Turn) = q            # Julia's `power_by_squaring` copies its argument for the first power
turnpow(q::Turn, n::Int64) = Base.power_by_squaring(q, n)
@testset "power of a struct" begin
    g = Gauss(0.6, 0.8)
    t = Turn(cos(0.3), SVector(0.0, sin(0.3), 0.0))
    # Julia's own `^` on a number of the author's takes no negative power (it throws), so none is tried.
    src = check("structpower", [(Case(gausspow, g, n) for n in (0, 1, 2, 7))..., Case(gausscube, Gauss(1.5, -0.5)),
                                (Case(gausssquaring, g, n) for n in (0, 1, 6))..., (Case(turnpow, t, n) for n in (0, 1, 2, 5))...])
    @test occursin("return powi_Gauss(x, n);", src) && occursin("return powi_Gauss(x, 3);", src) && occursin("return powi_Turn(q, n);", src)
    @test occursin("x = mul_Gauss_Gauss(x, x);", src) && occursin("x = inv(x);", src) && occursin("return (Gauss){1.0, 0.0};", src)
    @test occursin("return (Turn){1.0, {0.0, 0.0, 0.0}};", src) && occursin("y = mul_Turn_Turn(y, x);", src)
end

@testset "placement" begin
    src = csource("placement", spun, spun2, rebuilt, bagged, counted, paired, early)
    @test occursin("Quat result;\n    mul_s_3(s, axis, result.v);\n    result.w = c;\n    return result;", src)
    @test occursin("Quat q;\n    mul_s_3(s, axis, q.v);\n    q.w = c;", src)
    @test occursin("mul_s_3(s, q.v, temp1);", src) && !occursin("mul_s_3(s, q.v, q.v)", src)      # rebuilt: the temp stays
    @test occursin("mul_s_3(s, axis, temp1);", src) && occursin("temp2.w = vsum(b);", src)             # bagged: the temp stays
    @test occursin("Bag b;\n    mul_s_3(s, axis, b.v);  // b.v = s * axis\n    Counter *temp1 = bump(c);", src)          # counted: placed, the effect after it as in Julia
    @test occursin("Tuple3xxF64 result;\n    mul_s_3(s, axis, result.a);  // result.a = s * axis\n    Counter *temp1 = bump(c);", src)   # paired: into the tuple's struct
    @test occursin("c->n++;", src)                                                                                            # a field store shortened like a variable's
    @test occursin("mul_s_3(s, axis, temp1);  // temp1 = s * axis\n    if (bad) {\n        return b.z;\n    }", src)   # early: the temp stays
end
check("struct", [Case(norm2, p), Case(make, 5.0, 6.0), Case(midpoint, Segment(p, q)), Case(momentum, b, v), Case(shifted, b, v),
                 Case(same, p, Point(3.0, 4.0)), Case(same, p, q), Case(swap, Pair2(1.0, 2.0)), Case(bump!, Counter(41)),
                 Case(peek, Counter(21)), Case(both, 1.5, 2), Case(untup, SVector(1.5, 2.0)), Case(held, 1.5, 3),
                 Case(tswap, 1.0, 2.0), Case(arrays, SVector(1.0, 2.0, 3.0)), Case(unarrays, SVector(1.0, 2.0, 3.0)),
                 Case(third, (1.0, 2.0, 3.0)), Case(viathird, 1.5), Case(step, 1.0, 0.0, 0.1), Case(twice, 1.0, 0.0, 0.1), Case(kept, 1.0, 0.1),
                 Case(rotated, Quaternion(cos(0.3), 0.0, 0.0, sin(0.3)), SVector(1.0, 0.0, 0.0)),
                 Case(turned, Quat(cos(0.3), SVector(0.0, 0.0, sin(0.3))), SVector(1.0, 0.0, 0.0))])
@testset "array-field struct passed whole" begin
    # A call returning a struct with an array field is written where it is used when the
    # whole struct goes there — returned, or passed to a call — never where a field of it
    # is read; and `a + b + c` on arrays accumulates in its destination.
    src = csource("quat", turned)
    @test occursin("return conj_Quat(q);", src)
    @test occursin("Quat temp2 = mul_Quat_Quat(mul_Quat_Quat(q, temp1), adjoint_Quat(q));  // temp2 = q * temp1 * q'", src)
    @test occursin("    // temp1 = Quat(0.0, v)\n    Quat temp1;\n", src)
    @test occursin("memcpy(out, temp2.v, sizeof(double[3]));", src)
    # The product's vector part is computed straight into the result's field (`placement`).
    @test occursin("Quat result;\n    add_3(temp1, temp2, result.v);  // result.v = temp1 + temp2", src)
    @test occursin("add_3(result.v, temp3, result.v);  // result.v += temp3\n    result.w = a.w * b.w - dot_3(a.v, b.v);\n    return result;", src)
    @test !occursin("temp4", src)
end
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
    @test occursin("step_t temp1 = step(x, xdot, dt);\n    x = temp1.x;\n    xdot = temp1.xdot;", src) && occursin("step_t twice(", src) && occursin("return step(x, xdot, dt);", src)
    @test occursin("step_t t = step(x, 0.0, dt);", src) && occursin("return t.x * t.xdot;", src)
    # A tuple parameter is spread; a tuple built for a call goes as its elements.
    @test occursin("double third(double t1, double t2, double t3)", src) && occursin("return t1 + t3;", src) && occursin("return third(a, 2 * a, 3 * a);", src)
    # Variables returned in any order keep their names; an expression returned has none,
    # so `arrays`, returning `(v, 2.0 * v)`, gets the structural struct with positional fields.
    @test occursin("typedef struct {\n    double b;\n    double a;\n} tswap_t;", src) && occursin("return (tswap_t){b, a};", src)
    @test occursin("Tuple3xx3 temp1 = arrays(v);", src)
end
# A constructor the author wrote is a function of the author's; only the one Julia gives every
# struct, one argument a field, is the C literal. Each of these was written as the literal
# before, the arguments dropped into the fields in order: a wrong answer, silently.
struct Made
    x::Float64
    n::Int
end
Made(n::Int64) = Made(Float64(n), n)
Made(x::Float64) = Made(x, 7)
Made(b::Bool) = Made(b ? 1.0 : -1.0)                    # one constructor calling another
struct Doubled
    x::Float64
    Doubled(x) = new(2x)                                # an inner one, in place of the default
end
struct Sorted
    lo::Float64
    hi::Float64
    Sorted(a, b) = a < b ? new(a, b) : new(b, a)
end
Pair2(a::T) where {T} = Pair2(a, a)                     # on a struct with a parameter
struct Ramp
    v::SVector{3,Float64}
    s::Float64
end
Ramp(s::Float64) = Ramp(SVector(s, 2s, 3s), s)          # filling an array field
madeint(n::Int) = Made(n)
madefloat(x::Float64) = Made(x)
madebool(b::Bool) = Made(b)
madedefault(x::Float64, n::Int) = Made(x, n)
madeconverted(n::Int) = Point(n, n)                     # Julia's own converting constructor is the default too
madeinner(x::Float64) = Doubled(x)
madesorted(a::Float64, b::Float64) = Sorted(a, b)
madepair(x::Float64) = Pair2(x)
madepairint(n::Int) = Pair2(n)
maderamp(s::Float64) = Ramp(s)
madeused(n::Int) = Made(n).x + Made(2.5).n + Doubled(1.5).x
@testset "constructor" begin
    src = check("constructor", [Case(madeint, 3), Case(madefloat, 2.5), Case(madebool, true), Case(madebool, false), Case(madedefault, 1.5, 2),
                                Case(madeconverted, 4), Case(madeinner, 1.5), Case(madesorted, 2.0, 1.0), Case(madesorted, 1.0, 2.0),
                                Case(madepair, 1.5), Case(madepairint, 2), Case(maderamp, 2.0), Case(madeused, 3)])
    # The author's: a function named for the struct it makes and what it makes it from.
    @test occursin("return Made_from_I64(n);", src) && occursin("Made Made_from_I64(int64_t n) {", src) && occursin("return (Made){(double)n, n};", src)
    @test occursin("Made Made_from_B(bool b) {", src) && occursin("return Made_from_F64(b ? 1.0 : -1.0);", src)
    @test occursin("Doubled Doubled_from_F64(double x) {", src) && occursin("Sorted Sorted_from_F64_F64(double a, double b) {", src)
    @test occursin("return (Sorted){a, b};", src) && occursin("return (Sorted){b, a};", src)             # `new` is the literal
    @test occursin("Pair2F64 Pair2F64_from_F64(double a) {", src) && occursin("Pair2I64 Pair2I64_from_I64(int64_t a) {", src)
    # Julia's: the literal, as it always was.
    @test occursin("return (Made){x, n};", src) && occursin("return (Point){n, n};", src) && !occursin("Point_from", src)
end

end
