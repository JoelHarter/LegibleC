# Philosophy

These principles govern every decision in this project. When they seem to
conflict, the earlier one wins.

### 0. Logic

The C **carries out the Julia author's logical intent**: the same
calculation, by the same steps, in the same order, with the same results.
Rounding differences are fine — bit-for-bit agreement is not the goal.
Nothing below is worth anything without this.

### 1. Speed

The C runs **as fast as C can run**. That is the standard every choice is
held to, and nothing is left slower than it could be for the sake of anything
below. Reaching full speed may take an optimization flag on the C compiler;
there should be one single, fixed setting under which everything we emit runs
at full speed.

### 2. Craft

The C looks **as if an experienced C programmer wrote it by hand**: expressive
names, helpful comments, an arrangement that makes sense to a person. Nothing
betrays a machine's bookkeeping.

The person it is written for may not be a C programmer. They are good at
math, physics or engineering and may know Julia, MATLAB or Python instead —
so a matrix product reads as a matrix product and a solve as a solve, with
the mathematics visible in the names and comments. The C stays the best C it
can be; it is presented so that reader can see their own formulas in it.

The same care is owed to the Julia side: **whatever is written in a very
Julian way, we find a way to transpile.** `test ? yes : no`, `x < 0 && return
0.0`, `for i in eachindex(v)`, `x, y = f(v)`, a dot on every operator — each
has a C form, and where C has no direct counterpart, the form is what a C
expert would have written for the same intent. We start with what Julians
reach for most.

### 3. Generality

Whatever can be written for the general case **is written for the general
case**.

The transpiler is a set of rules, each deciding how one kind of thing is
handled, and each written for the whole kind: arrays of any dimension, not
matrices; numbers, not `Float64`; real and complex alike. The C a rule emits
can be as specific as it likes — `add_2x2`, `mul_2x2_2x3`, `cross_F32` and a
hundred more — so long as one rule produces them all.

The Julia a rule was written against is a sample, not the boundary: a case
nobody had in mind should already work, and usually does. Every decision is
then made in one place — one rule to get right, one to read, one to trust —
and the Julia we accept grows by the rule, not by the case.
