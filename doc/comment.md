# Comment

How the Julia source's comments — and, optionally, its code — are carried into
the C. Everything here becomes a `//` comment in the output; the C itself is
unchanged by it.

## Above the function

Starting from the line just above the Julia definition, walk upward and
collect until the first line of code, the first blank line, or the top of the
file:

- **Comment lines** (`# …`) — carried over as written.
- **Block comments** (`#= … =#`) — every line inside, delimiters dropped.
- **A docstring** (`""" … """`, or a one-line `"…"`) — every line inside,
  delimiters dropped, blank lines kept so the docstring keeps its shape.
  Anything inside a docstring is text, even a `#`. Emitted as a Doxygen
  block; see below.

These go directly above the C definition (not the prototype), in their
original order. Plain comments become `//` lines. The docstring's text goes
into a **Doxygen block** — `/** … */` — exactly as written, followed by a
generated tail saying what the C declaration can't:

```julia
"""
    fancy(a, b)

Adds, then scales.
"""
function fancy(a::Float64, b::Float64)
```
```c
/**
 * fancy(a, b)
 *
 * Adds, then scales.
 *
 * Julia signature: fancy(a::Float64, b::Float64) @probe.jl:8
 * @param[in]  a    scalar
 * @param[in]  b    scalar
 */
double fancy(double a, double b) {
```

Doxygen reads the *signature* from the C declaration itself, so that's
always the C one. The generated tail adds the facts the declaration doesn't
carry: which Julia method this is (its name, argument types, and location —
so a mangled `poly_I64_I64` says it's `poly` at `(Int64, Int64)`), and what
each parameter is in the vocabulary the helper comments use — *scalar*,
*3-vector*, *3×3-matrix*. An array the function writes into (an `MVector`
assigned through `v[i] = …`) is tagged `[in,out]`; the trailing parameter
that carries an array result is `[out]`, the return value:

```c
 * @param[in]     A    3×3-matrix
 * @param[in,out] v    3-vector
 * @param[out]    out  3-vector, the return value
```

The C signature already says `double[3]`; the tail says *3-vector*, which
is what a reader coming from the math wants. That `out` is `restrict` is in
the signature too, and means what it says in C: the caller passes a fresh
array. Nothing else is invented for a parameter: the transpiler knows its
type, not its meaning. If the docstring describes them in prose, that
prose is right there above. Every function gets the block, docstring or not;
without a docstring it's just the tail. Section-header comments above a
function (`# --- division ---`) stay `//`, so Doxygen doesn't mistake them
for documentation.

A blank line between a comment and the definition means the comment isn't
attached, and it's left behind.

## Inside the body

Every line from the signature through the closing `end` is looked at, in order,
and placed in the C just ahead of the statement that does that line's work.
Comments that sit after the last statement (before `end`) come at the end of
the body.

| the line is… | what's carried over |
|---|---|
| blank | nothing — see *Spacing* below |
| only a comment (`# …`) | the comment, as `// …` |
| a `#= … =#` block | one `/* … */` block, its lines' indentation kept |
| code, with or without a trailing comment | the whole line, as `@file:line: code` — see below |
| only closing brackets or `end`, e.g. `end`, `)`, `])` | its trailing comment, if any; not the code |
| the signature line of a `function … end` | its trailing comment, if any; not the code |
| the whole line of a short-form `f(x) = …` | what follows the `=` — the signature is in the Doxygen block already |

A `#` inside a string literal isn't a comment.

**Code lines** are controlled by the `source` option of `transpile`, on by
default. When on, each line of code appears verbatim — trailing comment
included — prefixed with `@`, the file's name and the line number:

```c
    // first the sum
    // @probe.jl:10: s = a + b      # trailing on code
    s = a + b;
```

When off, only the comments are carried: the trailing comment of a code line
still appears, on its own.

**The rule in one sentence:** every comment before or inside the function is
copied over, and most of the code is too, all as comments; the lines whose
code isn't worth copying (brackets, `end`, a long-form signature) are treated
like blank lines *except* that a comment on the end of them still counts.

## Spacing

Julia's blank lines are not copied. Instead every Julia statement gets a
blank line before its C, comments included, so that a statement that became
several C lines reads as a paragraph of its own; there is none right after
an opening brace or against a closing one. Copying the author's spacing was
considered and set aside: a Julia function with no blank lines still comes
out dense, because the density comes from each line expanding, not from
spacing lost — so the break is put where the expansion is. The rule holds
with `source=false` too; the blank is then the only thing marking where one
statement's C ends and the next begins.

```c
    // @demo.jl:9: r = norm(x)
    double r = norm_3(x_);

    // @demo.jl:10: a = -x / r^3
    double temp1_r = r * r * r;
    double a[3];
    div_3_s(x_, -temp1_r, a);
```

## On the helpers

Every generated helper gets a `///` comment of two lines: what it does the
way a person would say it, then its defining equation in the parameter
names — operators where an operator exists (`+`, `.+`, `*`, `\`, `/`),
`ᵀ` for a transpose, and `returns` for a helper that returns a scalar:

```c
/// 2×3 * 3×3 matrix multiplication
/// out = A * B
/// 3-vector + transposed 2-vector broadcast addition
/// out = a .+ bᵀ
/// 3-vector dot product
/// returns a ⋅ b
/// 4×4-matrix \ 4-vector solve by LU with partial pivoting
/// out = A \ b
/// LU decomposition of a 4×4-matrix with partial pivoting
/// L * U = A[p, :]
```

The words are deliberately ones the transpiler itself never uses. To it
there are only arrays of any dimension and one kind of pointwise operation;
a reader expects "scalar", "vector", "matrix" and "4×3×2-array", and
"element-wise" when the sizes match versus "broadcast" when they don't or a
scalar is involved. Sizes are written with `×`, `transposed` goes in front,
and the element type is named exactly when the helper's name carries types
(`Float64 3×2-matrix * Float32 3×2-matrix element-wise multiplication`).
Two plain operands of one kind share the noun (`2×3 * 3×3 matrix
multiplication`); identical operands are written once (`2×2-matrix
addition`). Known functions get their English name — `exponential`,
`square root`, `hyperbolic tangent` — and anything else is called by its
Julia name. Implementation: `src/prose.jl`.

A helper whose parameters aren't all inputs and `out` gets `@param` lines
under the brief, for exactly the parameters whose meaning isn't in their
name — the work array and permutation of an LU, the position of a slice:

```c
/// partial pivot of a 4×4-matrix at column k
/// @param LU  the work array being decomposed; rows k and best are swapped
/// @param p   the row permutation so far, swapped alongside
/// @param k   the column, 0-based
```

That is the whole of the Doxygen on helpers. They are `static`, and a full
block per helper would mostly restate a signature the name already
transcribes; the user's functions, which are the C interface, get the full
`/** … */` block described above.

## Steps

When one Julia line becomes several C operations, a reader has to follow
the temps to see what happened. So each operation of such a line gets a
*step* comment: two spaces after the statement when the step is one
statement, on the line above when it is a loop or several. The trailing ones
are not aligned with each other: with declarations sitting between the
steps, alignment would only look like it had failed.

```c
// @f.jl:12: f(A, b, c, D) = (A .+ b) \ c + D
double temp1[3][3];
addP_3x3_3(A, b, temp1);  // temp1 = A .+ b
double temp2_c[3];
solve_3x3_3(temp1, c, temp2_c);  // temp2_c = temp1 \ c
add_3(temp2_c, D, out);  // out = temp2_c + D
```

The text is the step as a textbook would write it, in the spelling the
helper comments use — `A * Bᵀ` (`B†` when the elements aren't real, since `'` is then the adjoint; the helper's *name* keeps `T` either way, `mul_2x3_T2x3`), `a ⋅ b`, `a × b`, `A \ b`, `A⁻¹`, `det(A)`,
`norm(a)`, `.+` and friends for a broadcast, `[C A; B C]` for a block
construction, `A[2, :]` for a slice, `.= 0` for zeroing — with the C names
of the operands, temps included. That's what lets the comments chain: the
name a step produces is the name the next step consumes.

A Julia line that became a single operation gets no step comment: its
source line is right above it and says the same thing. A step is an
operation on arrays — a helper call, a data movement, a scalar-returning
helper such as `dot` or `det`; plain scalar arithmetic is its own comment.
The steps stay on when `source=false`, since they are then the only Julia
in sight.

Implementation: `step!` and `steps!` in `src/c.jl`; every array emitter
records its step.

## Placement details

- A line's comment goes ahead of the first C statement produced by that line.
  A line that produces no C (a pure comment, or code that folded away) is
  emitted when the next line that does produce C is reached, so relative order
  is preserved.
- A Julia statement spanning several lines — brackets still open, or an
  operator waiting for its right side, at the end of a line — is one block
  comment above its C, `/* @file:14-18:` in front, the lines inside with
  their own indentation, `*/` on its own line.
- Leading whitespace is dropped; the C's own indentation applies.
- Generated helpers have no Julia source; they get the `///` line above and nothing else.
- A function whose source can't be found (defined at the REPL, or via `-e`)
  gets no annotations at all, silently; the blank lines between statements
  are still placed, since the line numbers come from the IR, not the file.

## Implementation

`src/source.jl`: `Source` (the file and the span of the definition, found by
parsing from the signature's line), `leading`, `body`, `statementlines`.
Line numbers per IR statement come from the lowered `CodeInfo`
(`Base.uncompressed_ast`), which matches the unoptimized typed IR statement for
statement; the typed IR carries no line table of its own. `annotate!` in
`src/c.jl` drives it.
