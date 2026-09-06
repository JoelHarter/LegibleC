# Error

What a refusal means, and how to check a translation.

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
