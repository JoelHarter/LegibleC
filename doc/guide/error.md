# Error

What a refusal means, and how to check a translation.

## When it refuses

Anything the transpiler doesn't understand is an `ArgumentError` at
transpile time, never C that compiles and does something else. Every refusal
leaves the same way: what it is and what to write instead, then the function,
the file and line, and the Julia line itself.

```
ArgumentError: a range kept in a variable has no C: ranges are supported as the
range of a `for` and as an index, `v[2:4]`. Write the range in the `for` itself
  in `total`, orbit.jl:41:  r = 1:n
```

The Julia has to be in working order first. A refusal is about Julia that runs
and that the transpiler can't yet write as C; it is not a check of the Julia.

The usual causes:

- a call it has no rule for — check [syntax.md](syntax.md); the fix is to
  write the operation another way, or reach the C function directly with
  `ccall`;
- an array whose size isn't in its type, or a sized `Array` target without
  its size;
- a non-ASCII character literal, since C's `char` holds one byte;
- a `dims` keyword that isn't a literal;
- a signed integer compared with or divided by an unsigned one of at least its
  width, where no C operator means what Julia means: convert one side.

## When the transpiler itself goes wrong

A mistake of the transpiler's own is a `LegibleC.Fault`, not an
`ArgumentError`. It says so, names the function and line it was working on,
and asks to be reported. The error underneath and its stack are kept in
`LegibleC.failure[]` for whoever looks into it.


## Checking a translation

The test suite's harness does what you'd do by hand: transpile, write a
`main` that calls each function on fixed inputs and prints the results,
compile, run, and compare with Julia. `test/check.jl` is that harness, and
`julia test/runtests.jl` runs everything through it. For your own code the
same pattern works: a `main.c` that `#include`s the generated file and
prints, against the Julia values.
