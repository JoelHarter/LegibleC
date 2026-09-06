# Limit

What the transpiler does not do.

Every size is known at transpile time; nothing is allocated. There are no
strings built at run time, no closures, no `try`, no growing arrays, and no
Julia runtime on the C side. Results agree with Julia to rounding, not bit
for bit. The open list is `doc/dev/todo.md`.
