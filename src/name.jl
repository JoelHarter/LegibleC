# Julia identifiers -> valid C identifiers.
#
# Julia lets a name be nearly any Unicode; C allows only [A-Za-z0-9_] with no leading
# digit. A name is converted character by character:
#
#   a character in the user's `spelling`   its entry (`transpile(…; spelling=Dict('ħ' => "hred"))`)
#   otherwise, after compatibility decomposition (NFKD), which turns subscripts,
#   superscripts, fractions and font variants into plain characters and splits an
#   accent off the letter it sits on, each resulting character is:
#     an ASCII letter, digit or `_`        kept
#     in `overrides`                        that spelling: ε -> epsilon, ∇ -> nabla
#     in Julia's own table                  what one types after `\` to get it: ω -> omega,
#                                           ħ -> hbar, ∂ -> partial, ̇ -> dot, 🤠 -> facewithcowboyhat
#     anything else                         U + its code point in hex
#
# The table is the REPL's `\name<tab>` completion list, LaTeX and emoji — the names the
# author typed to get the characters, so the C says what the Julia said. A character with
# several names takes the shortest; `overrides` holds the few where that
# isn't the spelling a reader wants. A name is stripped to its letters and digits —
# underscores too, since the name stands for one indivisible character — and if what's
# left doesn't start with a letter, the hex fallback applies.
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
using REPL: REPLCompletions

include("reserved.jl")

# Julia's table, inverted: each identifier character to the shortest name that reaches
# it (alphabetically first among equals), made C-safe. Built once, when the package loads.
const spelled = let table = Dict{Char, String}()
    names = Dict{Char, Vector{String}}()
    for (k, v) in REPLCompletions.latex_symbols
        length(v) == 1 && Base.is_id_char(only(v)) && push!(get!(names, only(v), String[]), k[2:end])
    end
    for (k, v) in REPLCompletions.emoji_symbols
        length(v) == 1 && Base.is_id_char(only(v)) && push!(get!(names, only(v), String[]), strip(k[2:end], ':'))
    end
    for (c, ns) in names
        clean = replace(sort(ns; by=n -> (length(n), n))[1], r"[^A-Za-z0-9]" => "")
        occursin(r"^[A-Za-z]", clean) && (table[c] = clean)
    end
    table
end

# Where the table's first name isn't the spelling a reader wants. (After NFKD, ϵ is ε
# and ϕ is φ, so these cover both forms.)
const overrides = Dict('ε' => "epsilon", 'φ' => "phi", '∇' => "nabla", 'ð' => "eth",
                       '👍' => "thumbsup", '👎' => "thumbsdown", '🔢' => "box1234", '💯' => "hundred", '♂' => "mars", '̶' => "strike")

# The user's own spellings for the current `transpile` call, checked by `checkspelling`.
const spelling = Ref(Dict{Char, String}())

# The module the current `transpile` call was written in (its `scope`): names in it are
# bare; names elsewhere carry their module path, relative to it.
const scope = Ref{Module}(Main)

# The C base name of a method: an operator's word — `*` is `mul`, `+` is `add` — since C
# has no operator overloading; anything else its own name.
const operators = Dict(:* => "mul", :+ => "add", :- => "sub", :/ => "div", :\ => "ldiv", :^ => "pow", :(==) => "eq",
                       :!= => "ne", :< => "lt", :<= => "le", :> => "gt", :>= => "ge", :! => "not",
                       :adjoint => "adjoint", :transpose => "transpose", :conj => "conj")
fname(name::Symbol) = get(operators, name, string(name))

# The C name of a user's method of a Julia operator, by the helper scheme: the
# operator's word, then each input's kind — a struct's name, an array's shape, `s` for
# a scalar — `mul_Quaternion_Quaternion`, `mul_Quaternion_s`; `add` and `sub` (and the
# comparisons) on two of a kind write it once, `add_Quaternion`, as `add_2x2` does.
function operatorname(name::Symbol, sig)
    haskey(operators, name) || return string(name)
    piece(T) = isstruct(T) ? structname(T) : T <: AbstractArray ? dims(T) : "s"
    pieces = [piece(T) for T in sig]
    once = name in (:+, :-, :(==), :!=, :<, :<=, :>, :>=) && allequal(pieces)
    return operators[name] * "_" * (once ? pieces[1] : join(pieces, "_"))
end

"""
    qualified(name, mod) -> String

The C name of `name` defined in module `mod`, as seen from the call's `scope`: the
name itself for something in the scope, otherwise the module path in front, joined
with `_` — `Physics.c` is `Physics_c` from `Main`, and `c` from inside `Physics`;
`Earth.Orbit.a` is `Earth_Orbit_a` from `Main` and `Orbit_a` from inside `Earth`. `Main`
contributes nothing, being the program. Collisions that survive get `_` like any other.
"""
function qualified(name::AbstractString, mod::Module)
    path = [String(s) for s in fullname(mod)]
    here = [String(s) for s in fullname(scope[])]
    isempty(path) || path[1] != "Main" || popfirst!(path)
    isempty(here) || here[1] != "Main" || popfirst!(here)
    k = 0
    while k < length(path) && k < length(here) && path[k+1] == here[k+1]
        k += 1
    end
    return join([identifier.(path[k+1:end]); identifier(name)], "_")
end

"""
    identifier(name) -> String

`name` converted to a valid C identifier by the rules at the top of `name.jl`.
Collisions are not handled here; see [`identifiers`](@ref).
"""
function identifier(name::AbstractString)
    # Julia's trailing `!` marks a function that mutates its argument; C has no such
    # mark, so it's dropped: `bump!` -> `bump`.
    name = String(name)
    endswith(name, "!") && (name = name[1:end-1])
    # The user's spelling is consulted for the character as written and again for what
    # it decomposes into, so `'²' => "sq"` and `'ε' => "eps"` (which then covers ϵ) both work.
    user = spelling[]
    s = join(haskey(user, c) ? user[c] : join(get(user, d, piece(d)) for d in Unicode.normalize(string(c), :NFKD)) for c in name)
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
    haskey(overrides, c) && return overrides[c]
    haskey(spelled, c) && return spelled[c]
    return "U" * uppercase(string(UInt32(c), base=16))
end

# The user's `spelling`: single characters Julia allows in a name, none of them an
# ASCII letter, digit or `_` (those are themselves), each spelled as a C identifier piece.
function checkspelling(d::AbstractDict)
    for (c, name) in d
        c isa Char || throw(ArgumentError("spelling: keys are single characters, got $(repr(c))"))
        Base.is_id_char(c) || throw(ArgumentError("spelling: $(repr(c)) can't appear in a Julia name"))
        isascii(c) && (isletter(c) || isdigit(c) || c == '_') && throw(ArgumentError("spelling: $(repr(c)) is already itself in C"))
        name isa AbstractString && occursin(r"^[A-Za-z0-9_]+$", name) || throw(ArgumentError("spelling: $(repr(c)) => $(repr(name)) isn't C identifier text"))
    end
    return Dict{Char, String}(d)
end

"""
    mangled(name, instances) -> Vector{String}

C names for instances of one Julia function, all called `name`. A single instance
keeps the plain name. Several get per-argument descriptions appended, escalating
only as far as needed for the names to differ:

1. array dimensions — `f_3`, `f_2x3`, `f_4x3x4`; scalars contribute nothing
2. the type abbreviation after — `f_4x4F32`, `f_I64_I64` — except that a function
   whose arguments are all `F64` leaves the abbreviations off

See `doc/naming.md` and `doc/math/scalar.md`.
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
    (isstruct(T) || istuple(T)) && return structname(T)
    if T <: AbstractArray
        d = dims(T)
        level >= 2 && !alldouble && (d *= abbrev(eltype(T)))
        return d
    end
    return level >= 2 && !alldouble ? abbrev(T) : ""
end

# Are all of a signature's types Float64, counting an array by its element type?
alldouble(sig) = all(T -> (T <: AbstractArray ? eltype(T) : T) === Float64, sig)
