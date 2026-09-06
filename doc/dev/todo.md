# Todo

Open work, gathered from the "not yet" and "known cost" notes across the
docs. Nothing here is started unless its box is checked. The thinking behind
the open items — the decisions taken so far and the two-way survey of what
could still map between Julia and C — lives in [doc/dev/](.):
[decision.md](decision.md) and [map.md](map.md). What the
transpiler does today is in [doc/](..), starting with
[syntax.md](../guide/syntax.md).

⬜ Readability (philosophy.md, Craft)
    ✅ Collapse single-use temps into expressions: `d = (a + b) * c / 2;` instead of three temps — done 2026-09-05, `doc/copy.md` item 5
        ✅ Precedence and parenthesisation for every operator in `render` — the condition inliner's table, now used everywhere
        ✅ Decide when an expression is long enough that a named temp reads *better* — resolved by mirroring the author: what they named is named, what they didn't isn't
        ✅ Store straight into a variable instead of through a temp (`d = temp3;`) — falls out of the same rule
        ✅ Wrap a very long expression line at its loosest operators — done 2026-09-05, the `width` option (100)
        ✅ `return sqrt(…);` instead of `double result = sqrt(…); return result;` — done 2026-09-05; `result` remains for a `ccall`'s value and a value returned from several places
    ⬜ `NamedTuple`: `return (x=x, ẋ=ẋ)` names the fields of a returned struct when what's returned isn't plain variables; a `NamedTuple` parameter names the spread parameters
    ⬜ Rebinding is free: `A, B = B, A` on immutable values should swap which C variable each name refers to and emit nothing, instead of the three-copy swap (correct today, but five `copy_2x2` calls where a person writes none). Same idea as forwarding an SSA copy, applied to a slot whose old value is dead
    ⬜ Rewrite loop variables used only as indices to the C idiom: `for (i = 0; i < n; i++) v[i]` instead of `v[i - 1]`
    ⬜ `return a > b && b > c;` when both branches of a value-`&&`/`||` just return
    ✅ `x = x + e` is `x += e`, an integer's `n + 1` is `n++`; the redundant `continue` a trailing `x && (n += 1)` produced is gone — done 2026-09-06
    ✅ A loop bound that is a call is computed once before the loop — done 2026-09-06
    ⬜ `return c ? x : y;` for a ternary whose branches both return
    ⬜ Continuation lines of a multi-line expression land after its C; put them before it (`comment.md`)
    ✅ One-line `///` Doxygen comment on each generated helper — done 2026-09-03, `src/prose.jl`
    ⬜ `Δt` → `Deltat`: decide whether a spelled-out character followed by a letter gets a separator
    ⬜ From the magnifying glass on `sandbox/demo.c` (2026-09-05), each with its reasoning in the conversation that raised it:
        ✅ Declare a named local at its first assignment — done 2026-09-05, `doc/math/array.md` *Declarations*: at the assignment at the top level of the body; a variable first assigned inside an `if` or a loop is declared just ahead of that construct
        ✅ A reassigned parameter — done 2026-09-05, after a round trip: a scalar is reassigned in place; an array is copied at the top of the function, in a block under a comment giving the reason, as `x_`. The no-copy `x_new` scheme was built and then set aside the same day (decision entry)
        ✅ Per-operation aliasing: elementwise helpers write in place and lose `restrict`; products, solves, inverses, cross, transposed operands and constructions keep the temp — done 2026-09-05, `doc/math/array.md`, `doc/helper.md`, decision entry
        ✅ `memcpy(out, x_new, sizeof x_new)` for a whole local array; `sizeof(double[3])` where the source is a parameter or a partial row — done 2026-09-05
        ✅ Step comments: two spaces and no alignment — done 2026-09-05
        ✅ `-x / r^3` — the sign folds onto the scalar, `div_3_s(x, -temp2_r, a)` — done 2026-09-05; the general fusion into one loop stays under Language coverage
        ⬜ Result placement: a variable whose value ends up in `out` (`return [x; v]` after `x = …`, `v = …`) should be computed in `out` from the start, so the final `memcpy`s vanish. Parked by request 2026-09-05 — to be discussed
        ✅ Collapse a single-use scalar temp into its use: `div_3_s(x, -(r * r * r), a)` — done 2026-09-05 with the general item above; `-x / -s` now cancels to `div_3_s(x, s, d)`
        ✅ A blank line before each Julia statement's C, none against a brace — done 2026-09-05, `doc/comment.md` *Spacing*
        ✅ Doxygen tail: `Julia signature:`, `@param[in]  x    3-vector`, `@param[out] out  6-vector, the result; must not overlap an input` — done 2026-09-05

⬜ Language coverage (`doc/flow.md`; the wider catalogue of what could map, both ways, is `doc/dev/map.md`)
    ✅ Slicing and slice assignment in any dimension — done 2026-09-05, inline; still open: a range held in a variable, `A[:, 1] .= 0`
    ✅ Reductions: `sum`, `prod`, `maximum`, `minimum`, `norm`, `any`, `all` — done 2026-09-04; `maximum`/`minimum` skip a NaN where Julia returns it
    ✅ Operations along one dimension: `sum(A; dims=1)` and friends, `diff`, `cumsum`, `cumprod` — done 2026-09-06, `doc/math/array.md` *Slices and reductions*
    ✅ `for x in v` over a vector's elements — done 2026-09-06, `doc/flow.md`; still open: a matrix (column-major order), and ranges with a non-literal step
    ✅ `while` whose header can't be inlined — the `while (true) { …; if (!c) break; }` fallback, now tested (it recursed; fixed 2026-09-06)
    ✅ Integer `^` beyond 2 and 3 — done 2026-09-05, `powi(x, n)` by squaring, `doc/math/scalar.md`
    ✅ `mod` on floats (`modulo`), `Float32` math (`sqrtf` and friends) — done 2026-09-06
    ✅ Tuples as values, multiple return values — done 2026-09-04, `struct.md`
    ✅ Structs → C structs — done 2026-09-04, `struct.md`: by value, mutable through a pointer, parametric, nested
    ✅ Printing (`print`, `println`, `@printf`, `@show`) — done 2026-09-05, `doc/io.md`
    ✅ `Char` (ASCII `char`) and `String` (`const char *`): literals, comparison, `ctype.h` classes, `length`/`ncodeunits`/`s[i]`, printing — done 2026-09-06, `doc/guide/syntax.md`
    ⬜ Strings built at run time: `@sprintf`, `string(…)`, concatenation, `split`, `for c in s` — needs buffers and an owner
    ⬜ Files: `open`, `close`, `print(io, …)`, `read`, `readline`, `eachline` — into `src/io.jl`, the stream-first helpers already take a `FILE *`
    ⬜ `try`/`catch`, comprehensions, closures — decide which of these have any C meaning at all
    ⬜ Anonymous functions bound to a name: `f = x -> …` currently emits `U2329`; use the binding name
    ✅ Broadcast: comparison operators, `.&`, `.|`, `.!`, and `ifelse.` — done 2026-09-06
    ⬜ Fuse a broadcast chain into one loop when the extra passes ever matter

⬜ Arrays (`doc/math/array.md`, `doc/math/scalar.md`)
    ⬜ Regular arrays as *regular* arrays: `staticarray=false`, runtime sizes — the option exists and refuses. Design in `doc/dev/map.md` §3.4: VLA parameters `void f(size_t m, size_t n, const double A[m][n])`, helpers taking the sizes as leading parameters, and a result's size derived symbolically from the inputs'. That last part makes it a redesign of the helper layer rather than an addition, which is why it's still open
    ⬜ Growing vectors (`push!`, `pop!`) — heap storage with an ownership rule (`doc/dev/map.md` §3.4)
    ⬜ Per-argument static/regular mixing in one signature (currently all-or-nothing)
    ⬜ A boundary helper for the row-major ↔ column-major layout swap when raw memory crosses Julia ↔ C (`doc/math/array.md`, *Representation*)
    ⬜ Complex numbers (`C64`/`C32`, `complex.h` — its names are not yet reserved), pointers (`Ptr{T}` ↔ `T*`), `char32_t`
    ⬜ Structured matrices, by the (storage map, support) rule of `doc/dev/map.md` §3.14: `Diagonal` and the triangulars first, then `Symmetric`/`Hermitian`, with loop bounds from the support and zeros written in a result's dead half
    ⬜ `mul` of two vectors where Julia would allow it (a 1×n matrix), and matrix × row
    ✅ `inv(A)`, `A \ b`, `B / A`, Cholesky — done 2026-09-04, `doc/math/solve.md`
    ⬜ A static SVD and QR: `pinv` and least squares for a rank-deficient `A`, as Julia does them (the Gram route reports `PosDefException` there)
    ⬜ LDLT: Julia has no `ldlt` for static matrices, so there's no syntax to hang it on; either a reference implementation shipped with the transpiler or `bunchkaufman`
    ⬜ `cholesky(A).L` / `.U` (the `U` is the transposed tag of `L`, free), `cholesky(A) \ B` with a matrix `B`, `B / cholesky(A)`, QR, `eigen` for symmetric 3×3 in closed form
    ⬜ `sizeof`, `@kwdef` constructors, `Union{T, Nothing}` fields, structs holding mutable structs, creating a mutable struct inside transpiled code (needs allocation and an ownership rule)
    ⬜ Passing an eagerly transposed matrix straight to a user function (`g(A')`): materialize into a temp at the call
    ⬜ `Cstring`, function-pointer targets, and pointer results in `ccall`
    ✅ In-place zeroing and filling: `fill!(A, x)`, `A .= 0`, `A .= x`, and `A .= B .* 2` — done 2026-09-06
    ⬜ Hardcode sizes 1–3 wherever a general algorithm would be slower or read worse than the written-out form (as `det` does), and say so in each helper's comment
    ✅ `SMatrix{3,3}(2I)`, `A + 2I`, `A - I`, `2I - A` — done 2026-09-06, `addI_3x3` and friends
    ✅ A numeric literal coefficient, `-3A`: the integer literal takes the array's element type, `mul_s_2x2(-3.0, A, out)` — done 2026-09-06
    ✅ `zero(x)`, `one(x)` on scalars — done 2026-09-06
    ⬜ Loop order in `mul` when an operand is transposed: `mul_2x3_T2x3` walks `b[j][k]` with `j` inside, which strides; hand-written C would sum over `k` innermost there

⬜ Portability
    ✅ `M_PI` and `M_E` are POSIX, not ISO C — done 2026-09-06: `M_PI` stays the default; the `portable` option defines `LEGIBLEC_PI` and `LEGIBLEC_E` (as the doubles, `string(Float64(π))`) at the top of the file and uses those

⬜ Correctness
    ⬜ Signed integer overflow: Julia wraps, C says undefined — pick the one fixed compiler flag (`-fwrapv`) or emit unsigned arithmetic
    ⬜ `Int64(x)` on a non-integer float: Julia throws, the C cast truncates — decide whether to reproduce the check
    ⬜ A loop variable reassigned inside its own `for` body (Julia: affects that iteration only; the C `for` would drift)
    ✅ A mutable array passed to a user function that writes it kept its `const` here — fixed 2026-09-05 through the callee's effects (`effects!`)
    ⬜ A *mutable* array parameter that is rebound and then mutated (`a, b = b, a; a[1] = 0.0` with `MVector`s): Julia mutates the caller's `b`, the C mutates a local copy, because a reassigned parameter becomes a fresh variable. Exactly right for immutable arrays; a divergence for mutable ones. Needs the parameter to stay a pointer to the caller's storage when it's mutable

⬜ Targets beyond functions (`transpile` overloads)
    ✅ A struct definition: `transpile(Point)` — done 2026-09-06, with the docstring as a Doxygen block
    ⬜ An `@enum` type → a C `enum`
    ⬜ A math operator with types: `(+, SVector{3,Float64}, SVector{3,Float64})` generates the helper instead of transpiling Julia's method; requested helpers become ordinary functions with prototypes, not `static inline`; broadcasts as a symbol `(:.*, T, T)`; along-a-dimension as `(sum, T; dims=1)`
    ✅ A variable: by keyword, `transpile(fall; g)`, `@transpile(…; g)` for the calling scope, `:name => value` and `GlobalRef` as escape hatches — done 2026-09-06; `initializer` moved into `src`
    ✅ Functions read a global by its C name; the global is pulled in like a callee — done 2026-09-06; a mutable global must be typed (`k::Float64 = 2.0`)
    ✅ Definitions come from anywhere Julia sees them; a REPL-defined function just carries no source comments (a refusal was tried 2026-09-06 and withdrawn the same day)
    ⬜ Functions that write globals (`global count += 1`) → assignment to the C variable
    ⬜ A module: `transpile(MyModule)` walks its names — functions, structs, constants
    ⬜ A file: `transpile("physics.jl")` includes it into a fresh module and does the same
    ⬜ The companion `.h` (also under Project) — constants, typedefs, and public helpers are what a C caller needs to see

⬜ Demos (`demo/`; each is a folder with a Julia file, its checked-in `out/`, and a line on what to look at; `orbit`, `showcase` and `sincos` are there since 2026-09-06). The list below is suggestions, not a plan:
    ⬜ Orbit: the README's `orbit` plus a few steps of integration in a loop — arrays, a reduction, reassignment, the copy comment, a loop
    ⬜ Kalman filter, one predict/update step: small matrices, `*`, `'`, `\`, `inv`, `I` — the linear-algebra helpers side by side, and `A + Q` reading as the textbook equation
    ⬜ Quaternion rotation and a rigid body: a `struct` with array fields, `cross`, `norm`, a normalize step — structs by value and Doxygen from docstrings
    ⬜ PID controller: a `mutable struct` holding state, `clamp`, a `while` loop stepping a plant — the mutable-through-a-pointer interface, `x += e`, `min`/`max`
    ⬜ Kinematics of a two-link arm: `sin`/`cos`, `atan(y, x)`, a `Tuple` return of angles — scalars, `math.h`, multiple return values as a struct
    ⬜ Runge–Kutta 4 on a vector field: a function passed as a user call, four `k` stages, `x + h/2 * k1` — inlined scalar expressions and the step comments on each array line
    ⬜ Statistics of a sample: `sum`, `extrema`, `argmax`, `sum(A; dims=1)`, `diff` on an `SVector` — the reductions and along-a-dimension helpers
    ⬜ Names: a function written in a Julian way, with `ω`, `θ̇`, `x₁`, `Δt`, `ħ`, `∇`, and the same run with `spelling=` — the naming rules and the override in one place
    ⬜ Text: a character classifier and a tiny tokenizer over a `String` — `char`, `strcmp`, `utf8len`
    ⬜ Portable: the same function with `portable=true` and `precise=true`, the two outputs diffed
    ⬜ A C `main` for one of the above that compiles and prints, so the folder also shows what calling the C looks like

⬜ Project
    ✅ Turn the sandbox suites into real tests in `test/` — done 2026-09-04: `test/runtests.jl`, C against Julia for every case
    ✅ Wrap the transpiler in a module — done 2026-09-06; a package since the same day: `Project.toml`, `src/LegibleC.jl`, `] dev` it and `using LegibleC`
    ⬜ Register the package in General when it's ready for strangers; until then `] add` by URL
    ✅ The companion `<outfile>.h`: typedefs, `extern` globals, documented prototypes with their return structs — done 2026-09-06
    ✅ Each file includes only the standard headers its own text uses — done 2026-09-06. (One call generates everything: list every function in one `transpile`; a later call into the same `out/` simply writes its own files over the old ones)
    ⬜ Give at least one `rule.jl` function a docstring so the Doxygen path is exercised by the standing suites
    ⬜ Add `complex.h` to `reserved.jl` when it joins the might-include list — note it defines `I`, so a Julia variable `I` would become `I_`
