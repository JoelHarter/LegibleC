# Design

How the transpiler works, end to end, and where each part lives.

## The idea

Julia already does the hard part. By the time a method has been inferred,
every value has a concrete type, every array a fixed size, every call a
resolved target, and the code is a flat list of simple statements in SSA
form. The transpiler asks Julia for that — the *unoptimized* typed IR, so
local names survive and arithmetic is still `+` rather than an intrinsic —
and walks it once, statement by statement, writing C.

Nothing is guessed. A type the transpiler doesn't know, a call it has no
rule for, a shape that doesn't line up: each is an `ArgumentError` at
transpile time, never C that compiles and does the wrong thing.

## The pipeline

1. **Targets to instances** (`src/transpile.jl`). Each target — a function
   with one concrete method, or a function with argument types spelled out
   — is resolved to a `MethodInstance`. A regular `Array` argument gets its
   size from the call and is carried as a shaped stand-in, so it goes
   through exactly the same rules as a static array.
2. **Names** (`src/name.jl`). Every Julia name that will reach the C is
   converted first: Unicode to ASCII, reserved words and collisions given
   `_`, several signatures of one function told apart by their types.
3. **One function at a time** (`src/c.jl`). A `Scope` holds the state for
   one function: what each IR value is called in C, which slots are arrays
   and of what size, which statements are consumed by others. A prepass
   (`analyze!`) finds the loops and conditionals (`src/flow.jl`), the
   values that will be rendered inline, and the bookkeeping statements that
   have no C. Then every statement is emitted: scalar calls become
   expressions or temps, array operations become helper calls, control flow
   is emitted as the construct it came from.
4. **Helpers on demand** (`src/helper.jl`). The first time a computation is
   needed at some argument types — `add` of two 2×2 matrices, `solve` of a
   4×4 against a vector — its C function is generated and remembered by
   name: `static inline` for the small ones, `static` for the solvers.
   Moving data is not a computation and gets no helper: a copy, a block
   construction, a slice is written inline as `memcpy`, `memset`, or a loop
   (`src/move.jl`). A helper can ask for other helpers (`det_4x4` needs `det_3x3`).
   Each carries a one-line English comment (`src/prose.jl`).
5. **Callees on demand**. A call to another user function registers that
   function's instance; the loop continues until nothing new is needed.
6. **The file**. Includes, then struct typedefs, then prototypes for
   `ccall`ed symbols, then a prototype for every function, then the helpers
   in dependency order, then the functions. Comments and source lines from
   the Julia (`src/source.jl`) are placed as the statements are emitted.

## The source files

| file | holds |
|---|---|
| `transpile.jl` | the `transpile` API, target resolution, the `Program` that spans one output file, the file writer |
| `c.jl` | the IR walk: `Scope`, `analyze!`, `statement!`, values and temps, constructions, broadcasts, array calls, solves, slices, user calls, `ccall`, structs and tuples |
| `flow.jl` | recognising `if`/`while`/`for`/`&&`/`||`/`?:` in the lowered jumps, and rendering conditions inline |
| `helper.jl` | the helper generators: the axis model (`access`, `contraction`), elementwise and pointwise loops, block placement, `det`, `pivot`/`lu`/`solve`/`inv`, Cholesky, `pinv`, reductions, slices; helper names and parameter names |
| `prose.jl` | the English comment on each helper |
| `name.jl` | Julia identifiers to C identifiers; function-name mangling |
| `reserved.jl` | the names the output must never take |
| `type.jl` | scalar types, the shaped stand-in for regular arrays, the transposed tag, the axis model's `axis`/`extent`, structs and tuples, C declarations |
| `source.jl` | reading the Julia file for comments, docstrings, and code lines |
| `io.jl` | printing (`print`, `println`, `@printf`) and, later, files — `printf` as a C programmer writes it, and the one `printarray` helper |
| `move.jl` | data movement written inline: copies, block construction, slices and slice assignment, `zeros`/`fill`/identity — `memcpy`, `memset`, or a loop |

## Shapes of things in C

- A scalar is itself. A returned scalar is a return value.
- An array is a fixed-size row-major C array, passed as an array parameter
  (`const double A[2][3]`). An array result comes out through a trailing
  `restrict` parameter named `out`, since C can't return arrays.
- A transposed array is the same storage; only the transpiler knows.
- A struct is a `typedef struct`, by value; a mutable struct is a pointer.
- A tuple is a struct with fields `a`, `b`, `c`, …
- `Nothing` is `void`.

Everything lives on the stack in arrays of the static size. There is no
allocation anywhere in the output.

## Errors

A Julia program that throws an exception nobody catches prints it and
stops. The C does the same where it can happen inside a helper — a singular
matrix in an LU solve, a non-positive-definite one in Cholesky — with
`fprintf(stderr, …)` and `abort()`. Julia checks the transpiler doesn't
reproduce (`Int64(2.5)`, `div(1, 0)`) are listed in `scalar.md`.

## Tests

`test/runtests.jl` runs every test. Each transpiles a few functions, builds
a C program that calls them on fixed inputs, compiles it with warnings as
errors, runs it, and compares what C printed with what Julia computes for
the same calls. The machinery is `test/check.jl`; adding a case is one line.

## Adding a rule

Find where the kind of thing is handled — a scalar call in `render`, an
array operation in `arraycall!`, a construction in `construct!` — and add
the Julia function there; if it needs a C helper, write one generator in
`helper.jl` for the general case (any dimension, any element type) and let
`helpername` name it. Add a case to the matching test file. If the choice
took real thought, record it in `dev/decision.md`.
