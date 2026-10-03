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
steps(A::SMatrix{3,3,Float64,9}, b::SVector{3,Float64}, c::SVector{3,Float64}, D::SVector{3,Float64}) = (A .+ b) \ c + D
built(A::SMatrix{3,3,Float64,9}, B::SMatrix{3,3,Float64,9}) = (C = A * B'; [C A; B C] .* 2.0)
single(A::SMatrix{3,3,Float64,9}, B::SMatrix{3,3,Float64,9}) = A * B
#= A block comment directly above the definition. =#
function longexpr(a::Float64, b::Float64)
    t = (a + b) *
        (a - b)          # continuation line comes before the C, with the first
    t
end
function brackets(u::SVector{3,Float64}, v::SVector{3,Float64})
    w = (
        u + v
    )   # a line that is only a closing bracket keeps this comment, not the bracket
    -w
end

src = csource("comment", scaled, project, nodoc, steps, built, single, longexpr, brackets)
# A multi-line call whose arguments are statements of their own lines (2026-10-01): the
# statement is one block comment, and the cursor moves to its end, or the inner lines were
# written again one by one before the next statement.
function multiline(x::Float64)
    v = SVector(
        sin(x),
        cos(x),
        x
    )
    return v
end
# A closure given a name: the name is the C function's, and the line that opens it is a signature, not code.
Named = () -> begin
    Γ = @MMatrix [
        0.0 1.0;
        1.0 0.5
    ]
    return π * Γ
end
@testset "multi-line statement" begin
    src = csource("multiline", multiline, Named)
    @test occursin(r"    /\* @comment\.jl:\d+-\d+:\n       v = SVector\(\n           sin\(x\),\n           cos\(x\),\n           x\n       \)\n    \*/\n    v\[0\] = sin\(x\);", src)
    @test !occursin(r"// @comment\.jl:\d+: sin\(x\),", src) && !occursin(r"// @comment\.jl:\d+: cos\(x\),", src)
    @test occursin("Julia signature: anonymous()", src) && occursin("void anonymous(double out[restrict 2][2]) {", src) && !occursin("-> begin", src)
    @test occursin(r"    /\* @comment\.jl:\d+-\d+:\n       Γ = @MMatrix \[\n           0\.0 1\.0;\n           1\.0 0\.5\n       \]\n    \*/\n    double Gamma\[2\]\[2\] = \{", src)
    @test Main.LegibleC.plainname(Symbol("#Outrage")) == "Outrage" && Main.LegibleC.plainname(Symbol("#5")) == "anonymous" && Main.LegibleC.plainname(:f) == "f"
end

@testset "comment" begin
    @test occursin("/**", src) && occursin("Scales a 2x2 matrix, then adds it to itself.", src)
    @test occursin("Julia signature: scaled(", src) && occursin("@param[in]  A  2×2-matrix", src) && occursin("@param[in]  s  scalar", src)
    @test occursin("@param[out] C  2×2-matrix, the return value", src)   # the returned variable is the out parameter
    @test occursin("// trailing on the signature", src)
    @test occursin("// Scale first.", src)
    @test occursin("// @comment.jl:", src) && occursin("B = A * s      # trailing on a line of code", src)
    @test occursin(r"// @comment\.jl:\d+: A \* v\n", src) && !occursin("// @comment.jl:19: project(", src)   # a short-form line carries only its body
    @test occursin(r"Julia signature: project\(A::SMatrix\{2, 3, Float64, 6\}, v::SVector\{3, Float64\}\) @comment\.jl:\d+\n", src)
    @test occursin("One-line docstring in plain quotes.", src)
    @test occursin("/// 2×2-matrix * scalar multiplication", src)
    @test occursin("/// 2×3-matrix * 3-vector multiplication", src)
    # Steps: one comment per operation of a Julia line that became several, in the
    # helpers' spelling with the C names; a loop gets it above; a single-step line none.
    @test occursin(r"addP_3x3_3\(A, b, temp1\); +// temp1 = A \.\+ b", src)
    @test occursin(r"solve_3x3_3\(temp1, c, temp2_c\); +// temp2_c = temp1 \\ c", src)
    @test occursin(r"add_3\(temp2_c, D, out\); +// out = temp2_c \+ D", src)
    @test occursin(r"mul_3x3_T3x3\(A, B, C\); +// C = A \* Bᵀ", src)
    @test occursin("    // temp1_C_A_B = [C A; B C]\n    for (int i = 0; i < 3; i++) {", src)
    @test occursin("// out = temp1_C_A_B .* 2.0", src)
    @test occursin("mul_3x3_3x3(A, B, out);\n", src) && !occursin("mul_3x3_3x3(A, B, out);  //", src)
    bare = csource("commentless", scaled; source=false)
    @test occursin("// Scale first.", bare) && !occursin("B = A * s      #", bare)
    # Spacing: a blank line before each Julia statement's C, source comments or not;
    # none after the opening brace or before the closing one.
    @test occursin("mul_2x2_s(A, s, B);\n\n    // @comment.jl:", src) && occursin("mul_2x2_s(A, s, B);\n\n    add_2x2(B, A, C);", bare)   # C lives in out (`outplacement!`)
    @test occursin(") {\n    // trailing on the signature\n    // Scale first.", src) && occursin("    return x * x;\n}", src)
    @test !occursin("\n\n\n", src) && !occursin("\n\n}", src)
    # A multi-line expression: its C at the first line, the continuation lines after it
    # (the known imprecision); a line that is only a bracket contributes its comment only.
    @test occursin("    double t = (a + b) * (a - b);\n\n    // @comment.jl:", src) && occursin("# continuation line comes before the C, with the first", src)
    @test occursin(r"    /\* @comment\.jl:\d+-\d+:\n       t = \(a \+ b\) \*\n           \(a - b\)          # continuation line comes before the C, with the first\n    \*/\n    double t = ", src)
    @test occursin("/* A block comment directly above the definition. */", src)
    @test occursin(r"    /\* @comment\.jl:\d+-\d+:\n       w = \(\n           u \+ v\n       \)   # a line that is only a closing bracket keeps this comment, not the bracket\n    \*/", src)
end
end
