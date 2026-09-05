# Flow

How control flow gets its shape back.

By the time the transpiler sees a function, Julia has lowered every `if`,
`while`, `for`, `&&`, `||`, and `?:` into jumps: `goto L` and `goto L if not
c`. Emitting those as C `goto`s would be correct and unreadable. Instead the
patterns Julia's lowering produces are recognised and emitted as the
constructs they came from — and anything that doesn't match is an error,
never a `goto`.

| Julia | what the IR looks like | C |
|---|---|---|
| `if c … end` | `goto L if not c`, body, `L:` | `if (c) { … }` |
| `if c … else … end` | then-block ends with a jump past the else-block | `if (c) { … } else { … }` |
| `elseif` | an else-block that is exactly one `if` ending at the same place | `} else if (c) {` |
| `a && b` in a condition | two tests failing to the same place | `if (a && b)` |
| `a \|\| b` in a condition | a test failing *into* another test, with a jump to the body between | `if (a \|\| b)` |
| `a && b`, `a \|\| b` as a value | the same tests, both branches assigning | `bool r = a && b;` |
| `x < 0 && return 0.0` | a test and an early return | `if (x < 0.0) { return 0.0; }` |
| `c ? x : y` | an `if` whose branches both return, or both assign | `if (c) { return x; } return y;` |
| `while c … end` | a header, a test to the exit, a jump back to the header | `while (c) { … }` |
| `while true` | the same with a literal `true` | `while (true) { … }` |
| `for i in a:b` | the `iterate`/`getfield` idiom around a body | `for (int64_t i = a; i <= b; i++)` |
| `for i in a:s:b` | same, with a literal step | `for (…; i <= b; i += s)` (`>=` for a negative step) |
| `for i in eachindex(v)`, `1:length(v)`, `axes(A, d)` | same; the bound comes from the array's size | `for (int64_t i = 1; i <= 3; i++)` |
| `for x in v` over a vector's elements | the same idiom on the array itself | `for (int64_t i = 0; i < 3; i++) { double x = v[i]; …` — a 0-based index Julia never named; over a matrix, not supported (Julia's order is column-major) |
| `for i in 1:2, j in 1:3` | nested loops; the inner loop re-binds `i` | nested `for`s, one `i` |
| `break`, `continue` | jumps to the loop's exit or its next-iteration point | `break;`, `continue;` |
| `return x` anywhere | a `ReturnNode` | `return x;` (`return;` in a void function) |

Loop variables are Julia's, 1-based, so an element read is `v[i - 1]`.
Turning `for (i = 1; i <= n; i++) v[i - 1]` into the C idiom
`for (i = 0; i < n; i++) v[i]` when `i` is only ever used as an index is a
readability step still to come.

**Conditions and bounds are expressions, not temps.** `while (temp1)` would
test a value computed once. So the calls that feed a test or a range bound —
single-use, side-effect free — are rendered inline, with C precedence and
parentheses handled (`operand` in `src/flow.jl`), rather than as the temps
everything else becomes. If a `while` header contains something that can't
be inlined, the loop becomes `while (true) { …; if (!(c)) break; … }`.

**Ranges** exist only as the range of a `for` or a literal index
(`v[2:4]`); a range stored in a variable is an error, and a step must be a
literal.

Not yet: `for x in A` over a matrix's elements, `try`/`catch`, comprehensions,
closures, `do` blocks, `@goto`.

Implementation: `findfors`, `findwhiles`, `markinlined!`, `block!` in
`src/flow.jl`.
