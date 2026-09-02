# Flow

What ordinary Julia syntax the transpiler handles inside a function body, and
how control flow gets back its shape.

## Recovering structure

By the time the transpiler sees a function, Julia has lowered every `if`,
`while`, `for`, `&&`, `||`, and `?:` into jumps: `goto L` and `goto L if not
c`. Emitting those as C `goto`s would be correct and unreadable. Instead the
patterns Julia's lowering produces are recognised and emitted as the
constructs they came from — and anything that doesn't match is an error, never
a `goto`.

| Julia | what the IR looks like | C |
|---|---|---|
| `if c … end` | `goto L if not c`, body, `L:` | `if (c) { … }` |
| `if c … else … end` | then-block ends with a jump past the else-block | `if (c) { … } else { … }` |
| `elseif` | an else-block that is exactly one `if` ending at the same place | `} else if (c) {` |
| `a && b` in a condition | two tests failing to the same place | `if (a && b)` |
| `a \|\| b` in a condition | a test failing *into* another test, with a jump to the body between | `if (a \|\| b)` |
| `c ? x : y` | an `if` whose branches both return, or both assign | `if (c) { return x; } return y;` |
| `while c … end` | a header, a test to the exit, a jump back to the header | `while (c) { … }` |
| `while true` | the same with a literal `true` | `while (true) { … }` |
| `for i in a:b` | the `iterate`/`getfield` idiom around a body | `for (int64_t i = a; i <= b; i++)` |
| `for i in a:s:b` | same, with a literal step | `for (…; i <= b; i += s)` (`>=` for a negative step) |
| `for i in eachindex(v)`, `1:length(v)`, `axes(A, d)` | same; the bound comes from the array's size | `for (int64_t i = 1; i <= 3; i++)` |
| `for i in 1:2, j in 1:3` | nested loops; the inner loop re-binds `i` | nested `for`s, one `i` |
| `break`, `continue` | jumps to the loop's exit or its next-iteration point | `break;`, `continue;` |
| `return x` anywhere | a `ReturnNode` | `return x;` (`return;` in a void function) |

Loop variables are Julia's, 1-based, so an element read is `v[i - 1]`. Turning
`for (i = 1; i <= n; i++) v[i - 1]` into the C idiom `for (i = 0; i < n; i++)
v[i]` when `i` is only ever used as an index is a readability step still to
come.

**Conditions and bounds are expressions, not temps.** `while (temp1)` would
test a value computed once. So the calls that feed a test or a range bound —
single-use, side-effect free — are rendered inline, with C precedence and
parentheses handled (`operand` in `src/flow.jl`), rather than as the temps
everything else becomes. If a `while` header contains something that can't be
inlined, the loop becomes `while (true) { …; if (!(c)) break; … }`.

**Ranges** are only supported as the range of a `for`; a range stored in a
variable is an error. A range step must be a literal.

## Scalar operations

| Julia | C | note |
|---|---|---|
| `+ - * /` | `+ - * /` | integer `/` casts to floating; see `array.md` |
| `÷`, `%` | `/`, `%` | both truncate toward zero in both languages |
| `mod(a, b)` | `((a % b) + b) % b` | integers only |
| `x^2`, `x^3` | `x * x`, `x * x * x` | |
| `x^n`, `x^y` (floats) | `pow(x, n)` | integer `^` beyond 3 is an error |
| `< <= > >= == !=` | the same | |
| `!`, `&`, `\|`, `xor`, `<<`, `>>`, `~` | `!`, `&`, `\|`, `^`, `<<`, `>>`, `~` | |
| `sqrt sin cos tan asin acos atan sinh cosh tanh exp exp2 expm1 log log2 log10 log1p cbrt floor ceil trunc hypot copysign` | the same, from `math.h` | |
| `abs(x)` | `fabs(x)`; `llabs(x)` for `Int64` (`stdlib.h`) | |
| `max`, `min` on floats | `fmax`, `fmin` | |
| `max`, `min` on integers | `(a > b ? a : b)` | |
| `round(x)` | `rint(x)` | both round half to even |
| `atan(y, x)` | `atan2(y, x)` | |
| `Float64(a)`, `Int64(x)`, … | `(double)a`, `(int64_t)x` | a cast: Julia's `InexactError` is not reproduced |
| `round(Int64, x)`, `floor(Int64, x)`, … | `(int64_t)rint(x)`, … | |
| `pi`, `ℯ`, `Inf`, `NaN` | `M_PI`, `M_E`, `INFINITY`, `NAN` | from `math.h` |
| `length(v)`, `size(A, d)` | the number, since sizes are known | |

`math.h` and `stdlib.h` are included only when something above needs them.

## Arrays inside a body

| Julia | C |
|---|---|
| `v[i]`, `A[i, j]` | `v[i - 1]`, `A[i - 1][j - 1]`; literal indices are shifted at transpile time |
| `v[i] = x` | `v[i - 1] = x;` — a parameter written this way loses its `const` |
| `zeros(n)`, `zeros(m, n)`, `ones(…)`, `fill(x, …)` | a `fill_<dims>` helper; dimensions must be literal |

## Not yet

Slicing (`v[2:3]`), reductions other than `dot` (`sum`, `maximum`, `norm`),
tuples beyond the iterator internals, strings, printing, structs, closures,
`try`/`catch`, comprehensions, and ranges with a non-literal step.
Broadcasting, array literals, block construction, row vectors, `dot`, and
`cross` are covered in `array.md`.
