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
 * @param[out] result  The value the Julia function returns.
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

## Placement details

- A line's comment goes ahead of the first C statement produced by that line.
  A line that produces no C (a pure comment, or code that folded away) is
  emitted when the next line that does produce C is reached, so relative order
  is preserved.
- A Julia expression spanning several lines produces its C at its first line;
  the continuation lines are emitted after that C, when the next statement
  arrives. Acceptable, and noted as a known imprecision.
- Leading whitespace is dropped; the C's own indentation applies.
- Nothing is emitted for generated helpers — they have no Julia source.
- A function whose source can't be found (defined at the REPL, or via `-e`)
  gets no annotations at all, silently.

## Implementation

`src/source.jl`: `Source` (the file and the span of the definition, found by
parsing from the signature's line), `leading`, `body`, `statementlines`.
Line numbers per IR statement come from the lowered `CodeInfo`
(`Base.uncompressed_ast`), which matches the unoptimized typed IR statement for
statement; the typed IR carries no line table of its own. `annotate!` in
`src/c.jl` drives it.
