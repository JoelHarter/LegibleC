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
  the globals as `extern`, and each function's prototype under a Doxygen
  block made from its docstring, with its own return struct right above it
  when it returns a tuple. Include this from your C.
- `body.c` — the functions themselves, the globals with their values, and
  the `#include`s they need. It includes `body.h`.
- `helper.h` — everything generated that your functions need: small
  helpers as `static inline` functions, each with a two-line comment, and
  prototypes for the larger ones.
- `helper.c` — the larger helpers: solvers, factorizations, array printing.

It compiles as a unit:

```
cc -std=c11 -O2 -Wall -Wextra -c out/*.c
```

Argument types must be concrete: `Float64`, `SVector{3,Float64}`,
`SMatrix{2,3,Float64,6}`, a `struct` of those. A function whose method has
an abstract or missing type is refused.
