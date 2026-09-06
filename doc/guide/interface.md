# Interface

How to call the generated C: what each Julia type becomes on the C side.

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
