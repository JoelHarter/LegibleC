# doc

How the transpiler works and what it does today, one topic per file. A
suggested order for a first read:

1. [guide/](guide/README.md) — the user guide: install, what's accepted, targets, options, calling the C, names, when it refuses.
2. [philosophy.md](philosophy.md) — the principles behind every decision: logic, speed, craft, generality.
3. [design.md](design.md) — how it works: the pipeline, the source files, the shape of the output.
4. [math/scalar.md](math/scalar.md) — numbers: types, arithmetic, math, conversions.
5. [flow.md](flow.md) — control flow, recovered from the IR.
6. [math/array.md](math/array.md) — arrays: representation, transposes, broadcasting, products, construction.
7. [helper.md](helper.md) — the generated C helpers: one generator per operation, how they're named.
8. [math/solve.md](math/solve.md) — solving linear systems: determinants, inverses, pseudo-inverses, Cholesky, LU.
9. [struct.md](struct.md) — structs and tuples.
10. [call.md](call.md) — calls between functions and into C.
11. [naming.md](naming.md) — how every name in the output is chosen.
12. [comment.md](comment.md) — comments and docstrings carried into the C.
13. [copy.md](copy.md) — why the C has the temps it has, and no more.
14. [io.md](io.md) — printing, and later files.

What's still to be decided is in [dev/](dev/).
