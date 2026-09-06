# The options that change how scalars are spelled: C23 float types, and an integer as bool.
module Option
using Test, StaticArrays
import Main: Case, check, csource
import LegibleC: transpile

mix(x::Float64, y::Float32) = x * 2 + Float64(sqrt(y))
flag(x::Float64) = x > 0
pick(b::Bool, x::Float64) = b ? x : -x
same(a::Bool, b::Bool) = a == b
tally(b::Bool, n::Int64) = Int64(b) + n
truth() = true
masked(m::SVector{3,Bool}) = sum(m)
printed(b::Bool) = println(b)

check("boolint", [Case(flag, 2.0), Case(flag, -1.0), Case(pick, true, 3.0), Case(pick, false, 3.0), Case(same, true, true), Case(same, true, false),
                  Case(tally, true, 5), Case(truth), Case(masked, SVector(true, false, true))]; bool=Int32)
@testset "option" begin
    # C23 float types, wherever a double or float was: text only, since the compiler
    # here doesn't know them.
    dir = mktempdir()
    path = transpile(mix; outfile="c23", outpath=dir, c23floattypes=true, scope=@__MODULE__)
    src = read(path, String) * read(joinpath(dirname(path), "c23.h"), String)
    @test occursin("_Float64 mix(_Float64 x, _Float32 y)", src) && occursin("return x * 2 + (_Float64)sqrtf(y);", src)
    @test !occursin("double", src) && !occursin(r"\bfloat\b", src)
    # An integer as bool: the type wherever a Bool was, the names with it, writes of 0
    # and 1, and a stored value read as nonzero where it enters arithmetic or a comparison.
    src = csource("boolint", flag, pick, same, tally, truth, masked, printed; bool=Int32)
    @test occursin("int32_t flag(double x)", src) && occursin("return x > 0;", src)
    @test occursin("double pick(int32_t b, double x)", src) && occursin("if (b) {", src)
    @test occursin("int32_t same(int32_t a, int32_t b)", src) && occursin("return (a != 0) == (b != 0);", src)
    @test occursin("return (int64_t)(b != 0) + n;", src)
    @test occursin("int32_t truth(void)", src) && occursin("return 1;", src)
    @test occursin("int64_t masked(const int32_t m[3])", src) && occursin("sum += (a[i] != 0);", src) && occursin("sum_3I32", src)
    @test occursin("int32_t truth(void) {\n    // @option.jl:12: true\n    return 1;\n}", src)
    @test occursin("printf(\"%d\\n\", b != 0);", src) && !occursin("stdbool.h", src)
    @test_throws ArgumentError csource("boolfloat", flag; bool=Float64)
end
end
