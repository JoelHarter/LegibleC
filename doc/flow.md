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
| `a && b`, `a \|\| b`, `c ? x : y` as a value | a hidden variable stored on both sides of a test, read once where they meet | `bool ok = a && b;`, `sqrt(c ? x : y)` — see below |
| `if a && (b \|\| c)` | the inner part is such a value, then an ordinary test | `if (a && (b \|\| c))` |
| `x < 0 && return 0.0` | a test and an early return | `if (x < 0.0) { return 0.0; }` |
| `return c ? x : y` | an `if` whose branches both return | `if (c) { return x; } return y;` |
| `while c … end` | a header, a test to the exit, a jump back to the header | `while (c) { … }` |
| `while true` | the same with a literal `true` | `while (true) { … }` |
| `for i in a:b` | the `iterate`/`getfield` idiom around a body | `for (int64_t i = a; i <= b; i++)` |
| `for i in a:s:b` | same, with a literal step | `for (…; i <= b; i += s)` (`>=` for a negative step) |
| `for i in eachindex(v)`, `1:length(v)`, `axes(A, d)` | same; the bound comes from the array's size | `for (int64_t i = 1; i <= 3; i++)` |
| `for x in v` over a vector's elements | the same idiom on the array itself | `for (int64_t i = 0; i < 3; i++) { double x = v[i]; …` — a 0-based index Julia never named; over a matrix, not supported (Julia's order is column-major) |
| `for i in 1:2, j in 1:3` | nested loops; the inner loop re-binds `i` | nested `for`s, one `i` |
| `for k in 1:n` where the body changes `n` | Julia builds the range once | the bound in a temp before the loop — see [block.md](block.md) |
| `for k in 1:n` where the body assigns `k` | lasts for the pass; the next pass gets the range's next value | `for (int64_t i = 1; i <= n; i++) { int64_t k = i; …` — the counting is an index of ours, as for `for x in v` |
| `for x in v` where the body gives `v` a new value | Julia goes on through the array it began with | the loop reads a copy made before it |
| `while a && b`, `while a \|\| b` | the same merged tests an `if` opens with | `while (a && b)` |
| `break` inside `for i in 1:n, j in 1:m` | leaves the whole nest, which C's `break` doesn't | a flag the outer loops test, `i <= n && !done`, set before the inner `break`; with the `goto` option, `goto done;` and a label after the nest |
| `let a = …` … `end` | no trace in the lowered code; found in the source | a bare block, `{ … }` — see [block.md](block.md) |
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
`src/flow.jl`; the structure itself in `src/tree.jl`.

## What Julia has already decided

A test whose answer inference already has, `if usefast()` on a function that
returns `true`, `x isa Float64` on a `Float64`, `if typemax(Float64) == 0.0`, is
not written. Julia has dropped the branch that can't run, so the one that runs
stands alone in the C, and a trait function that costs nothing in Julia costs
nothing in C. The Julia line still stands above it as a comment. A condition
with an effect is still computed; a function that was only asked about, and is
never called, is not brought into the output. A loop's own tests always stay.

The same goes for a variable nothing ever reads, the author's `t = 2x` with no
`t` after it, or the `val` that `@inbounds s += v[k]` leaves behind: its stores
are not written, nor is what was computed only for them, unless that has an
effect. In C it would be a variable declared, set, and warned about.

Implementation: `analyze!` in `src/c.jl` (`sc.folded`, `sc.gone`).

A type parameter compared with a number, `if T == 0` in a function `where T`,
is decided the moment the type is chosen, so each instantiation gets the
branch that is its own and no `if`: `b += 2;` for `Obj{0}`, `b += 3;` for
`Obj{1}`.

## A value that a test chooses

`a && b`, `a || b` and `c ? x : y` are lowered the same way wherever a value is
wanted: Julia makes a variable of its own, stores into it on both sides of a
test, and reads it once where the sides meet. C has the same three operators,
with the same order of evaluation and the same promise that only the chosen side
is evaluated. So the value is written as one expression where it is used:

```c
bool ok = a && (b || n > 3);
double w = (k > 2 && a > 0.0) ? a : 2.0 * a;
return sqrt(c ? x : 2.0 * x);
```

This is also what makes `if a && (b || c)` an ordinary condition. Julia lowers
the inner part as such a value, so by the time the `if` is looked at it has two
tests, `a` and a value, like any `a && b`.

It applies only when each side is an expression and nothing more. A side with
work of its own, an array helper say, keeps its `if` and `else`. Nothing in it
may have an effect either, since the expression is written a little later than
where Julia computed it. When the value can't go inside what uses it, because it
is read twice or because the consumer writes its operand twice (`(c ? x : y)^2`),
it goes on one line into a temp: `double temp1 = c ? x : y;`.

Whether a choice can be an expression is decided together with what is written
inline, since it is the same question, and each depends on the other: a value may
move past a choice that is an expression and not past one that is an `if`. Every
choice is supposed to hold, the marking is done, the ones that turned out not to
hold are dropped, and the marking is done again until none is dropped.

Implementation: `src/choice.jl`, and `markinlined!` in `src/flow.jl`.

A function may end on such an assignment, `b = a > 0 ? 3 : 4` as its last
line, the value being the function's. Julia lowers that with its own
variable read twice and `b` never read, where `return b` afterwards gives
one read and a store of it. The two mean the same, so the first is put in
the second's shape before anything else looks at it (`canonical!` in
`src/c.jl`), and both come out as `int64_t b = a > 0 ? 3 : 4; return b;`.

## The structure is recovered first, and checked

The C used to be written *while* the structure was being worked out: `block!` met
a jump and decided, there and then, what construct it opened. That was compact,
and it is where the mistakes were. An adversarial hunt over loops (2026-09-20)
found seven wrong answers here and none in the code that was new that week, and
four of them had one cause: a helper that answers "what is the next statement that
matters" (`nextlive`) by skipping what is consumed elsewhere, used where the
question was really "where does control go".

Now the whole function's structure is recovered before any C is written
(`recover` in `src/tree.jl`): every `if` with its merged tests, its branches and
where it ends, every `while`, every `break` and `continue`. `block!` writes C from
that and decides nothing. Before it does, the structure is checked three ways,
and whatever fails is refused by line:

| check | what it catches |
|---|---|
| every jump in the function belongs to exactly one construct | a loop the walk went past, a test taken for something else |
| nothing jumps into the middle of a branch, a loop or a choice | two constructs that overlap |
| each way out of each test goes where the C written for it would go | a condition whose parts can't be one C condition |

The third check is the independent one. `place` follows the lowered code and
nothing else: past every statement that does nothing, along every plain jump, to
the first statement that does something. Two statements are the same place
exactly when that is equal. For each test of an `if` or a `while`, the place the
lowered code goes when it holds and when it fails is compared with where the C
would go: the next test, the body, the `else`, what follows. A loop's own working
is never "nothing": looking through it is how "falls into the next pass" and
"leaves the loop" came to look like one place.

## A part of a condition that needs lines of its own

`if a && sum(x .* x) > 1.0 … else … end`: the second part is array work, which
has no place inside a C condition. Without the `else`, nesting says it: `if (a) {
…; if (…) { … } }`. With an `else`, a failed second test must reach it, and
nesting would lose it. So the condition is worked out into a truth value first,
part by part in Julia's order, stopping where Julia stops:

```c
bool temp1 = a;
if (temp1) {
    double temp2[3];
    mulP_3_3(x, x, temp2);
    temp1 = sum_3(temp2) > 1.0;
}
if (temp1) {
    r = 10.0;
} else {
    r = 20.0;
}
```

For `||` the next part runs only if the ones before it failed, `if (!temp1) { … }`.
In a `while` whose parts are joined by `&&` there is no need for the name: each
part in turn, and `break` as soon as one fails. Parts that need no lines stay
together in one expression, as they always were.

The parts are found by the same walk that merges `a && b` (`tests` in
`src/flow.jl`). What tells a part's working-out from the first statements of the
body is that it is nothing but the working-out of an expression: calls, reads,
stores into variables of Julia's own making, and jumps that stay among them. A
store into a variable of the author's, a loop or a `return` is the body. The
nested form is kept wherever it goes where the lowered code goes, so this is
written only where nothing else would be right.
