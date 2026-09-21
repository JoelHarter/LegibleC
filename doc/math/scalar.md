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
| `mod(a, b)` | `((a % b) + b) % b` by a small literal; otherwise `moduloI64(a, b)`; on floats `modulo(a, b)`. Helpers with Julia's definition | C's `%` and `fmod` take the dividend's sign, Julia's `mod` the divisor's |
| `zero(x)`, `one(x)`, `zero(Float64)` | `0.0`, `1.0` | the literal of the type |
| `s, c = sincos(x)` | `s = sin(x); c = cos(x);` | ISO C has no `sincos`; the compiler fuses the two calls. The pair itself is not a value: `t = sincos(x)` is refused |
| `x^2`, `x^3` | `x * x`, `x * x * x` | `x^0` is `1.0`, `x^1` is `x` |
| `x^-1` | `1.0 / x` | |
| `x^n`, any other literal `n` | `powi(x, n)`, one helper by squaring (`powiF32`, `powiI64` off the double) | the exponent is a literal at every call, so at `-O2` the compiler unrolls the helper into the bare multiply chain — five multiplies for `x^13`, no loop, no branch. Julia's `Float64^Int` is a compensated squaring, a bit more accurate; this is the plain one, three times faster |
| `x^y` (floats) | `pow(x, y)` | a negative power of an integer is a `DomainError` in Julia, and an error here |
| `< <= > >= == !=` | the same | |
| `!`, `&`, `\|`, `xor`, `~` | `!`, `&`, `\|`, `^`, `~` | |
| `<<`, `>>`, `>>>` | the same where the count is known to lie within the width, a literal or a loop's own variable; otherwise `shl(x, n)`, `shr`, `shru` | Julia defines every count, `5 << 64` is 0; C defines none outside the width |
| `&&`, `\|\|`, `c ? x : y` | the same, or an `if` — see `flow.md` | |
| `sqrt sin cos tan asin acos atan sinh cosh tanh exp exp2 expm1 log log2 log10 log1p cbrt floor ceil trunc hypot copysign` | the same, from `math.h`; the `f` family on a `Float32` (`sqrtf`, `fabsf`, `powf`) | |
| `'a'`, `c + 1`, `c - 'a'`, `Int(c)`, `Char(n)`, `isdigit(c)`, `uppercase(c)` | `'a'`, `c + 1`, `c - 'a'`, `(int64_t)c`, `(char)n`, `isdigit(c)`, `(char)toupper(c)` | a `Char` is an ASCII `char`; the `ctype.h` classes agree with Julia's on all 128, except `ispunct`, which is written with the nine characters Julia calls symbols taken out |
| `s == "abc"`, `length(s)`, `ncodeunits(s)`, `isempty(s)`, `s[i]` | `strcmp(s, "abc") == 0`, `utf8len(s)`, `(int64_t)strlen(s)`, `s[0] == '\0'`, `s[i - 1]` | a `String` is `const char *`, UTF-8 in both languages |
| `pi`, `ℯ`, `Base.MathConstants.γ`, `catalan`, your own `Base.@irrational` | `LEGIBLEC_PI`, `LEGIBLEC_E`, `LEGIBLEC_GAMMA`, `LEGIBLEC_CATALAN`, `LEGIBLEC_<NAME>` | any `AbstractIrrational`, by its symbol: a macro named after it, defined in the helper header to 128-bit precision, which the compiler rounds to the nearest double; the `posix` option writes POSIX's `M_PI` and `M_E` for π and ℯ instead |
| `abs(x)` | `fabs(x)`; `llabs(x)` for `Int64`, `abs(x)` for `Int32` (`stdlib.h`) | |
| `max`, `min` on floats | `maxN(a, b)`, `minN(a, b)`, a small helper | a NaN is kept, as in Julia; `fmax` and `fmin` drop it |
| `max`, `min` on integers | `(a > b ? a : b)` | |
| `round(x)` | `rint(x)` | both round half to even |
| `atan(y, x)` | `atan2(y, x)` | |
| `Float64(a)`, `Int64(x)`, … | `(double)a`, `(int64_t)x` | a cast |
| `round(Int64, x)`, `floor(Int64, x)`, … | `(int64_t)rint(x)`, … | |
| `Inf`, `NaN`, `Inf32`, `NaN32` | `INFINITY`, `NAN` | from `math.h`; the macros serve both widths |
| `isnan`, `isinf`, `isfinite`, `signbit` | the same | `math.h` |
| `typemax(Int64)`, `typemin(Int32)`, `typemax(UInt8)` | `INT64_MAX`, `INT32_MIN`, `UINT8_MAX` | `stdint.h`; `typemin` of an unsigned type is `0` |
| `typemax(Float64)`, `typemin(Float64)` | `INFINITY`, `-INFINITY` | |
| `floatmax`, `floatmin`, `eps` of `Float64` / `Float32` | `DBL_MAX`, `DBL_MIN`, `DBL_EPSILON` / `FLT_…` | `float.h`; `eps(x)` of a value is not yet |
| `length(v)`, `size(A, d)` | the number, since sizes are known | |

Headers are included only when something needs them.

## Two types

An expression has two types. Julia's, which inference gives. And C's, which
follows from C's own rules: a literal that fits is an `int`, whatever Julia
calls it; anything narrower than `int` is promoted to it; a signed operand
beside an unsigned one of its width is converted to unsigned. Julia computes
`a + b` in the type its promotion gives. C computes it in the type its
conversions give. Where the two differ and a value can tell, a cast is
written. `src/term.jl` holds the expression until it is printed, with both
types and how far the value can reach, and decides this in one place.

| Julia says | C says | what is written |
|---|---|---|
| `1 << k` is an `Int64` | `int` | the first operand is cast, which makes C's type Julia's: `(int64_t)1 << k` |
| `(a + 1) * 100000000` on a `UInt8` is an `Int64` | `a + 1` is an `int`, and so is the product | `(int64_t)(a + 1) * 100000000` |
| `a + 1` on a `UInt8` is an `Int64` | `int`, and 256 at most in both | `a + 1`: no value can tell |
| `a + b` on two `UInt8` wraps at 256 | `int` | the result is cast, which is the wrap: `(uint8_t)(a + b)` |
| `a + b + n`, two `UInt8` and an `Int64`: the first sum wraps | `int`, then `long` | `(uint8_t)(a + b) + n` |
| `div(a, -1)` on an `Int32` is an `Int64`, 2147483648 at most | `int`, which that overflows | `(int64_t)a / -1` |
| `u > m`, a `UInt32` and an `Int8`, compared as the numbers they are | `m` becomes unsigned, and -1 is 4294967295 | a type that holds both: `(int64_t)u > m` |
| `u > -1` and `u >= 0` on a `UInt32` are true, whatever `u` | the same, once cast | `true`: what the types alone decide is written as the truth value it is, since a compiler warns of a comparison that can only go one way |
| `n == x`, an `Int32` and a `Float32`, compared exactly | `n` is rounded to a `float`, exact to 2^24 | `(double)n == x` |
| `k < u`, an `Int64` and a `UInt64` | `k` becomes unsigned | refused: no type holds both |
| `max(u, k)`, a `UInt32` and an `Int32`: both converted to `UInt32` | the same | `(u > (uint32_t)k ? u : (uint32_t)k)`, said out loud since a compiler warns of the silent one |
| `max(x32, y64)` is a `Float64` | `fmaxf` would take two `float`s | the variant of the result, `maxN` |

"A value can tell" is a question of reach. Every integer expression knows the
least and greatest value it can have: a literal is itself, a variable is its
type's range, a sum is the sum of the ranges. A cast is written only where
that range leaves the type C computes in, or the type Julia wraps in.

`test/grid.jl` tries every scalar function on every pair of number types at
the values where the languages part ways, so a rule here is checked on all
of them. It reads the transpiler's own table of scalar functions
(`src/idiom.jl`, a row each), so a function is tried on every type the day
its row is added. That is how `ispunct` was caught: to Julia `$ + < = > ^ | ~`
and the backtick are symbols, to C they are punctuation.

## Where the languages differ

The philosophy asks for Julia's *logical intent*, not its bit pattern, so
rounding-level differences are accepted and these are the ones to know:

- **Integer overflow.** Julia wraps; C leaves signed overflow undefined.
  `-fwrapv` is part of the one compiler setting the C is written for
  ([guide/start.md](../guide/start.md)), and makes C wrap as Julia does.
- **Checks Julia makes and C doesn't.** `Int64(2.5)` throws in Julia and
  truncates in C; `div(1, 0)` throws in Julia and is undefined in C. Julia
  that throws never reaches C: the C is for the Julia that works.
- **An integer past 2^53 beside a `double`.** Julia compares the two numbers
  exactly. C rounds the integer to a `double` first, as both languages do
  in arithmetic. `9007199254740993 == 9007199254740992.0` is false in Julia
  and true in C. The exact form is a function's worth of C at every
  comparison of an integer with a float, so this one is left.
