# Globals: read by a function and pulled in, or listed by keyword; struct types as
# targets; the file rule.
module Global
using Test, StaticArrays
import Main: Case, check, csource
using LegibleC: @transpile

const g = 9.81
const w = SVector(1.0, 2.0, 3.0)
k::Float64 = 2.0         # a typed global: mutable in Julia, so in C
u = 1.0                  # untyped and mutable: no type to compile against
const title = "LegibleC"
"A point in the plane."
struct Point
    x::Float64
    y::Float64
end
const origin = Point(0.0, 0.0)
const τ = 2π                       # a full turn: the initializer is the expression, with π as the macro
const frame = [1.0 0.0; 0.0 π]

const tally = MVector(0, 0, 0)      # `const` fixes the binding, not the contents: a function that writes it needs it writable in C
function counted(k::Int64)
    tally[2] += k
    return tally[2] + 1
end
const SHIELD_H = 2.0                # spelled like the include guard of a file named `shield`
shielded(x::Float64) = x * SHIELD_H
fall(t::Float64) = 0.5 * g * t^2
turn(x::Float64) = τ * x + frame[2, 2]
shifted(v::SVector{3,Float64}) = v + w
scaled(x::Float64) = k * x
dist(p::Point) = sqrt((p.x - origin.x)^2 + (p.y - origin.y)^2)
plain(x::Float64) = x + 1.0
module Physics
const c = 3.0e8   # the speed of light, m/s
speed(t::Float64) = c * t
end
module Moon; const a = 1737.0; end
travel(t::Float64) = Physics.speed(t) + Moon.a + Physics.c
unstable(x::Float64) = u * x
energy(m::Float64) = m * Physics.c^2

check("global", [Case(fall, 2.0), Case(shifted, SVector(1.0, 1.0, 1.0)), Case(scaled, 3.0), Case(dist, Point(3.0, 4.0)), Case(energy, 2.0), Case(turn, 1.5)])
@testset "global" begin
    # A global a function reads is pulled in and referenced by name; `const` follows Julia.
    src = csource("pulled", fall, shifted, scaled, dist)
    @test occursin("const double g = 9.81;", src) && occursin("return 0.5 * g * (t * t);", src)
    @test occursin("const double w[3] = {1.0, 2.0, 3.0};", src) && occursin("add_3(v, w, out);", src)
    @test occursin("\ndouble k = 2.0;", src) && occursin("return k * x;", src)
    @test occursin("const Point origin = {0.0, 0.0};", src) && occursin("origin.x", src)
    # A global's initializer is its Julia expression where a static initializer can hold it:
    # `π` is the macro, defined in the helper header, which the header then includes.
    # An include guard is a macro, and would erase a name spelled like it: the guard gives way.
    wr = csource("written", counted)
    @test occursin("\nint64_t tally[3] = {0, 0, 0};", wr) && occursin("extern int64_t tally[3];", wr) && !occursin("const int64_t tally", wr)
    sh = csource("shield", shielded)
    @test occursin("#ifndef SHIELD_H_\n#define SHIELD_H_\n", sh) && occursin("static const double SHIELD_H = 2.0;", sh) && occursin("#endif  // SHIELD_H_", sh)
    sym = csource("symbolic", turn)
    @test occursin("static const double tau = 2 * LEGIBLEC_PI;", sym) && occursin("static const double frame[2][2] = {\n    {1.0, 0.0},\n    {0.0, LEGIBLEC_PI},\n};", sym)
    @test occursin("#define LEGIBLEC_PI 3.141592653589793", sym) && !occursin("LEGIBLEC_E", sym) && occursin("#include \"helper.h\"", sym)
    # Listed by keyword, looked up in `scope`; a struct type on its own, with its docstring.
    vars = csource("listed", Point, plain; g, k, title, origin, scope=@__MODULE__)   # a type before the functions: after one, it reads as an argument type
    @test occursin("const double g = 9.81;", vars) && occursin("\ndouble k = 2.0;", vars)
    @test occursin("const char *title = \"LegibleC\";", vars) && occursin("const Point origin = {0.0, 0.0};", vars)
    @test occursin("/**\n * A point in the plane.\n */\ntypedef struct {\n    double x;\n    double y;\n} Point;", vars)
    # A value with no binding in scope is a constant; a pair names one outright.
    loose = csource("loose", plain, :width => 3.0; q=k + 1, scope=@__MODULE__)
    @test occursin("const double q = 3.0;", loose) && occursin("const double width = 3.0;", loose)
    # The macro sets `scope` to where it is written.
    dir = mktempdir()
    path = @transpile(plain; k, outfile="mac", outpath=dir)
    @test occursin("\ndouble k = 2.0;", read(path, String))
    # A definition typed at the REPL transpiles; it just has no source to comment from.
    include_string(@__MODULE__, "replfun(x::Float64) = 2x", "REPL[7]")
    repl = csource("repl", replfun)
    @test occursin("return 2 * x;", repl) && !occursin("// @REPL", repl)
    @test_throws ArgumentError csource("abstract", plain, Vector{Float64})
    @test_throws ArgumentError csource("untyped", unstable)                            # an untyped mutable global
    @test occursin("\ndouble u = 1.0;", csource("untypedlisted", plain; u, scope=@__MODULE__))   # listed, its value has a type, and the binding isn't const
    # Names carry their module path, relative to the scope: bare in it, prefixed elsewhere.
    far = csource("far", travel, energy; scope=@__MODULE__)
    @test occursin("const double Physics_c = 3.0e8;", far) && occursin("const double Moon_a = 1737.0;", far)
    # The constant's Julia line comes with it, as a statement's does, its comment along; a
    # name read twice is written twice, not held in a temp.
    @test occursin(r"// @global\.jl:\d+: const c = 3\.0e8   # the speed of light, m/s\nstatic const double Physics_c = 3\.0e8;\n", far) && occursin("Moon_a = 1737.0;\n", far)
    @test occursin("const double Physics_c = 3.0e8;  // the speed of light, m/s", csource("farbare", travel, energy; scope=@__MODULE__, source=false))   # source off: the note after the declaration
    @test occursin("return m * (Physics_c * Physics_c);", far)
    @test occursin("double Physics_speed(double t)", far) && occursin("return Physics_speed(t) + Moon_a + Physics_c;", far) && occursin("double travel(double t)", far)
    near = csource("near", Physics.speed; scope=Physics)
    @test occursin("const double c = 3.0e8;", near) && occursin("double speed(double t)", near) && occursin("return c * t;", near)
end
end
