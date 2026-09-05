# Copy

How the transpiler eliminates copies, and the conditions under which doing so
is safe. This is deliberately a small topic right now; the section at the end
lists what's been left for later.

## Where copies come from

Julia's lowered IR is in SSA form: every intermediate value gets its own
numbered slot, and named variables are read into and written from those
slots explicitly. So `d = a; d = d + 1.0` lowers to something like

```
%1 = a          read a
%2 = (d = %1)   store into d; %2 is the value stored
%3 = d          read d back
%4 = %3 + 1.0
%5 = (d = %4)
```

Emitted literally, every one of those reads and stores would be a C
statement with its own temp. None of them are computation; they're
bookkeeping. The C a person would write is `d = a; d = d + 1.0;`.

## The rule

**A copy of a value may be replaced by the thing it copies, at a given use,
if the thing it copies still holds the same value at that use.**

For SSA values that's always true — an SSA value is assigned exactly once and
never changes — so a pure SSA-to-SSA copy (`%8 = %6`) is always forwarded and
never emitted.

For a *variable* it's true only if the variable is not reassigned between
the point of the copy and the point of the use. That's the entire safety
condition, and it's what `stable` in `src/c.jl` checks: for SSA value `i`
standing for variable `x`, every statement that uses `%i` is examined, and
if any assignment to `x` sits between the copy and that use, the copy is
kept as a real temp.

## What's done today

All of this is straight-line only — see below.

1. **Reads.** `%i = x` becomes nothing; uses of `%i` say `x`. Kept as a
   temp (`temp3_x = x`) only when `x` is reassigned before some use.
2. **Stores.** `%i = (x = rhs)` emits `x = rhs;`, and uses of `%i` say `x`,
   under the same condition.
3. **SSA aliases and literals.** `%i = %j` and `%i = 5` are forwarded
   unconditionally.
4. **Temp stored into a variable.** After `x = temp3;` where `x` is stable,
   later uses of `temp3` say `x`. This is what makes a function whose last
   line is `d = expr` return `d` rather than the temp.
5. **Unnamed scalar values are written where they are used.** `d = (a + b) *
   c / 2` is `double d = (a + b) * c / 2;`, and `sqrt(sq(a) + sq(b))` is
   exactly that: a scalar SSA value with one use is rendered inside its
   consumer, never as a temp. The rule mirrors the author — what they named
   is named, what they didn't isn't — which is also the answer to "when is a
   named temp more readable": the author already decided. Precedence is
   handled by `render`, which returns every expression with its C precedence
   level so `operand` can parenthesise (with extra parentheses under a shift
   or bitwise operator, and around `&&` under `||`, where a person adds them
   too). A `return` is a consumer like any other: `return sqrt(sq(a) +
   sq(b));`. Two exceptions keep a temp:
   - **a consumer that writes its operand twice** — `x^2` is `x * x`, `mod`,
     integer `max` and `min`, `==` on a struct — since a call evaluated twice
     costs twice;
   - **an effect in the way**: C leaves the order of a call's arguments and
     an operator's operands unspecified, so a value may move only past work
     that can't notice. A pure value moves past pure work; a value carrying
     an effect — a print, a store, a `setindex!`, a `ccall`, a user function
     that does any of those, read off the callee's own IR transitively
     (`effects!` in `src/flow.jl`) — moves past nothing that computes, not
     even a read. So in `mutate!(v, 1.0) + mutate!(v, 2.0) + v[1]` both calls
     are pinned as temps in Julia's order, and `shout(a) + shout(b)` comes
     out `temp1_a + shout(b)`.
   `markinlined!` in `src/flow.jl` decides; conditions and loop bounds were
   its first consumers and follow the same rule.

   A line that would run past the `width` option (100 columns) is wrapped at
   the operators binding least tightly, each continuation line starting with
   the operator, aligned under the first operand — `emitexpr!` in
   `src/c.jl`. A one-line Julia expression is otherwise a one-line C
   expression, however long.

## What's not done

- **Control flow** turned out not to be a problem for the rule. The `stable`
  check walks statements textually, and that is sound for Julia's lowering
  because it is *structured*: every statement executed between a value's
  definition and a use of it lies between them in the statement list too
  (jumps only skip forward within a construct or return to a loop's header,
  and a value defined inside one iteration is never used in the next — that
  goes through a variable). The unoptimized IR has no phi nodes; branches
  meet through variables, which the check already accounts for.
- **Multiple returns.** Related: `result` (or `out`) is currently claimed once per
  function; with several return paths it needs to be declared once and
  assigned on each path.

None of these change the rule. They change how much of the program the rule
can see.
