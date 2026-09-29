# stackmath: a library of static linear algebra in C — every operation the transpiler
# knows, at every size from 2 to 10, vectors and matrices, in Float64. Run it to produce
# out/ next to it: one file per operation, `add.c` with `add.h`, `multiply.c` with
# `multiply.h`, each function documented, each an ordinary function to call by name.
# An operation that needs helpers of its own (the LU behind `solve`) keeps them in a
# helper file of its own name, so the calls don't overwrite each other's.
using LegibleC
using LinearAlgebra
using StaticArrays

const F = Float64
const N = 2:10
const vectors = [(F, n) for n in N]
const matrices = [(F, m, n) for m in N for n in N]
const squares = [(F, n, n) for n in N]
const shapes = [vectors; matrices]

lib(name, targets; kw...) = (print(rpad(name, 12)); t = @elapsed transpile(targets...; outfile=name, helper=name * "helper", outpath=@__DIR__, kw...); println(lpad(length(targets), 5), " functions, ", round(t; digits=1), " s"))

unary(op, list=shapes) = [(op, s...) for s in list]
binary(op, list=shapes) = [(op, s..., s...) for s in list]
# A broadcast by a scalar on either side, a matrix by a column or a row, and — where
# that isn't plain `+` or `-` — between matching shapes.
function broadcasts(op)
    targets = [[(op, s..., F) for s in shapes]; [(op, F, s...) for s in shapes];
               [(op, F, m, n, F, m) for m in N for n in N]; [(op, F, m, n, F, 1, n) for m in N for n in N]]
    op in (:.*, :./) && append!(targets, binary(op))
    return targets
end
# Along each dimension of a matrix.
along(f) = [[((A -> f(A; dims=1)), s...) for s in matrices]; [((A -> f(A; dims=2)), s...) for s in matrices]]

# Arithmetic, elementwise and broadcast.
lib("negate", unary(-))
lib("add", [binary(+); broadcasts(:.+)])
lib("subtract", [binary(-); broadcasts(:.-)])
lib("multiply", [[(*, F, s...) for s in shapes]; [(*, s..., F) for s in shapes]; broadcasts(:.*);
                 [(*, F, m, n, F, n) for m in N for n in N];                                  # A * b
                 [(*, F, m, k, F, k, n) for m in N for k in N for n in N];                    # A * B
                 [(((A, b) -> A' * b), F, k, m, F, k) for k in N for m in N];                 # Aᵀ * b
                 [(((A, B) -> A' * B), F, k, m, F, k, n) for k in N for m in N for n in N];   # Aᵀ * B
                 [(((A, B) -> A * B'), F, m, k, F, n, k) for m in N for k in N for n in N];   # A * Bᵀ
                 [(((A, B) -> A' * B'), F, k, m, F, n, k) for k in N for m in N for n in N];  # Aᵀ * Bᵀ
                 [(((a, b) -> a * b'), F, m, F, n) for m in N for n in N]])                   # a * bᵀ, the outer product
lib("divide", [[(/, s..., F) for s in shapes]; broadcasts(:./)])

# Products of two vectors, transposes, and the square-matrix operations.
lib("dot", [(dot, F, n, F, n) for n in N])
lib("cross", [(cross, F, 3, F, 3)])
lib("transpose", unary(transpose, matrices))
lib("solve", [[(\, s..., F, s[2]) for s in squares]; [(\, s..., F, s[2], k) for s in squares for k in N];
              [(((A, b) -> cholesky(A) \ b), s..., F, s[2]) for s in squares];                       # symmetric positive definite
              [(((A, B) -> cholesky(A) \ B), s..., F, s[2], k) for s in squares for k in N]])
lib("inverse", unary(inv, squares))
lib("determinant", unary(det, squares))
lib("trace", unary(tr, squares))

# Reductions: of the whole, and along each dimension of a matrix.
lib("norm", unary(norm))
lib("sum", [unary(sum); along(sum)])
lib("prod", [unary(prod); along(prod)])
lib("maximum", [unary(maximum); along(maximum)])
lib("minimum", [unary(minimum); along(minimum)])
lib("cumsum", [unary(cumsum, vectors); along(cumsum)])
lib("cumprod", [unary(cumprod, vectors); along(cumprod)])
lib("diff", [unary(diff, vectors); along(diff)])

# Constants: a zero of every shape, an identity of every square size — plain functions,
# since neither is an operator, made here in a loop, so without the source line quoted.
for (F, n) in vectors; @eval $(Symbol("zero_", n))() = zeros(SVector{$n, Float64}); end
for (F, m, n) in matrices; @eval $(Symbol("zero_", m, "x", n))() = zeros(SMatrix{$m, $n, Float64}); end
for (F, n, _) in squares; @eval $(Symbol("identity_", n, "x", n))() = SMatrix{$n, $n, Float64}(I); end
lib("zero", [[getfield(@__MODULE__, Symbol("zero_", n)) for n in N]; [getfield(@__MODULE__, Symbol("zero_", m, "x", n)) for m in N for n in N]]; source=false)
lib("identity", [getfield(@__MODULE__, Symbol("identity_", n, "x", n)) for n in N]; source=false)
