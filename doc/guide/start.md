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

- `body.c` — your functions: the `#include`s, any `#define`s, `typedef
  struct`s for the structs used, each function's prototype (with its own
  return struct right above it, when it returns a tuple), and the functions
  themselves, each under a Doxygen block made from its docstring.
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
