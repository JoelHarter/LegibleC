# newt

A Julia-to-C transpiler.

## Philosophy

Three principles govern every decision in this project. When they seem to
conflict, the earlier one wins.

### 1. The C runs as fast as it possibly can

Transpiled C should be as fast and as efficient as C can be, while matching the
**logical intent** of the Julia it came from. Bit-for-bit agreement is not the
goal: rounding differences and the like are acceptable. Identical logic is not
negotiable.

It is fine if reaching full speed requires an optimization flag on the C
compiler — as long as there is always a single, fixed setting under which
*everything* we emit runs as fast as it can. We never emit code that needs one
flag here and a different flag there.

### 2. The C reads as if a human wrote it

The output is generated code. It must not *look* like generated code. Someone
reading it should see the program a careful C programmer would have written by
hand: natural names, natural expressions, nothing that betrays a machine's
bookkeeping.

### 3. Generalize whatever can be generalized

Code that can be written for the general case is written for the general
case. Don't write one specific matrix function when a generic
any-dimensional array function would have done the job. A rule that covers
vectors, matrices, and higher-dimensional arrays alike is one rule to get
right, one rule to read, and one rule to trust.
