# Scalar

Numbers: which types the transpiler knows, how each is spelled in C, and how
scalar arithmetic and the math library come out.

## Types

| Julia     | C          | in a mangled name |
|-----------|------------|---|
| `Bool`    | `bool`     | `B`     |
| `Int8`    | `int8_t`   | `I8`    |
| `UInt8`   | `uint8_t`  | `U8`    |
| `Int16`   | `int16_t`  | `I16`   |
| `UInt16`  | `uint16_t` | `U16`   |
| `Int32`   | `int32_t`  | `I32`   |
| `UInt32`  | `uint32_t` | `U32`   |
| `Int64`   | `int64_t`  | `I64`   |
| `UInt64`  | `uint64_t` | `U64`   |
| `Float32` | `float`    | `F32`   |
| `Float64` | `double`   | `F64`   |

`Float64` is the default: a function or helper whose inputs are all
`Float64` leaves the abbreviation out of its name entirely (`naming.md`,
`helper.md`). The table in `src/type.jl` is the one the code reads; keep the
two in step. `Nothing` is `void`, as a return type only.

Not yet, though both languages have them: complex numbers (`double
_Complex` ↔ `ComplexF64`, with the same operators), pointers (`T*` ↔
`Ptr{T}`, except inside `ccall`), characters (C's `char` is a byte; Julia's
`Char` is a Unicode scalar, whose honest match is `char32_t`). Not cleanly
on one side or the other: `Int128` (a compiler extension in C), `Float16`
(optional in C23), `long double` (no Julia equivalent), `Rational`, `BigInt`,
`BigFloat`.

## Operations

| Julia | C | note |
|---|---|---|
| `+ - *` | `+ - *` | |
| `/` | `/` | Julia's `/` is always floating: two integers get `.0` on a literal or a cast on a variable, `(double)a / (double)b` |
| `a \ b` | `b / a` | |
| `÷`, `%` | `/`, `%` | both truncate toward zero in both languages |
| `mod(a, b)` | `((a % b) + b) % b` | integers only |
| `x^2`, `x^3` | `x * x`, `x * x * x` | |
| `x^-1` | `1.0 / x` | |
| `x^n`, `x^y` (floats) | `pow(x, n)` | integer `^` beyond 3 is an error |
| `< <= > >= == !=` | the same | |
| `!`, `&`, `\|`, `xor`, `<<`, `>>`, `~` | `!`, `&`, `\|`, `^`, `<<`, `>>`, `~` | |
| `&&`, `\|\|`, `c ? x : y` | the same, or an `if` — see `flow.md` | |
| `sqrt sin cos tan asin acos atan sinh cosh tanh exp exp2 expm1 log log2 log10 log1p cbrt floor ceil trunc hypot copysign` | the same, from `math.h` | |
| `abs(x)` | `fabs(x)`; `llabs(x)` for `Int64`, `abs(x)` for `Int32` (`stdlib.h`) | |
| `max`, `min` on floats | `fmax`, `fmin` | |
| `max`, `min` on integers | `(a > b ? a : b)` | |
| `round(x)` | `rint(x)` | both round half to even |
| `atan(y, x)` | `atan2(y, x)` | |
| `Float64(a)`, `Int64(x)`, … | `(double)a`, `(int64_t)x` | a cast |
| `round(Int64, x)`, `floor(Int64, x)`, … | `(int64_t)rint(x)`, … | |
| `pi`, `ℯ`, `Inf`, `NaN` | `M_PI`, `M_E`, `INFINITY`, `NAN` | from `math.h` |
| `length(v)`, `size(A, d)` | the number, since sizes are known | |

Headers are included only when something needs them.

## Where the languages differ

The philosophy asks for Julia's *logical intent*, not its bit pattern, so
rounding-level differences are accepted and these are the ones to know:

- **Integer overflow.** Julia wraps; C leaves signed overflow undefined. Not
  yet reconciled — `-fwrapv` as the one fixed flag is the likely answer.
- **Checks Julia makes and C doesn't.** `Int64(2.5)` throws in Julia and
  truncates in C; `div(1, 0)` throws in Julia and is undefined in C.
- **`mod` on floats** and **`Float32` math** (`sqrtf` and friends) are not
  yet supported.
