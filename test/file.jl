# One file for everything, or every function and struct in a file of its own.
module File
using Test, StaticArrays
import Main: Case, check, csource
import LegibleC: transpile

const g = 9.81   # gravity, m/s²
struct Point
    x::Float64
    y::Float64
end
"Squared."
square(x::Float64) = x * x
fall(t::Float64) = 0.5 * g * square(t)
height(t::Float64) = 100.0 - fall(t)
far(p::Point) = square(p.x) + square(p.y)
alone(x::Float64) = x + 1.0
doubled(v::SVector{3,Float64}) = v + v
point(p::Point) = p.x
function step(x::Float64, ẋ::Float64, dt::Float64)
    ẋ += dt * -x
    x += dt * ẋ
    return x, ẋ
end
function twice(x::Float64, ẋ::Float64, dt::Float64)
    x, ẋ = step(x, ẋ, dt)
    return step(x, ẋ, dt)
end

check("lib", [Case(fall, 2.0), Case(far, Point(3.0, 4.0)), Case(alone, 1.0), Case(twice, 1.0, 0.0, 0.1)]; split=true)
@testset "file" begin
    dir = mktempdir()
    # Split: every function in its own file, listed or not, every struct in its own
    # header, the constant in the base header, which includes all the others.
    paths = transpile(height, far, alone; outfile="lib", split=true, outpath=dir, scope=@__MODULE__)
    @test basename.(paths) == ["height.c", "far.c", "alone.c", "fall.c", "square.c"]
    out = dirname(paths[1])
    @test sort(readdir(out)) == ["Point.h", "alone.c", "alone.h", "fall.c", "fall.h", "far.c", "far.h", "height.c", "height.h", "lib.h", "square.c", "square.h"]
    text(f) = read(joinpath(out, f), String)
    @test occursin("// @file.jl:7: const g = 9.81   # gravity, m/s²\nstatic const double g = 9.81;", text("lib.h"))
    @test all(occursin("#include \"$h\"", text("lib.h")) for h in ("height.h", "far.h", "alone.h", "fall.h", "square.h", "Point.h"))
    @test occursin("#include \"lib.h\"\n#include \"square.h\"\n#include \"fall.h\"\n", text("fall.c")) && occursin("return 0.5 * g * square(t);", text("fall.c"))
    @test occursin("#include \"fall.h\"\n#include \"height.h\"\n", text("height.c"))
    @test occursin("#include \"Point.h\"\n\n/**", text("far.h")) && occursin("typedef struct {\n    double x;\n    double y;\n} Point;", text("Point.h"))
    @test occursin("/**\n * Squared.", text("square.h"))
    # A return struct stays with its function; a pass-through's header includes it.
    paths = transpile(twice; outfile="lib", split=true, outpath=dir, scope=@__MODULE__)
    @test basename.(paths) == ["twice.c", "step.c"]
    @test occursin("} step_t;", text("step.h")) && !occursin("} step_t;", text("twice.h")) && occursin("#include \"step.h\"\n\n/**", text("twice.h"))
    # Names that differ only in case share a file, named in lowercase.
    fresh = mktempdir()
    @test transpile(point; outfile="lib", split=true, outpath=fresh, scope=@__MODULE__) == joinpath(fresh, "out", "point.c")
    @test sort(readdir(joinpath(fresh, "out"))) == ["lib.h", "point.c", "point.h"]
    merged = read(joinpath(fresh, "out", "point.h"), String)
    @test occursin("} Point;", merged) && occursin("double point(Point p);", merged)
    # One file, as ever.
    @test transpile(height, far; outfile="both", outpath=dir, scope=@__MODULE__) == joinpath(out, "both.c")
    @test occursin("double square(double x)", text("both.c")) && occursin("static const double g = 9.81;", text("both.h"))
    @test_throws ArgumentError transpile(height; outfile="helper", outpath=dir, scope=@__MODULE__)
    # The helper files by another name, so two calls into one `out/` keep both sets.
    path = transpile(doubled; outfile="geo", helper="geohelper", outpath=dir, scope=@__MODULE__)
    @test isfile(joinpath(out, "geohelper.h")) && occursin("#include \"geohelper.h\"", text("geo.c")) && occursin("LEGIBLEC_GEOHELPER_H", text("geohelper.h"))
    @test_throws ArgumentError transpile(far; outfile="same", helper="same", outpath=dir, scope=@__MODULE__)
end
end
