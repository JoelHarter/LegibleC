# Julia identifiers -> valid C identifiers.
#
# Julia lets a name be nearly any Unicode; C allows only [A-Za-z0-9_] with no leading
# digit. Names are first put through compatibility decomposition (NFKD), which turns
# subscripts and superscripts into plain characters and splits accents off the letters
# they sit on. Then, character by character:
#
#   ASCII letters, digits, `_`    kept
#   Greek letters                  spelled out: ω -> omega, Ω -> Omega
#   combining marks and primes     named and appended to what they sit on: ẋ -> xdot, x̂ -> xhat
#   anything else                  U + its code point in hex: 🤠 -> U1F920
#
# A name that collides with a C keyword, or with another name in the same scope, gets
# `_` appended until it doesn't. The reserved words live in `reserved.jl`. A name that
# starts with `_` has its underscores moved to the end, since C reserves those. (Julia
# already forbids a leading digit, sub- or superscript, so nothing here can produce a
# name C rejects for starting wrong.)
#
# This applies to every Julia name that reaches C: variables, functions, types, fields —
# anything that has to be spelled in the output.

using Unicode

include("reserved.jl")

"""
    identifier(name) -> String

`name` converted to a valid C identifier by the rules at the top of `name.jl`.
Collisions are not handled here; see [`identifiers`](@ref).
"""
function identifier(name::AbstractString)
    s = join(piece(c) for c in Unicode.normalize(String(name), :NFKD))
    # C keeps every file-scope name that starts with `_` (and `_X…`, `__…` anywhere) for
    # itself, so leading underscores move to the end: `_x` -> `x_`, `__Foo` -> `Foo__`.
    m = match(r"^_+", s)
    m === nothing || (s = s[length(m.match)+1:end] * m.match)
    return s
end

"""
    identifiers(names) -> Vector{String}

C identifiers for a list of names that share a scope. Each is converted with
[`identifier`](@ref), then given a trailing `_` (repeatedly if needed) until it
matches neither a reserved word (`reserved.jl`), nor a name in `blocked` (the
generated helpers, on a second pass), nor any name earlier in the list.
"""
function identifiers(names; blocked=())
    taken = union(reserved, blocked)
    out = String[]
    for n in names
        s = identifier(n)
        while s in taken
            s *= "_"
        end
        push!(taken, s)
        push!(out, s)
    end
    return out
end

# The C spelling of one (decomposed) character.
function piece(c::Char)
    isascii(c) && (isletter(c) || isdigit(c) || c == '_') && return string(c)
    g = greek(c)
    g === nothing || return g
    c == '̀' && return "grave"
    c == '́' && return "acute"
    c == '̂' && return "hat"
    c == '̃' && return "tilde"
    c == '̄' && return "bar"
    c == '̆' && return "breve"
    c == '̇' && return "dot"
    c == '̈' && return "ddot"
    c == '̊' && return "ring"
    c == '̌' && return "check"
    c == '⃗' && return "vec"
    c == '⃛' && return "dddot"
    c == '′' && return "prime"
    c == '″' && return "dprime"
    c == '‴' && return "tprime"
    return "U" * uppercase(string(UInt32(c), base=16))
end

function greek(c::Char)
    names = ("alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota",
             "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi", "rho", "varsigma", "sigma",
             "tau", "upsilon", "phi", "chi", "psi", "omega")
    'α' <= c <= 'ω' && return names[c - 'α' + 1]
    'Α' <= c <= 'Ω' && c != '΢' && return uppercasefirst(names[c - 'Α' + 1])
    return nothing
end

"""
    mangled(name, instances) -> Vector{String}

C names for instances of one Julia function, all called `name`. A single instance
keeps the plain name. Several get per-argument descriptions appended, escalating
only as far as needed for the names to differ:

1. array dimensions — `f_3`, `f_2x3`, `f_4x3x4`; scalars contribute nothing
2. the type abbreviation after — `f_4x4F32`, `f_I64_I64` — except that a function
   whose arguments are all `F64` leaves the abbreviations off

See `doc/naming.md` and `doc/type.md`.
"""
function mangled(name::AbstractString, sigs)
    length(sigs) == 1 && return [name]
    for level in 1:2
        names = [join([name; filter(!isempty, [describe(T, level, alldouble(sig)) for T in sig])], "_")
                 for sig in sigs]
        allunique(names) && return names
    end
    throw(ArgumentError("two different methods of $name would have the same C signature: $(join(sigs, ", "))"))
end

# The mangled description of one argument type at a given level.
function describe(T::Type, level, alldouble)
    if T <: AbstractArray
        d = dims(T)
        level >= 2 && !alldouble && (d *= abbrev(eltype(T)))
        return d
    end
    return level >= 2 && !alldouble ? abbrev(T) : ""
end

# Are all of a signature's types Float64, counting an array by its element type?
alldouble(sig) = all(T -> (T <: AbstractArray ? eltype(T) : T) === Float64, sig)
