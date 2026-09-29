# Block

Where a variable is declared, and how Julia's scopes become C's blocks. The
companion to [naming.md](naming.md): this page decides *where* a variable
lives, that one what it is called, and the second leans on the first.

## Two languages, two ideas of scope

| | Julia | C |
|---|---|---|
| a function's body | one scope | one scope, the outer block |
| `if` / `else` | **no scope**: a variable assigned inside is the function's | a block: a declaration inside dies at `}` |
| `for`, `while`, `let` | **a scope**: a variable first assigned inside is new on every pass | a block |
| shadowing | inner hides outer | inner hides outer, silently |
| an array | a value | storage: a name is a place |

C hides an outer name behind an inner one without a word, so every mistake
here is silent: the C compiles and computes something else. Two were found
by compiling, not by reasoning, and both are in the tests:

```julia
const g = 10.0
function after(n)
    s = 0.0
    for k in 1:n
        g = Float64(k)      # the loop's own g, gone after the loop
        s += g
    end
    return s * g            # the global
end
```

Julia gives 60. With `double g;` declared above the loop, as every loop's
variable used to be, the leftover local captures the last line and the C
gives **18**. Declared inside the loop, where Julia has it, 60.

## The rule

> A variable is declared in the innermost block that holds every statement
> reading or assigning it, moved outward past any loop that carries its
> value from one pass to the next.

Too narrow, and a use falls outside the braces. Too wide, and the variable
outlives its Julia scope and can capture a later use of something else of
the same name. The rule is the narrowest place that is never too narrow.

What it gives:

- **A loop's own variables are declared in the loop.** `w = 2.0 * k` inside
  a `for` is `double w = 2.0 * k;` inside the braces, so two loops each
  have their `w`.
- **A variable assigned in an `if` and used after it is declared just above
  the `if`**, in the enclosing block. That is exactly Julia's meaning, since
  an `if` makes no scope.
- **A variable whose every use is inside one branch is declared in that
  branch**, at its first assignment: `double t = a * b;`, not a bare
  `double t;` floating above. Narrowing across an `if` is always safe:
  within one pass through the enclosing block a branch runs at most once,
  so nothing can be carried between two entries.
- **A variable a loop carries is declared outside it.**

```julia
local prev
for k in 1:n
    if n > 0
        if k > 1; s += prev; end     # reads the last pass's value
        prev = Float64(k)
    end
end
```

Every statement that touches `prev` is inside one branch inside the loop,
but declared there it would be made anew on each pass. The test (`carried`
in `src/flow.jl`) is: *can some pass read the variable before that pass has
assigned it?* It walks the pass's statements in order, and does not count on
an assignment made inside a nested block, since that block may not have run.
So it errs toward saying yes, and yes only costs a declaration one level
further out. It is checked on `while`, on a value an outer loop carries out
of an inner one, across `continue`, `break` and an early `return`.

Where a declaration can't go at the first assignment (the assignment is
deeper than the variable's block), it goes just above the construct in that
block that the assignment is inside, ahead of its source comment.

## Julia's own scope is not asked for

It would be the natural thing to ask, and the compiler doesn't say. Its
variables are numbered (slots), and two variables that share a name are two
slots, which says they are *different* and nothing about where each lives.
Its marker for "this variable is made anew here" (`NewvarNode`) is emitted
only when the variable might be read unassigned: an ordinary loop local has
none, a `let` leaves no trace at all, and a variable assigned in a branch
gets its marker at the top of the function. An earlier version counted that
marker as a use and declared every branch's variable at the top.

It turns out not to be needed. What makes a C scope wrong was never "it
differs from Julia's". It is one of two concrete things, too wide or carried,
and both are read off the statements. A variable Julia scopes to the whole
function, assigned before every read in each pass and never touched outside
the loop, sits inside the loop in C, narrower than Julia has it, and nothing
can tell. Julia's "new on every pass" is only observable through a closure
(not supported) or a read before assignment (Julia throws, so the code never
gets here).

## How the blocks are found

The `if`s of a function are only recognised as they are emitted
(`ifelse!` pattern-matches the jumps). So **a function is walked twice**
(`cfunction`). The first walk exists to find the blocks: `nested!` opens one
for every loop body and branch, recording the statements it holds, its parent
and whether it is a loop. From that, `homes` gives each variable its block.
The second walk writes the C with every declaration in place. Emission is
repeatable, which the tests check, so the two walks agree. The same first
walk is what [naming](naming.md#when-two-names-meet) reads.

## `let`

A bare block, `{ … }`, is a legal C statement that opens a scope, and the
idiom for limiting one. It is not an imitation of a Julia scope, it *is* one:
what is declared in it dies at the brace, the inner hides the outer, siblings
are independent.

```julia
a = x + 1.0
let a = 10.0, b = 2.0      # the inner a hides the outer
    x = x + a * b
end
let b = 5.0
    x = x + b
end
return x + a
```

```c
    double a = x + 1.0;
    // @lets.jl:4: let a = 10.0, b = 2.0      # the inner a hides the outer
    {
        double a = 10.0;
        double b = 2.0;
        x += a * b;
    }
    // @lets.jl:7: let b = 5.0
    {
        double b = 5.0;
        x += b;
    }
    return x + a;
```

**Cosmetics choose, proof decides.** The compiler's statements have no trace
of a `let`, so the source is the only thing that knows one was written
(`findlets` parses the function's text for `let … end` line ranges). But the
source only *proposes where the braces go*. Statements are emitted in order
with the braces between them, so what is inside a block is exact by
construction, whatever the line numbers claimed; and every declaration is
then placed by the rule above, against the blocks as they really are. A
variable of the function's that the `let` body assigns, and that is used
after it, is declared outside the braces. A wrong guess about a `let`'s
extent can cost a badly placed brace and nothing else: a bare block only
narrows the lifetime of what is declared in it.

A `let` that shares its line with other code, is used as a value (`y = let …
end`), or is written on one line proposes nothing, and comes out flat, its
variables named by the ordinary rule. Correct, just not as pretty.

## A loop's bound is read once

Julia builds a range once. C's `for` header reads its end on every pass.

```julia
for k in 1:n
    n -= 1
    s += k
end
```

Julia: 21 for `n = 6`. `for (k = 1; k <= n; k++) { n--; … }`: **6**. So a
bound the body can change is taken into a temp before the loop
(`boundchanges`): one that reads a variable the body assigns, or reads memory
(an element, a field) when the body may write memory at all, by a store or by
calling a function of the author's. A bound nothing changes stays in the
header, where it reads best. A bound that is a call was already taken out,
since in the header it would run on every pass.

## What isn't done

- A read on a path that never assigned the variable (`if c; x = 1.0; end;
  return x`) returns garbage in C. Julia throws there, so working code never
  reaches it; at most it deserves a refusal for the message.
- An assignment on both branches of an `if`, then a read, inside a loop:
  never carried, but the test doesn't pair the branches, so the variable is
  declared outside the loop. Correct, one level wider than it need be.
- Closures, which are the one way Julia's "new on every pass" can be seen.
