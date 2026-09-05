# Array

How arrays come out in C: their sizes, their storage, and each thing Julia
can do with them. The generated functions that do the work are described in
`helper.md`; products, determinants, solving, and inverting in `linear.md`.

## Which arrays

An array's size must be known at transpile time. Two ways:

- **In the type.** `SMatrix{2,2,Float64}`, `SVector{3,Float64}`, `MMatrix`,
  `SArray{Tuple{2,2,2},…}` — any type on which `size` works without an
  instance. Inference then knows every size in the function.
- **In the `transpile` call.** In a tuple target, a type followed by
  integers is an array of that element type and those dimensions:
  `(f, Float64, 3, Float64, 2, 3)` is a 3-vector and a 2×3 matrix. This is
  how a function written for regular `Array`s gets its sizes.

For each array given by dimensions the transpiler first tries the static
type; if the function has a method for it, inference does the rest. If not
— the method says `::Matrix{Float64}` — it uses a regular `Array` and
carries the size itself, propagating it through every operation by the same
rules the helpers use, with declarations emitted after the body is walked.
Either way the C is identical. That is what the `staticarray` option means:
a regular array *is* a static array. Runtime sizes are not supported yet;
the design is in `dev/map.md`.

## Representation

An array is a fixed-size, row-major C array: a 2×2 `Float64` matrix is
`double A[2][2]`, a 3-vector `double v[3]`, a 2×2×2 array `double t[2][2][2]`.
It's passed as an array parameter, not a bare pointer, so the compiler knows
the shape at every call:

```c
void add(const double A[2][2], const double B[2][2], double out[restrict 2][2])
```

Inputs are `const` unless the function writes into them. C can't return an
array, so a function whose Julia result is an array becomes `void` and takes
it as a trailing parameter named `out` (`out_` if the Julia already has an
`out`), declared `restrict` because a Julia result is always a fresh array
and never overlaps an input. A returned *scalar* that needs a name is
`result` — see `naming.md`.

Julia stores column-major; C row-major. Inside the C, `A[i][j]` is Julia's
`A[i+1, j+1]` and the storage order is invisible. It only matters at the
boundary, when raw memory crosses between the two — then a transpose of the
layout is needed, and that boundary helper is on the todo.

## Elements

`v[i]` and `A[i, j]` read as `v[i - 1]` and `A[i - 1][j - 1]`: Julia's
indices are 1-based, C's are 0-based, and literal indices are shifted at
transpile time. `v[i] = x` writes the same way, and a parameter written
through costs it its `const`. `length(v)` and `size(A, d)` are the numbers.

## Every dimension counts

The transpiler has no notion of a vector or a matrix, only of arrays of any
dimension. An operand has exactly the dimensions it has — a vector one, a
matrix two, a 7-D array seven, a scalar none — and each lines up with an
axis: a vector's with the first, a matrix's with the first and second.
Along an axis where it has no dimension its extent is taken as 1, which is
how it lines up with anything there; no dimension is ever added to make
that so, and none is ever dropped: `3×1×3` times `1×1×1×1×3×1×1` is a
`double out[3][1][3][1][3][1][1]`, not a squeezed `[3][3][3]`. The inputs
determined that shape; the C reproduces it, however odd it looks. Loops
exist only for the dimensions with something to loop over (that result gets
three, `i`, `j`, `k`, not seven), and an input with fewer dimensions is
subscripted with exactly the ones it has (`a[i][0][j]` next to
`out[i][0][j][0][k][0][0]`).

This one model — which axis each dimension sits on, and extent 1 where
there's none — is what every helper is generated from; see `helper.md`.

## Transposes

`'` and `transpose` emit no C at all, for anything Julia allows them on
(scalars, vectors, matrices — Julia has no 3-D transpose). A C variable
never knows it's transposed, just as it never knows a vector is a row rather
than a column: it's the same storage either way. Julia knows, through the
type, and so does the transpiler, which is all it takes to emit the right
operation. A transposed value keeps its dimensions and lines them up with
the axes in the other order: `v'` is still one dimension, now on the second
axis, so it's a **row**; `A'` on a 2×3 is still stored as `double A[2][3]`,
read the other way round. In names, a `T` in front: `T3`, `T2x3`.

So `A * B'` is one helper, `mul_2x3_T2x3`, whose inner product reads
`a[i][k] * b[j][k]` — what a person writes — with no copy of `B` made first.
Transposing twice gives the original back, again for free.

The one place a transpose costs anything is where the value has to land
somewhere — `B = A'`, or a function that *returns* `A'` — and there the C
follows Julia's type for the landing spot. A vector's `v'` is a lazy
`Adjoint` in Julia, so it lands as the same storage, `copy_3`, and the
receiver knows it holds a row. A matrix's `A'` on a `StaticArrays` matrix is
*eager* — Julia really makes a 3×2 — so it lands through `copy_T2x3`, which
writes `out[i][j] = a[j][i]` into a `double B[3][2]`. Either way the C type
is exactly Julia's.

## Broadcasting

`A .+ B`, `v .* M`, `exp.(v)`, `v .* w'` and so on become **pointwise**
helpers, `P` after the operation: `addP_3_3`, `mulP_3_3x2`, `expP_3`. The
rules are Julia's: dimensions line up from the left, and a size of 1
stretches to match. An operand with no dimension on some axis simply
contributes nothing there — a vector has one dimension, on the first axis; a
row one, on the second; a scalar none — so `v .* w'` is an outer product and
`v .+ 2.0` is still a vector. Julia fuses a chain like `exp.(v) .+ 2.0` into
one loop; here each level is its own helper, chained through a temp
(`expP_3`, then `addP_3_s`) — the same result, one more pass over the data.
Functions supported under a dot: `+ - * / ^`, unary `-`, and the `math.h`
functions in `scalar.md`.

## Construction

`[A B; C D]`, `[u; v]`, `[u v]` become `hvcat2x2_…`, `vcat_…`, `hcat_…`
helpers that copy each block into place, with the grid in `hvcat`'s name
since the blocks alone don't say how they're arranged. A scalar among the
blocks takes one cell. A literal with no arrays in it — `[1.0 2.0; 3.0 4.0]`,
`[1.0, 2.0, 3.0]`, `SVector(1.0, 2.0, 3.0)`, `@SMatrix […]`, `SA[…]` — is
assigned element by element, no helper:

```c
out[0][0] = 1.0;
out[0][1] = 2.0;
out[1][0] = 3.0;
out[1][1] = 4.0;
```

`zeros`, `zeros(T)`, and `zero(A)` are one `memset` (`zero_3x4`); `ones` and
`fill` assign every element (`fill_3x4`); `one(A)` and `SMatrix{3,3}(I)` are
the `memset` and then ones down the diagonal (`identity_3x3`).

## Slices and reductions

`A[i, :]`, `A[:, j]`, and `v[2:4]` are copies, as in Julia, through
`row_2x3(A, i - 1, out)`, `col_2x3`, and `slice_5_3(v, 1, out)`, with the
position a 0-based parameter so one helper serves every position. `sum`,
`prod`, `maximum`, `minimum`, `any`, `all`, and `norm` are one loop each,
returning the scalar (`sum_3`, `maximum_2x3`, `norm_3`); `maximum` and
`minimum` compare, so a NaN is passed over where Julia would return it.

## Assignment and aliasing

`B = -A` writes straight into `B`: `neg_2x2(A, B);`. But when the destination
is also an operand — `A = A * A`, or `v = [v[3], v[1] + v[2], 0.0]` — writing
into it directly would overwrite values still being read, so the result goes
through a temp and is then copied: `mul_2x2_2x2(A, A, temp1_A);
copy_2x2(temp1_A, A);`. Elementwise operations would survive aliasing;
matrix multiplication wouldn't. The rule is applied uniformly rather than
per operation, and it is what makes `restrict` on every `out` an honest
promise.

A Julia argument that's reassigned (`A = A * A` where `A` is a parameter) is a
second variable in the IR with the same name; it comes out as `A_`, and the
parameter stays `const`.

## Everything, in one table

The meaning of each follows Julia's definition.

| Julia | helper | note |
|---|---|---|
| `A + B`, `A - B`, `-A` | `add_2x2`, `sub_2x2`, `neg_2x2` | same-shaped arrays of any dimension |
| `copy(A)`, `B = A` | `copy_2x2` | |
| `s * A`, `A * s`, `A / s`, `s \ A` | `mul_s_2x2`, `div_2x2_s` | elementwise |
| `A * B`, `A * v`, `v' * A`, `v * w'`, `A * B'` | `mul_2x2_2x3`, `mul_2x2_2`, `mul_T3_3x2`, `mul_3_T3`, `mul_2x3_T2x3` | one contraction for all; `linear.md` |
| `v' * w`, `dot(v, w)` | `mul_T3_3`, `dot_3` | return the scalar |
| `cross(v, w)` | `cross` | |
| `det(A)`, `A \ b`, `B / A`, `inv(A)`, `pinv(A)`, `cholesky(A) \ b` | `det_3x3`, `solve_3x3_3`, `rsolve_2x3_3x3`, `inv_3x3`, `pinv_4x3`, `solveLLT_3x3_3` | `linear.md` |
| `A .+ B`, `v .* M`, `exp.(A)` | `addP_2x2_2x2`, `mulP_3_3x2`, `expP_2x2` | every input listed: broadcasting leaves the shapes open |
| `A'`, `transpose(A)` | nothing | the same storage |
| `[A B; C D]`, `[u; v]`, `[u v]` | `hvcat2x2_…`, `vcat_3_3`, `hcat_3_3` | |
| `zeros`, `zero(A)`; `ones`, `fill`; `one(A)`, `SMatrix{3,3}(I)` | `zero_3x4`, `fill_3x4`, `identity_3x3` | |
| `A[i, :]`, `A[:, j]`, `v[2:4]` | `row_2x3`, `col_2x3`, `slice_5_3` | |
| `sum`, `prod`, `maximum`, `minimum`, `any`, `all`, `norm` | `sum_3`, `maximum_2x3`, `norm_3` | |

Shape mismatches are errors at transpile time, as they'd be at run time in
Julia. `A + B + C` (one call in Julia) is chained through a temp.
