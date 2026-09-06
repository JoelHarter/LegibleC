# Helper

Every *computation* on arrays is a call to a *helper*: a `static` C
function generated for that operation at those argument types, written
once, ahead of the functions that use it. This is what they look like, how
they're built, and how they're named.

A helper is for computation; *moving* data is written inline where it
happens, as a C programmer writes it — `memcpy` for a contiguous run,
`memset` to zero, a loop otherwise. Copies, block construction, slices and
slice assignment, `zeros`, `fill`, and the identity have no helpers and no
names; the `file:line:` comment above them says what they are. See
`math/array.md`, and `src/move.jl`.

```c
/// 2×2-matrix * 2-vector multiplication
/// out = A * b
static inline void mul_2x2_2(const double A[2][2], const double b[2], double out[restrict 2]) {
    for (int i = 0; i < 2; i++) {
        out[i] = 0.0;
        for (int k = 0; k < 2; k++) {
            out[i] += A[i][k] * b[k];
        }
    }
}
```

Helpers take their inputs first and write the output into their last
parameter, or return it when it's a scalar. They're written for C's memory
layout, not Julia's: a multiplication runs its inner loop along a row of the
output and a row of the second operand, both contiguous in row-major
storage. Helpers are written to `out/helper.h` (the `static inline` ones,
and prototypes of the rest) and `out/helper.c` (solvers, factorizations,
array printing).
Speed first (`philosophy.md`); the loops are still plain enough to
read. Helpers that call other helpers — `det_4x4` calls `det_3x3`,
`solve_4x4_4` calls `lu_4x4` calls `pivot_4x4` — are written in dependency
order, so no prototypes are needed.

A helper is `static inline` when it is straight-line code or plain loops —
`add_2x2`, `dot_3`, `cross`, `copy_3`, `zero_3x4`, `row_2x3`, `sum_3`, `powi`, the
written-out `det_3x3`, `solve_3x3_3`, `inv_3x3` — the small things a C
programmer marks `inline`. It is plain `static` when it calls other helpers,
searches, or can abort: `det_4x4` and up, `pivot`, `lu`, `solve` and `inv`
from 4×4, `llt`, the Cholesky solves, `pinv`, `rsolve`, and the
column-by-column and least-squares solves. Nobody wants a factorization
copied into every caller, and the compiler shouldn't be nudged toward it.
All helpers are `static`: they are the file's own implementation details,
and a header of `static inline` helpers is the natural next step when two
outputs need to share them.

## One generator per operation

Following the philosophy's Generality principle, no helper body is written for
one particular kind of array. Every generator is written once from the
model in `math/array.md`: an operand has exactly its own dimensions, each on some
axis, with extent 1 along any axis it has none on. From that, one `access`
function produces the right C subscript for any operand — a scalar, a
vector, a transposed matrix, a 7-D array — and:

- every `*` of two arrays — matrix×matrix, matrix×vector, row×matrix,
  column×row, row×column, `dot` — is the single contraction
  `out(i,j) = Σ_k a(i,k) b(k,j)`, emitting only the loops with something to
  loop over (that's why `mul_2x2_2` above has no `j` loop, and `dot_3` is just a
  sum);
- every broadcast is one loop over the result's dimensions, each operand
  subscripted on the axes it has a dimension on and by `0` where its extent
  is 1 — Julia's stretching rule falls out of the subscript;
- every elementwise operation walks the output in storage order with plain
  subscripts when every operand lines up the same way, and through `access`
  when one is transposed relative to the others (`A + B'`);
- every reduction is one loop in storage order.

Loops of extent 1 are not emitted; their index is `0`. Implementation:
`access`, `nest`, `loopindices`, `contraction`, `helpercode`,
`broadcasthelper!`, `reducehelper!` in `src/helper.jl`.

## Names

A helper's name says exactly **what the operation's contract leaves open**,
and nothing the contract already fixes.

**Describing one input.** Its shape, then its type when a type is needed:

| input | shape | with type |
|---|---|---|
| 3-vector | `3` | `3F32` |
| 2×2 matrix | `2x2` | `2x2F32` |
| 4×3×4 array | `4x3x4` | `4x3x4I32` |
| transposed 3-vector (a row) | `T3` | `T3F32` |
| transposed 2×3 matrix | `T2x3` | `T2x3F32` |
| scalar | `s` | `sF32` |

A scalar's shape is `s`, always, so a description is always shape then type
and `F32` on its own can never be mistaken for a scalar. No `S`/`M` class
letters: the C doesn't distinguish static from mutable. A type is written
exactly when not every input is `Float64`, and then on every input,
including the `Float64` ones — so `F64` appears only next to something that
isn't. The abbreviations are in `math/scalar.md`.

**What the contract leaves open decides what's listed.**

- An operation that leaves the shapes open lists every input in order:
  `mul_2x2_2x3`, `mul_2x2_2`, `mul_s_2x2`, `mul_sF32_2x2F64`, `mul_T3_3x2`.
  Matrix multiplication only *constrains* the shapes (inner sizes equal), and
  there is no notation for that a reader would grasp at once, so it lists
  both.
- Every **pointwise** operation (`.+`, `.*`, `exp.(A)`, …) leaves the shapes
  open, since broadcasting lets them differ, so it lists every input, with a
  `P` after the operation: `mulP_3_3x2`, `mulP_3x2_3x2`, `mulP_s_3x3`,
  `addP_3_sF32`, `expP_3x3`. The letter follows the Julia syntax, not the
  arithmetic: `2.0 * A` is `mul_s_2x2` and `2.0 .* A` is `mulP_s_2x2` — the
  same loop, named for what was written.
- An operation whose contract fixes the shapes as identical — `add`, `sub`,
  `dot` — writes the shape **once**, then the types run together in input
  order, one if they all agree: `add_2x2`, `add_2x2F32`, `add_2x2F32F64`,
  `sub_3`, `dot_3`, `dot_3I32F64`. (A transposed operand, `A + B'`, still
  lists in full as `add_2x3_T3x2`: the shapes agree but the storage doesn't.)
- `cross` fixes the shapes entirely — always two 3-vectors — so only the
  types remain: `cross`, `cross_F32`, `cross_F64F32`.
- When the inputs don't determine the **output**, the output's description
  goes in. Today that is only `printarray`'s element type (`io.md`); the
  block, slice, and fill helpers that used to need it are inline now.
- Unary operations have one input: `neg_2x2`, `copy_3`, `det_3x3`, `sum_3`.
- **Algorithms** carry their method: `solve_4x4_4` and `inv_4x4` (LU),
  `solveLLT_3x3_3` and `invLLT_3x3` (Cholesky), `rsolve_2x3_3x3` (`B / A`),
  `pinv_4x3`; and their pieces `pivot_4x4`, `lu_4x4`, `llt_3x3`. See
  `math/solve.md`.

| Julia | helper |
|---|---|
| `A + B`, both 2×2 | `add_2x2` |
| `A + B`, 2×2 `Float32` and `Float64` | `add_2x2F32F64` |
| `A * v`, 2×2 and 2-vector | `mul_2x2_2` |
| `2.0 * A` | `mul_s_2x2` |
| `Float32(2) * A` | `mul_sF32_2x2F64` |
| `-A`, 3-vector of `Int32` | `neg_3I32` |
| `A .* B`, both 3×3 | `mulP_3x3_3x3` |
| `v .* M`, 3-vector and 3×2 | `mulP_3_3x2` |
| `exp.(A)`, 3×3 | `expP_3x3` |
| `dot(v, w)` | `dot_3` |
| `cross(v, w)` | `cross` |
| `v' * A`, 3-vector and 3×2 | `mul_T3_3x2` |
| `A * B'`, both 2×3 | `mul_2x3_T2x3` |

A helper's name can collide with a name of the user's; `naming.md` says
what happens. Implementation: `helpername` in `src/helper.jl`.

## Parameters

A helper's inputs are named by marching up the alphabet, `a`, `b`, `c`, …,
capitalized when the input is a matrix or a higher-dimensional array and
lowercase for a vector or a scalar, so a call reads like the mathematics:
`mul_2x3_3(const double A[2][3], const double b[3], double out[2])`,
`hvcat2x2_…(A, B, C, D, out)` for `[A B; C D]`. The output is always `out`.
Should a helper ever have more than 26 inputs, the names continue `aa`,
`ab`, … like spreadsheet columns. A parameter that is neither an input nor
the output — the row of a slice, the column of a pivot — is named for what
it is (`i`, `k`, `from`).

Loop indices are `i`, `j`, `k` for up to three nested loops; past three,
`i1`, `i2`, `i3`, … for *all* of them, so the pattern is obvious at a
glance. One that would collide with an input (the ninth input is `i`) gets
`_` appended: `i_`.

An output array is declared `restrict` — `double out[restrict 3]` — when
no input could be the same array as the output: a product, a solve, an
inverse, a cross product, anything whose output element reads inputs at
other indices. Saying so lets the compiler keep loads in registers across
the stores, and it is a promise the transpiler keeps (such a result that is
also an operand goes through a temp; `math/array.md`). An elementwise helper —
`add_3`, `mul_3_s`, `neg_2x2`, a pointwise `addP_…` with an input of the
output's shape — reads each input only at the index it writes, so it is
correct with `out` the same array as an input, and its `out` is left plain
so that callers may do exactly that. A user function's `out` is always
`restrict`, even when the function happens to finish reading its inputs
before it writes: the transpiler passes it a fresh array, a C caller must
too, and the promise is what lets the compiler vectorize the writes into it
without a runtime overlap check. Implementation: `inputs`, `indices`,
`alike`, `declare` in `src/helper.jl` and `src/type.jl`.

## Comments

Every helper gets a `///` comment: a line saying what it does the way a
person would say it — `2×3 * 3×3 matrix multiplication`, `3-vector + scalar
broadcast addition`, `LU decomposition of a 4×4-matrix with partial
pivoting` — and a line giving its defining equation in the parameter names:
`out = A * b`, `out = a .+ bᵀ`, `returns a ⋅ b`, `out = A \ b`,
`out = [A B; C D]`, `L * U = A[p, :]`. The rules for the words are in
`comment.md`.
