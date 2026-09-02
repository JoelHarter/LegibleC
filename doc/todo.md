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
    ⬜ One-line `///` Doxygen comment on each generated helper
    ⬜ `Δt` → `Deltat`: decide whether Greek-then-letter gets a separator

⬜ Language coverage (`flow.md`)
    ⬜ Slicing: `v[2:3]`, `A[i, :]`, `A[:, j]`
    ⬜ Reductions: `sum`, `prod`, `maximum`, `minimum`, `norm`, `any`, `all`
    ⬜ `for` over the elements of an array (`for x in v`), and ranges with a non-literal step
    ⬜ `while` whose header can't be inlined — the `while (true) { …; if (!c) break; }` fallback is written but untested
    ⬜ Integer `^` beyond 2 and 3 (a `power` helper), `mod` on floats, `Float32` math (`sqrtf` and friends)
    ⬜ Tuples as values, multiple return values
    ⬜ Structs → C structs (the naming rule already covers type and field names)
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

⬜ Correctness
    ⬜ Signed integer overflow: Julia wraps, C says undefined — pick the one fixed compiler flag (`-fwrapv`) or emit unsigned arithmetic
    ⬜ `Int64(x)` on a non-integer float: Julia throws, the C cast truncates — decide whether to reproduce the check
    ⬜ A loop variable reassigned inside its own `for` body (Julia: affects that iteration only; the C `for` would drift)

⬜ Project
    ⬜ Turn the sandbox suites into real tests in `test/`: transpile, compile, and compare every function against Julia numerically (the harnesses already exist in the session history)
    ⬜ Wrap the transpiler in a module so user code can't collide with its internals (`greek`, `reserved`, `body` already have)
    ⬜ Emit a companion `.h` with the prototypes
    ⬜ Give at least one `rule.jl` function a docstring so the Doxygen path is exercised by the standing suites
    ⬜ Add `complex.h` (and any other header the output may include) to `reserved.jl` when it joins the might-include list
