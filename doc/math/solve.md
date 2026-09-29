# Solve

Solving a linear system, and its relatives: determinants, inverses,
pseudo-inverses, Cholesky and LU. (Products, `dot` and `cross` are ordinary
array operations, in `array.md`.) Every one of these is a helper
(`helper.md`), and every one follows a single rule about size:

> **Sizes 1–3 are written out in full**, the way StaticArrays writes them.
> **From 4 on it's a deterministic algorithm that guards against
> singularity.** Everything lives on the stack, in arrays of the static
> size; nothing is ever allocated.

## Determinants

`det(A)` is `det_NxN(A)`, a scalar-returning helper: 1×1, 2×2, and 3×3
written out; from 4×4, cofactor expansion along the first row — a loop over
the column, the minor cut into a local `M`, a call to the next size down,
so `det_5x5` calls `det_4x4` calls `det_3x3`. The sign alternates through a
local `sign`.

## Solving and inverting

`A \ b` at sizes 1–3 is Cramer's rule straight from `det_NxN`; `inv(A)` is
the adjugate over the determinant. Both are the exact formulas StaticArrays
uses, and neither checks for a zero determinant, as StaticArrays doesn't.

From 4×4 on it's **LU with partial pivoting**, in three pieces:

- `pivot_4x4(LU, p, k)` — for column `k`, swap the row with the largest
  magnitude at or below `k` into row `k`, in the work array and in the
  permutation. The one definition of "choose the pivot", shared by every
  elimination.
- `lu_4x4(A, LU, p)` — copy `A` into `LU`, then for each column pivot and
  eliminate. `L` is below the diagonal with a unit diagonal, `U` on and
  above it. A zero pivot is a singular matrix.
- `solve_4x4_4(A, b, out)` — `lu_4x4`, then forward substitution with the
  permuted `b` and back substitution. `inv_4x4` is the same once per column
  of the identity.

A matrix right-hand side (`A \ B`) is solved column by column through the
vector solve, `solve_3x3_3x2`. `B / A` is every row of `B` solved against
`Aᵀ` — `rsolve_2x3_3x3`, which calls `solve_T3x3_3`, the same solve reading
`A` transposed, at no cost. `lu(A) \ b` is the same as `A \ b`.

**Cholesky.** `cholesky(A) \ b` and `inv(cholesky(A))` go through
`llt_3x3(A, L)`, the lower factor with `A = L Lᵀ`, written out for 1–3 and a
loop beyond, then two triangular solves (`solveLLT_3x3_3`) or one per
identity column (`invLLT_3x3`).

**Least squares.** A non-square `A \ b` is a least-squares problem. Tall,
it solves the normal equations `AᵀA x = Aᵀb` through Cholesky
(`solve_4x3_4`); short, it gives the minimum-norm solution `Aᵀ(AAᵀ)⁻¹b`
(`solve_3x4_3`). `pinv(A)` is the same two formulas as a matrix —
`(AᵀA)⁻¹Aᵀ` and `Aᵀ(AAᵀ)⁻¹` — and the plain inverse when square, one helper
per shape: `pinv_4x3`, `pinv_3x4`, `pinv_3x3`. The Gram matrix is built with
the transposed tag, so `AᵀA` is one `mul_T4x3_4x3` call and no transpose is
ever formed. The solve is faster than `pinv` followed by a multiply — one
Cholesky solve instead of an inverse and a product — which is why it exists
separately.

## Where Julia differs

- Julia uses QR for least squares and the SVD for `pinv`, both of which
  survive a rank-deficient `A`. The Gram route is faster and agrees to
  rounding for a well-conditioned full-rank `A`, and reports
  `PosDefException` for a rank-deficient one rather than a silent answer.
- A singular matrix in the LU path or a non-positive-definite one in the
  Cholesky path is Julia's `SingularException` / `PosDefException`. The C
  prints that to `stderr` and `abort`s, which is what an uncaught exception
  does in Julia.

Not yet: LDLT (Julia has no `ldlt` for static matrices to hang it on),
`cholesky(A).L`, `cholesky(A) \ B` with a matrix `B`, `B / cholesky(A)`, QR,
eigenvalues, a static SVD.
