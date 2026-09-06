# Julia's own operators as targets: the helper they become, as a function of the user's.
module Operator
using Test, StaticArrays, LinearAlgebra
import Main: Case, check, csource
import LegibleC: transpile

lenb(a::SVector{3,Float64}, b::SVector{3,Float64}) = norm(a + b)
traced(A::SMatrix{3,3,Float64,9}) = tr(A) + 1
struct Pair2
    x::Float64
    y::Float64
end
Base.:-(p::Pair2) = Pair2(-p.x, -p.y)
flipped(p::Pair2) = (-p).x

check("operator", [Case(lenb, SVector(1.0, 2.0, 3.0), SVector(1.0, 1.0, 1.0)), Case(flipped, Pair2(1.0, 2.0)), Case(traced, SMatrix{3,3}(1.0, 2, 3, 4, 5, 6, 7, 8, 9))];
      targets=((+, Float64, 3, Float64, 3), (*, Float64, 3, 3, Float64, 3), (\, Float64, 4, 4, Float64, 4), (dot, Float64, 3, Float64, 3), (+, Float64, Float64), lenb, (-, Pair2), flipped, traced))
@testset "operator" begin
    src = csource("operator", (+, Float64, 3, Float64, 3), (*, Float64, 3, 3, Float64, 3), (\, Float64, 4, 4, Float64, 4), (dot, Float64, 3, Float64, 3), (+, Float64, Float64), lenb, (-, Pair2))
    # The helper, promoted: its body, its two comment lines in a Doxygen block that names
    # the operator, no `static inline`, and gone from helper.h.
    @test occursin("void add_3(const double a[3], const double b[3], double out[3]) {\n    for (int i = 0; i < 3; i++) {\n        out[i] = a[i] + b[i];\n    }\n}", src)
    @test occursin(" * 3-vector addition\n * out = a + b\n *\n * Julia signature: +(::SVector{3, Float64}, ::SVector{3, Float64})\n * @param[in]  a    3-vector\n * @param[in]  b    3-vector\n * @param[out] out  3-vector, the return value\n */\nvoid add_3(", src)
    @test !occursin("static inline void add_3", src) && !occursin("static inline double dot_3", src)
    @test occursin("void mul_3x3_3(const double A[3][3], const double b[3], double out[3]);", src)
    @test occursin("void solve_4x4_4(", src) && occursin("void lu_4x4(", src) && occursin("Julia signature: \\(::SMatrix{4, 4, Float64, 16}, ::SVector{4, Float64})", src)
    @test occursin("double dot_3(const double a[3], const double b[3]);", src) && occursin(" * returns a ⋅ b\n", src)
    # A scalar operator has no helper to promote: a small function under the scheme's name.
    @test occursin("double add_s(double a, double b) {\n    return a + b;\n}", src) && occursin("Julia signature: +(::Float64, ::Float64)", src) && !occursin("@transpile.jl", src)
    # The user's own code calls the promoted function; a user's unary minus is `neg`.
    @test occursin("add_3(a, b, temp1_a_b);", src) && occursin("Pair2 neg_Pair2(Pair2 p)", src)
    # Split: the operator's function has a file of its own.
    dir = mktempdir()
    paths = transpile((+, Float64, 3, Float64, 3), lenb; outfile="lib", split=true, outpath=dir, scope=@__MODULE__)
    @test basename.(paths) == ["add_3.c", "lenb.c"] && occursin("#include \"add_3.h\"", read(joinpath(dir, "out", "lenb.c"), String))
    @test_throws ArgumentError csource("bare", *)
    # A broadcast is a symbol beginning with `.`: an operator's, or a function's.
    src = csource("broadcast", (:.+, Float64, 3, Float64), (:.*, Float64, 3, 2, Float64, 3), (broadcast, sqrt, Float64, 3), (:.+, Float64, 3, 2, Float64, 1, 2))
    @test occursin("void addP_3_s(const double a[3], double b, double out[3])", src) && occursin("Julia signature: .+(::SVector{3, Float64}, ::Float64)", src)
    @test occursin("void mulP_3x2_3(const double A[3][2], const double b[3], double out[3][2])", src) && occursin("out[i][j] = A[i][j] * b[i];", src)
    @test occursin("void sqrtP_3(const double a[3], double out[3])", src) && occursin("Julia signature: sqrt.(::SVector{3, Float64})", src)
    @test occursin("out[i][j] = A[i][j] + B[0][j];", src)
    @test_throws ArgumentError csource("nodot", (:sqrt, Float64, 3))
    # An anonymous function says what the tuple can't: a keyword, a transposed operand.
    src = csource("anonymous", (A -> sum(A; dims=1), Float64, 3, 3), ((A, B) -> A' * B, Float64, 4, 2, Float64, 4, 3), ((a, b) -> a * b', Float64, 3, Float64, 2), (tr, Float64, 3, 3))
    @test occursin("void sum1_3x3(const double A[3][3], double out[1][3])", src) && occursin("Julia signature: (::SMatrix{3, 3, Float64, 9}) -> sum(A; dims=1)", src)
    @test occursin("void mul_T4x2_4x3(const double A[4][2], const double B[4][3], double out[restrict 2][3])", src) && occursin("Julia signature: (::SMatrix{4, 2, Float64, 8}, ::SMatrix{4, 3, Float64, 12}) -> Aᵀ * B", src)
    @test occursin("void mul_3_T2(const double a[3], const double b[2], double out[restrict 3][2])", src)
    @test occursin("double tr_3x3(const double A[3][3]) {\n    double sum = 0.0;\n    for (int i = 0; i < 3; i++) {\n        sum += A[i][i];\n    }\n    return sum;\n}", src) && occursin("/**\n * 3×3-matrix trace\n * returns tr(A)", src)
    @test_throws ArgumentError csource("named", ((a, b) -> norm(a + b), Float64, 3, Float64, 3))
    @test_throws ArgumentError csource("square", (tr, Float64, 2, 3))
end
end
