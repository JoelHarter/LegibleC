# Target

What `transpile` accepts as a target.

`transpile` takes any number of targets, and one call makes one file.

| target | meaning |
|---|---|
| `energy` | a function with exactly one method, all argument types concrete |
| `(f, Float64, 3, Float64, 2, 3)` | `f` at these argument types; a type followed by integers is an array of that element type and size, static or a sized `Array` |
| `(poly, Int64, Int64)`, `(poly, Float64, Float64)` | the same function at two signatures; the C names get the types appended, `poly_I64_I64`, `poly_F64_F64` |
| a `Core.MethodInstance` | a specialization you already have |

Anything a target calls is transpiled too, and anything *that* calls, so
listing the entry points is enough.
