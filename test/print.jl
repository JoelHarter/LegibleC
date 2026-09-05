# Printing: printf as a C programmer writes it, and one array helper. The C program's
# output is compared with what we decided it prints.
module Print
using Test, StaticArrays, Printf
import Main: csource, flags

const V3 = SVector{3,Float64}

numbers(x::Float64) = println(x, " ", 3.0, " ", 0.1, " ", 1e-7, " ", 1e6, " ", 1234567.0, " ", -0.0, " ", 0.1 + 0.2)
extremes() = println(Inf, " ", -Inf, " ", NaN, " ", 1.5f0, " ", 1f-5)
mixed(x::Float64, n::Int64, b::Bool) = println("x = ", x, ", n = ", n, ", b = ", b, ", u = ", UInt8(200), " 100%")
arrays(v::V3, A::SMatrix{2,2,Float64,4}, T::SArray{Tuple{2,2,2},Float64,3,8}) = (println(v); println(A); println(T))
ints(v::SVector{3,Int64}, b::SVector{2,Bool}) = (println(v); println(b))
interpolated(x::Float64) = println("value: $x and twice $(2x)")
shown(x::Float64) = @show x
formatted(x::Float64, n::Int64) = @printf("%.3f | %5d | %-8.2e | %s | %%\n", x, n, x, "lit")
toerr(x::Float64) = println(stderr, "bad: ", x)
rows(A::SMatrix{2,3,Float64,6}) = println(A')

function run(src, calls)
    dir = mktempdir()
    write(joinpath(dir, "print.c"), src)
    write(joinpath(dir, "main.c"), "#include \"print.c\"\nint main(void) {\n" * join("    " .* calls, "\n") * "\n    return 0;\n}\n")
    exe = joinpath(dir, "main")
    Base.run(`cc $flags -I$dir $(joinpath(dir, "main.c")) -o $exe`)
    out = read(pipeline(`$exe`; stderr=joinpath(dir, "err.txt")), String)
    return out, read(joinpath(dir, "err.txt"), String)
end

calls = ["numbers(2.5);", "extremes();", "mixed(1.5, -7, true);",
         "double v[3] = {1, 2, 3}, A[2][2] = {{1, 3}, {2, 4}}, T[2][2][2] = {{{1, 5}, {3, 7}}, {{2, 6}, {4, 8}}};",
         "arrays(v, A, T);", "int64_t iv[3] = {1, -2, 3}; bool bv[2] = {true, false}; ints(iv, bv);",
         "interpolated(0.25);", "shown(3.0);", "formatted(3.14159, 42);", "toerr(2.0);",
         "double B[2][3] = {{1, 2, 3}, {4, 5, 6}}; rows(B);"]
expected = """
2.5 3 0.1 1e-07 1e+06 1.23457e+06 -0 0.3
inf -inf nan 1.5 1e-05
x = 1.5, n = -7, b = 1, u = 200 100%
           1           2           3
           1           3
           2           4
           1           5
           3           7

           2           6
           4           8
           1          -2           3
           1           0
value: 0.25 and twice 0.5
x = 3
3.142 |    42 | 3.14e+00 | lit | %
           1           4
           2           5
           3           6
"""

@testset "print" begin
    src = csource("print", numbers, extremes, mixed, arrays, ints, interpolated, shown, formatted, toerr, rows)
    out, err = run(src, calls)
    @test out == expected || (println("C printed:\n", out, "expected:\n", expected); false)
    @test err == "bad: 2\n"
    @test occursin("printf(\"x = %g, n = %lld, b = %d, u = %llu 100%%\\n\", x, (long long)n, b, (unsigned long long)temp1);", src)
    @test occursin("printarray(stdout, &A[0][0], 2, (const int[]){2, 2});", src) && occursin("printarray(stdout, v, 1, (const int[]){3});", src)
    @test occursin("static void printarray_I64(FILE *f, const int64_t *a, int ndims, const int dims[])", src) && occursin("printarray_B(", src)
    @test occursin("fprintf(stderr, \"bad: %g\\n\", x);", src)
    @test occursin("printf(\"%.3f | %5lld | %-8.2e | %s | %%\\n\", x, (long long)n, x, \"lit\");", src)
    # every digit, on request
    exact = csource("exact", numbers; precise=true)
    out, _ = run(exact, ["numbers(0.1);"])
    @test out == "0.10000000000000001 3 0.10000000000000001 9.9999999999999995e-08 1000000 1234567 -0 0.30000000000000004\n"
    @test occursin("%25.17g", csource("exactarray", arrays; precise=true))
end
end
