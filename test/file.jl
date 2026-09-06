# Several output files: one per target, or as named; what they share goes to common.
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

check("split", [Case(fall, 2.0), Case(far, Point(3.0, 4.0)), Case(alone, 1.0)]; outfile=("motion", "geometry", "geometry"))
@testset "file" begin
    dir = mktempdir()
    # Named per target: two targets with one name share a file; `square`, reached from
    # both files, goes to common.h/.c, which each includes; `fall`, reached only from
    # `height`, goes with it. A constant is `static const` in its header.
    paths = transpile(height, far, alone; outfile=("motion", "geometry", "geometry"), outpath=dir, scope=@__MODULE__)
    @test basename.(paths) == ["common.c", "motion.c", "geometry.c"]
    out = dirname(paths[1])
    @test sort(readdir(out)) == ["common.c", "common.h", "geometry.c", "geometry.h", "motion.c", "motion.h"]
    common = read(joinpath(out, "common.c"), String)
    motion = read(joinpath(out, "motion.c"), String)
    geometry = read(joinpath(out, "geometry.c"), String)
    @test occursin("double square(double x)", common) && !occursin("double square(double x)", motion) && !occursin("double square(double x)", geometry)
    @test occursin("double fall(double t)", motion) && occursin("double height(double t)", motion)
    @test occursin("double far(Point p)", geometry) && occursin("double alone(double x)", geometry)
    @test occursin("#include \"common.h\"\n#include \"motion.h\"", motion) && occursin("#include \"common.h\"\n#include \"geometry.h\"", geometry)
    @test occursin("static const double g = 9.81;  // gravity, m/s²", read(joinpath(out, "motion.h"), String)) && !occursin("9.81", motion)
    @test occursin("typedef struct {\n    double x;\n    double y;\n} Point;", read(joinpath(out, "geometry.h"), String))
    @test occursin("/**\n * Squared.", read(joinpath(out, "common.h"), String))
    # `nothing` names every file after its target; one string is one file, as ever.
    paths = transpile(height, far; outfile=nothing, outpath=dir, scope=@__MODULE__)
    @test basename.(paths) == ["common.c", "height.c", "far.c"]
    @test transpile(height, far; outfile="both", outpath=dir, scope=@__MODULE__) == joinpath(out, "both.c")
    @test occursin("double square(double x)", read(joinpath(out, "both.c"), String))
    @test_throws ArgumentError transpile(height, far; outfile=("one",), outpath=dir, scope=@__MODULE__)
    @test_throws ArgumentError transpile(height, far; outfile=("helper", "x"), outpath=dir, scope=@__MODULE__)
    @test_throws ArgumentError transpile(height, far; outfile=("common", "x"), outpath=dir, scope=@__MODULE__)
end
end
