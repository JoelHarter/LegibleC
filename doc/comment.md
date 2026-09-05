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
 * Julia: fancy(a::Float64, b::Float64), probe.jl:8
 * @param[in]  a
 * @param[in]  b
 */
double fancy(double a, double b) {
```

Doxygen reads the *signature* from the C declaration itself, so that's
always the C one. The generated tail adds the facts the declaration doesn't
carry: which Julia method this is (its name, argument types, and location —
so a mangled `poly_I64_I64` says it's `poly` at `(Int64, Int64)`), and, for
a function whose Julia result is an array, that the trailing parameter is an
output holding the Julia return value:

```c
 * @param[in]  A
 * @param[in]  B
 * @param[out] out  The value the Julia function returns.
```

No descriptions are invented for parameters: the transpiler knows their
types, not their meaning. If the docstring describes them in prose, that
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
| blank | nothing |
| only a comment (`# …`, or inside `#= =#`) | the comment |
| code, with or without a trailing comment | the whole line, as `file:line: code` — see below |
| only closing brackets or `end`, e.g. `end`, `)`, `])` | its trailing comment, if any; not the code |
| the signature line of a `function … end` | its trailing comment, if any; not the code |
| the whole line of a short-form `f(x) = …` | the whole line — it *is* the body |

A `#` inside a string literal isn't a comment.

**Code lines** are controlled by the `source` option of `transpile`, on by
default. When on, each line of code appears verbatim — trailing comment
included — prefixed with the file's name and the line number:

```c
    // first the sum
    // probe.jl:10: s = a + b      # trailing on code
    s = a + b;
```

When off, only the comments are carried: the trailing comment of a code line
still appears, on its own.

**The rule in one sentence:** every comment before or inside the function is
copied over, and most of the code is too, all as comments; the lines whose
code isn't worth copying (brackets, `end`, a long-form signature) are treated
like blank lines *except* that a comment on the end of them still counts.

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

## Placement details

- A line's comment goes ahead of the first C statement produced by that line.
  A line that produces no C (a pure comment, or code that folded away) is
  emitted when the next line that does produce C is reached, so relative order
  is preserved.
- A Julia expression spanning several lines produces its C at its first line;
  the continuation lines are emitted after that C, when the next statement
  arrives. Acceptable, and noted as a known imprecision.
- Leading whitespace is dropped; the C's own indentation applies.
- Generated helpers have no Julia source; they get the `///` line above and nothing else.
- A function whose source can't be found (defined at the REPL, or via `-e`)
  gets no annotations at all, silently.

## Implementation

`src/source.jl`: `Source` (the file and the span of the definition, found by
parsing from the signature's line), `leading`, `body`, `statementlines`.
Line numbers per IR statement come from the lowered `CodeInfo`
(`Base.uncompressed_ast`), which matches the unoptimized typed IR statement for
statement; the typed IR carries no line table of its own. `annotate!` in
`src/c.jl` drives it.
