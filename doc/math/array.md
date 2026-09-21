# Array

How arrays come out in C: their sizes, their storage, and each thing Julia
can do with them. The generated functions that do the work are described in
`helper.md`; determinants, solving, and inverting in `solve.md`.

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
rules the helpers use; by the time the array is first assigned, and so
declared, its size is known. Either way the C is identical: a regular array
*is* a static array here. Runtime sizes are not supported yet; the design is
in `dev/map.md`.

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

## Products

Every `*` of two arrays is the one contraction `out(i,j) = Σ_k a(i,k) b(k,j)`
over the operands' axes, with only the loops that have something to loop
over: `mul_2x2_2x3`, `mul_2x2_2` (matrix × vector), `mul_T3_3x2` (row ×
matrix, a row back), `mul_3_T3` (column × row, the outer product),
`mul_T3_3` (row × column, a scalar returned). A transposed operand costs
nothing: `A * B'` is `mul_2x3_T2x3` reading `a[i][k] * b[j][k]`. `dot(v, w)`
is `dot_3`; `cross(v, w)` is `cross`, written out.

## Construction

`[A B; C D]`, `[u; v]`, `[u v]`, and the `;;` forms — `[A; B;; C; D]`,
`[A;; B]`, `[B;; C;;; D;; E]` for a 2×4×2 array — are all one rule, Julia's
own: a construction is a tree of concatenations, each `;`-group stacked
along the first dimension, the results joined along the second, `;;;` along
the third, and so on. The pieces of one group only have to agree in the
dimensions it doesn't join along, so `[A; B;; B; A]` with a scalar `A` and a
2-vector `B` is a 3×2, `[A B; B A]` with a 1×2 `B` is a 2×3, and a ragged
`[A B; C]` works. From the tree come every block's offsets.

There is no helper for any of this. Each block is copied into place where
the construction happens, one `memcpy` per contiguous row when the block's
storage lines up with the result's, a loop when it doesn't (a vector into a
column, a transposed block), a single assignment for a scalar. That's what
a C programmer writes, and the `file:line:` comment above says which
construction it is:

```c
// matrix.jl:9: blocks(A::M2, B::M2, C::M2, D::M2) = [A B; C D]
for (int i = 0; i < 2; i++) {
    memcpy(&out[i][0], A[i], sizeof(double[2]));
    memcpy(&out[i][2], B[i], sizeof(double[2]));
}
…
```

A literal with no arrays in it — `[1.0 2.0; 3.0 4.0]`,
`[1.0, 2.0, 3.0]`, `SVector(1.0, 2.0, 3.0)`, `@SMatrix […]`, `SA[…]` — is
declared with its initializer, in one go as the Julia was written, a vector
on one line and a matrix one row per line (a global array the same way):

```c
double A[2][2] = {
    {1.0, 2.0},
    {3.0, 4.0},
};
```

Where it can't be declared there — into the out parameter, or a
reassignment — it is assigned element by element, `out[0][0] = 1.0;`.

`zeros`, `zeros(T)`, and `zero(A)` are one `memset`, inline; `ones` and
`fill` are a loop; `one(A)` and `SMatrix{3,3}(I)` are the `memset` and then
ones down the diagonal. `copy(A)` and `B = A` are one `memcpy`; a copy that
changes layout (`B = A'` where Julia makes a real matrix) is a loop.

## Slices and reductions

`A[i, :]`, `A[:, j]`, `v[2:4]`, `A[1:2, 2:3]`, `A[:, 2:end]`, `A[i, 2:3]`, in
any dimension, are copies, as in Julia, written inline: a row or a run is
one `memcpy`, a block a `memcpy` per row, a column a loop. Each index is a
scalar (that dimension is dropped), a colon, a literal range, or a list of
indices; `end` is the size, which inference knows for a static array and the
transpiler for a regular one it sized. A list written out, `A[2:end, [1, 3]]`
or `v[[3, 1, 2]]`, is a gather: one copy per listed index, those sharing loops
written in one nest, and the list itself never built; a listed index beyond
the dimension is refused. A list held at run time, `v[idx]` with `idx` an
integer vector of known length, is a loop reading `v[idx[i] - 1]`.

Assigning the other way into a mutable array — `A[2, :] = v`, `A[:, 1] = v`,
`A[:, 3:end] = B`, `v[2:3] = w`, `A[:, [1, 3]] = B`, `v[idx] = w` — is the
same movement reversed. The shapes
must match, as Julia requires. Not yet: a scalar or broadcast into a slice
(`A[:, 1] .= 0`), and a range held in a variable. `sum`,
`prod`, `maximum`, `minimum`, `any`, `all`, and `norm` are one loop each,
returning the scalar (`sum_3`, `maximum_2x3`, `norm_3`); `maximum` and
`minimum` compare, so a NaN is passed over where Julia would return it.

Along one dimension — `sum(A; dims=1)`, `prod`, `maximum`, `minimum` with
`dims`, `diff`, `cumsum`, `cumprod` — the result is an array and the helper
carries the dimension on its name: `sum1_2x3(A, out)` sums a 2×3 along
dimension 1 into a 1×3, `diff2_2x3` differences along dimension 2 into a
2×2, `cumsum1_2x3` keeps the shape. The dimension is glued to the operation
because it says how the operation works, not what it is given; the shape
suffix after the underscore is the input's, as everywhere. A vector has one
dimension, so `diff_4` and `cumsum_4` leave it off — except `sum(v; dims=1)`,
which is `sum1_4`, since `sum_4` is the sum to a scalar. The `dims` keyword
must be a literal; the loops run over the other dimensions outside and the
one worked along inside.

## Declarations

A variable is declared where it is first assigned, as C is written today
and as a reader who never declares anything expects: `double r = norm_3(x);`,
or `double a[3];` right above the call that fills it. When that first
assignment is inside an `if` or a loop, a declaration there would be scoped
to the block, so the variable is declared just ahead of the construct — on
the line above its source comment — and assigned inside. Nothing is declared
at the top of a function for its own sake.

## Assignment and aliasing

`B = -A` writes straight into `B`: `neg_2x2(A, B);`. When the destination is
also an operand, it depends on the operation. Anything elementwise —
`A = A + B`, `v = 2.0 * v`, `A = A ./ s`, a broadcast of same-shaped arrays
— is safe in place, because each output element depends only on the same
element of each input, so it writes into the destination directly:
`add_3(v, temp1, v)`. A product, a solve, an inverse, a cross product, a
transposed operand (`A = A + A'`) or a construction (`v = [v[3], v[1] + v[2],
0.0]`) reads elements the output has already overwritten, so those go
through a temp and are then copied: `mul_2x2_2x2(A, A, temp1_A);
memcpy(A, temp1_A, sizeof temp1_A);`. The helpers say which they are: an
elementwise helper's `out` is a plain array, the others' is `restrict`
(`helper.md`).

A scalar parameter that is reassigned — `a = c * 2.0` where `a` is a
parameter — is reassigned in place: C passes scalars by value, which is
Julia's semantics exactly. An array parameter is the caller's memory, so
one that is reassigned (`x = x + dt * v`) is worked on as a copy, made at
the top of the function in one block with the reason written above it, and
the parameter stays `const`:

```c
    // copy x and v to prevent modification within this function
    double x_local[3];
    memcpy(x_local, x, sizeof x_local);
    double v_local[3];
    memcpy(v_local, v, sizeof v_local);

    // orbit.jl:9: r = norm(x)
```

This is what Julia itself does (the reassigned name is a fresh slot,
initialized from the argument), and it is one rule with no cases: the body
reads and writes `x_local` throughout, whether the reassignment is in a loop, a
branch, or straight-line code. The copy yields the name to the parameter, and
being the local version of that very name it is `x_local` (`naming.md`).

## One array under two names

In C an array variable is its storage and its name in one: `double v[3];`.
Julia's mutable arrays keep the two apart. `m = v` is a second name for the
same array, and a write through either is seen through both.
`x, xnew = xnew, x` moves two names between two arrays and copies nothing.
So before any C is written, every mutable array variable is found to be one
of three kinds (`src/storage.jl`):

| kind | when | the C |
|---|---|---|
| storage | it is the only name for what it holds, which is almost every variable | `double v[3];`, as always |
| second name | given another variable's array, once | `double *const m = v;`, and for a matrix `double (*const M)[3] = A;` |
| moving name | given other variables' arrays more than once: a swap, one array or another by a test | `double x_data[3], *x = x_data;`, then `x = xnew;` |

Indexing doesn't change: `m[i]` and `M[i][j]` read the same through a
pointer. Parameters are pointers already, so two parameters swapped need no
declaration at all. The usual iteration with two buffers comes out as a C
programmer writes it:

```c
    double x_data[3], *x = x_data;
    double xnew_data[3], *xnew = xnew_data;
    for (int64_t k = 1; k <= n; k++) {
        ...
        xnew[i - 1] = s / A[i - 1][i - 1];
        ...
        double *temp1_x = x;
        x = xnew;
        xnew = temp1_x;
    }
```

Only where it matters: a mutable array, and a write somewhere among the
names. Where nothing is written a copy means the same thing, and an
immutable array is a value in both languages, so both stay as they were.

A write through one name is a write to what the others hold. A parameter
written through a second name loses its `const`. And wherever the
transpiler asks whether two operands may be the same storage, names that
can come to hold one array count as the same: an operation that reads what
it overwrites goes through a temp.

One case is refused, by line: a variable given a freshly made array while
another name may still hold the one it had. In Julia the two are then
different arrays. C has one storage for the variable, and would write the
new array over what the other name still reads. A parameter's working copy
is the exception that was always there: `a = a .+ 1.0` and then
`a[1] = 0.0` writes the new array, which is the copy.

Not yet: `view`, a name for part of an array.

## Everything, in one table

The meaning of each follows Julia's definition.

| Julia | helper | note |
|---|---|---|
| `A + B`, `A - B`, `-A` | `add_2x2`, `sub_2x2`, `neg_2x2` | same-shaped arrays of any dimension |
| `copy(A)`, `B = A` | inline `memcpy` | |
| `s * A`, `A * s`, `A / s`, `s \ A` | `mul_s_2x2`, `div_2x2_s` | elementwise |
| `A * B`, `A * v`, `v' * A`, `v * w'`, `A * B'` | `mul_2x2_2x3`, `mul_2x2_2`, `mul_T3_3x2`, `mul_3_T3`, `mul_2x3_T2x3` | one contraction for all; *Products* above |
| `v' * w`, `dot(v, w)` | `mul_T3_3`, `dot_3` | return the scalar |
| `cross(v, w)` | `cross` | |
| `det(A)`, `A \ b`, `B / A`, `inv(A)`, `pinv(A)`, `cholesky(A) \ b` | `det_3x3`, `solve_3x3_3`, `rsolve_2x3_3x3`, `inv_3x3`, `pinv_4x3`, `solveLLT_3x3_3` | `solve.md` |
| `A .+ B`, `v .* M`, `exp.(A)` | `addP_2x2_2x2`, `mulP_3_3x2`, `expP_2x2` | every input listed: broadcasting leaves the shapes open |
| `v .< w`, `v .>= 0.0`, `.==`, `.!=`, `c .& d`, `.!c`, `ifelse.(c, a, b)` | `ltP_3_3`, `andP_3B_3B`, `ifelseP_3B_3F64_3F64` | a `bool` array out; `ifelse.` is `c[i] ? a[i] : b[i]` |
| `fill!(A, x)`, `A .= 0`, `A .= x`, `A .= B .* 2` | inline `memset` or a loop, or the pointwise helper writing into `A` | into a mutable array; it loses `const` |
| `A + 2I`, `A - I`, `2I - A`, `SMatrix{3,3}(2I)` | `addI_3x3(A, 2.0, out)`, `subI_3x3`, `rsubI_3x3`; `memset` and a diagonal loop | square only |
| `A'`, `transpose(A)` | nothing | the same storage |
| `[A B; C D]`, `[u; v]`, `[u v]`, `[A;; B]`, `[B;; C;;; D;; E]` | inline `memcpy` per row, or a loop | any dimension, any pieces that line up |
| `zeros`, `zero(A)`; `ones`, `fill`; `one(A)`, `SMatrix{3,3}(I)` | inline `memset`; a loop; both | |
| `A[i, :]`, `A[:, j]`, `v[2:4]`, `A[1:2, 2:3]`, `A[i, 2:3]` | inline `memcpy` or a loop | any dimension |
| `A[2:end, [1, 3]]`, `v[[3, 1, 2]]`, `v[idx]` | a gather: one copy per listed index, sharing a nest; a loop over `idx[i] - 1` for a list held at run time | a listed index beyond the dimension is refused |
| `A[2, :] = v`, `A[:, j] = v`, `A[:, 3:4] = B`, `v[2:3] = w`, `A[:, [1, 3]] = B`, `v[idx] = w` | inline `memcpy` or a loop | into a mutable array |
| `sum`, `prod`, `maximum`, `minimum`, `any`, `all`, `norm`, `count` | `sum_3`, `maximum_2x3`, `norm_3`, `count_3` | to a scalar |
| `argmax`, `argmin`, `extrema` | `argmax_4` (Julia's 1-based index), `extrema_4` (a `(min, max)` tuple, as a struct) | vectors only for `argmax`/`argmin`; a matrix gives a `CartesianIndex` in Julia |
| `sum(A; dims=1)`, `prod`, `maximum`, `minimum` with `dims` | `sum1_2x3(A, out)`, a 1×3 | the dimension is on the operation's name |
| `diff(v)`, `diff(A; dims=2)` | `diff_4`, `diff2_2x3` | one shorter along that dimension |
| `cumsum(v)`, `cumsum(A; dims=1)`, `cumprod` | `cumsum_4`, `cumsum1_2x3`, `cumprod_4` | |

Shape mismatches are errors at transpile time, as they'd be at run time in
Julia. `A + B + C` (one call in Julia) accumulates in its destination,
`add_3(A, B, out); add_3(out, C, out);`, when every step has the
destination's type and no later operand is the destination; the elementwise
helpers let their output alias an input. A chain of matrix products, whose
helper's output is `restrict`, goes through a temp per step.
