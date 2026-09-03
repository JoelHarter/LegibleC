# Todo

Open work, gathered from the "not yet" and "known cost" notes across the other
docs. Nothing here is started unless its box is checked.

⬜ Readability (README principle 2)
    ⬜ Collapse single-use temps into expressions: `d = (a + b) * c / 2;` instead of three temps — the can of worms in `copy.md`
        ⬜ Precedence and parenthesisation for every operator in `render` (the condition inliner already has the table)
        ⬜ Decide when an expression is long enough that a named temp reads *better*
        ⬜ Store straight into a variable instead of through a temp (`d = temp3;`), for scalars and arrays alike
    ⬜ Rewrite loop variables used only as indices to the C idiom: `for (i = 0; i < n; i++) v[i]` instead of `v[i - 1]`
    ⬜ `return a > b && b > c;` when both branches of a value-`&&`/`||` just return
    ⬜ `return c ? x : y;` for a ternary whose branches both return
    ⬜ Continuation lines of a multi-line expression land after its C; put them before it (`comment.md`)
    ✅ One-line `///` Doxygen comment on each generated helper — done 2026-09-03, `src/prose.jl`
    ⬜ `Δt` → `Deltat`: decide whether Greek-then-letter gets a separator

⬜ Language coverage (`flow.md`)
    ⬜ Slicing: `v[2:3]`, `A[i, :]`, `A[:, j]`
    ⬜ Reductions: `sum`, `prod`, `maximum`, `minimum`, `norm`, `any`, `all`
    ⬜ `for` over the elements of an array (`for x in v`), and ranges with a non-literal step
    ⬜ `while` whose header can't be inlined — the `while (true) { …; if (!c) break; }` fallback is written but untested
    ⬜ Integer `^` beyond 2 and 3 (a `power` helper), `mod` on floats, `Float32` math (`sqrtf` and friends)
    ⬜ Tuples as values, multiple return values
    ⬜ Structs → C structs (the naming rule already covers type and field names). Investigated 2026-09-04; the IR is plain and needs:
        ⬜ A `typedef struct { double x; double y; } Point;` emitted once per Julia struct that appears in any signature or body, fields by the naming rule, array fields as C arrays (`double pos[3]`)
        ⬜ `Base.getproperty(p, :x)` → `p.x` (the IR passes the field as a literal symbol)
        ⬜ `Point(x, y)` (the constructor call, callee is the type) → `(Point){x, y}`
        ⬜ `Base.setproperty!(c, :n, v)` → `c->n = v;` — only on `mutable struct`, which is a reference in Julia and so a pointer `Counter *c` in C; an immutable struct is passed and returned by value
        ⬜ Decide how a mutable struct is returned (`bump!(c) = (c.n += 1; c)` returns the same object: the pointer)
        ⬜ Nested structs and structs holding structs, parametric structs at a concrete instantiation
    ⬜ Strings and printing (`println` → `printf`)
    ⬜ `try`/`catch`, comprehensions, closures — decide which of these have any C meaning at all
    ⬜ Anonymous functions bound to a name: `f = x -> …` currently emits `U2329`; use the binding name
    ⬜ Broadcast: comparison operators (`.==`, `.<`) and `ifelse.`
    ⬜ Fuse a broadcast chain into one loop when the extra passes ever matter

⬜ Arrays (`array.md`, `type.md`)
    ⬜ Regular arrays as *regular* arrays: `staticarray=false`, dynamic sizes, allocation — the option exists and refuses
    ⬜ Per-argument static/regular mixing in one signature (currently all-or-nothing)
    ⬜ A boundary helper for the row-major ↔ column-major layout swap when raw memory crosses Julia ↔ C
    ⬜ Complex numbers (`C64`/`C32`, `complex.h` — its names are not yet reserved), pointers (`Ptr{T}` ↔ `T*`), `char32_t`
    ⬜ `mul` of two vectors where Julia would allow it (a 1×n matrix), and matrix × row
    ⬜ `inv(A)` for sizes 1–3 by the adjugate (the cofactors `det` already expands), LU beyond; `A \ b`
    ⬜ In-place zeroing and filling: `fill!(A, 0)`, `A .= 0`, `A .= x` on a mutable array → the same `zero_`/`fill_` helper called on the existing variable (there's no separate C: "make a zero array" is a declaration plus `zero_3x4(A)`, "wipe this one" is just `zero_3x4(A)`)
    ⬜ Hardcode sizes 1–3 wherever a general algorithm would be slower or read worse than the written-out form (as `det` does), and say so in each helper's comment
    ⬜ `SMatrix{3,3}(2I)` — a multiple of the identity; only `I` itself is accepted
    ⬜ `zero(x)`, `one(x)` on scalars
    ⬜ Loop order in `mul` when an operand is transposed: `mul_2x3_T2x3` walks `b[j][k]` with `j` inside, which strides; hand-written C would sum over `k` innermost there

⬜ Correctness
    ⬜ Signed integer overflow: Julia wraps, C says undefined — pick the one fixed compiler flag (`-fwrapv`) or emit unsigned arithmetic
    ⬜ `Int64(x)` on a non-integer float: Julia throws, the C cast truncates — decide whether to reproduce the check
    ⬜ A loop variable reassigned inside its own `for` body (Julia: affects that iteration only; the C `for` would drift)

⬜ Project
    ⬜ Turn the sandbox suites into real tests in `test/`: transpile, compile, and compare every function against Julia numerically (the harnesses already exist in the session history)
    ⬜ Wrap the transpiler in a module so user code can't collide with its internals (`greek`, `reserved`, `body` already have)
    ⬜ Emit a companion `.h` with the prototypes
    ⬜ Give at least one `rule.jl` function a docstring so the Doxygen path is exercised by the standing suites
    ⬜ Add `complex.h` to `reserved.jl` when it joins the might-include list — note it defines `I`, so a Julia variable `I` would become `I_`
