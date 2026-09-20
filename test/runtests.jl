# Every test in one run: `julia test/runtests.jl` from the repo root. Each file is a
# module of its own, so its functions can't collide with the transpiler's or another
# file's. `check.jl` is the machinery: C against Julia, for every case.
using Test
include("check.jl")

@testset "LegibleC" begin
    for file in ("scalar", "flow", "array", "linear", "reduce", "call", "struct", "name", "comment", "print", "inline", "text", "global", "file", "option", "operator", "complex", "scope")
        include("$file.jl")
    end
end
