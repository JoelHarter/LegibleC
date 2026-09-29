# Struct

Structs and tuples. The C for both is a `typedef struct`, emitted once per
type ahead of everything else, with the fields declared by the same rules as
any variable (`double x;`, `double pos[3];`, a nested struct by value).

## Structs

An immutable `struct` is passed and returned **by value**, which is Julia's
semantics for it. `Point(x, y)` is `(Point){x, y}`; `p.x` is `p.x`;
`p == q` compares field by field; a struct with an array field is built field
by field, the array copied in, since C can't initialize an array member from
another array in a compound literal.

A `mutable struct` is a reference in Julia — two variables can hold the same
one — so in C it is always handled **through a pointer**: `Counter *c`,
`c->n`, and a function that returns the object it was given returns the
pointer. Creating a mutable struct inside transpiled code would need an
allocation and an ownership rule, so it's refused; the C caller owns those.

A method of a Julia operator on the struct — `Base.:*(a::Quaternion,
b::Quaternion)` — is the user's function, named the way a helper is, since
it is one: the operator's word and each input's kind, `mul_Quaternion_Quaternion`,
`mul_Quaternion_s`, and `add_Quaternion` for two of a kind, as `add_2x2`.
`a * b * c`, one call in Julia through its fold, is the two
binary calls. A struct built to be returned is the literal in the `return`,
`return (Point){x, y};`, broken one field per line when long; a small struct
value used once — a constructor, a call returning one — is written where it
is used, like a scalar. An array whose one use is a field of a struct or
tuple being built is computed straight into that field — `Quat(c, s * axis)`
is `mul_s_3(s, axis, result.v)`, no temp, no copy — when nothing between
the computation and the store can see the destination: not a statement in
between, not the value's own operands, not the construction's other
arguments, not a call handed the variable, not a `return` of it. Anything
that can, and the temp stays. A struct with an array field is built field by field
as above, but a call returning one is still written where it is used when
the whole struct goes there — `return conj_Quat(q);`, or as an argument to
another call — and gets a variable when a field of it is read, since
`f(q).v` reads a field of a temporary, which no one writes.

A parametric struct at a concrete instantiation is one C struct per
instantiation, named by the struct and its parameters run together:
`Pair2F64`, `Body3` (`naming.md`, *A type with parameters*). Field and type
names go through the usual conversion, which also drops the `!` from `bump!`.

Not yet: `@kwdef` constructors, structs holding mutable structs, `Union`
fields, `sizeof`.

## Tuples

A function that returns a tuple returns **its own struct**, named after the
function and with fields named after the variables it returns: `return x, ẋ`
in `step` gives `step_t` with `x` and `xdot`, and the return is the literal
`return (step_t){x, xdot};`. C returns small structs in registers and larger
ones through a hidden pointer the caller provides, so this costs what
output pointers would have cost, and it keeps the Julia's meaning: one value,
returned. At a call site `x, ẋ = step(…)` reads `step_t temp1_step =
step(…); x = temp1_step.x; ẋ = temp1_step.xdot;`, a tuple kept whole is
`step_t t = step(…)` with `t[2]` as `t.xdot`, and a function that returns
another's tuple straight on returns that function's struct. When what is
returned isn't plain variables — `(v, 2.0 * v)`, or returns that disagree —
the fields are positional letters and the struct is the structural
`Tuple3xx3`.

A **tuple parameter** is spread into one parameter per element:
`third(t::NTuple{3,Float64})` is `double third(double t1, double t2, double
t3)`, and `t[1]` inside is `t1`. A tuple built only to be passed to a
function goes as its elements, `third(a, 2 * a, 3 * a)`, so no struct is
made for it; a tuple that only feeds a constructor or block construction —
`SVector(a, b, c)`, `[A B; C D]` — never exists in C either. A tuple held as
a value elsewhere — a struct field, a tuple of tuples — is the structural
`TupleF64xI64` with fields `a`, `b`, … named like helper inputs.

Not yet: a `NamedTuple`, which would name the fields when what's returned
isn't variables.

## A property the author defines

`q.x` is a field read only while `getproperty` is Julia's own. A method of
the author's, `getproperty(q::Quaternion, s::Symbol) = s === :x ? q.v[1] : …`,
takes the property's name at run time, and C has no way to pass a name. Such
a read, and a `setproperty!` of the author's, is refused by field, with the
advice to write what the method computes or to read the field itself with
`getfield`. A C function per property, the method's body with the name
folded in, is the way to support it later.
