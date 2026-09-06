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
fails the philosophy's readability principle. Spelling out the full expression
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

> **Revised 2026-09-03.** The class level (`S`/`M`/none) was dropped: C
> doesn't distinguish static from mutable, and under `staticarray` every
> array is the same thing in C, so the letter never told a reader anything.
> Instances of one method differing only in class are the same C function
> and are emitted once; only two different methods landing on one C
> signature is an error. Escalation is now dimensions, then type.

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

**Resolved 2026-09-03.** A regular `Array{T,N}` gets its size from the
`transpile` call: a type followed by integers, `(f, Float64, 2, 3)`. See the
entry below.

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
  Speed wins the tie per the philosophy; the i-k-j form is still short.
- *Direct store unless the destination is an operand.* `B = -A` writes into
  `B`; `A = A * A` goes through a temp. Checked by name, uniformly, rather
  than reasoning per operation about which ones tolerate aliasing.

**Alternatives considered.** A struct wrapper (`struct { double a[2][2]; }`)
would let arrays be returned by value and assigned with `=`, at the cost of
`.a` on every access and a hidden copy on return. Flat `double *` parameters
with explicit strides would hide the shape from the compiler. Both rejected
for readability and speed respectively.

---

## 2026-09-03 — Array sizes come from the `transpile` call: a type, then integers

**Context.** Under `staticarray` a regular array is to be a static array in
every respect, but `Matrix{Float64}` carries no size. Something outside the
type has to say it.

**Options considered.** Static types at the call, matched to `Matrix` methods
by erasing the size; a separate `(Matrix{Float64}, 2, 3)` form naming both
the Julia type and the size; supporting only untyped functions specialized
with static types; deferring.

**Decision.** In a tuple target, a type followed by integers is an array of
that element type and those dimensions — `(f, Float64, 3, Float64, 2, 3)`.
Nothing says "array"; the integers do. For each such array the static type is
tried first; if the function has no method for it, a regular `Array` of the
same size is used and the transpiler carries the size itself through the
body, by the same rules the helpers use. Same C either way.

**Why.** Under the option there is exactly one kind of array as far as the
output is concerned, so the input shouldn't have to name a kind either — just
element type and size, which is all the C needs. Trying static first means a
function that *can* be inferred with full sizes is; the regular path exists
for methods that insist on `::Matrix`.

**Mechanics worth knowing.** The regular path uses an internal shaped
stand-in (`Shaped{T,size,N}`) wherever a type is asked for its size, so
`declare`, helper naming, and function mangling are unchanged. Sizes of
locals are known only once something is stored in them, so declarations are
emitted after the body is walked. Static-vs-regular is decided for the whole
signature, not per argument.

---

## 2026-09-03 — The Julia source rides along as comments

**Decision.** Comments directly above a definition (up to a blank line or a
line of code), every comment inside the body, and — under the `source`
option, on by default — every line of code, prefixed `file:line:`, are
emitted as `//` comments placed just ahead of the C each line produces. Lines
that are only brackets or `end` give up their trailing comment but not their
code. Full rules in `comment.md`.

**Why.** The C is meant to be read. A reader with the Julia line next to the
C it became can check the translation, find their way back to the source, and
keep the author's own explanations — which the emitter can't reproduce and
shouldn't drop. Making the code lines optional acknowledges that some
readers will want the comments without the doubling.

**Mechanics that shaped it.** The typed IR the emitter walks has no line
table; the lowered IR does, and its statements match one for one, so lines
come from there by index. A definition's extent is found by parsing from the
signature's line. "Where the work happens" means the first statement the
line produced; comments on lines that produce nothing ride with the next line
that does. Continuation lines of a multi-line expression land after that
expression's C — a known imprecision, accepted over parsing every statement.

---

## 2026-09-03 — Doxygen blocks: the docstring's words, plus what C can't say

**Decision.** Every C function gets a `/** … */` block: the Julia docstring's
text verbatim (if there is one), then a generated tail — the Julia method it
came from (name, argument types, file:line), `@param[in]` for each input, and
`@param[out] result` marking the trailing parameter that carries an array
return value. No parameter descriptions, no `@return`, no `@brief`. Other
attached comments stay `//`.

**Why.** Doxygen is the de facto standard for documenting C and hand-written
libraries use it, so the block makes the output look like a library, not
like generated code. Doxygen takes the signature from the C declaration, so
the signature is always the C one; what the declaration *can't* say is
exactly where C and Julia diverge — that a `void` function's last parameter
is really its return value, and that `poly_I64_I64` is Julia's `poly` at
`(Int64, Int64)`. Those are facts the transpiler has, so it states them.
Parameter meanings it doesn't have, so it doesn't invent them — `@param a a`
is the line that gives generated code away. Keeping plain comments as `//`
stops section headers from being mistaken for documentation.

---

## 2026-09-03 — Control flow is recovered from Julia's gotos, never emitted as gotos

**Context.** Julia lowers every `if`, `while`, `for`, `&&`, `||`, and `?:`
into `goto`s before the transpiler sees the function. C has `goto`, so the
literal translation exists — and would fail the philosophy's readability
principle completely.

**Decision.** Recognise the goto patterns Julia's lowering produces and emit
the constructs they came from: `if`/`else if`/`else`, `while`, `for` over
integer ranges, `break`/`continue`, `&&`/`||` in conditions. A pattern the
recogniser doesn't know is an error, not a `goto`. Full table in `flow.md`.

**Why this is feasible.** Julia's lowering is regular: the same source shape
always produces the same jump shape, and the result is structured (jumps go
forward within a construct or back to a loop header). So a small set of
patterns covers the language's everyday control flow, and the textual
copy-elimination check in `copy.md` stays sound.

**Conditions inline.** A `while` whose test was a temp computed once would be
wrong, so the calls feeding a condition or a loop bound are rendered inline as
expressions — the first, deliberate crack in the "one temp per value" scheme,
limited to where correctness demands it. C precedence and parenthesisation are
handled explicitly.

**Loop variables stay 1-based.** `for (int64_t i = 1; i <= n; i++)` with
`v[i - 1]` is correct and matches the Julia; rewriting to the C idiom when the
variable is only an index is a later readability pass.

**`for` only over ranges, with a literal step.** That is the loop C can
express directly. Iterating a collection by element, or a runtime step, needs
a different shape and isn't attempted yet.

---

## 2026-09-03 — Row vectors are free; broadcasts are un-fused; block construction is a helper

**Context.** Adding `[A B; C D]`, broadcasting, `v'`, `dot`, `cross`, and
`transpose`.

**Decisions.**

- *A row vector is the same C storage as its column, remembered as a row.*
  `v'` emits nothing; the value is tagged `Row{T,N}` internally, named `r3`,
  and every helper that gets one treats it as 1×N (`mul_r3_3x2`,
  `mulP_3_r3`). The alternative — a real 1×N C array `double r[1][3]` — would
  cost a copy at every transpose and read worse. Since the C is identical
  either way, the tag is the cheaper truth.
- *Broadcast chains are un-fused.* Julia turns `exp.(v) .+ 2.0` into one loop;
  here it's `expP_3` then `addP_3_s` through a temp. One helper per
  operation keeps the naming scheme (one name, one operation, its input
  sizes) intact and the helpers reusable. The cost is an extra pass over
  small arrays; fusing is a later optimization if it ever matters.
- *Block construction is a helper that lists every input.* `[A B; C D]` is
  `hvcat2x2_2x2_2x2_2x2_2x2`: the block count matters, so identical
  descriptions aren't collapsed the way they are for `add_2x2`. All-scalar
  literals skip the helper and assign element by element, which is what a
  person writes.
- *`cross` is unmangled.* Always 3-vectors, so a size would say nothing.
- *Scalar-returning helpers* (`dot_3`, `mul_r3_3`) return their value rather
  than taking an out-parameter — a scalar is what C returns naturally.

---

## 2026-09-03 — Helper generators are written once, for the general case

**Context.** The philosophy's third principle — generalize whatever can be —
arrived after the linear-algebra helpers, which had grown separate bodies for
matrix×vector, matrix×matrix, row×matrix, column×row, and separate access
code for vectors, rows, and matrices in broadcasting and block placement.

**Decision.** One primitive: an operand's logical shape (`bshape`) plus the
logical dimensions it stores (`stored`), from which `access` produces any
operand's C subscript. On top of it, one `contraction` for every `*`
(including the scalar-returning ones), one broadcast loop, one block-placement
loop. Loops of extent 1 are not emitted; their index is `0`.

**Why.** Five hand-written multiply bodies were five places to get a sign or
an index wrong and five things to read; one contraction is one. The generated
C is unchanged in every case that existed before except matrix×vector, which
now zeroes and accumulates into `out[i]` like the others instead of through a
local `sum` — the same i-k-j order the earlier decision chose, with no
separate zeroing pass. All 23 numeric checks still agree with Julia.

---

## 2026-09-03 — One letter for pointwise operations: `P`

**Decision.** Broadcast helpers are named with `P` (pointwise) after the
operation — `mulP_3_3x2`, `addP_3`, `expP_3x3` — and otherwise by the same
rule as every other helper. This replaces the earlier `E` (element-wise,
same sizes, size written once, types run together) and `B` (broadcast, sizes
differ, everything listed).

**Why.** Two letters and two formats were more scheme than the distinction
was worth: whether the sizes happened to match is visible from the name
either way. One letter, one rule, nothing to remember.

---

## 2026-09-03 — Helper names list every input, always

**Decision.** A helper's name is the operation plus one description per
input, with no collapsing of identical inputs: `add_2x2_2x2`, `mul_2x2_2x2`,
`mulP_3x2_3x2`, `dot_3_3`, `cross_3_3`. This replaces "if both args match we
only say one" (`add_2x2`) and the `cross` exception.

**Why.** `mulP_3x2` reads like a function of one thing — "a function that
always multiplies 2 and 3 and gives 6." A name should stand on its own, and
the collapsed form only ever made sense next to its call. Listing everything
makes the name a transcription of the signature, needs no exceptions (the
`cat` helpers had already had to opt out, since block count matters), and
generalizes to any arity with no rule to remember. The cost is a few
characters. `fill_3` and `hvcat2x2_…` carry output information because their
inputs don't determine it — the rule's extension, not an exception to it.

---

## 2026-09-03 — Operands keep exactly their own dimensions

**Context.** The generalized helpers first described every operand by a
padded "logical shape": a vector as N×1, a row vector as 1×N, a scalar as
1×1. It worked, but the wording was wrong, and the code said the wrong
thing too.

**Decision.** A vector has one dimension. A row vector has one dimension,
which lines up with the second axis of whatever it meets. A scalar has zero
dimensions (and, like 0!, a size of 1). Nothing is ever added: an operand is
described by the axis each of its own dimensions lines up with (`axis`), and
its extent along any axis is its size there or 1 where it has no dimension
(`extent`). `bshape`/`stored` are gone; `access`, the contraction, the
broadcast loop, and block placement all read from `axis`/`extent`.

**Why.** It's the same principle as keeping every dimension the inputs
gave us, read the other way: the shape is exactly what the inputs
determined, no more and no less. Saying "a vector is N×1" invites someone to
one day emit `double v[3][1]`, which would be wrong. The generated C is
byte-identical before and after; only the description became true.

---

## 2026-09-03 — A transpose is a tag, never a copy, and its name is `T`

**Context.** A vector's transpose was already free: the same storage,
tagged `Row`, named `r3`. A matrix's transpose was a helper that copied
into a temp, followed by the ordinary operation on the temp — `A * B'` cost
a `transpose_2x3` pass that no one writing C by hand would make.

**Decision.** One tag, `Transposed`, for the transpose of anything Julia
lets you transpose (0–2 dimensions; a scalar's is itself and Julia inlines
it away). It carries only the storage shape; what changes is which axis each
dimension lines up with — reversed. Nothing in C records that a value is
transposed, exactly as nothing records that a vector is a row: it's the same
storage, and only Julia's type (hence the transpiler) knows. So `A * B'` is
`mul_2x3_T2x3` with `a[i][k] * b[j][k]` inside, `A + B'` is
`add_2x3_T3x2`, and `transpose_2x3` no longer exists. Where the value must
land — `B = A'`, or a function returning `A'` — the C follows Julia's type
for the landing spot: a lazy `Adjoint` (a vector's) is the same storage,
copied as `copy_3`; an eager one (StaticArrays materializes a matrix
transpose into a real 3×2) is copied axes-swapped by `copy_T2x3` into a
`double [3][2]`. The tag never decides a C type; Julia's type does. In names, `T`
in front of the storage shape (`T3`, `T2x3`) replaces `r3`: it's the
mathematical notation, it covers matrices where "row" didn't, and it can't
be read as a type suffix.

**Why.** With operands described by the axis each of their dimensions lines
up with, a transposed matrix needed no new machinery — reversing the axes
is a one-line rule, and `access` then places every subscript. That is the
generalization principle doing its job: `Row` was the special case, this is
the general one it belongs to. The elementwise helpers walk storage order
with plain subscripts when every operand lines up the same way (unchanged
output, contiguous) and switch to axis-placed subscripts only when one is
transposed relative to the others.

---

## 2026-09-03 — Helper comments speak like a person; the code never does

**Decision.** Each generated helper carries a one-line `///` comment in
ordinary mathematical English: `2×3 * 3×3 matrix multiplication`,
`4-vector + 4×3×2-array broadcast addition`, `2×2-matrix negation`,
`2×3-matrix element-wise exponential`, `transposed 3-vector * 3-vector
multiplication`. The vocabulary — scalar, vector, matrix, N-D array,
element-wise versus broadcast, `×` between sizes — lives in `src/prose.jl`
and nowhere else.

**Why.** The transpiler deliberately has no notion of a vector or a matrix
(only arrays of any dimension, each dimension on an axis) and no notion of
element-wise versus broadcast (only pointwise, one loop over the result).
Those distinctions are exactly what made the code general, so they mustn't
creep back in. But a reader thinks in them, and the philosophy's second
principle is that the output reads as hand-written. Keeping the human words
in one prose layer gives the reader what they expect without giving the
code an exception to make. Known functions are named in English
(`exponential`, `square root`); user-defined or unlisted ones keep their
Julia name, so nothing is refused for lack of a translation.

---

## 2026-09-04 — Helper parameters are letters; the output is `out`

**Decision.** A helper's inputs are `a`, `b`, `c`, … in order, capitalized
for a matrix or higher-dimensional array and lowercase for a vector or
scalar, continuing `aa`, `ab`, … past 26 like spreadsheet columns; the output
is `out`. A loop index that would collide with an input gets `_` appended
(`i_`). The user function's array out-parameter is also `out` now (it was
`result`); a returned scalar stays `result`.

**Why.** `mul_2x3_3(const double A[2][3], const double b[3], double out[2])`
reads like the mathematics, and `hvcat(A, B, C, D, out)` reads like
`[A B; C D]`. One rule covers every arity with nothing to remember. On
`out` versus `result`: an earlier entry rejected `out` because in C it
connotes an output parameter — which is exactly what the trailing array
parameter is, and exactly what a returned scalar isn't. Both names are now
used, each where it means the right thing, and helpers and user functions
agree.

---

## 2026-09-04 — Arrays from nothing are one `memset`

**Decision.** `zeros`, `zero(A)` produce `zero_3x4(out)`, whose body is
`memset(out, 0, sizeof(double[3][4]))`; `one(A)` and `SMatrix{3,3}(I)`
produce `identity_3x3(out)`, the same `memset` followed by ones down the
diagonal. `ones` and `fill` still assign every element, since there's no
byte pattern for an arbitrary value.

**Why.** All-zero bytes are zero in every type the transpiler emits (IEEE
floats, two's-complement integers, `bool`), so `memset` is both the fastest
and the most hand-written form. `sizeof(double[3][4])` rather than a byte
count keeps it readable and self-checking.

---

## 2026-09-04 — Name collisions: rename variables, refuse functions, reserve widely

**Decision.** Three rules, in `naming.md`:

- A user *variable* whose C name matches a generated helper's is renamed
  with `_`, by generating that function again once the helper names are
  known. A user *function* whose name matches a helper's is an error.
- The reserved list grows from the headers the output might emit to the
  headers C written around the output commonly includes (`stdio`, `time`,
  `ctype`, `limits`, `float`, `errno`, `assert`, the POSIX names a default
  compiler exposes), all three widths of every `math.h` function, and
  `main`. A reserved name gets `_` appended, as before; nothing is refused.
- A name beginning with `_` has its leading underscores moved to the end.

**Why.** Renaming a variable is invisible to the caller; renaming a function
changes the C interface, and the user should choose the new name. Reserving
by header regardless of whether the header is included keeps the output
stable (adding an include later can't rename an existing variable) and
keeps it safe next to outside C. The underscore rule is the only one that
can't be an `_` suffix, since a leading underscore is the problem.

---

## 2026-09-04 — `det`: sizes 1–3 written out, cofactor expansion beyond

**Decision.** `det(A)` becomes `det_NxN(A)`, a scalar-returning helper. For
1×1, 2×2 and 3×3 the formula is written out in full, as a person writes it.
From 4×4 up the body is cofactor expansion along the first row: a loop over
the column, the minor cut into a local `M`, and a call to the next size
down, so `det_5x5` calls `det_4x4` calls `det_3x3`. The sign alternates
through a local `sign`, not `pow(-1, j)`.

**Why.** For small fixed sizes the expanded formula is both the fastest
thing and the most readable, and those are the sizes that dominate the
kinds of code this transpiler is for. Cofactor expansion is exponential and
would be the wrong choice for large matrices, but a large *static* matrix
is rare, and the recursion through generated helpers reads exactly like the
textbook. This is the pattern for the more involved algorithms to come:
sizes 1–3 hardcoded, a general form beyond, both as helpers.

---

## 2026-09-04 — `restrict` on every output array

**Decision.** Every output array — a helper's `out`, a user function's
trailing `out` — is declared `double out[restrict 3]`. The Doxygen line on
the user function says the caller must not overlap it with an input.

**Why.** A Julia result is always a fresh array, so `out` provably never
aliases an input; the transpiler already routes a result that is also an
operand through a temp, and now that promise is written down where the C
compiler can use it to keep loads in registers across the stores and to
vectorize. It's the philosophy's first principle for free. The array-parameter
spelling (`out[restrict 3]`) is legal C99 and keeps the size visible, which
`double *restrict out` would lose.

---

## 2026-09-04 — Calls are calls; callees come in on demand; `ccall` passes through

**Decision.** A call to a user function is a C call. The callee is resolved
at the call's argument types and transpiled if it wasn't asked for, with
its Julia name unless that's taken. A `ccall` becomes the symbol called
directly, with the standard header when the name is one of a known
header's and a prototype from the `ccall`'s types otherwise. A `Ptr`
argument is `const` when the Julia value is an immutable static array.

**Why.** Real programs are more than one function; and Julia that already
calls C is the easiest possible thing to turn into C — the call *is* the
C. Bringing callees in on demand means the user lists entry points, not
every function, and recursion needs nothing special since every function
has a prototype. The `const` rule is Julia's own: an immutable static
array can't be written through a pointer, a mutable one can.

---

## 2026-09-04 — Structs by value, mutable structs by pointer, tuples as structs

**Decision.** An immutable `struct` is a C struct passed and returned by
value; a `mutable struct` is always a pointer; a parametric struct is one C
struct per concrete instantiation, named like a function at several
signatures; a tuple is a struct `Tuple_F64_I64` with fields `a`, `b`, …
Creating a mutable struct inside transpiled code is refused. A trailing `!`
on a function name is dropped.

**Why.** Each of these is what the Julia semantics say: an immutable struct
*is* a value, a mutable one *is* a reference, and C has exactly one honest
spelling for each. Making a mutable struct would need an allocation and an
answer to who frees it — the design in `map.md` §3.1 — and refusing it now
keeps everything on the stack, which is where this project lives. Tuple
fields can't have meaningful names, and the letters are already the
convention for anonymous inputs. `bump!` → `bump` because `bumpU21` is what
the general Unicode rule would produce, and nobody would write that.

---

## 2026-09-04 — Solvers: sizes 1–3 written out, pivoted LU from 4, all on the stack

**Decision.** `A \ b` and `inv(A)` at sizes 1–3 are Cramer's rule and the
adjugate over the determinant, written out exactly as StaticArrays writes
them. From 4 on: LU with partial pivoting, with the pivot step its own
helper (`pivot_NxN`), the decomposition another (`lu_NxN`), and the solve
and inverse built on those. `cholesky(A) \ b` and `inv(cholesky(A))` are
Cholesky, written out for 1–3. `B / A` is the same solve with `A` read
transposed, one row at a time, and `\` and `/` on scalars and
array-over-scalar are the plain division they are in Julia. A singular or
non-positive-definite matrix prints Julia's exception and `abort`s. Every
work array is a stack array of the static size; nothing is allocated.

**Why.** This is the user's rule for every involved algorithm, and it is
also what makes the code both fastest and most readable at the sizes that
dominate: the written-out forms have no loops, no branches, and no pivot
search, and they are what a person writes for a 3×3. Beyond that, an
unguarded algorithm would fail on perfectly ordinary matrices, so the
deterministic guard is partial pivoting, factored out so that every
elimination — the coming QR and LDLT included — shares one definition of
"choose the pivot". `abort` on singularity is the error mapping `map.md`
§3.8 proposes: an uncaught exception ends a Julia program the same way.
LDLT is deferred because Julia offers no `ldlt` for static matrices to hang
it on; it needs a reference implementation first.

---

## 2026-09-04 — Runtime-sized arrays stay open

**Decision.** `staticarray=false` still refuses. The VLA design in
`map.md` §3.4 stands, unbuilt.

**Why.** Sizes are in every helper's name, loops, and result type. Runtime
sizes mean helpers that take sizes as parameters and, harder, result sizes
derived symbolically from input sizes (`A * B'` is `m×m`). That's a second
helper layer, not an extension of this one, and it deserves its own
session rather than the tail of one that added six features. Nothing done
here makes it harder.

---

## 2026-09-04 — `pinv` and least squares through the Gram matrix

**Decision.** `pinv(A)` is one helper per shape — `pinv_4x3`, `pinv_3x4`,
`pinv_3x3` — computing `(AᵀA)⁻¹Aᵀ` for a tall matrix, `Aᵀ(AAᵀ)⁻¹` for a
short one, and the inverse for a square one; the Gram matrix goes through
Cholesky. A non-square `A \ b` is the matching solve: the normal
equations for tall, the minimum-norm solution for short, one Cholesky
solve instead of an inverse and a product.

**Why.** Julia uses the SVD for `pinv` and QR for least squares, both of
which survive a rank-deficient `A`. Reproducing them would mean a static
SVD, a large piece of work; the Gram route is a few lines on top of
helpers that already exist, it's faster, and for the full-rank,
well-conditioned matrices this project is for it agrees to rounding. The
rank-deficient case is reported (`PosDefException`) rather than
silently wrong. The transposed tag is what makes it cheap: `AᵀA` is one
multiply helper reading `A` both ways, with no transpose ever formed.

---

## 2026-09-04 — A helper's name says what the contract leaves open

**Decision.** This replaces "helper names list every input, always". A
description is always shape then type, with a scalar's shape `s` (`sF32`,
never a bare `F32`). An operation that leaves the shapes open lists every
input: matrix multiplication (`mul_2x2_2x3`, `mul_sF32_2x2F64`) and every
pointwise operation (`mulP_3x2_3x2`). One whose contract fixes the shapes
as identical writes the shape once and then the types run together, one if
they agree: `add_2x2`, `add_2x2F32F64`, `dot_3`. `cross`, whose shapes are
fixed entirely, keeps only the types: `cross`, `cross_F32`, `cross_F64F32`.
A transposed operand still lists in full (`add_2x3_T3x2`), since the
storage differs. Output-named helpers (`fill_3`, `slice_5_3`) are unchanged.

**Why.** For `add` and `dot` the second description said nothing: the
operation already demands identical shapes. The earlier objection —
`mulP_3x2` reads like "multiply 2 and 3" — was really about pointwise
operations, where broadcasting lets shapes differ and one description
leaves the reader guessing; those keep listing every input, so the
objection is met by the narrower rule rather than contradicted. Making a
scalar always `s` is what lets `cross_F32` exist: under the old scheme a
bare `F32` *was* a scalar, so `cross_F32` would have read as a scalar
cross product. Multiplication stays fully listed because its contract only
constrains the shapes, and no notation for "inner sizes equal" would be
understood at a glance. The result has no exceptions: `cross` is just what
the rule produces for an operation that fixes everything.

---

## 2026-09-05 — Small helpers are `static inline`; solvers are `static`

**Decision.** A helper that is straight-line code or plain loops is
`static inline`; one that calls other helpers, searches, or can abort — the
solvers and factorizations from 4×4, Cholesky, `pinv`, and their pieces — is
plain `static`. Helpers stay in the `.c`; no header yet.

**Why.** For a `static` function in one translation unit the optimizer
inlines a three-line loop at any sane setting, so `inline` is mostly a
hint; but it is the hint an experienced C programmer writes on a small
helper, it costs nothing, and it helps at the margins (many call sites, a
conservative compiler). On a factorization it is the wrong signal. Drawing
the line by *shape of the code* — no calls, no search, no abort — rather
than by judgment per helper keeps it one rule. Header-only helpers would
pay off only when two outputs share them, which is also when the companion
`.h` on the todo becomes necessary; marking the small ones `inline` now is
exactly what that header will need, so this leaves that step open.

---

## 2026-09-05 — Printing is `printf`, the way a C programmer writes it

**Decision.** `print`/`println` become one `printf` per run of strings and
scalars: `%g` for a floating value (`%.17g` under the `precise` option),
`%lld` for an integer, `%d` for a boolean; `fprintf(stderr, …)` when the
stream is given. Arrays go through one helper per element type,
`printarray(f, a, ndims, dims)`, which prints one row per line in
right-aligned `%12g` fields, a blank line between 2-D slices, two between
3-D blocks, and so on for any dimension, nothing after the last element.
`@printf` passes its format through with 64-bit widening. All of it lives
in `src/io.jl`, apart from the rest of the emitter.

**Why.** A first version reproduced Julia's output character for character
— shortest round-trip digits, `3.0`, `[1.0 3.0; 2.0 4.0]`, `Bool[1, 0]` —
with a helper per floating type and per array shape. That was the wrong
goal: the C isn't trying to grow up to be Julia, it's trying to be the best
C it can be, and a C programmer prints a number with `%g` and a matrix as an
aligned block. `%g` differs from Julia's `3.0` and six digits from
seventeen; `precise` exists for when the digits matter, and the difference
is documented rather than papered over. The one helper is the one place a
shape is passed at run time instead of baked into a name; it bends the
sizes-in-names convention, not the no-allocation rule, and for printing
that's the right trade — it's the `print_matrix(a, rows, cols)` every C
programmer has written, generalized. The stream-first signature is what
lets files arrive later without touching any of this, and printing is a
different kind of thing from arithmetic, so it gets a file of its own.

---

## 2026-09-05 — Moving data is written inline; a helper is for computation

**Decision.** Copies, block construction, slices and slice assignment,
`zeros`, `fill`, and the identity are written where they happen — `memcpy`
for a contiguous run, `memset` to zero, a loop otherwise — and the helpers
that did them (`copy_2x2`, `hvcat2x2_…`, `row_2x3`, `set_2x4_2x2`,
`zero_3x4`, `fill_3x4`, `identity_3x3`) are gone. Block construction
follows Julia's real rule, a tree of concatenations whose pieces need only
agree in the dimensions they don't join along, so `[A; B;; B; A]` with a
scalar and a vector, `[A B; B A]` with a scalar and a row, and `[B;; C;;;
D;; E]` all work. One primitive, `move!` in `src/move.jl`, does every
movement.

**Why.** A C programmer doesn't write a function called
`hvcat2x2_2x2_2x2_2x2_2x2`; they write `memcpy(&out[i][2], B[i], …)` where
it happens, and the source line above already says `[A B; C D]`. The names
were unreadable and hard to design, the same construction rarely recurs
enough to earn one, and copying an array through a function call was the
least C thing the output did. The line between the two kinds of thing is
clean: computation (arithmetic, products, solves, reductions) has an
algorithm worth a name and a comment; movement has neither. The earlier
grid layout was also wrong for Julia — it demanded that blocks tile — and
the tree is both correct and simpler.

---

## 2026-09-05 — Step comments: the math of each operation, in C names

**Decision.** When a Julia line becomes several C operations, each gets a
comment giving that step as a textbook writes it, with the C names
including temps: `addP_3x3_3(A, b, temp1);  // temp1 = A .+ b`, then
`// temp2_c = temp1 \\ c`, then `// out = temp2_c + D`. A step that is a
loop gets the comment above it; a line that became one operation gets
none, since its source comment already says it. The spelling is the one
the helper comments use: `ᵀ`, `⋅`, `×`, `\\`, `⁻¹`, `.+`, `[C A; B C]`,
`A[2, :]`.

**Why.** This is the second paragraph of Craft (`philosophy.md`) made
concrete: the reader is someone strong in math who may not know C, and
when the helpers for data movement went inline that reader lost the name
that told them what a block of `memcpy`s was. A C programmer helping such a
reader would write exactly these comments. Using the C names rather than
re-spelling the Julia sub-expression keeps each comment short and makes
them chain — the temp one step produces is the temp the next consumes —
which is where a reader following an expression through temps actually
gets lost. A single-step line would only repeat its source line, so it
gets nothing.

---

## 2026-09-05 — Declare at first assignment; `x_new`; aliasing decided per operation

**Decision.** Three rules, from a close reading of `sandbox/demo.c`.
(1) A variable is declared at its first assignment: `double r = norm_3(x);`,
`double a[3];` right above the call that fills it. When that assignment is
inside an `if` or a loop, the declaration goes just ahead of the construct.
Nothing is declared at the top of a function for its own sake.
(2) A parameter that Julia reassigns is never copied at entry. It is read as
the parameter until the reassignment; the new value is a second variable
named `x_new`, declared there and written straight into. Inside a construct,
`x_new` is declared ahead of it as a copy of `x`, and the construct reads
`x_new` throughout. A Julia name that is itself `x_new` gets the usual `_`.
(3) Whether `x = f(x, …)` may write into `x` is decided per operation.
Elementwise operations (`+`, `-`, a scalar multiple or quotient, a broadcast
of same-shaped arrays) write in place, and those helpers' `out` is no longer
`restrict`. Products, solves, inverses, `pinv`, the cross product, a
transposed operand and a construction keep the temp and the `restrict`.
Also: step comments follow two spaces with no alignment; a whole local array
is copied with `sizeof x`; the Doxygen tail reads `Julia signature:`,
describes array parameters as `3-vector`, `4×2-matrix`, and ends
`out  6-vector, the result; must not overlap an input`.

**Why.** All three are what the Craft reader (`philosophy.md`) trips over.
A declaration a dozen lines above the first use is a C habit from before
C99 that no one coming from Julia has, and no one writing C today keeps.
`memcpy(x_, x, …)` at the top of a function is a copy the program never
asked for — the input is only ever read — and `x_` names nothing; `x_new`
is what a physicist would write for the updated state. Applying the temp
rule uniformly was simpler to state, but it cost an unneeded temp and copy
on the most common line in numerical code, `v = v + dt * a`; the safety
argument is local to each helper (an elementwise helper reads each input
only where it writes), so the decision is made where the knowledge is. The
price is that elementwise helpers give up `restrict`, which they never
needed for their loops to vectorize. The earlier alternatives — `x_copy`, a
copy at the top, hoisting everything — were each weighed and set aside in
the conversation that led here, and the summary is the rule above.

---

## 2026-09-05 — Sign folding; Doxygen tags; `restrict` on `out` stays

**Decision.** `-x / s` and `-x * s`, where `x` is an array and `s` a
scalar, put the sign on the scalar: `div_3_s(x, -s, a)`, no `neg_3`, no
temp. The Doxygen tail describes every parameter — `scalar`, `3-vector`,
`3×3-matrix` — tags an array the function writes into `[in,out]`, and says
of the result parameter only `6-vector, the return value`. The result
parameter keeps `restrict` unconditionally.

**Why.** The fold is exact — IEEE rounding is symmetric, so `x / (-s)` is
bit-for-bit `(-x) / s` — and it is what anyone writes by hand; a helper
call to negate three numbers is the kind of thing that makes generated code
look generated. The old `@param[out] out  … must not overlap an input`
restated `restrict` in English right after a name that already says `out`;
the C reader knows the word, and the description a math reader wants is the
shape. `[in,out]` is Doxygen's own tag for a mutated input, and the
transpiler already knows which those are. Dropping `restrict` where a
function finishes reading its inputs before writing was considered and set
aside: it would buy a caller the freedom to pass overlapping buffers, which
no one wants, and cost the vectorization of every write into `out`. Copying
inputs to make aliasing safe was set aside for the same reason the entry
copy of a rebound parameter was removed the same day.

---

## 2026-09-05 — Reassigned array parameters: copy at the top, with the reason written

**Decision.** Reverses part of the morning's entry. A reassigned *scalar*
parameter is reassigned in place — C passes it by value. A reassigned
*array* parameter is worked on as a copy `x_`, made at the top of the
function in one block, all such copies together, with a comment above:
`// copy x and v to prevent modification within this function`, and a
blank line after. One name reads `copy x to …`; three or more are listed
with commas and an Oxford comma, `copy x, y, and z to …`. The body then uses `x_` throughout. The
`x_new` scheme — no copy, read the parameter until the reassignment, hoist
a copy ahead of a construct when the reassignment sits inside one — is
withdrawn.

**Why.** The copy was never the problem; the *unexplained* copy was. With
the reason on the line above, the copy reads as a deliberate act — the same
one Julia performs, a fresh slot initialized from the argument — and one
rule with no cases replaces a scheme that had to know whether the
reassignment was in a loop, a branch, or straight-line code, and in the
construct case made the very copy it existed to avoid. For a scalar there
is nothing to copy at all, and `a_new` for a by-value parameter was simply
wrong. `x_` rather than `x_new` because, with the copy made at entry, the
variable is the working copy of `x` from the first line, not a new value
that appears partway through; the plain collision rule already gives that
name, so nothing is added.

---

## 2026-09-05 — A blank line before each Julia statement's C

**Decision.** Every Julia statement's C — its source comment, any comment
lines above it, and the code — is preceded by one blank line, at every
nesting depth, except directly after an opening brace; a blank never sits
against a closing brace. Julia's own blank lines stay uncopied. The rule
holds with `source=false`.

**Why.** The output felt crammed, and the cause was not the lost blank
lines of the Julia but the expansion: one Julia line becomes a comment,
temps and a helper call, and consecutive paragraphs with no space between
them read as one wall. So the break goes where the expansion is, one per
statement, which is how a person comments C by hand — a comment introducing
a small block, the block, a gap. Copying the author's spacing instead would
have left a function with no blank lines, like `orbit`, exactly as dense as
before. With `source=false` the blank is the only thing left marking where
one statement's C ends and the next begins, which is the argument for
keeping it there too. Implementation: `separate!` in `src/c.jl`, called
from `block!` when a statement starts a new line; line numbers come from
the IR, so it works without the source file.

---

## 2026-09-05 — Unnamed scalar values are written where they are used

**Decision.** A scalar SSA value with one use is rendered inside the
expression that consumes it: `double result = sqrt(sq(a) + sq(b));`, not
three temps. The rule mirrors the author: a value they named in Julia is a
named C variable; a value they didn't name is not. Three exceptions keep a
temp — the consumer is a `return` (the result stays `result`), the consumer
writes its operand twice (`x^2` as `x * x`, `mod`, integer `max`/`min`,
struct `==`), or an effect stands between the value and its use (a print, a
store, a `ccall`, a user function with any of those, found by reading the
callee's IR). Conditions and loop bounds, which already inlined this way,
follow the same code. Alongside: `-(-x)` is `x`, `a + -b` is `a - b`,
`a - -b` is `a + b`; `v[i + 1]` is `v[i]`; and parentheses are added under
shift and bitwise operators and around `&&` under `||`.

**Why.** Named single-use temps for scalar arithmetic were the most
generated-looking thing left in the output, and nobody writes C that way.
The question "when is a temp more readable" has no heuristic answer that
survives contact with real code; the author's own choice of what to name is
the right one, and following it means a long Julia one-liner becomes a long
C line, which is fair. The exceptions are about meaning, not taste:
evaluating a call twice doubles its cost and its effects, and C's
unspecified evaluation order would let two prints swap. Purity is read off
the callee's IR because the transpiler already has it; the same reading
fixed a real bug, a `const` parameter handed to a callee that writes it.
Speed is neutral throughout; the compiler produces the same code either way.

---

## 2026-09-05 — `return` is a consumer too; long lines wrap

**Decision.** Amends the entry above. An unnamed scalar value consumed by a
`return` is written in the `return`: `return sqrt(sq(a) + sq(b));`. The
name `result` remains only where the value can't be written there — a
`ccall`'s result, a value returned from several places. Effects are handled
more finely than "pure calls only": a call with an effect may be written
where it is used when nothing that computes stands between, not even a
read, while a pure value may move past any pure work. And a line that would
run past the new `width` option (100 columns) wraps at its loosest
operators, continuation lines led by the operator and aligned under the
first operand.

**Why.** With everything else inlined, `double result = …; return result;`
was the last two-line form of a one-line thought, and `return expr;` is
what everyone writes. Allowing effectful calls to inline, adjacent to their
consumer only, gives `return shout(a);` and `x = f!(v) * 2;` without
letting an effect slide past a read that would see it — the case
`mutate!(v, 1.0) + mutate!(v, 2.0) + v[1]` makes concrete: Julia lowers the
sum as one three-operand call, so the read of `v[1]` sits between the second
write and the sum, and both writes stay pinned in order. Wrapping exists
because mirroring the author's one-liners can produce a 150-column line;
100 is the width the docs use, and an option rather than a constant because
teams differ on it.

---

## 2026-09-05 — Integer powers beyond 2, 3 and -1: one `powi` helper by squaring

**Decision.** `x^2`, `x^3`, `x^-1` stay written out. Any other literal
integer exponent is `powi(x, n)`: one helper per base type (`powiF32`,
`powiI64` off the double) holding the ordinary power-by-squaring loop, with
the reciprocal taken at the end for a negative `n`. A negative power of an
integer is a `DomainError` in Julia and an error here.

**Why.** The exponent is a literal at every call, so an optimizing compiler
inlines the helper, unrolls the loop over the exponent's bits, folds the
`1.0` start away and drops the dead last squaring. Measured on clang 15 at
`-O2`, `powi(x, 13)` is five multiplies and no branch — instruction for
instruction the chain a person would write out — and `powi(x, -5)` is three
multiplies and a divide. So a helper per exponent (`pow_5`, `pow_13`, …),
which was built first the same day, bought nothing at `-O2` and cost a
family of near-identical functions; one `powi` is what a C programmer
expects to find. Below `-O2` the loop runs as a loop, which nobody
benchmarks. Julia's own `Float64^Int` is a compensated squaring — nearly
correctly rounded, at about three times the multiplications; here speed
wins the conflict, and results agree to within a few units in the last
place. `powi` is the established name: LLVM's intrinsic, GCC's builtin,
Rust's `f64::powi`.

---

## 2026-09-06 — Operations along a dimension: the dimension on the operation's name

**Decision.** `sum(A; dims=1)`, `prod`, `maximum` and `minimum` with `dims`,
`diff`, `cumsum` and `cumprod` become helpers whose name carries the
dimension directly after the operation, then the usual shape suffix:
`sum1_2x3`, `diff2_2x3`, `cumsum1_2x3`. A vector leaves the dimension off,
`diff_4`, `cumsum_4`, except a reduction with `dims` on a vector, `sum1_4`,
because `sum_4` is the sum to a scalar. The `dims` keyword is read at
transpile time from the `kwcall`'s tuple, whose construction is skipped.

**Why.** The suffix after the underscore has always described the inputs —
shapes, and types when not all double. The dimension worked along describes
the operation itself: `sum1` and `sum2` are different functions of the same
2×3, not the same function of different arguments, so the dimension belongs
on the name and not in the suffix. A vector has one dimension, and saying so
would only make `diff_4` read as "diff along the 4th". The keyword call is
the first `kwcall` the transpiler handles; its keyword tuple is a constant,
so the statements that build it are no more C than a type parameter is.

---

## 2026-09-06 — The transpiler is a module

(The project was renamed from newt to LegibleC the same day; the module, the
`LEGIBLEC_` macros and the paths below carry the new name.)

**Decision.** `src/transpile.jl` wraps everything in `module LegibleC`, exports
`transpile`, and ends with `using .LegibleC`, so `include("src/transpile.jl")`
followed by `transpile(…)` works exactly as before. The test harness imports
the dozen internals it uses by name.

**Why.** The transpiler defined some two hundred functions and constants in
`Main`, with ordinary names — `shape`, `index`, `value`, `literal`,
`dotted` — and a user's function of the same name either failed to define
("already has a value") or silently added a method to the transpiler's own.
The sandbox tripped over it twice in one day. A module makes the user's
namespace theirs. The trailing `using .LegibleC` keeps the one-line usage in the
README, and is the whole of what a user sees.

---

## 2026-09-06 — Logic is its own principle, numbered zero

**Decision.** `philosophy.md` now has four principles: 0 Logic, 1 Speed,
2 Craft, 3 Generality. Logic — the C does what the Julia does, in the same
order, with the same effects, agreeing to rounding — was previously a clause
inside Speed ("while matching the logical intent"). Nothing about the
philosophy changed; what changed is that the clause is now stated on its
own, first, and numbered zero to say that it isn't weighed against the
others. Earlier decision entries that say "first", "second" or "third
principle" mean Speed, Craft and Generality, as they did when written.

**Why.** The morning's work on inlining showed how often the logic clause is
the deciding one — evaluation order, effects, repeated operands — and each
time it had to be dug out of the middle of a paragraph about speed. A rule
that decides that often should be the first thing on the page.

---

## 2026-09-06 — Characters and strings where the languages agree

**Decision.** `Char` is C's `char`, and only ASCII: a non-ASCII character
literal is a transpile-time error. Comparisons, `c + 1`, `c - 'a'`, `Int(c)`,
`Char(n)`, the `ctype.h` classes (`isdigit`, `isalpha` for `isletter`,
`isupper`, …) and `toupper`/`tolower` come through as themselves. `String`
is `const char *`, read-only: literals, `strcmp` for `==`, `strlen` for
`ncodeunits`, a `utf8len` helper for `length`, `s[i - 1]` for `s[i]`, `%s`
in prints, and a string parameter may be returned. Nothing that builds a
string is accepted.

**Why.** Julia's `Char` is a code point and C's `char` a byte; `char32_t`
would represent it exactly, but no C library function takes one and no C
programmer writes it, so for the ASCII range where the two agree we use
`char`, and refuse what wouldn't fit rather than truncate it. Strings are
the opposite case: both languages hold UTF-8 bytes, so a literal, a
comparison, a byte count and a print carry any Unicode through unchanged,
and `length` counts characters with the one loop a C programmer writes for
it. What's left out — concatenation, `string(…)`, `@sprintf` — needs a
buffer and an owner, which is a design question on its own.

---

## 2026-09-06 — A package, unregistered

**Decision.** The repo is a Julia package: `Project.toml` with the name, a
UUID, version `0.1.0`, the dependencies and their compat bounds;
`src/LegibleC.jl` is the module file and includes `c.jl` and
`transpile.jl`. It is installed with `] dev` (or `] add` by URL) and used
with `using LegibleC`. The `include("src/transpile.jl")` entry and the
`using .LegibleC` after the module are gone. Registration in General waits.

**Why.** Precompilation — `using LegibleC` is cached instead of re-parsed
every session — and explicit, bounded dependencies, so the transpiler no
longer relies on the caller having loaded StaticArrays first. A version to
pin, `] test`, and a `using` line that doesn't break when a folder moves.
Registration is a one-time step later; nothing here depends on it.

---

## 2026-09-06 — Names of characters come from Julia's own table

**Decision.** A non-ASCII character in a name is spelled by the REPL's
`\name<tab>` completion table (`REPL.REPLCompletions.latex_symbols` and
`emoji_symbols`), after NFKD decomposition: `ħ` is `hbar`, `∂` is
`partial`, `̇` is `dot`, `🤠` is `facewithcowboyhat`. The hand-written
lists of Greek letters and combining marks are gone; the table has them. A
character with several names takes the shortest, and a short
`overrides` dictionary holds the four where that isn't the reader's word:
`ε` → `epsilon` (the table says `varepsilon`), `φ` → `phi`, `∇` → `nabla`
over `del`, `ð` → `eth` over `dh`, `👍` → `thumbsup` (the table says `+1`).
A table name is stripped to its letters and digits, underscores included,
since it stands for one indivisible character; if what's left doesn't
start with a letter, the `U` + hex fallback stays. On top of everything, the user's own
`spelling=Dict('ħ' => "hred")`, validated: single characters Julia allows
in a name, not ASCII letters, digits or `_`, spelled as C identifier text.
REPL becomes a dependency.

**Why.** The Generality tenet, in the form clarified today: where Julia
already holds the general thing, ask Julia rather than keep a copy. The
table is what the author typed to get the character, so the C says what
the Julia said, and it grows when Julia's does. "The shortest name" is a
rule that stays sensible if the table changes; the overrides are
only the cases where it doesn't, hardcoded so a change in the table can't
move them. NFKD before the table dissolves nearly every awkward name
(superscripts, fractions, font variants) into plain letters, which is why
the override list is four entries and not forty.

---

## 2026-09-06 — A returned tuple is the function's own struct

**Decision.** A function returning a tuple returns a struct named after
it, `step_t`, with fields named after the variables it returns, and the
return is the literal `return (step_t){x, xdot};`. The struct is decided
by the function alone: a caller that passes the value on into another
function or wraps it in its own return never changes it. Destructuring at
a call site reads the fields by name; a tuple kept whole keeps the struct;
a pass-through wrapper returns the callee's struct. A tuple parameter is
spread into one parameter per element, `t1`, `t2`, and a tuple built to be
passed goes as its elements, so no struct is ever invented for a call. The
structural `Tuple_F64_I64` with fields `a`, `b` remains where a tuple is
genuinely a value on its own — an expression returned, a struct field. A
temp holding a call's result is named after the function, `temp1_step`,
and that name composes into later temps like an operand's would.

**Why.** Output pointers are the older C idiom; returning a small struct by
value is equally C (`div_t`, `struct timeval`) and is what the Julia says:
one value, returned. The ABI returns it in registers or through a hidden
pointer, so nothing is copied that pointers wouldn't have written. With
fields named `a` and `b` the struct route was merely equal to pointers;
with the author's names it reads as what they wrote. Keeping the decision
local to the function is what makes it safe: nothing about `step`'s
signature can move because of code elsewhere. Spreading tuple parameters
is what a C programmer writes for an unnamed tuple, and it removes the
need to convert between struct types at call boundaries.

**Amended the same day, temp names.** Naming a call's temp after the
function was withdrawn within the hour: whether a call becomes "a function
in the file" is a fact about the transpiler, not the author's code, and it
made the reader guess. The rule is now: a temp is named after the
variables that went into it, as before; except that the temp holding a
call's result is named after the variable the callee returns, when it
returns one of the author's (`temp1_omega`), and, for an unnamed tuple
being unpacked, after the callee (`temp1_step`). A `tempsuffix` option
turns every suffix off. The numbering is what keeps the code correct; the
suffix is only ever for the reader, so a rule here can look odd but never
break anything.

---

## 2026-09-06 — The output is a folder

**Decision.** `transpile` writes an `out/` folder under `outpath`:
`<outfile>.c` with the user's functions, `helper.h` and `helper.c` with
everything generated that they need (a split into `mathhelper` and
`helper` was tried the same day and merged back: nearly every helper is
mathematics, and one pair of files is one thing to include). The header holds what its
helpers need — the standard includes, the constants, the typedefs — plus
prototypes of the out-of-line helpers and the `static inline` ones
themselves; the `.c` holds the out-of-line helpers, which lose `static`
so the functions file can call them. A function's own return struct sits
right above its prototype in the functions file. The helper files are
`helper`, not `math`, because `math.h` would shadow the standard header
under `-I out`.

**Why.** One file was right while the helpers were a few lines; with
solvers, factorizations and printing in it, the user's functions were the
last fifth of a long file. Small `static inline` helpers belong in a
header, where every translation unit gets the body, which is how a C
programmer ships them; the large ones belong in a `.c` compiled once.
The typedef sits with the
prototype because C needs the type before its first use and the prototype
is that use; together they are the function's interface, which is what a
later companion header will lift out.

---

## 2026-09-06 — Globals, struct types, and the calling scope

**Decision.** A global a function reads is pulled into the program like a
callee: `const double g = 9.81;` near the top of the functions file, and
`0.5 * g * (t * t)` where the literal used to be. `const` follows Julia's
binding; a plain global must be typed (`k::Float64 = 2.0`) to be read by a
function, since an untyped one has no type Julia compiles against either.
A variable can also be listed by keyword, `transpile(fall; g, μ)`, whether
or not anything reads it; its name is looked up in `scope` to decide
`const`, and a value with no binding there is a constant. `@transpile`
sets `scope` to the module the call is written in. `:name => value` and a
`GlobalRef` are the escape hatches for a name that is an option's or a
binding in another module. A struct type is a target on its own, with its
docstring as a Doxygen block. (Refusing REPL-defined functions was tried
the same day and withdrawn: see below.)

**Why.** "One call generates everything" means a function's globals are
part of everything, so they come along the way callees do, and a constant
should read as its name, not its digits. A value carries no name, so the
keyword carries it; the keyword form is a plain call, composes with a
splatted `NamedTuple`, and needs no macro — except that a function cannot
see its caller's scope, which is the one job a macro exists for, so
`@transpile` supplies `scope` and nothing else. `Main` is not special: the
lookup happens wherever the call was written.

**Withdrawn the same day, the file rule.** Refusing a method defined at the
REPL bought little: Julia records a file for methods only, so globals and
types slipped through anyway, and a REPL-defined function was already
handled honestly — a bare Doxygen block, no source lines, because there is
no source. What it cost was the most Julian workflow there is, defining a
function at the prompt to see what the transpiler makes of it. The guide
now says that regenerating the C needs the Julia in a file, and leaves it
at that.

---

## 2026-09-06 — Names carry their module path

**Decision.** A function, global or struct type from a module other than
the call's `scope` is named with its module path in front, joined with
`_`: `Physics_c`, `Earth_Orbit_a`, `Physics_speed`, relative to the scope
(`Orbit_a` from inside `Earth`; bare inside its own module); `Main` adds
nothing. Reading through an import doesn't change the name. Whatever
still collides gets `_`.

**Why.** Julia's modules are exactly the thing that lets two libraries
both name something `a`, and C's single namespace throws that away if the
module is dropped. `Earth.a` and `Moon.a` as `Earth_a` and `Moon_a` is
what a C programmer writes by hand (`gsl_const_…`, `M_PI`). Relative to
the scope, because that is how Julia itself resolves names where the call
is written, so `@transpile` from inside a module reads like the Julia
there. Obscure collisions can still occur; rather than refusing, the
existing `_` rule takes them, since the C stays correct either way.

---

## 2026-09-06 — The companion header

**Decision.** `out/<outfile>.h` holds what a caller needs and nothing else:
the standard type headers, the typedefs of the structs the functions use,
the program's globals as `extern` declarations, and each function's
prototype under its Doxygen block, with its own return struct right above
it. `<outfile>.c` includes that header and holds the definitions, the
globals with their values, and the includes its bodies need; it has no
prototypes of its own. The helper headers are not included by the user's
header unless a prototype mentions a struct the helpers own.

**Why.** A header is how C states an interface, and the Doxygen block is
documentation of the interface, so it moves there; a hand-written library
puts it in the header too, and Doxygen reads it from either. The `.c`
including its own header lets the compiler check every definition against
its declaration, which is the reason the idiom exists. Helpers are
implementation, so a caller never sees `helper.h` — the one exception is a
struct type the helpers defined that shows up in a prototype, where the
header must reach it.

---

## 2026-09-06 — Operator methods on the user's structs

**Decision.** A method of a Julia operator on a user struct,
`Base.:*(a::Quaternion, b::Quaternion)`, is transpiled like any user
function and named the way a helper is, since it is one:
`mul_Quaternion_Quaternion`, `mul_Quaternion_s`, `add_Quaternion`. `a * b * c`, which
Julia parses as one call resolved to its own fold, is the two binary calls.
A small struct value used once — a constructor, a call returning one — is
written where it is used; a struct built to be returned is the literal in
the `return`, one field per line when long. A multi-line Julia statement is
carried whole above its C.

**Why.** The function is Julia's but the method is the author's, and a
quaternion product is the ordinary way a Julian writes it; refusing it
would refuse the most natural struct code there is. C has no operator
overloading, so the method needs a name, and the operator's word is the
one a C programmer picks by hand. The rest follows the rules already in
place for scalars and tuples — inline what the author wrote inline, return
what is returned — extended to by-value structs, where they cost nothing.
The continuation-line placement was the last "known imprecision" in the
comment rules; a four-line initializer with its source underneath was too
strange to leave.

---

## 2026-09-06 — A struct with an array field, passed whole; `A + B + C` in place

**Decision.** A call that returns a struct with an array field is written
where it is used when the whole struct goes there — `return conj_Quat(q);`,
`mul_Quat_Quat(mul_Quat_Quat(q, p), adjoint_Quat(q))` — and gets a
variable when a field of it is read. A constructor of such a struct is
always built field by field. An n-ary array sum or difference, `a + b + c`,
accumulates in its destination — `add_3(a, b, out); add_3(out, c, out);` —
when every step has the destination's type, the helper's output may alias
an input, and no later operand is the destination; a matrix product's
output is `restrict`, so a chain of those keeps a temp per step.

**Why.** `Quat result = conj_Quat(q); return result;` is not what anyone
writes, and neither is a named variable for `q'` that is used once in the
next call. What kept these out was the rule that a struct with an array
field can't be a compound literal, which is about constructing one, not
about passing one along. `f(q).v`, reading an array field of a temporary,
is legal C11 that no one writes and some compilers warn about, so a field
read still gets a variable. The in-place accumulation is how a person
writes a three-term sum with such helpers; it also keeps the temps numbered
in the order they appear, which the temp-per-step form did not.

**Step comments** (same day, on request). An accumulating step reads
`temp4 += temp3`, the form every C reader knows, and never
`temp4 = temp4 + temp3`. An operator on structs gets a step comment spelled
in Julia — `temp2_q_v = q * temp1_v * q'`, `conj(q)` — the way a matrix
step reads `A \ b`, since `mul_Quat_Quat(adjoint_Quat(q))` is a helper's
name, not the mathematics. A struct built over several lines is a step of
its line too, `temp1_v = Quat(0.0, v)`, so the line's other steps get their
comments rather than counting as its only one.
The step text is a blend of textbook notation, Julia spelling and C names,
mixed by readability alone (`doc/comment.md`, *Steps*); it is never held
to one language. On a struct, `q'` keeps its prime in the comment rather
than becoming `qᴴ`: the superscripts mark arrays, whose transpose or adjoint the
transpiler performs and knows the meaning of, while on a struct `'` is
whatever the author's `adjoint` method does — for a quaternion the
conjugate, which a mathematician would write q̄ or q*, not qᴴ — so it is
spelled as written. Complex scalars, when they come, get their own rule.

---

## 2026-09-07 — A constant's comment comes with it; a name is never held in a temp

**Decision.** The trailing comment on a global's definition, `const c =
299_792_458.0  # speed of light, m/s`, is carried onto its C declaration
in both the header and the `.c`: `extern const double SI_c;  // speed of
light, m/s`. It is found by searching the module's file from where the
module begins (`Base.moduleloc`) for the first line defining the name,
since Julia keeps no location per binding; a global with no module or no
file gets none. And `SI.c`, a constant read through its module, is always
written where it is read — `SI_c * SI_c` for `SI.c^2` — never `temp1 =
SI_c` first.

**Why.** The comment is the one thing the caller wants to know about
`SI_c` and it was sitting in the source. The temp came from the rule that
an operand a square writes twice is not inlined, which is about
expressions with work in them; a name costs nothing to repeat, and
`temp1 * temp1` for `c²` was the one unreadable line in the relativity
demo.

---

## 2026-09-07 — One file, or a file per function; constants in the header

**Decision.** `split=true` puts every function in a file of its own,
named after it, listed or not, with its own header; every struct in a
header of its own; a function's return struct, `step_t`, with that
function. `<outfile>.h` holds the globals and includes every other header,
so a caller can still include one file; `<outfile>.c` holds the mutable
globals, and is written only when there are any. A file includes another's
header when its text names something placed there. Names that differ only
in case, `point` and `Point`, share one file, named in lowercase whatever
the spellings were. Without `split`, everything but the helpers is in
`<outfile>`, as before. Constants sit in the header as `static const`,
with their comments; only mutable globals are defined in the `.c` and
`extern` in the header. `transpile` returns the paths in file order when
there are several.

**Why.** The first design of the day placed each function by which
targets reached it, with a `common` file for what several reached. That
made a function's home depend on the target list: add one target that
calls `square` and `square` moves from `motion.c` to `common.c`, breaking
a caller's include for a reason nobody can see in the Julia. Generated
files should change only where the Julia changed, and a file per function
has that property by construction; it is also how musl and the BSD libcs
are laid out, so it reads as a known C style. The umbrella header keeps
the caller's side as simple as one file. Case collisions are merged
rather than refused because a case-insensitive file system would have
merged them anyway, and lowercase is the one spelling every collision
agrees on. A constant in the `.c` behind an `extern` is a load from
memory in every other file and can't fold into `v * v / (c * c)`;
`static const` in the header is a compile-time constant everywhere, and
it is where a C programmer puts one, next to its comment. A plain `const`
in a C header would be a duplicate symbol at link time, which is what the
`static` is for.
