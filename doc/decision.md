# Decision

A running record of important decisions in this project: what we chose, and the
reasoning that led there. Newest entries at the bottom.

---

## 2026-09-02 — `sandbox/` is tracked, but its contents are not

> **Superseded 2026-09-03.** The sandbox moved out of the repository
> altogether, to a sibling folder, so there is nothing to ignore. Kept for
> the record.

**Context.** We want a scratch space in the repo for throwaway work that should
never reach GitHub, while still having the folder exist for anyone who clones.

**Decision.** `sandbox/.gitignore` containing:

```
*
!.gitignore
```

**Why.** Git tracks files, not folders, so an entirely-ignored folder simply
wouldn't exist in a fresh clone — the scratch space would have to be recreated by
hand each time. Un-ignoring the `.gitignore` itself gives git one file to track,
which materializes the folder on clone while still ignoring everything else put
inside it.

**Alternatives.** A `.gitkeep` alongside a blanket ignore does the same job with
an extra file; a root-level `sandbox/` entry in a top-level `.gitignore` keeps the
rule central but loses the self-materializing folder. The local `.gitignore` is
the smallest thing that does both jobs.

---

## 2026-09-02 — The transpiler walks unoptimized typed IR, not the surface AST

**Context.** `transpile` needs some representation of each concrete method to
turn into C. Three candidates were on the table.

**Options considered.**

- *Surface AST* (`Meta.parse` of the source text). Literally the abstract
  syntax tree, and the output would read like the source. But it carries no
  types: we'd have to re-infer or guess the C type of every variable ourselves,
  and the concrete `MethodInstance` that `concretemethod` produces would go
  unused. It also requires the source file to be findable at transpile time.
- *Optimized typed IR* (`code_typed(optimize=true)`). Inlined all the way down
  to intrinsics (`add_float`, `div_float`, …) — a closed set with exact C
  equivalents. But local variable names and assignments are optimized away,
  and control flow becomes gotos, so the C is hard to read and "assignment"
  as a construct effectively disappears.
- *Unoptimized typed IR* (`code_typed(optimize=false)` on the MethodInstance).
  Every value carries its inferred concrete type, local names survive, and
  arithmetic appears as calls to `+`, `-`, `*`, `/` that map to C operators.

**Decision.** Unoptimized typed IR.

**Why.** It's the only option where the type information we already paid for
(inference on a concrete signature) drives the C types directly, *and* the
output stays recognizable — `d = (a + b) * c / 2` becomes a handful of typed
temporaries plus `d = _6;`. Cases like `Int / Int → Float64` are visible in the
IR as a call returning `Float64`, so the emitter can insert the C cast. The cost
is that calls stay generic (`+` rather than `add_float`), so the emitter keeps
its own table of which Julia functions map to which C operators. That table
will grow, but each entry is explicit and readable.

**Shape of the emitted C.** Each SSA value becomes a temporary `_N` declared
with its type; each Julia local becomes a C local of the same name declared at
the top of the function. An assignment statement `%i = (x = rhs)` binds both
`_i` and `x`, since later IR may refer to either. Prototypes are emitted before
definitions so functions can call each other regardless of order.

---

## 2026-09-02 — C names: keep the Julia name, mangle only on collision

> **Extended 2026-09-03.** The mangling itself is now the escalating scheme
> in the entry below; "plain name unless there's a collision" still holds.

**Context.** A Julia function transpiled at two signatures (`fun1(Float64…)`
and `fun1(Int64…)`) can't both be `fun1` in C.

**Options considered.** Always mangle with the argument types; keep the plain
name and error on collision; keep the plain name and mangle only the colliding
ones.

**Decision.** Plain Julia name by default; when several instances in one
`transpile` call share a name, those instances get the argument types appended
(`fun1_Float64_Float64_Float64`).

**Why.** Readable names in the common case matter more than perfectly stable
names. The known cost is that a function's C name depends on what else is in
the same batch — transpiling `fun1` alone gives `fun1`, alongside another
signature gives the mangled form. Acceptable for now; revisit if the output is
ever consumed by other C code that needs stable symbol names.

---

## 2026-09-03 — Intermediate values are named `temp<N>_<variables>`

**Context.** Every intermediate value in the IR becomes a C local. The names
`_4`, `_5` mirrored SSA numbering, which is machine bookkeeping on display and
fails the README's readability principle. Spelling out the full expression
instead (no temps at all) is a separate, later step; this decides what temps
are called while they exist.

**Decision.** Within each function, temps are `temp1`, `temp2`, … in creation
order, with the named variables used directly in the calculation appended:
`temp1_a_b = a + b`. Literals contribute nothing; a variable appears at most
once; a temp passes along only its suffix, never its base, so
`temp8_a_b = temp7_a + b` and `temp9_a = temp6 + a`. A number is skipped if any
of the user's own variables is `temp<N>` or `temp<N>_…` — `temp1001` blocks
only 1001. If the mangled name would exceed `templimit` (default 40, a
`transpile` option), the suffix is dropped and the temp is just `temp<N>`.
Full rules live on `temp!` in `src/c.jl`.

**Why.** The suffix tells a reader what a temp *is* without chasing its
definition, while the numeric base keeps temps distinguishable and ordered.
Skipping numbers the user has already used avoids two things that look alike
meaning different things. Dropping the suffix past a length limit keeps
pathological names from making a line unreadable — the limit is an option
because the right cutoff depends on the reader.

**Also decided here.** Pure copies in the IR (`%7 = d`, `%8 = %6`) don't become
temps; the reference is forwarded, as long as the variable isn't reassigned
before the value is used. So `d = a; d = d + 1.0` comes out as written rather
than through a temp per read.

---

## 2026-09-03 — Julia names become C names by a fixed per-character rule

**Context.** Julia identifiers can contain Greek, sub/superscripts, combining
accents, emoji — none of which C accepts. Something has to rename them, and
the result should be readable and deterministic.

**Decision.** Rules in `doc/naming.md`, implemented in `src/name.jl`. The
notable choices:

- *NFKD first.* Compatibility decomposition handles all sub/superscripts,
  lookalike letters, and accent-splitting in one standard step, so the rule
  table only needs Greek, a short list of combining marks, and a fallback.
  A side effect is that Greek variants (`ϵ`/`ε`, `ϕ`/`φ`) fold to the same
  name and rely on collision handling.
- *Repeated marks follow LaTeX:* `ddot`, `dddot`. `dotdot` was considered.
- *No rule for a leading digit.* One was drafted (`var` prefix, since C
  reserves leading `_`), then dropped: Julia forbids identifiers starting
  with a digit, subscript, or superscript, so the case can't arise.
- *Reserved words are a hand-maintained list* (`src/reserved.jl`): C
  keywords, names from every standard header the output *might* include,
  and anything the transpiler's own scheme claims. A Julia function or
  variable called `long` becomes `long_`, the same way two names that
  converge get `_`. A list rather than something derived, so that what's
  off-limits is explicit and reviewable, and grows deliberately as headers
  and rules are added.
- *Header names are reserved even when the header isn't included.* `exp`
  is `exp_` in every file, `math.h` or not. This keeps the C stable across
  development updates — adding a header to the emitter later can't rename
  something that used to be fine — and keeps it compatible with outside C
  that may include any of those headers itself. The cost, a handful of
  common words (`exp`, `log`, `round`) always carrying a `_`, was judged
  worth it.
- *Every name takes the same path* — variables, functions, and, once they're
  emitted, types and fields. The argument-type mangling for same-named
  function instances happens on the converted name.

---

## 2026-09-03 — An unnamed result is `result`

**Decision.** When a function's last statement is a calculation rather than
a named variable, the value returned is named `result` instead of
`temp<N>_…`. `result` takes part in collision handling like any name, so a
function that already has a `result` gets `result_`. A temp that is stored into a variable is
referred to by the variable afterward (when the variable isn't reassigned),
so `d = expr` as the last line returns `d`.

**Why.** `return temp7_a_b_joelwashere;` tells a reader nothing except that
the machine ran out of ideas; `return result;` says what the value is. The
variable aliasing exists for the same reason: `d = temp3; return temp3;` is
correct but not what anyone would write.

`result` over `out`: `result` is the conventional name in hand-written C for
a computed value held briefly before return, whereas `out` connotes an output
parameter. Domain-specific names (`sum`, `area`) aren't inferred — if the
Julia wants one, it names the variable, and the name comes through.

---

## 2026-09-03 — Mangling escalates: dimensions, then class, then type

**Context.** Same-named instances were told apart by appending the full Julia
type names (`fun1_Float64_Float64_Float64`). Correct, but long, and it
doesn't say the thing a reader most wants to know about an array argument —
its shape.

**Decision.** Per group of same-named instances, append per-argument
descriptions, escalating only until the names differ: array dimensions
(`3`, `2x3`); then the array class in front (`S`/`M`/none), only if classes
differ in the group; then a type abbreviation after (`F32`, `I64`), omitted
for any function whose arguments are all `Float64`. Scalars are silent until
the type level. Full rules in `naming.md`; abbreviations in `type.md`.

**Why.** Shape is the most distinguishing and most readable fact about an
array, so it goes first and is often all that's needed. Class and element
type are added only when they actually disambiguate, so names carry no dead
weight. `Float64` as the unmarked default matches how the code will mostly
be written: `poly` and `poly_I64_I64`, not `poly_F64_F64` and `poly_I64_I64`.

**Open.** A regular `Array{T,N}` has no size in its type. It mangles as `1D`,
`2D` for now; where its fixed size comes from under `staticarray` is
undecided, and the mangling will follow that decision.

---

## 2026-09-03 — Arrays are C arrays; every array operation is a generated helper

**Context.** First linear algebra: `+`, `-`, unary `-`, `*`, `copy` on
fixed-size arrays. Three things had to be decided: how an array is
represented in C, how operations are emitted, and how results come back.

**Decisions.**

- *Fixed-size row-major C arrays, passed as array parameters*
  (`const double A[2][2]`), not pointers. The compiler sees the shape at every
  call, which is what lets it unroll and vectorize; and it's what a C
  programmer would write for a known-size matrix. Julia's column-major order
  is not preserved — inside the C the layout is invisible, and the helpers are
  written for C's order. Boundary crossings need a layout transpose.
- *One `static` helper per (operation, argument types)*, generated on demand
  and written ahead of the user functions. `static` keeps helpers file-local
  (two outputs can each have their own `add_2x2`) and lets the compiler inline
  them. Names always carry size and type, so a reader can tell `mul_2x2_2`
  from `mul_2x2_2x3` at the call site.
- *Output through the last parameter*, for helpers and for user functions
  that return arrays alike. C can't return an array by value; a trailing
  out-parameter is the idiom, and using the same convention for both keeps the
  call shapes uniform.
- *Matrix–matrix multiply in i-k-j order.* The textbook i-j-k form reads more
  obviously as "multiply", but its inner loop strides down a column of `b`.
  Speed wins the tie per the README; the i-k-j form is still short.
- *Direct store unless the destination is an operand.* `B = -A` writes into
  `B`; `A = A * A` goes through a temp. Checked by name, uniformly, rather
  than reasoning per operation about which ones tolerate aliasing.

**Alternatives considered.** A struct wrapper (`struct { double a[2][2]; }`)
would let arrays be returned by value and assigned with `=`, at the cost of
`.a` on every access and a hidden copy on return. Flat `double *` parameters
with explicit strides would hide the shape from the compiler. Both rejected
for readability and speed respectively.
