# Guide

Using LegibleC, start to finish: installing it, calling it, reading what it
writes, calling that from C, and steering it when it needs steering. What
Julia it accepts is listed in [syntax.md](syntax.md); how it works is the
rest of this folder.

## Install

```julia
] dev /path/to/LegibleC          # track a checkout
] add https://github.com/JoelHarter/LegibleC   # or install from GitHub
using LegibleC
```

`transpile` is the package's one exported name.

## A first function

```julia
using StaticArrays, LinearAlgebra

"Kinetic energy of a body of mass `m` moving at `v`."
energy(m::Float64, v::SVector{3,Float64}) = m * dot(v, v) / 2

transpile(energy; outfile="body", outpath=".")
```

That writes `body.c` and returns its path. The file holds, in order: the
`#include`s it needs, any `#define`s, `typedef struct`s for the structs and
tuples used, a prototype for every function, the generated helpers
(`static inline`, each with a two-line comment), and your functions, each
under a Doxygen block made from its docstring. It compiles on its own:

```
cc -std=c11 -O2 -Wall -Wextra -c body.c
```

Argument types must be concrete: `Float64`, `SVector{3,Float64}`,
`SMatrix{2,3,Float64,6}`, a `struct` of those. A function whose method has
an abstract or missing type is refused.

## Targets

`transpile` takes any number of targets, and one call makes one file.

| target | meaning |
|---|---|
| `energy` | a function with exactly one method, all argument types concrete |
| `(f, Float64, 3, Float64, 2, 3)` | `f` at these argument types; a type followed by integers is an array of that element type and size, static or a sized `Array` |
| `(poly, Int64, Int64)`, `(poly, Float64, Float64)` | the same function at two signatures; the C names get the types appended, `poly_I64_I64`, `poly_F64_F64` |
| a `Core.MethodInstance` | a specialization you already have |

Anything a target calls is transpiled too, and anything *that* calls, so
listing the entry points is enough.

## Options

| option | default | what it does |
|---|---|---|
| `outfile` | `"juliatranspiled"` | the file name; `.c` is added if missing |
| `outpath` | `pwd()` | the folder |
| `source` | `true` | copy each Julia line above its C as `// file.jl:12: …`; comments are always carried, this controls the code lines |
| `precise` | `false` | print floats with every digit (`%.17g`) instead of `%g` |
| `portable` | `false` | define `LEGIBLEC_PI` and `LEGIBLEC_E` at the top of the file instead of using `M_PI` and `M_E`, which are POSIX rather than ISO C |
| `width` | `100` | the longest line; a long scalar expression wraps at its loosest operators |
| `templimit` | `40` | the longest name a temporary may be given before its descriptive suffix is dropped |
| `staticarray` | `true` | every array is fixed-size; `false` is refused until dynamic arrays exist |
| `spelling` | `Dict()` | your own C spellings for characters in names — see [Names](#names) |

## Calling the C

**Scalars** are what they look like: `double`, `int64_t`, `bool`, `char`.
A scalar result is the return value.

**Arrays** are fixed-size C arrays, row-major: a 2×3 matrix is
`double A[2][3]`, and `A[i][j]` is Julia's `A[i+1, j+1]`. Inputs are
`const`, unless the function writes into them. A function whose Julia result
is an array returns `void` and takes a trailing `out` parameter, declared
`restrict`: pass a fresh array, never one of the inputs.

```c
double x[3] = {1.0, 0.0, 0.0}, v[3] = {0.0, 1.0, 0.0}, out[6];
orbit(x, v, 0.01, out);          /* out[0..2] is the new x, out[3..5] the new v */
```

**Structs.** An immutable `struct` is a C struct passed and returned by
value. A `mutable struct` is handled through a pointer, `Counter *c`, and
you own the object: create it, pass its address, read it back.

**Tuples** and multiple return values are a generated struct,
`Tuple_F64_I64`, with fields `a`, `b`, `c`, … returned by value.

**Strings** are `const char *` and characters are `char`. Printing goes to
`stdout` through `printf`.

Julia stores arrays column-major and C row-major. Inside the generated file
that is invisible; it matters only if you hand raw memory from one to the
other, which the transpiler doesn't do for you.

## Names

Every Julia name that reaches the C is converted first, so the output uses
the names you wrote:

| Julia | C | rule |
|---|---|---|
| `omega`, `x1` | the same | ASCII letters, digits and `_` are kept |
| `ω`, `Ω`, `ħ`, `∂`, `∞` | `omega`, `Omega`, `hbar`, `partial`, `infty` | the name you type after `\` to get the character — Julia's own completion table |
| `x₁`, `x²` | `x1`, `x2` | subscripts and superscripts become plain |
| `ẋ`, `x̂`, `x⃗`, `x′` | `xdot`, `xhat`, `xvec`, `xprime` | accents and primes are named and appended |
| `🤠` | `facewithcowboyhat` | emoji are in the table too |
| `bump!` | `bump` | the `!` is dropped |
| `long`, `printf` | `long_`, `printf_` | a C reserved word gets `_` |
| `omega` and `ω` together | `omega`, `omega_` | a collision gets `_` |

**Your own spellings.** When the built-in spelling isn't the word you want,
give yours:

```julia
transpile(field; spelling=Dict('ħ' => "hred", '∂' => "d", 'ε' => "eps"))
```

Each key is a single character that Julia allows in a name, other than an
ASCII letter, digit or `_`, which are always themselves. Each value is the
C text to use for it: letters, digits and `_`, nothing else. The dictionary
applies to every name in the call — variables, functions, types, fields —
and is consulted both for the character as written and for what it
decomposes into, so `'ε' => "eps"` also covers the lunate `ϵ`, and the
collision rule tells the two apart. Anything not in your dictionary is
spelled as above.

The full rules, including how a function at several signatures is named
and how temporaries get their names, are in [naming.md](naming.md).

## When it refuses

Anything the transpiler doesn't understand is an `ArgumentError` at
transpile time, naming the construct and the IR statement, never C that
compiles and does something else. The usual causes:

- a call it has no rule for — check [syntax.md](syntax.md); the fix is to
  write the operation another way, or reach the C function directly with
  `ccall`;
- an array whose size isn't in its type, or a sized `Array` target without
  its size;
- a non-ASCII character literal, since C's `char` holds one byte;
- a `dims` keyword that isn't a literal.

## Checking a translation

The test suite's harness does what you'd do by hand: transpile, write a
`main` that calls each function on fixed inputs and prints the results,
compile, run, and compare with Julia. `test/check.jl` is that harness, and
`julia test/runtests.jl` runs everything through it. For your own code the
same pattern works: a `main.c` that `#include`s the generated file and
prints, against the Julia values.

## What it won't do

Every size is known at transpile time; nothing is allocated. There are no
strings built at run time, no closures, no `try`, no growing arrays, and no
Julia runtime on the C side. Results agree with Julia to rounding, not bit
for bit. The open list is the repo's `todo.md`.
