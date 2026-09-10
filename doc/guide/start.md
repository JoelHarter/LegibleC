# Start

Installing LegibleC and transpiling a first function.

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

That writes an `out/` folder next to where you ran it, and returns the path
of `out/body.c`. The folder holds:

- `body.h` — what a caller needs: `typedef struct`s for the structs used,
  the constants as `static const` with their values and the comments from
  their definitions, any other global as `extern`, and each function's
  prototype under a Doxygen block made from its docstring, with its own
  return struct right above it when it returns a tuple. Include this from
  your C.
- `body.c` — the functions themselves, the mutable globals with their
  values, and the `#include`s they need. It includes `body.h`.
- `helper.h` — everything generated that your functions need: small
  helpers as `static inline` functions, each with a two-line comment, and
  prototypes for the larger ones.
- `helper.c` — the larger helpers: solvers, factorizations, array printing;
  absent when there are none.

It compiles as a unit, and this is the setting it is written for:

```
cc -std=c11 -O2 -ffast-math -fno-finite-math-only -ffp-contract=fast -march=native -Wall -Wextra -c out/*.c
```

Every fast-math shortcut is welcome — reassociation, reciprocals, no
`errno`, no traps — since only rounding changes; the one left out,
`-ffinite-math-only`, would let the compiler assume NaN and Inf never
happen, and a singular matrix must still come out as one. `-std=c11` on
its own forbids fusing a multiply and an add, so `-ffp-contract=fast` puts
FMA back, and `-march=native` gives the instruction on x86, where it isn't
baseline. Leave `-march=native` off for a build that must run on other
machines. The test suite compiles with these flags. When linking, add
`-lm` for the math library, which Linux doesn't link on its own.

Argument types must be concrete: `Float64`, `SVector{3,Float64}`,
`SMatrix{2,3,Float64,6}`, a `struct` of those. A function whose method has
an abstract or missing type is refused.
