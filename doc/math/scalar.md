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
| `Char`    | `char`     | `C`     |
| `String`  | `const char *` | `S` |
| `Float64` | `double`   | `F64`   |
| `ComplexF32` | `float complex`  | `C` in front, `F32` after |
| `ComplexF64` | `double complex` | `C` in front |

`Float64` is the default: a function or helper whose inputs are all
`Float64` leaves the abbreviation out of its name entirely (`naming.md`,
`helper.md`), and `ComplexF64` counts as double for that rule, marked by
the `C` in front of the shape, `add_C3`, `mul_CH3x2_C3x2`, `Cs` for a scalar
— placed like the `T` of a transpose and the `H` of an adjoint, which is
what it reads like. The table in `src/type.jl` is the one the code reads;
keep the two in step. `Nothing` is `void`, as a return type only.

Complex numbers are C99's, from `<complex.h>`: the operators as they are,
`conj`, `creal`, `cimag`, `cabs`, `carg` and the `c` family of functions,
`CMPLX(a, b)` for `Complex(a, b)`, `I` for `im`; `abs2` is one small helper.
On real elements `'` transposes, on complex it conjugates too: an adjoint
operand is read as `conj(A[k][i])` inside the helper, `dot` conjugates its
first argument, `norm` sums squared magnitudes, `cholesky` factors `L Lᴴ`
with real pivots, and LU pivots on `cabs`. Not on MSVC, which has no C99
complex. `transpose(A')`, a conjugate without a transpose, must be stored
as `conj.(A)`.

Not yet, though both languages have them: pointers (`T*` ↔
`Ptr{T}`, except inside `ccall`), characters (C's `char` is a byte; Julia's
`Char` is a Unicode scalar, whose honest match is `char32_t`). Not cleanly
on one side or the other: `Int128` (a compiler extension in C), `Float16`
(optional in C23), `long double` (no Julia equivalent), `Rational`, `BigInt`,
`BigFloat`.

## Operations

| Julia | C | note |
|---|---|---|
| `+ - *` | `+ - *` | |
| `x += e`, `x = x * e`; `n += 1` | `x += e`, `x *= e`; `n++` for an integer | only when `e` is one operand: `x = x + y - z` stays as written |
| `/` | `/` | Julia's `/` is always floating: two integers get `.0` on a literal or a cast on a variable, `(double)a / (double)b` |
| `a \ b` | `b / a` | |
| `÷`, `%` | `/`, `%` | both truncate toward zero in both languages |
| `mod(a, b)` | `((a % b) + b) % b`; on floats `modulo(a, b)`, a helper with Julia's definition | C's `fmod` takes the dividend's sign, Julia's `mod` the divisor's |
| `zero(x)`, `one(x)`, `zero(Float64)` | `0.0`, `1.0` | the literal of the type |
| `s, c = sincos(x)` | `s = sin(x); c = cos(x);` | ISO C has no `sincos`; the compiler fuses the two calls. The pair itself is not a value: `t = sincos(x)` is refused |
| `x^2`, `x^3` | `x * x`, `x * x * x` | `x^0` is `1.0`, `x^1` is `x` |
| `x^-1` | `1.0 / x` | |
| `x^n`, any other literal `n` | `powi(x, n)`, one helper by squaring (`powiF32`, `powiI64` off the double) | the exponent is a literal at every call, so at `-O2` the compiler unrolls the helper into the bare multiply chain — five multiplies for `x^13`, no loop, no branch. Julia's `Float64^Int` is a compensated squaring, a bit more accurate; this is the plain one, three times faster |
| `x^y` (floats) | `pow(x, y)` | a negative power of an integer is a `DomainError` in Julia, and an error here |
| `< <= > >= == !=` | the same | |
| `!`, `&`, `\|`, `xor`, `<<`, `>>`, `~` | `!`, `&`, `\|`, `^`, `<<`, `>>`, `~` | |
| `&&`, `\|\|`, `c ? x : y` | the same, or an `if` — see `flow.md` | |
| `sqrt sin cos tan asin acos atan sinh cosh tanh exp exp2 expm1 log log2 log10 log1p cbrt floor ceil trunc hypot copysign` | the same, from `math.h`; the `f` family on a `Float32` (`sqrtf`, `fabsf`, `powf`) | |
| `'a'`, `c + 1`, `c - 'a'`, `Int(c)`, `Char(n)`, `isdigit(c)`, `uppercase(c)` | `'a'`, `c + 1`, `c - 'a'`, `(int64_t)c`, `(char)n`, `isdigit(c)`, `(char)toupper(c)` | a `Char` is an ASCII `char`; the `ctype.h` classes agree with Julia's there |
| `s == "abc"`, `length(s)`, `ncodeunits(s)`, `isempty(s)`, `s[i]` | `strcmp(s, "abc") == 0`, `utf8len(s)`, `(int64_t)strlen(s)`, `s[0] == '\0'`, `s[i - 1]` | a `String` is `const char *`, UTF-8 in both languages |
| `pi`, `ℯ` | `M_PI`, `M_E` | POSIX, not ISO C; the `portable` option defines `LEGIBLEC_PI` and `LEGIBLEC_E` at the top of the file instead |
| `abs(x)` | `fabs(x)`; `llabs(x)` for `Int64`, `abs(x)` for `Int32` (`stdlib.h`) | |
| `max`, `min` on floats | `fmax`, `fmin` | |
| `max`, `min` on integers | `(a > b ? a : b)` | |
| `round(x)` | `rint(x)` | both round half to even |
| `atan(y, x)` | `atan2(y, x)` | |
| `Float64(a)`, `Int64(x)`, … | `(double)a`, `(int64_t)x` | a cast |
| `round(Int64, x)`, `floor(Int64, x)`, … | `(int64_t)rint(x)`, … | |
| `pi`, `ℯ`, `Inf`, `NaN`, `Inf32`, `NaN32` | `M_PI`, `M_E`, `INFINITY`, `NAN` | from `math.h`; the macros serve both widths. `M_PI` and `M_E` are POSIX rather than ISO C — see the todo |
| `isnan`, `isinf`, `isfinite`, `signbit` | the same | `math.h` |
| `typemax(Int64)`, `typemin(Int32)`, `typemax(UInt8)` | `INT64_MAX`, `INT32_MIN`, `UINT8_MAX` | `stdint.h`; `typemin` of an unsigned type is `0` |
| `typemax(Float64)`, `typemin(Float64)` | `INFINITY`, `-INFINITY` | |
| `floatmax`, `floatmin`, `eps` of `Float64` / `Float32` | `DBL_MAX`, `DBL_MIN`, `DBL_EPSILON` / `FLT_…` | `float.h`; `eps(x)` of a value is not yet |
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
