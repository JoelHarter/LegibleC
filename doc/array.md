# Array

How arrays and linear algebra come out in C.

## Which Julia arrays

An array's size must be part of its type — `SMatrix{2,2,Float64}`,
`SVector{3,Float64}`, `MMatrix{…}`, or any type on which `size` works
without an instance. A regular `Array` doesn't carry its size and isn't
supported yet (see the note under `staticarray` in `type.md`).

## Representation

An array is a fixed-size, row-major C array: a 2×2 `Float64` matrix is
`double A[2][2]`, a 3-vector `double v[3]`, a 2×2×2 array `double t[2][2][2]`.
It's passed as an array parameter, not a bare pointer, so the compiler knows
the shape at every call:

```c
void add(const double A[2][2], const double B[2][2], double result[2][2])
```

Inputs are `const`. C can't return an array, so a function whose Julia result
is an array becomes `void` and takes the result as a trailing parameter — named
by the same rule as any result (`result`, or the variable's name if the
Julia returned one — see `naming.md`).

Julia stores column-major; C row-major. Inside the C, `A[i][j]` is Julia's
`A[i+1, j+1]` and the storage order is invisible. It only matters at the
boundary, when raw memory crosses between the two — then a transpose of the
layout is needed.

## Helpers

Every operation on arrays is a call to a helper: a `static` C function
generated for that operation *at those argument types*, written once ahead of
the functions that use it. Helpers take their inputs first and write the
output into their last parameter:

```c
static void mul_2x2_2(const double a[2][2], const double b[2], double out[2]) {
    for (int i = 0; i < 2; i++) {
        double sum = 0.0;
        for (int k = 0; k < 2; k++) {
            sum += a[i][k] * b[k];
        }
        out[i] = sum;
    }
}
```

Helper bodies are written for C's memory layout, not Julia's: matrix–matrix
multiplication runs its inner loop along a row of the output and a row of `b`,
both contiguous in row-major storage. That's the speed-first principle from
the README; the loops are still plain enough to read.

**Naming.** A helper's name always carries size and type, whether or not
that distinguishes anything: `add_2x2`, `mul_2x2_2`, `sub_2x2x2`. An array is
described by its dimensions, plus its element type unless every argument is
`Float64`; a scalar is always described by its type (so `mul_F64_2x2` can't
be confused with `mul_2x2`). Arguments with identical descriptions are written
once: `add_2x2`, not `add_2x2_2x2`. Mismatched element types are spelled out:
`add_2x2F64_2x2F32`. No `S`/`M` class — the C doesn't distinguish them.

**Operations so far** — the meaning follows Julia's definition of each:

| Julia | helper | applies to |
|---|---|---|
| `A + B`, `A - B` | `add`, `sub` | same-shaped arrays of any dimension |
| `-A` | `neg` | any array |
| `copy(A)` | `copy` | any array; also used for `B = A` |
| `s * A`, `A * s` | `mul` | scalar and any array |
| `A * v` | `mul` | matrix × vector |
| `A * B` | `mul` | matrix × matrix, inner dimensions equal |

Shape mismatches are errors at transpile time, as they'd be at run time in
Julia. `A + B + C` (one call in Julia) is chained through a temp.

## Assignment and aliasing

`B = -A` writes straight into `B`: `neg_2x2(A, B);`. But when the destination
is also an operand — `A = A * A` — writing into it directly would overwrite
values still being read, so the result goes through a temp and is then copied:
`mul_2x2(A, A, temp1_A); copy_2x2(temp1_A, A);`. Elementwise operations would
survive aliasing; matrix multiplication wouldn't. The rule is applied
uniformly rather than per operation.

A Julia argument that's reassigned (`A = A * A` where `A` is a parameter) is a
second variable in the IR with the same name; it comes out as `A_`, and the
parameter stays `const`.
