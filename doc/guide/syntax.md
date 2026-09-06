# Syntax

Every piece of Julia the transpiler accepts, in one place. The other documents
explain *how* each part is handled; this one only says *what* works, so a
reader can tell at a glance whether a function will go through. Anything not
listed here is an error at transpile time, never silently wrong C — and
the repo's `todo.md` lists what's coming.

## Calling the transpiler

```julia
transpile(f, g, (h, Float64, 3, Float64, 2, 3); outfile="name", outpath=dir)
```

A target is a function with one concrete method, a `MethodInstance`, or a
tuple of a function and argument types — where a type followed by integers is
an array of that element type and size. Options: `outfile`, `outpath`,
`templimit`, `staticarray` (on), `source` (on), `precise`, `portable`, `width`
(100), `spelling` (your own C names for characters, `../naming.md`). One
`.c` file comes out, with
prototypes, the helpers it needs, and the functions.

## Functions

| Julia | works |
|---|---|
| `f(x, y) = …`, `function f(x, y) … end` | yes; the name is kept in C |
| argument types: the scalars below, static arrays, `Array{T,N}` with a size given in the call | yes |
| the same function at several signatures | yes; each gets the types appended to its name (`poly_I64_I64`) |
| default arguments, keyword arguments | untested (the IR should already show the filled-in call) |
| returning a scalar | `return x;` |
| returning an array | through a trailing `out` parameter |
| `return nothing`, a `Nothing` result | `void` |
| tuples, multiple return values | yes, as a generated struct (`../struct.md`) |
| calling another user function | yes; brought in on demand if not listed, recursion included (`../call.md`) |
| `ccall`, `@ccall` | yes: the call itself, with a header or a prototype (`../call.md`) |
| docstrings and comments | carried into the C (see `../comment.md`) |
| `print`, `println`, to `stdout` or `stderr`; `"x = $x"`; `@show`; `@printf` | yes, as `printf` and one array helper (`../io.md`) |
| `@sprintf`, `string(…)` as a value, `show`, `display`, `printstyled`, files | not yet |

## Scalar types

`Bool`, `Int8`–`Int64`, `UInt8`–`UInt64`, `Float32`, `Float64`, `Char`,
`String`. See `../math/scalar.md` for the C spelling of each. `struct` (immutable
by value, mutable through a pointer, parametric at concrete types) and `Tuple`
— see `../struct.md`. Not yet: complex, `Int128`, `Float16`, `Rational`,
`BigInt`, `@enum`, `Union{T, Nothing}`.

## Characters and strings

Where the two languages agree. A `Char` is C's `char`, so ASCII: a non-ASCII
character literal is an error. A `String` is `const char *`, UTF-8 bytes in
both languages, read-only.

| Julia | works |
|---|---|
| `'a'`, `'\n'`; `c == 'a'`, `c < 'z'`; `c + 1`, `c - 'a'`; `Int(c)`, `Char(n)` | yes |
| `isdigit isletter isspace isuppercase islowercase isnumeric ispunct iscntrl isprint isxdigit isascii`, `uppercase`, `lowercase` | yes, from `ctype.h` |
| `"abc"` as an argument or return value; `s == t`, `s != t` | yes: a literal, `strcmp` |
| `length(s)` (characters), `ncodeunits(s)`, `sizeof(s)` (bytes), `isempty(s)`, `s[i]`, `codeunit(s, i)` | yes; `s[i]` is the byte |
| `print(s)`, `print(c)`, `"$s"` | yes, `%s` and `%c` |
| concatenation, `string(…)`, `@sprintf`, `split`, `for c in s`, a built or returned new string | not yet — needs buffers and an owner |

## Scalar expressions

| Julia | works |
|---|---|
| `+ - * / \ ÷ %`, `mod` | yes; `mod` on floats keeps Julia's sign rule |
| `x^2`, `x^3`, `x^-1`, `x^n` for any literal integer `n`, `x^y` | yes; `powi(x, n)` by squaring from the 4th power |
| `< <= > >= == !=` | yes |
| `! & \| xor << >> ~` | yes |
| `&&`, `\|\|`, `c ? x : y` | yes, in conditions and as values |
| `sqrt sin cos tan asin acos atan sinh cosh tanh exp exp2 expm1 log log2 log10 log1p cbrt floor ceil trunc round hypot copysign abs max min atan(y, x)` | yes; the `f` family on `Float32` |
| `zero(x)`, `one(x)` | yes |
| `Float64(a)`, `Int64(x)`, `round(Int64, x)`, `floor(Int64, x)`, … | yes, as casts |
| `pi`, `ℯ`, `Inf`, `NaN`, `Inf32`, `NaN32`, numeric literals | yes |
| `isnan`, `isinf`, `isfinite`, `signbit`; `typemax`, `typemin`, `floatmax`, `floatmin`, `eps` of a type | yes, as the `math.h`, `stdint.h`, `float.h` names |
| `length(v)`, `size(A, d)` | yes, as the number |
| integer overflow | Julia wraps, C doesn't define it: not yet reconciled |

## Control flow

| Julia | works |
|---|---|
| `if`, `elseif`, `else` | yes |
| `while c … end`, `while true` | yes |
| `for i in a:b`, `a:s:b` with a literal step | yes |
| `for i in eachindex(v)`, `1:length(v)`, `axes(A, d)` | yes |
| `for i in 1:2, j in 1:3` | yes |
| `for x in v` over a vector's elements | yes |
| `break`, `continue`, `return` anywhere | yes |
| `for x in A` over a matrix, a non-literal step, a range in a variable, `enumerate`, `zip` | not yet |
| `try`/`catch`, comprehensions, closures, `do` blocks | not yet |

## Variables

Any Julia name, including Unicode (`ω` → `omega`, `x₁` → `x1`, `ẋ` → `xdot`),
reassignment, and reassigning a loop variable's name outside the loop. See
`../naming.md` for the conversion and collision rules.

## Arrays

Arrays are `StaticArrays` types (`SVector`, `SMatrix`, `SArray`, and their
mutable forms) of any dimension, or `Array{T,N}` under the `staticarray`
option with the size supplied in the `transpile` call. The size is always
known at transpile time; dynamic sizes and allocation are not yet supported.

| Julia | works |
|---|---|
| `v[i]`, `A[i, j]`, `T[i, j, k]` read and write | yes |
| `A + B`, `A - B`, `-A`, `s * A`, `A * s` | yes |
| `A * B`, `A * v`, `v' * A`, `v' * w`, `v * w'`, `A * B'`, `A' * B` | yes |
| `dot(v, w)`, `cross(v, w)`, `det(A)` | yes |
| `sum`, `prod`, `maximum`, `minimum`, `any`, `all`, `norm`, `count`, `argmax`, `argmin`, `extrema` | yes |
| `sum(A; dims=1)`, `prod`, `maximum`, `minimum` with `dims`; `diff`, `cumsum`, `cumprod` | yes |
| `A[i, :]`, `A[:, j]`, `v[2:4]`, `A[1:2, 2:3]`, `A[:, 2:end]`, `A[i, 2:3]`, any dimension (literal ranges) | yes |
| `A[2, :] = v`, `A[:, j] = v`, `A[:, 3:end] = B`, `v[2:3] = w` into a mutable array | yes |
| `A \ b`, `A \ B`, `B / A`, `A / s`, `inv(A)`, `cholesky(A) \ b`, `inv(cholesky(A))`, `lu(A) \ b` | yes; 1–3 written out, LU with partial pivoting beyond |
| `A \ b` with a non-square `A`, `pinv(A)` | yes: least squares / minimum norm through the Gram matrix and Cholesky (full rank only) |
| `v'`, `A'`, `transpose(…)` | yes, free (0–2 dimensions, as in Julia) |
| broadcasting: `.+ .- .* ./ .^`, unary `.-`, `f.(A)` for the `math.h` functions above, any shapes Julia allows | yes |
| `zeros`, `ones`, `fill`, `zero(A)`, `one(A)`, `SMatrix{n,n}(I)`, `SMatrix{n,n}(2I)` | yes |
| `A + 2I`, `A - I`, `2I - A` | yes |
| `fill!(A, x)`, `A .= 0`, `A .= B .* 2` into a mutable array | yes |
| `[1.0 2.0; 3.0 4.0]`, `[1.0, 2.0]`, `SVector(…)`, `@SMatrix […]`, `SA[…]` | yes |
| `[A B; C D]`, `[u; v]`, `[u v]`, `[A; B;; C; D]`, `[A;; B]`, `[B;; C;;; D;; E]`, with scalars among the blocks, ragged rows and columns | yes, any dimension |
| `B = A`, `B = A'`, `A = A * A` | yes (copies, and a temp when the destination is an operand) |
| `.==`, `.<`, `.<=`, `.>`, `.>=`, `.!=`, `.&`, `.\|`, `.!`, `ifelse.` | yes, a `Bool` array |
| a range in a variable, `A[:, 1] .= 0` | not yet |
| runtime-sized `Array` arguments (`staticarray=false`) | not yet — see `../dev/map.md` §3.4 for the VLA design |

## Comments

Every comment before and inside the function is carried into the C, and by
default each line of code too, as `file:line: code`. A docstring becomes a
Doxygen block. See `../comment.md`.
