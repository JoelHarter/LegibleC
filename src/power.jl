# x to an integer power, by squaring: one definition, for every type.
#
# It is written once, here, in Julia, and the transpiler translates it for whatever type a
# power is asked of: a `double`, an `int64_t`, a complex number, a 3×3 matrix, a struct of the
# author's that has a `*`. Nothing about a type is said here. What `x * x` is, what `one(x)` is
# and what `inv(x)` is are whatever they already are for that type, the author's own methods
# included. A new kind of thing that can be multiplied can be raised to a power the day it can
# be multiplied.
#
# The order of the products is that of Julia's own `power_by_squaring`, so the rounding is too.

# `x^n` for `n` not below zero.
function powi(x, n::Int64)
    n == 0 && return one(x)
    # Square while the power is even, and start the result there.
    while iseven(n)
        x = x * x
        n >>= 1
    end
    y = x
    n >>= 1
    # For each bit left: square, and multiply in where the bit is set.
    while n > 0
        x = x * x
        if isodd(n)
            y = y * x
        end
        n >>= 1
    end
    return y
end

# `x^n` for any `n`, where the type has an inverse of its own kind: a negative power is that
# power of the inverse, as it is in Julia.
function powinv(x, n::Int64)
    if n < 0
        x = inv(x)
        n = -n
    end
    n == 0 && return one(x)
    # Square while the power is even, and start the result there.
    while iseven(n)
        x = x * x
        n >>= 1
    end
    y = x
    n >>= 1
    # For each bit left: square, and multiply in where the bit is set.
    while n > 0
        x = x * x
        if isodd(n)
            y = y * x
        end
        n >>= 1
    end
    return y
end

# The program a table of helpers belongs to: a helper written by translating Julia needs the
# whole program, and most helper generators are handed the table alone.
const programs = IdDict{Any, Any}()

"""
    powerhelper!(helpers, T) -> name

The C function that raises a `T` to an integer power, `powi(x, n)`, `powiF32`, `powiI64`,
`powi_3x3(A, n, out)`, `powi_Quat(q, n)`: `powi` or `powinv` above, translated for `T`. A type
with an inverse of its own kind takes negative powers; an integer, whose inverse is a float,
doesn't, and neither does Julia. For a scalar or an array it is a helper like any other. For a
struct of the author's it is a function beside the author's own, since it calls their `*`.
"""
function powerhelper!(helpers::Dict{String, String}, T::Type)
    prog = programs[helpers]
    J = T <: Shaped ? T : juliatype(T)
    E = isarray(T) ? eltype(T) : T
    inverse = isstruct(T) ? hasmethod(inv, Tuple{T}) && Base.promote_op(inv, T) === T : E <: Union{AbstractFloat, Complex}
    f = inverse ? powinv : powi
    spec = T <: Shaped ? Any[eltype(T), shape(T)..., Int64] : Any[J, Int64]
    mi, sig = any(x -> x isa Integer, spec) ? resolve(f, spec) : (m = Base.method_instance(f, Tuple(spec)); (m, argtypes(m)))
    if isstruct(T)
        haskey(prog.calls, mi) && return prog.calls[mi]
        name = claim!(prog, mi, "powi_" * structname(T), "powi")
        prog.calls[mi] = name
        push!(prog.pending, (mi, sig, name))
        return name
    end
    name = isarray(T) ? helpername(:powi, (T,)) : "powi" * (T === Float64 ? "" : abbrev(T))
    haskey(helpers, name) && return name
    helpers[name] = ""                                  # it is being written
    walking = prog.walking
    _, _, body, _ = cfunction(name, mi, sig, prog; source=false)
    prog.walking = walking
    # A function of the author's has a blank line between statements. A helper is closer set:
    # one is kept only above a comment.
    rows = split(body, "\n")
    body = join((r for (k, r) in enumerate(rows) if !(isempty(r) && k < length(rows) && !startswith(lstrip(rows[k+1]), "//"))), "\n") * "\n"
    what = isarray(T) ? describe(T) : T === Float64 ? "a scalar" : T <: AbstractFloat ? "a float" : T <: Complex ? "a complex number" : "an integer"
    doc = "/// $what to an integer power, by squaring\n/// " * (isarray(T) ? "out = xⁿ" : "returns x^n") * "\n"
    helpers[name] = doc * (isarray(T) ? "" : "static inline ") * body
    return name
end
