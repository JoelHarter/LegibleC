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
