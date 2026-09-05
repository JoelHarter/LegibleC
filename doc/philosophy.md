# Philosophy

Three principles govern every decision in this project. When they seem to
conflict, the earlier one wins.

### 1. Speed

The C must run **as fast as C can possibly run**, while matching the
*logical intent* of the Julia it came from. Bit-for-bit agreement is not the
goal: rounding differences and the like are acceptable. Identical logic is
not negotiable. It's fine if reaching full speed needs an optimization flag
on the C compiler, as long as there is always one single, fixed setting under
which *everything* we emit runs as fast as it can; we never emit code that
needs one flag here and a different flag there.

### 2. Craft

The C should look **as if an experienced C programmer wrote it by hand** —
like the best C code looks. Not terse to the point of gibberish; quite the
opposite: expressive names, helpful comments, and an arrangement that makes
logical sense to a human, especially one who knows C. Nothing should betray
a machine's bookkeeping.

The same idea applies on the Julia side, where we control nothing but owe
the author something: **if the source was written in a very Julian way, we
always find a way to transpile it.** The constructs Julians reach for
constantly — `test ? yes : no`, `x < 0 && return 0.0`,
`for i in eachindex(v)`, `x, y = f(v)`, a dot on every operator — must each
have a C form, and when C has no direct counterpart, that form is whatever
a C expert would have written for the same intent. We aim to handle as much
Julia as possible, and we start with what hardcore Julians use most.

### 3. Generality

Whatever can be written for the general case **is written for the general
case**.

The thing written generally is a rule inside the transpiler: the logic that
decides how some kind of thing is handled. It is not a function in the Julia
we read, and not a function in the C we write. Those can be as many and as
specific as a program needs — `add_2x2`, `mul_2x2_2x3`, `cross_F32`, and a hundred more —
as long as one piece of transpiler logic produces all of them.

So: don't write a rule for matrices when a rule for arrays of any dimension
would have done the job. Don't write one rule for `Float64` and another for
`Int16` when the same rule serves both. Don't write one for real numbers and
another for complex. Those are the examples we've met so far, not the limits
of the idea; other places it applies will be imagined, or discovered along
the way, and get the same treatment.

One rule that covers every case is one rule to get right, one rule to read,
and one rule to trust.
