# stackmath: a library of static linear algebra in C — every operation the transpiler
# knows, at every size from 2 to 10, vectors and matrices, in Float64. Run it to produce
# out/ next to it: one file per operation, `neg.c` with `neg.h`, `mul.c` with `mul.h`,
# each function documented, each an ordinary function to call by name. An operation
# that needs helpers of its own (the LU behind `solve`) keeps them in a helper file of
# its own name, so the calls don't overwrite each other's.
using LegibleC
using LinearAlgebra

const F = Float64
const N = 2:10
const vectors = [(F, n) for n in N]
const matrices = [(F, m, n) for m in N for n in N]
const squares = [(F, n, n) for n in N]
const shapes = [vectors; matrices]

lib(name, targets) = (print(rpad(name, 10)); t = @elapsed transpile(targets...; outfile=name, helper=name * "helper", outpath=@__DIR__); println(length(targets), " functions, ", round(t; digits=1), " s"))

unary(op, list=shapes) = [(op, s...) for s in list]
binary(op, list=shapes) = [(op, s..., s...) for s in list]

# Elementwise arithmetic on matching shapes, and by a scalar.
lib("neg", unary(-))
lib("add", binary(+))
lib("sub", binary(-))
lib("scale", [[(*, F, s...) for s in shapes]; [(*, s..., F) for s in shapes]; [(/, s..., F) for s in shapes]])

# Products: matrix × vector, matrix × matrix at every compatible pair, dot, cross.
lib("mul", [[(*, F, m, n, F, n) for m in N for n in N]; [(*, F, m, k, F, k, n) for m in N for k in N for n in N]])
lib("dot", [(dot, F, n, F, n) for n in N])
lib("cross", [(cross, F, 3, F, 3)])

# Transposes, and the square-matrix operations: solve, inverse, determinant.
lib("transpose", unary(transpose, matrices))
lib("solve", [[(\, s..., F, s[2]) for s in squares]; [(\, s..., F, s[2], k) for s in squares for k in N]])
lib("inv", unary(inv, squares))
lib("det", unary(det, squares))

# Reductions.
lib("norm", unary(norm))
lib("sum", unary(sum))
lib("prod", unary(prod))
lib("maximum", unary(maximum))
lib("minimum", unary(minimum))

# Broadcasts: by a scalar on either side, elementwise between matching shapes (where
# that isn't plain `+` or `-`), and a matrix by a column or a row.
for (name, op) in (("addP", :.+), ("subP", :.-), ("mulP", :.*), ("divP", :./))
    targets = [[(op, s..., F) for s in shapes]; [(op, F, s...) for s in shapes];
               [(op, F, m, n, F, m) for m in N for n in N]; [(op, F, m, n, F, 1, n) for m in N for n in N]]
    op in (:.*, :./) && append!(targets, binary(op))
    lib(name, targets)
end

# Elementwise functions.
for f in (sqrt, abs, exp, log, sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, floor, ceil, round)
    lib(string(nameof(f)) * "P", [(broadcast, f, s...) for s in shapes])
end
