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
