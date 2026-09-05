# Todo

Open work, gathered from the "not yet" and "known cost" notes across the
docs. Nothing here is started unless its box is checked. The thinking behind
the open items — the decisions taken so far and the two-way survey of what
could still map between Julia and C — lives in [doc/dev/](doc/dev/):
[decision.md](doc/dev/decision.md) and [map.md](doc/dev/map.md). What the
transpiler does today is in [doc/](doc/), starting with
[syntax.md](doc/syntax.md).

⬜ Readability (philosophy.md, Craft)
    ⬜ Collapse single-use temps into expressions: `d = (a + b) * c / 2;` instead of three temps — the can of worms in `copy.md`
        ⬜ Precedence and parenthesisation for every operator in `render` (the condition inliner already has the table)
        ⬜ Decide when an expression is long enough that a named temp reads *better*
        ⬜ Store straight into a variable instead of through a temp (`d = temp3;`), for scalars and arrays alike
    ⬜ Rebinding is free: `A, B = B, A` on immutable values should swap which C variable each name refers to and emit nothing, instead of the three-copy swap (correct today, but five `copy_2x2` calls where a person writes none). Same idea as forwarding an SSA copy, applied to a slot whose old value is dead
    ⬜ Rewrite loop variables used only as indices to the C idiom: `for (i = 0; i < n; i++) v[i]` instead of `v[i - 1]`
    ⬜ `return a > b && b > c;` when both branches of a value-`&&`/`||` just return
    ⬜ `return c ? x : y;` for a ternary whose branches both return
    ⬜ Continuation lines of a multi-line expression land after its C; put them before it (`comment.md`)
    ✅ One-line `///` Doxygen comment on each generated helper — done 2026-09-03, `src/prose.jl`
    ⬜ `Δt` → `Deltat`: decide whether Greek-then-letter gets a separator

⬜ Language coverage (`doc/flow.md`; the wider catalogue of what could map, both ways, is `doc/dev/map.md`)
    ✅ Slicing: `v[2:3]`, `A[i, :]`, `A[:, j]` — done 2026-09-04; still open: `A[1:2, :]`, `A[i, 2:3]`, a range held in a variable, N-D
    ✅ Reductions: `sum`, `prod`, `maximum`, `minimum`, `norm`, `any`, `all` — done 2026-09-04; `maximum`/`minimum` skip a NaN where Julia returns it
    ⬜ `for` over the elements of an array (`for x in v`), and ranges with a non-literal step
    ⬜ `while` whose header can't be inlined — the `while (true) { …; if (!c) break; }` fallback is written but untested
    ⬜ Integer `^` beyond 2 and 3 (a `power` helper), `mod` on floats, `Float32` math (`sqrtf` and friends)
    ✅ Tuples as values, multiple return values — done 2026-09-04, `struct.md`
    ✅ Structs → C structs — done 2026-09-04, `struct.md`: by value, mutable through a pointer, parametric, nested
    ⬜ Strings and printing (`println` → `printf`)
    ⬜ `try`/`catch`, comprehensions, closures — decide which of these have any C meaning at all
    ⬜ Anonymous functions bound to a name: `f = x -> …` currently emits `U2329`; use the binding name
    ⬜ Broadcast: comparison operators (`.==`, `.<`) and `ifelse.`
    ⬜ Fuse a broadcast chain into one loop when the extra passes ever matter

⬜ Arrays (`doc/array.md`, `doc/scalar.md`)
    ⬜ Regular arrays as *regular* arrays: `staticarray=false`, runtime sizes — the option exists and refuses. Design in `doc/dev/map.md` §3.4: VLA parameters `void f(size_t m, size_t n, const double A[m][n])`, helpers taking the sizes as leading parameters, and a result's size derived symbolically from the inputs'. That last part makes it a redesign of the helper layer rather than an addition, which is why it's still open
    ⬜ Growing vectors (`push!`, `pop!`) — heap storage with an ownership rule (`doc/dev/map.md` §3.4)
    ⬜ Per-argument static/regular mixing in one signature (currently all-or-nothing)
    ⬜ A boundary helper for the row-major ↔ column-major layout swap when raw memory crosses Julia ↔ C (`doc/array.md`, *Representation*)
    ⬜ Complex numbers (`C64`/`C32`, `complex.h` — its names are not yet reserved), pointers (`Ptr{T}` ↔ `T*`), `char32_t`
    ⬜ Structured matrices, by the (storage map, support) rule of `doc/dev/map.md` §3.14: `Diagonal` and the triangulars first, then `Symmetric`/`Hermitian`, with loop bounds from the support and zeros written in a result's dead half
    ⬜ `mul` of two vectors where Julia would allow it (a 1×n matrix), and matrix × row
    ✅ `inv(A)`, `A \ b`, `B / A`, Cholesky — done 2026-09-04, `doc/linear.md`
    ⬜ A static SVD and QR: `pinv` and least squares for a rank-deficient `A`, as Julia does them (the Gram route reports `PosDefException` there)
    ⬜ LDLT: Julia has no `ldlt` for static matrices, so there's no syntax to hang it on; either a reference implementation shipped with the transpiler or `bunchkaufman`
    ⬜ `cholesky(A).L` / `.U` (the `U` is the transposed tag of `L`, free), `cholesky(A) \ B` with a matrix `B`, `B / cholesky(A)`, QR, `eigen` for symmetric 3×3 in closed form
    ⬜ `sizeof`, `@kwdef` constructors, `Union{T, Nothing}` fields, structs holding mutable structs, creating a mutable struct inside transpiled code (needs allocation and an ownership rule)
    ⬜ Passing an eagerly transposed matrix straight to a user function (`g(A')`): materialize into a temp at the call
    ⬜ `Cstring`, function-pointer targets, and pointer results in `ccall`
    ⬜ In-place zeroing and filling: `fill!(A, 0)`, `A .= 0`, `A .= x` on a mutable array → the same `zero_`/`fill_` helper called on the existing variable (there's no separate C: "make a zero array" is a declaration plus `zero_3x4(A)`, "wipe this one" is just `zero_3x4(A)`)
    ⬜ Hardcode sizes 1–3 wherever a general algorithm would be slower or read worse than the written-out form (as `det` does), and say so in each helper's comment
    ⬜ `SMatrix{3,3}(2I)` — a multiple of the identity; only `I` itself is accepted
    ⬜ `zero(x)`, `one(x)` on scalars
    ⬜ Loop order in `mul` when an operand is transposed: `mul_2x3_T2x3` walks `b[j][k]` with `j` inside, which strides; hand-written C would sum over `k` innermost there

⬜ Correctness
    ⬜ Signed integer overflow: Julia wraps, C says undefined — pick the one fixed compiler flag (`-fwrapv`) or emit unsigned arithmetic
    ⬜ `Int64(x)` on a non-integer float: Julia throws, the C cast truncates — decide whether to reproduce the check
    ⬜ A loop variable reassigned inside its own `for` body (Julia: affects that iteration only; the C `for` would drift)
    ⬜ A *mutable* array parameter that is rebound and then mutated (`a, b = b, a; a[1] = 0.0` with `MVector`s): Julia mutates the caller's `b`, the C mutates a local copy, because a reassigned parameter becomes a fresh variable. Exactly right for immutable arrays; a divergence for mutable ones. Needs the parameter to stay a pointer to the caller's storage when it's mutable

⬜ Project
    ✅ Turn the sandbox suites into real tests in `test/` — done 2026-09-04: `test/runtests.jl`, C against Julia for every case
    ⬜ Wrap the transpiler in a module so user code can't collide with its internals (`greek`, `reserved`, `body` already have)
    ⬜ Emit a companion `.h` with the prototypes
    ⬜ Give at least one `rule.jl` function a docstring so the Doxygen path is exercised by the standing suites
    ⬜ Add `complex.h` to `reserved.jl` when it joins the might-include list — note it defines `I`, so a Julia variable `I` would become `I_`
