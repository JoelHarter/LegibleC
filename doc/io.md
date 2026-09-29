# IO

Printing to the screen now; reading and writing files later. Everything the
transpiler does with streams lives in `src/io.jl`, apart from the rest of the
emitter, because it's its own kind of thing: the C is `printf` and friends
rather than arithmetic.

The guiding idea is Craft (`philosophy.md`): the C should be what a C
programmer writes to print things, not a rendering of what Julia's REPL
shows. So `print(x)` is `printf("%g", x)`, not a reproduction of Julia's
`3.0`; an array is a block of aligned numbers, not `[1.0 3.0; 2.0 4.0]`; and
there is exactly one helper.

## `print` and `println`

`print` and `println` become one `printf` per run of strings and scalars:

```c
printf("x = %g, n = %lld, b = %d\n", x, (long long)n, b);
```

- A floating value is `%g`. With the `precise` option of `transpile`, it's
  `%.17g` (`%.9g` for `Float32`), every digit that reads back exactly.
- An integer is `%lld` with a cast (`%llu` unsigned), the portable spelling
  for `int64_t`. A boolean is `%d`.
- A stream given first goes where Julia sends it: `println(stderr, "bad: ",
  x)` is `fprintf(stderr, "bad: %g\n", x)`. A file handle will take the
  same slot later.
- An interpolated string, `"x = $x"`, arrives as `string(…)` and folds into
  the same `printf`. `@show x` arrives as `println("x = ", repr(x))` and
  does too.
- A literal `%` is doubled, quotes and newlines escaped.

So the screen shows `3` where Julia shows `3.0`, and six significant digits
where Julia shows seventeen. That's C's normal behavior, and it's what a C
programmer expects to read; `precise` is there for when the digits matter.

## Arrays

One helper, `printarray`, per element type — `printarray` for doubles,
`printarray_F32`, `printarray_I64`, `printarray_B`, named the way `cross` is,
since the shape is a runtime argument and only the element type is left to
say:

```c
printarray(stdout, &A[0][0], 2, (const int[]){2, 3});
```

It walks the elements in storage order and prints each in a right-aligned
field (`%12g`; wider under `precise`), so columns line up. Between elements
it counts how many dimensions end there: none is the end of nothing, one is
the end of a row, and each further one adds a blank line. So a vector is one
line, a matrix is one line per row, a 3-D array is its 2-D slices separated
by a blank line, a 4-D array has single and double blank lines, and so on
for any dimension:

```
           1           5
           3           7

           2           6
           4           8
```

Nothing is printed after the last element, so `print(A)` leaves the cursor
there and `println(A)` adds the newline, as for a scalar. A transposed value
is copied into its real layout first, since the helper reads the storage as
it is. `%g` picks fixed or scientific notation per number, as C does
(`1e-05`, `1.23457e+06`), and the field width keeps a mixed column aligned.

This is the one place the transpiler passes a shape at run time rather than
baking it into a name: for printing, one helper per element type is what a
C programmer writes, and nothing is allocated.

## `@printf`

Julia's format string is already C's, so `@printf("%.3f | %5d\n", x, n)` is
`printf("%.3f | %5lld\n", x, (long long)n)`: the only translation is
widening `%d`, `%u`, `%x`, `%o` to their 64-bit forms. A `%s` takes a string
literal.

## Not, or not yet

- `@sprintf` and `string(…)` as *values*: strings as values need buffers
  and an owner; on the todo.
- `show` and `display`: REPL-oriented, and for numbers the same as `print`.
- `printstyled`: ANSI escapes; little use in numeric C.
- Reading and writing files: planned, into this file and this design —
  `open("data.txt", "w")` as `fopen` with the string, `print(io, x)`
  unchanged, `close`.

Implementation: `print!`, `printf!`, `printarray!`, `printarrayhelper!` in
`src/io.jl`.
