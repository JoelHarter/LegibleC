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
   line is `d = expr` return `d` rather than the temp. The store itself still
   happens through the temp (`temp3 = expr; d = temp3;`) — see below.

## What's not done — the can of worms

- **Storing directly.** `double temp3_a_b_c = temp2 / 2; d = temp3_a_b_c;`
  should be `d = temp2 / 2;` when the temp has no other use. That's the same
  safety rule (the temp is an SSA value, so it's always safe) but requires
  deciding *at the temp's creation* that it will be consumed by a store, and
  emitting nothing there. Closely related to the next item.
- **Collapsing single-use temps into expressions.** `temp1 = a + b;
  temp2 = temp1 * c;` should be `temp2 = (a + b) * c` when `temp1` is used
  once. Always safe for SSA values; the work is precedence and
  parenthesization, and deciding when an expression has grown long enough
  that a named temp is *more* readable, not less.
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
