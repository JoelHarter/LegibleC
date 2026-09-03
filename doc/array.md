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
void add(const double A[2][2], const double B[2][2], double out[2][2])
```

Inputs are `const`. C can't return an array, so a function whose Julia result
is an array becomes `void` and takes it as a trailing parameter named `out`
(`out_` if the Julia already has an `out`). A returned *scalar* that needs a
name is `result`, not `out` — see `naming.md`.

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
        out[i] = 0.0;
        for (int k = 0; k < 2; k++) {
            out[i] += a[i][k] * b[k];
        }
    }
}
```

Loop indices are `i`, `j`, `k` for up to three nested loops. Past three, the
names are `i1`, `i2`, `i3`, `i4`, … for *all* of them — not `i, j, k, l` —
so the pattern is obvious at a glance.

Helper bodies are written for C's memory layout, not Julia's: multiplication
runs its inner loop along a row of the output and a row of `b`, both
contiguous in row-major storage. That's the speed-first principle from the
README; the loops are still plain enough to read.

**One generator per operation, for every shape.** Following the README's
third principle, no helper body is written for one particular kind of array.
An operand has exactly the dimensions it has — a vector one, a matrix two,
a scalar none — and each of them lines up with an axis: a vector's with the
first, a matrix's with the first and second. Transposed, the same dimensions
line up the other way round: a row vector's one dimension with the second
axis, a transposed matrix's two with the second and first. Along an axis
where it has no dimension its extent is
taken as 1, which is how it lines up with anything there; no dimension is
ever added to make that so. From those two facts, one `access` function
produces the right C subscript for any operand, and:

- every `*` of two arrays — matrix×matrix, matrix×vector, row×matrix,
  column×row, row×column, `dot` — is the single contraction
  `out(i,j) = Σ_k a(i,k) b(k,j)`, emitting only the loops with something to
  loop over (that's why `mul_2x2_2` above has no `j` loop, and `mul_r3_3`
  is just a sum);
- every broadcast is one loop over the result's dimensions, with each
  operand subscripted only on the axes it has a dimension on, and by `0`
  where that dimension's extent is 1 — Julia's stretching rule falls out of
  the subscript. Three things follow and are deliberate: loops
  exist only for the result's *true* dimensions (a 3×1×3×1×3×1×1 result gets
  three loops, `i`, `j`, `k`, not seven); a rank-deficient input is
  indexed with exactly the subscripts it has (`a[i][0][j]` next to
  `out[i][0][j][0][k][0][0]`), never padded to the output's rank; and the
  result keeps every dimension Julia gives it, extent-1 ones included —
  `3×1×3` times `1×1×1×1×3×1×1` is `double out[3][1][3][1][3][1][1]`, not a
  squeezed `[3][3][3]`. The inputs determined that shape; the C reproduces
  it, however odd it looks;
- every block in `[A B; C D]` is placed by one loop over its own dimensions
  with offsets added.

Implementation: `access`, `nest`, `contraction` in `src/helper.jl`.

### Naming

A helper's name is the operation, a separator, then **one description per
input, always** — whether or not that distinguishes it from anything, and
whether or not the inputs happen to match. The name transcribes the
signature: `add_2x2_2x2` takes two 2×2 matrices, `mul_2x2_2` a matrix and a
vector, `dot_3_3` two 3-vectors, `cross_3_3` likewise. When the inputs don't
determine the output — `fill`'s only input is a scalar, `hvcat`'s blocks
don't say how they're arranged — the output's description goes in the name
too: `fill_3`, `hvcat2x2_…`.

**Describing one input**

| input | description | with type |
|---|---|---|
| 3-vector | `3` | `3F32` |
| 2×2 matrix | `2x2` | `2x2F32` |
| 4×3×4 array | `4x3x4` | `4x3x4I32` |
| transposed 3-vector (a row) | `T3` | `T3F32` |
| transposed 2×3 matrix | `T2x3` | `T2x3F32` |
| scalar | `s` | `F32` — the type *replaces* `s` |

No `S`/`M` class letters: the C doesn't distinguish static from mutable.
The output's size and type are never in the name; Julia's promotion rules
decide them and the C signature shows them.

**When the fundamental type is written**

- If every input is `Float64` — arrays by element type, scalars by their own
  type — no type is written anywhere: `add_2x2_2x2`, `mul_s_2x2`, `mul_2x2_2`.
- Otherwise every input gets its type, *including the `Float64` ones*:
  `add_2x2F64_2x2F32`, `mul_F32_2x2F64`, `mul_F64_2x2F32`.
- So `F64` appears exactly when some other input isn't `F64`.

**Plain operations** (the linear-algebra meaning of `+`, `-`, `*`, `copy`, …)

- Each input listed in order: `add_2x2_2x2`, `add_2x2F32_2x2F32`,
  `mul_2x2_2`, `mul_2x2_2x3`, `add_2x2F64_2x2F32`.
- Unary: `neg_2x2`, `copy_3`, `neg_3I32`.

**Pointwise operations** (`.+`, `.*`, `exp.(A)`, …) get a `P` after the
operation and are otherwise named by exactly the same rule as everything
else: `mulP_3x3_3x3`, `mulP_3_3x2`, `mulP_s_3x3`, `mulP_3x3F64_3x3F32`,
`expP_3x3`, `expP_3x3F32`. (An earlier scheme used `E` for same-size inputs
with the size written once, and `B` for broadcasting; one letter and one rule
proved simpler.)

The letter follows the Julia syntax, not the arithmetic: `exp(A)` is the
matrix exponential and would be `exp_3x3`; `exp.(A)` is `expP_3x3`. Likewise
`2.0 * A` is `mul_s_2x2` and `2.0 .* A` is `mulP_s_2x2` — the same loop, named
for what was written.

**All together**

| Julia | helper |
|---|---|
| `A + B`, both 2×2 | `add_2x2_2x2` |
| `A + B`, 2×2 `Float64` and `Float32` | `add_2x2F64_2x2F32` |
| `A * v`, 2×2 and 2-vector | `mul_2x2_2` |
| `2.0 * A` | `mul_s_2x2` |
| `Float32(2) * A` | `mul_F32_2x2F64` |
| `-A`, 3-vector of `Int32` | `neg_3I32` |
| `A .* B`, both 3×3 | `mulP_3x3_3x3` |
| `A .* B`, 3×3 `Float64` and `Float32` | `mulP_3x3F64_3x3F32` |
| `v .* M`, 3-vector and 3×2 | `mulP_3_3x2` |
| `2.0 .* A`, 3×3 | `mulP_s_3x3` |
| `exp.(A)`, 3×3 | `expP_3x3` |

Implementation: `helpername` in `src/helper.jl`.

**Elements.** `v[i]` and `A[i, j]` read as `v[i - 1]` and `A[i - 1][j - 1]` —
Julia's indices are 1-based, C's are 0-based. `v[i] = x` writes the same way;
a parameter written through `setindex!` is declared without `const`.
`zeros`, `ones`, and `fill` with literal dimensions become a `fill_<dims>`
helper (named by what it makes, the one helper whose name describes its
output rather than its inputs). See `flow.md`.

**Operations so far** — the meaning follows Julia's definition of each:

| Julia | helper | applies to |
|---|---|---|
| `A + B`, `A - B` | `add`, `sub` | same-shaped arrays of any dimension |
| `-A` | `neg` | any array |
| `copy(A)` | `copy` | any array; also used for `B = A` |
| `s * A`, `A * s` | `mul` | scalar and any array |
| `A * v` | `mul` | matrix × vector |
| `A * B` | `mul` | matrix × matrix, inner dimensions equal |
| `v' * A` | `mul_T3_3x2` | row × matrix → row |
| `v' * w` | `mul_T3_3` | row × column → a scalar, returned |
| `v * w'` | `mul_3_T3` | column × row → outer product |
| `A * B'`, `A' * B` | `mul_2x3_T2x3`, `mul_T3x2_3x2` | the transpose costs nothing, see below |
| `dot(v, w)` | `dot_3_3` | returns the scalar |
| `det(A)` | `det_3x3` | returns the scalar; sizes 1–3 written out, cofactor expansion from 4 (`det_5x5` → `det_4x4` → `det_3x3`) |
| `sum(A)`, `prod`, `maximum`, `minimum`, `any`, `all`, `norm(v)` | `sum_3`, `maximum_2x2`, `norm_3` | one loop each, returning the scalar; `maximum`/`minimum` compare, so a NaN is passed over where Julia would return it |
| `A[i, :]`, `A[:, j]`, `v[2:4]` | `row_2x3(A, i - 1, out)`, `col_2x3`, `slice_5_3(v, 1, out)` | a copy, as in Julia; the position is a 0-based parameter |
| `A \ b`, `A \ B` | `solve_3x3_3`, `solve_3x3_3x2` | see *Solving* below |
| `inv(A)` | `inv_3x3` | see *Solving* below |
| `cholesky(A) \ b`, `inv(cholesky(A))` | `solveLLT_3x3_3`, `invLLT_3x3` | Cholesky, `llt_3x3` inside |
| `lu(A) \ b` | `solve_4x4_4` | the same as `A \ b` |
| `B / A`, `v' / A` | `rsolve_2x3_3x3` | each row against `Aᵀ`, through `solve_T3x3_3` |
| `A / s`, `s \ A` | `div_2x2_s` | elementwise |
| `A \ b`, `A` not square | `solve_4x3_4`, `solve_3x4_3` | least squares (tall) or minimum norm (short), through the Gram matrix and Cholesky |
| `pinv(A)` | `pinv_4x3`, `pinv_3x4`, `pinv_3x3` | `(AᵀA)⁻¹Aᵀ`, `Aᵀ(AAᵀ)⁻¹`, or the inverse |
| `cross(v, w)` | `cross_3_3` | 3-vectors only |
| `transpose(A)`, `A'` | nothing | free for anything: same storage, axes read the other way |
| `zeros(3, 4)`, `zeros(T)`, `zero(A)` | `zero_3x4` | one `memset`; `zero_2x2I64` when not `Float64` |
| `ones(…)`, `fill(x, …)` | `fill_3x4` | every element assigned |
| `one(A)`, `SMatrix{3,3}(I)` | `identity_3x3` | `memset`, then ones down the diagonal (`min(m, n)` of them) |

Shape mismatches are errors at transpile time, as they'd be at run time in
Julia. `A + B + C` (one call in Julia) is chained through a temp.

### Comments

Every helper gets a one-line `///` comment saying what it does the way a
person would say it:

```c
/// 2×3 * 3×3 matrix multiplication
/// 3-vector + scalar broadcast addition
/// 2×2-matrix negation
/// 3×2-matrix element-wise exponential
/// transposed 3-vector * 3-vector multiplication
/// vertical concatenation of two 3-vectors
```

The words are deliberately ones the transpiler itself never uses. To it
there are only arrays of any dimension and one kind of pointwise operation;
a reader expects "scalar", "vector", "matrix" and "4×3×2-array", and
"element-wise" when the sizes match versus "broadcast" when they don't or a
scalar is involved. Sizes are written with `×`, `transposed` goes in front,
and the element type is named exactly when the helper's name carries types
(`Float64 3×2-matrix * Float32 3×2-matrix element-wise multiplication`).
Two plain operands of one kind share the noun (`2×3 * 3×3 matrix
multiplication`); identical operands are written once (`2×2-matrix
addition`). Known functions get their English name — `exponential`,
`square root`, `hyperbolic tangent` — and anything else is called by its
Julia name. Implementation: `src/prose.jl`.

### Solving

`A \ b` and `inv(A)` follow one rule for every algorithm: **sizes 1–3 are
written out in full**, the way StaticArrays writes them — Cramer's rule
straight from the determinant for a solve, the adjugate over the
determinant for an inverse — and **from 4 on it's a deterministic algorithm
that guards against singularity**: LU with partial pivoting. The pivot is
its own helper, `pivot_4x4(LU, p, k)`, which swaps the largest remaining
entry of column `k` into place in the work array and the permutation;
`lu_4x4(A, LU, p)` calls it once per column; `solve_4x4_4` and `inv_4x4`
call `lu_4x4` and then substitute (the inverse once per identity column).
`cholesky(A) \ b` and `inv(cholesky(A))` go through `llt_3x3(A, L)`, written
out for 1–3 and a loop beyond, then two triangular solves. A matrix
right-hand side is solved column by column through the vector solve.

Everything lives on the stack in arrays of the static size — `double
LU[4][4]; int p[4];` — with no allocation anywhere. A singular matrix in the
LU path, or a non-positive-definite one in the Cholesky path, is Julia's
`SingularException` / `PosDefException`; the C prints that to `stderr` and
`abort`s, which is what an uncaught exception does in Julia. Sizes 1–3 don't
check: they divide by the determinant, as StaticArrays does.

A matrix that isn't square is a least-squares problem. `A \ b` with a tall
`A` solves the normal equations `AᵀA x = Aᵀb` through Cholesky; with a
short `A` it gives the minimum-norm solution `Aᵀ(AAᵀ)⁻¹b`. `pinv(A)` is the
same two formulas as a matrix — `(AᵀA)⁻¹Aᵀ` and `Aᵀ(AAᵀ)⁻¹` — and the plain
inverse when square, one helper per shape: `pinv_4x3`, `pinv_3x4`,
`pinv_3x3`. Both build the Gram matrix with the transposed tag, so `AᵀA` is
one `mul_T4x3_4x3` call and no transpose is ever formed. Julia goes through
QR and the SVD here, which also cope with a rank-deficient `A`; the
Gram-matrix route is faster and agrees to rounding for a well-conditioned
`A`, and reports `PosDefException` for a rank-deficient one. The solve is
faster than `pinv` followed by a multiply — one Cholesky solve instead of an
inverse and a product — which is why it exists separately.

Not yet: LDLT (Julia has no `ldlt` for static matrices to hang it on),
`cholesky(A).L`, `cholesky(A) \ B` with a matrix `B`, QR, eigenvalues.

### Parameters

A helper's inputs are named by marching up the alphabet, `a`, `b`, `c`, …,
capitalized when the input is a matrix or a higher-dimensional array and
lowercase for a vector or a scalar, so a call reads like the mathematics:
`mul_2x3_3(const double A[2][3], const double b[3], double out[2])`,
`hvcat2x2_…(const double A[2][2], const double B[2][2], const double C[2][2],
const double D[2][2], double out[4][4])`. The output is always `out`. Should
a helper ever have more than 26 inputs, the names continue `aa`, `ab`, … like
spreadsheet columns. Loop indices are `i`, `j`, `k`, then `i1`, `i2`, … past
three; one that would collide with an input (the ninth input is `i`) gets
`_` appended: `i_`. Every output array is declared `restrict` —
`double out[restrict 3]` — because a Julia result is always a fresh array, so
`out` never overlaps an input; saying so lets the compiler keep loads in
registers across the stores, and it's a promise the transpiler keeps
internally (a result that is also an operand goes through a temp). A C
caller must keep it too: the Doxygen line on every `out` says so.
Implementation: `inputs` and `indices` in `src/helper.jl`.

### Transposes

`'` and `transpose` emit no C at all, for anything Julia allows them on
(scalars, vectors, matrices — Julia has no 3-D transpose). A C variable
never knows it's transposed, just as it never knows a vector is a row rather
than a column: it's the same storage either way. Julia does know, through
the type, and so does the transpiler, which is all it takes to emit the
right operation. A transposed value keeps its dimensions and lines them up
with the axes in the other order: `v'` is still a single dimension, now on
the second axis, so it's a **row**; `A'` on a 2×3 is still stored as
`double A[2][3]`, with its first dimension on the second axis and vice
versa. In names, a `T` in front: `T3`, `T2x3`.

So `A * B'` is one helper, `mul_2x3_T2x3`, whose inner product reads
`a[i][k] * b[j][k]` — what a person writes — with no copy of `B` made first.
Transposing twice gives the original back, again for free. A scalar's
transpose is itself and never reaches the transpiler.

The one place a transpose costs anything is where the value has to land
somewhere — `B = A'`, or a function that *returns* `A'` — and there the C
follows Julia's type for the landing spot. A vector's `v'` is a lazy
`Adjoint` in Julia, so it lands as the same storage, `copy_3` into a
`double r[3]`, and the receiver knows it holds a row. A matrix's `A'` on a
`StaticArrays` matrix is *eager* — Julia really makes a 3×2 — so it lands
through `copy_T2x3`, which writes `out[i][j] = a[j][i]` into a
`double B[3][2]`. Either way the C type is exactly Julia's, and a user
function whose Julia argument or result is an `Adjoint`/`Transpose` takes or
returns that wrapper's storage.

### Broadcasting

`A .+ B`, `v .* M`, `exp.(v)`, `v .* w'` and so on become **pointwise**
helpers, `P` after the operation — the naming rules are under *Naming* below. The rules are Julia's: dimensions line up from
the left, and a size of 1 stretches to match. An operand with no dimension on
some axis simply contributes nothing there — a vector has one dimension, on
the first axis; a row vector one, on the second; a scalar none — so `v .* w'`
is an outer product and `v .+ 2.0` is still a vector. Julia
fuses a chain like `exp.(v) .+ 2.0` into one loop; here each level is its own
helper, chained through a temp (`expP_3`, then `addP_3_s`) — the same result,
one more pass over the data. Broadcast functions supported: `+ - * / ^`,
unary `-`, and the `math.h` functions listed in `flow.md`.

### Block construction and literals

`[A B; C D]`, `[u; v]`, `[u v]` become `hvcat2x2_…`, `vcat_…`, `hcat_…`
helpers that copy each block into place — `hvcat2x2_2x2_2x2_2x2_2x2`,
`vcat_3_3` — with the grid in `hvcat`'s name since the blocks alone don't
say how they're arranged. A scalar among the blocks takes one cell. The
result's shape is worked out from the blocks' shapes.

A literal with no arrays in it — `[1.0 2.0; 3.0 4.0]`, `[1.0, 2.0, 3.0]`,
`SVector(1.0, 2.0, 3.0)`, `@SMatrix […]`, `SA[…]` — is assigned element by
element, no helper:

```c
out[0][0] = 1.0;
out[0][1] = 2.0;
out[1][0] = 3.0;
out[1][1] = 4.0;
```

## Assignment and aliasing

`B = -A` writes straight into `B`: `neg_2x2(A, B);`. But when the destination
is also an operand — `A = A * A` — writing into it directly would overwrite
values still being read, so the result goes through a temp and is then copied:
`mul_2x2_2x2(A, A, temp1_A); copy_2x2(temp1_A, A);`. Elementwise operations would
survive aliasing; matrix multiplication wouldn't. The rule is applied
uniformly rather than per operation.

A Julia argument that's reassigned (`A = A * A` where `A` is a parameter) is a
second variable in the IR with the same name; it comes out as `A_`, and the
parameter stays `const`.
