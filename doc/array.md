# Array

How arrays and linear algebra come out in C.

## Which Julia arrays

An array's size must be known. Two ways:

- **In the type.** `SMatrix{2,2,Float64}`, `SVector{3,Float64}`, `MMatrix{…}`,
  or any type on which `size` works without an instance. Inference then knows
  every size in the function.
- **In the `transpile` call.** In a tuple target, a type followed by integers
  is an array of that element type and those dimensions:
  `(f, Float64, 3, Float64, 2, 3)` is a 3-vector and a 2×3 matrix. This is
  how a function written for regular `Array`s gets its sizes.

For each array given by dimensions, the transpiler first tries the static
type (`SArray{Tuple{2,3},Float64,…}`); if the function has a method for
that, inference does the rest. If not — the method says `::Matrix{Float64}`,
say — it uses a regular `Array{Float64,2}` and carries the size itself,
propagating it through every operation by the same rules the helpers use.
Either way the C is identical: same representation, same helpers, same names.
That is what the `staticarray` option means: a regular array *is* a static
array. (All-or-nothing per call: either every array is static or every one is
regular; mixing within one signature isn't attempted.)

A regular array's size in the *middle* of a function comes from what was
stored into it, so declarations are emitted after the body is walked.

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

### Naming

A helper's name always carries the size and type of its inputs, whether or
not that distinguishes it from anything. The name is the operation, a
separator, then one description per input.

**Describing one input**

| input | description | with type |
|---|---|---|
| 3-vector | `3` | `3F32` |
| 2×2 matrix | `2x2` | `2x2F32` |
| 4×3×4 array | `4x3x4` | `4x3x4I32` |
| scalar | `s` | `F32` — the type *replaces* `s` |

No `S`/`M` class letters: the C doesn't distinguish static from mutable.
The output's size and type are never in the name; Julia's promotion rules
decide them and the C signature shows them.

**When the fundamental type is written**

- If every input is `Float64` — arrays by element type, scalars by their own
  type — no type is written anywhere: `add_2x2`, `mul_s_2x2`, `mul_2x2_2`.
- Otherwise every input gets its type, *including the `Float64` ones*:
  `add_2x2F64_2x2F32`, `mul_F32_2x2F64`, `mul_F64_2x2F32`.
- So `F64` appears exactly when some other input isn't `F64`.

**Plain operations** (the linear-algebra meaning of `+`, `-`, `*`, `copy`, …)

- Inputs with identical descriptions are written once: `add_2x2`, not
  `add_2x2_2x2`; `add_2x2F32` when both are `Float32`.
- Otherwise each is listed in order: `mul_2x2_2`, `mul_2x2_2x3`,
  `add_2x2F64_2x2F32`.
- Unary: `neg_2x2`, `copy_3`, `neg_3I32`.

**Broadcast operations** (`.+`, `.*`, `exp.(A)`, …) — the letter after the
operation says which kind:

- `E`, element-wise, when every input has the same size. The size is written
  once. Types, if needed, run together directly after it in input order:
  `mulE_3x3`, `mulE_3x3F64F32`. If the inputs share one non-`Float64` type
  it's written once: `mulE_3x3F32`. Single-input broadcasts are always
  element-wise: `expE_3x3`, `expE_3x3F32`.
- `B`, broadcast, when sizes differ. Every input is listed with its own size
  and, if needed, type — nothing is collapsed: `mulB_1x3_3x3`,
  `mulB_1x3F64_3x3F32`. A scalar is a size of its own, so a scalar with an
  array is always `B`: `mulB_s_3x3`, `mulB_F32_3x3F64`.

The letter follows the Julia syntax, not the arithmetic: `exp(A)` is the
matrix exponential and would be `exp_3x3`; `exp.(A)` is `expE_3x3`. Likewise
`2.0 * A` is `mul_s_2x2` and `2.0 .* A` is `mulB_s_2x2` — the same loop, named
for what was written.

**All together**

| Julia | helper |
|---|---|
| `A + B`, both 2×2 | `add_2x2` |
| `A + B`, 2×2 `Float64` and `Float32` | `add_2x2F64_2x2F32` |
| `A * v`, 2×2 and 2-vector | `mul_2x2_2` |
| `2.0 * A` | `mul_s_2x2` |
| `Float32(2) * A` | `mul_F32_2x2F64` |
| `-A`, 3-vector of `Int32` | `neg_3I32` |
| `A .* B`, both 3×3 | `mulE_3x3` |
| `A .* B`, 3×3 `Float64` and `Float32` | `mulE_3x3F64F32` |
| `A .* B`, 1×3 and 3×3 | `mulB_1x3_3x3` |
| `2.0 .* A`, 3×3 | `mulB_s_3x3` |
| `exp.(A)`, 3×3 | `expE_3x3` |

Implementation: `helpername` in `src/helper.jl`. Broadcast operations
themselves aren't emitted yet; the naming is ready for them.

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
