# Call

Calls from one transpiled function to another, and calls from Julia into C.

## Between transpiled functions

A call to one of the user's own functions is a call in C. The callee is
resolved at the argument types the call has, exactly as `transpile` resolves
its targets, and if it wasn't among the targets it's transpiled anyway —
brought in on demand, and it may bring in others. Its C name is its Julia
name, with the argument types appended only if that name is already taken by
another signature. Every function gets a prototype at the top of the file, so
order never matters and recursion just works.

```c
void quad(const double v[3], double out[restrict 3]) {
    double temp1_v[3];
    twice(v, temp1_v);
    twice(temp1_v, out);
}
```

The shapes follow from the rest: a scalar result is a return value, an
array result comes through the trailing `out` parameter, a struct or tuple
result is returned by value. A call made for its effect, or whose result
goes unused, is a statement (`twice(v, temp1_v);`); `return nothing` and a
`Nothing` result are `void`.

Not yet: passing an eagerly transposed matrix straight to a call (`g(A')` —
store it first), keyword and default arguments (untested), and calling
functions from packages other than the ones the transpiler understands.

## `ccall`

`ccall(:cbrt, Float64, (Float64,), x)`, and the `@ccall cbrt(x::Cdouble)::Cdouble`
form, become the call itself: `cbrt(x)`. Julia that calls C becomes C that
calls C. So that the output stands alone, the symbol gets either the header
it comes from (`math.h`, `string.h`, `stdlib.h`, `stdio.h`, when the name is
one of theirs) or a prototype built from the `ccall`'s types:

```c
double mysum(const double *, int32_t);
```

A `Ptr{T}` argument holding an array passes the array (a vector as itself, a
matrix as `&A[0][0]`). Whether that pointer is `const` follows Julia's own
rule: an immutable static array is passed read-only; a mutable one may be
written through, which also costs our own parameter its `const`. Two calls
that disagree leave the prototype with the weaker promise. `Ref{T}` passes
`&x`.

Not yet: a function pointer as the target, `Cstring`, and pointer results.
