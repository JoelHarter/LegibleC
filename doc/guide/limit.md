# Limit

What the transpiler does not do.

Every size is known at transpile time; nothing is allocated. There are no
strings built at run time, no function pointers, no `try`, no growing arrays, and no
Julia runtime on the C side. Results agree with Julia to rounding, not bit
for bit.

An integer past 2^53 compared with a `Float64` is rounded to it first, as C
does; Julia compares the two exactly. Everything else about numbers is in
[math/scalar.md](../math/scalar.md).
