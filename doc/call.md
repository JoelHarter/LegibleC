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
    double temp1[3];
    twice(v, temp1);
    twice(temp1, out);
}
```

The shapes follow from the rest: a scalar result is a return value, an
array result comes through the trailing `out` parameter, a struct or tuple
result is returned by value. A call made for its effect, or whose result
goes unused, is a statement (`twice(v, temp1);`); `return nothing` and a
`Nothing` result are `void`.

Not yet: passing an eagerly transposed matrix straight to a call (`g(A')` —
store it first), keyword and default arguments (untested), and calling
functions from packages other than the ones the transpiler understands.

## A function as a value

In Julia every function has a type of its own, so a function handed to
another is known when the code is transpiled: Julia compiles a `newton` for
that `f`, and so does the C, which calls `f` by name. There is no function
pointer anywhere in the output.

```julia
root(a, x0) = newton(x -> x^2 - a, x -> 2x, x0)
```

```c
double root(double a, double x0) {
    return newton_fun1_fun2(a, x0);
}

double newton_fun1_fun2(double f_a, double x) {
    for (int64_t i = 1; i <= 20; i++) {
        x -= fun1(f_a, x) / fun2(x);
    }
    return x;
}

double fun1(double a, double x) {
    return x * x - a;
}
```

One rule covers every case: **a function value is what it captured, and
calling it is a call to the C function its body became, the captures first.**

- A named function, and a lambda that uses nothing from outside, captured
  nothing. They take no room: the parameter is gone from the C, and the
  function compiled for them says which in its name, `newton_f_df`,
  `twice_sin`.
- A lambda that captured `a` and `b` is `a` and `b`. Handed on, it is those
  values, one C argument each, `f_a`, `f_b`. Made and used in one function,
  `g = y -> a * y + 1`, it is no C at all: `g(x)` is `g(a, x)`, the captures
  written as the variables they were captured from.
- A function returned from a function is the one case that must be one value,
  so it is a struct of its captures, `fun1_t`, and calling it spreads the
  struct again: `fun1(h.a, h.b, 3.0)`.
- A function that captured a function holds that one's captures in place.
- A struct of the author's with a method of its own, `(p::Poly)(x) = …`, is
  called as `Poly_call(p, x)`; a second such method says its types,
  `Poly_call_F64_F64`.

This is sound because of what Julia itself guarantees: a captured variable
that is assigned again after the function is made is held in a `Core.Box`,
which has no type, and that is refused. So a capture that reaches C keeps its
value for as long as the function that captured it lives. The one place the
C could still go wrong is a function made inside a loop, whose captures move
on with the next pass; there it must be used straight away, before any
branch, or it is refused by line.

Julia doesn't compile a function anew for a function it only passes on,
`thru(g, x) = twice(g, x)`: there `g` is any `Function` to it. The transpiler
asks for the instance at exactly the function's type (`exact`), so the chain
is known all the way down.

### Handed to one of Julia's own

`sum(abs, v)`, `map(x -> x^2, v)`, `any(x -> x > t, v)`, `count(isodd, v)`,
`prod`, `all`, `maximum`, `minimum`, `foreach`, a `do` block, a generator
`sum(1 / k^2 for k in 1:n)`, a comprehension `[a * x for x in v]`, and
`g.(v)` with a function of the author's: each is the loop it stands for,
written where the call is.

```c
double s = 0.0;                       // s = sum(x -> x^2, v)
for (int64_t i = 0; i < 4; i++) {
    s += v[i] * v[i];
}
```

A lambda of one expression is that expression, with the element in place of
its parameter. Anything longer, a `do` block of several lines, is a function
called in the loop. A range goes by the lambda's own parameter name,
`for (int64_t k = 1; k <= n; k++)`. The loop works in the variable the value
is stored in when it can, and in a temp when the loop reads that variable or
the value is part of a larger expression. `any` and `all` stop at the first
element that decides them, as Julia does. `maximum` and `minimum` start from
the infinity that loses to everything, so a NaN comes out as Julia's does.

What is gone over is an array of a known size or a range of integers. A
comprehension over a range needs the range written in numbers, `1:4`, since
its length is the array's size.

### Not yet

- A lambda that writes into an array it captured. It is refused; write the
  loop, or pass the array as an argument.
- A function kept among other values: in a struct's field, a tuple, an
  array. Which function runs would be decided while the program runs.
- A captured variable that is assigned again (Julia's `Core.Box`).
- Keywords, `sum(abs, v; init=0.0)`; `mapreduce`, `filter`, `findfirst`.
- A struct called as a function as a target of `transpile` itself.

Implementation: `src/lambda.jl` (the value, its name, the call) and
`src/fold.jl` (the loops).

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
