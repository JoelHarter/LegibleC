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

fall(t::Float64) = 0.5 * g * t^2
shifted(v::SVector{3,Float64}) = v + w
scaled(x::Float64) = k * x
dist(p::Point) = sqrt((p.x - origin.x)^2 + (p.y - origin.y)^2)
plain(x::Float64) = x + 1.0
unstable(x::Float64) = u * x

check("global", [Case(fall, 2.0), Case(shifted, SVector(1.0, 1.0, 1.0)), Case(scaled, 3.0), Case(dist, Point(3.0, 4.0))])
@testset "global" begin
    # A global a function reads is pulled in and referenced by name; `const` follows Julia.
    src = csource("pulled", fall, shifted, scaled, dist)
    @test occursin("const double g = 9.81;", src) && occursin("return 0.5 * g * (t * t);", src)
    @test occursin("const double w[3] = {1.0, 2.0, 3.0};", src) && occursin("add_3(v, w, out);", src)
    @test occursin("\ndouble k = 2.0;", src) && occursin("return k * x;", src)
    @test occursin("const Point origin = {0.0, 0.0};", src) && occursin("origin.x", src)
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
    @test occursin("return 2 * x;", repl) && !occursin("// REPL", repl)
    @test_throws ArgumentError csource("abstract", plain, Vector{Float64})
    @test_throws ArgumentError csource("untyped", unstable)                            # an untyped mutable global
    @test occursin("\ndouble u = 1.0;", csource("untypedlisted", plain; u, scope=@__MODULE__))   # listed, its value has a type, and the binding isn't const
end
end
