# Comments carried into the C: docstrings as Doxygen, source lines, helper comments.
module Comment
using Test, StaticArrays
import Main: csource

"""
    scaled(A, s)

Scales a 2x2 matrix, then adds it to itself.
"""
function scaled(A::SMatrix{2,2,Float64,4}, s::Float64)   # trailing on the signature
    # Scale first.
    B = A * s      # trailing on a line of code
    C = B + A
    C
end
"One-line docstring in plain quotes."
project(A::SMatrix{2,3,Float64,6}, v::SVector{3,Float64}) = A * v
nodoc(x::Float64) = x * x

src = csource("comment", scaled, project, nodoc)
@testset "comment" begin
    @test occursin("/**", src) && occursin("Scales a 2x2 matrix, then adds it to itself.", src)
    @test occursin("@param[out] out  The value the Julia function returns. Must not overlap an input.", src)
    @test occursin("// trailing on the signature", src)
    @test occursin("// Scale first.", src)
    @test occursin("// comment.jl:", src) && occursin("B = A * s      # trailing on a line of code", src)
    @test occursin("One-line docstring in plain quotes.", src)
    @test occursin("/// 2×2-matrix * scalar multiplication", src)
    @test occursin("/// 2×3-matrix * 3-vector multiplication", src)
    bare = csource("commentless", scaled; source=false)
    @test occursin("// Scale first.", bare) && !occursin("B = A * s      #", bare)
end
end
