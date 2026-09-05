# newt

A Julia-to-C transpiler for numeric code. You write Julia — static arrays,
structs, tuples, loops, linear algebra — and get C that a careful C
programmer could have written by hand: fixed-size arrays on the stack,
`static` helpers named for what they do, comments carried across, and no
allocation anywhere.

```julia
using StaticArrays, LinearAlgebra

"Kinetic energy of a body of mass `m` moving at `v`."
energy(m::Float64, v::SVector{3,Float64}) = m * dot(v, v) / 2

transpile(energy; outfile="body")
```

```c
/// 3-vector dot product
static double dot_3(const double a[3], const double b[3]) {
    double sum = 0.0;
    for (int k = 0; k < 3; k++) {
        sum += a[k] * b[k];
    }
    return sum;
}

/**
 * Kinetic energy of a body of mass `m` moving at `v`.
 *
 * Julia signature: energy(m::Float64, v::SVector{3, Float64}), body.jl:4
 * @param[in]  m    scalar
 * @param[in]  v    3-vector
 */
double energy(double m, const double v[3]) {
    return m * dot_3(v, v) / 2;
}
```

## Using it

```julia
include("src/transpile.jl")
transpile(f, g, (h, Float64, 3, Float64, 2, 3); outfile="name", outpath=dir)
```

A target is a function with one concrete method, or a tuple of a function
and its argument types, where a type followed by integers is an array of
that element type and size. One `.c` file comes out with prototypes, the
helpers it needs, and the functions; anything a listed function calls is
transpiled too. Options: `outfile`, `outpath`, `source` (copy each Julia
line into the C as a comment, on by default), `precise` (print every digit
of a floating value), `portable` (own `NEWT_PI` macros instead of `M_PI`),
`width` (the longest C line, 100), `templimit`, `staticarray`.

Sizes are static: arrays are `StaticArrays` types, or `Array`s given a size
in the call. Every generated function is C11 and compiles clean under
`-Wall -Wextra -Werror`.

## What works

[doc/syntax.md](doc/syntax.md) is the one-page list of every piece of Julia
the transpiler accepts. In short: scalar arithmetic and `math.h`, control
flow, static arrays of any dimension with `+ - * / \` and broadcasting,
transposes, block construction, `det`, `inv`, `pinv`, solves through
Cramer's rule or pivoted LU or Cholesky, reductions and slices, structs
and tuples, calls between functions and into C via `ccall`, printing, and
comments.
Anything not on the list is an error at transpile time, never silently
wrong C.

## Documentation

- [doc/philosophy.md](doc/philosophy.md) — the three principles behind
  every decision, and which wins when they conflict.
- [doc/](doc/) — how the transpiler works, one topic per file, starting
  with `design.md`; the folder's README gives a reading order.
- [doc/dev/](doc/dev/) — the decision log and the survey of what could
  still map between Julia and C.
- [todo.md](todo.md) — what's open.

## Tests

```
julia test/runtests.jl
```

Every test transpiles a few Julia functions, builds a C program that calls
them on fixed inputs, and compares what C prints with what Julia computes
for the same calls.
