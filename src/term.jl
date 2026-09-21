# An expression, until it is written.
#
# It has two types. Julia's, which inference gives. And C's, which follows from C's own rules:
# a literal that fits is an `int`, anything narrower than `int` is promoted to it, a signed
# operand beside an unsigned one of its width is converted to unsigned. Julia computes `a + b`
# in the type its promotion gives, C in the type its conversions give, and where the two
# differ and a value can tell, a cast is written. That is decided here and nowhere else
# (`arithmetic`, `compared`, `choice`).
#
# "A value can tell" is a question about how far an integer can reach. `a + 1` on a `uint8_t`
# is an `int` in C and an `Int64` in Julia, and at most 256 in both: nothing to write. Times
# `100000000` it is past what an `int` holds: `(int64_t)(a + 1) * 100000000`.
#
# What an expression is made of stays known until it is printed, so that questions about it
# are asked of its parts and not of its text: is it `x + e`, for `x += e`; does it end in a
# literal, for `v[i + 1]` as `v[i]`; is it more than names and operators.
struct Term
    kind::Symbol            # :atom, :number, :prefix, :binary, :cast, :choice, :call, :paren, :text
    text::String            # a name, a number as written, an operator's sign, a cast's type, a function's name; for :text, the C itself
    parts::Vector{Term}
    julia::Any              # the type Julia gives the value
    c::Any                  # the type C computes it in, as the Julia type of that width and sign
    prec::Int
    reach::Any              # the least and greatest value an integer can have here, or `nothing`
end

# C's precedence levels.
const PRIMARY, UNARY, MUL, ADD, SHIFT, REL, EQ, BAND, BXOR, BOR, LAND, LOR, COND = 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3

# Every value a type has, for the integers C has, a truth value and a character.
limits(T) = T === Bool ? (big(0), big(1)) : T === Char ? (big(0), big(0x10ffff)) :
           T isa DataType && T <: Base.BitInteger64 ? (big(typemin(T)), big(typemax(T))) : nothing
fits(reach, T) = (w = limits(T); reach !== nothing && w !== nothing && w[1] <= reach[1] && reach[2] <= w[2])
magnitude(reach) = max(abs(reach[1]), abs(reach[2]))

# C does its arithmetic on nothing narrower than `int`.
promoted(C) = C === Bool || C === Char || C isa DataType && C <: Base.BitInteger64 && sizeof(C) < 4 ? Int32 : C

# The type C converts two operands to before it computes: floating before integer, the wider
# before the narrower, and unsigned before signed unless the signed type holds every value of
# the unsigned one. `nothing` for anything that isn't a plain number.
function common(A, B)
    A, B = promoted(A), promoted(B)
    all(X -> X isa DataType && X <: Union{Base.BitInteger64, Float32, Float64}, (A, B)) || return nothing
    (A === Float64 || B === Float64) && return Float64
    (A === Float32 || B === Float32) && return Float32
    A === B && return A
    (A <: Signed) == (B <: Signed) && return sizeof(A) >= sizeof(B) ? A : B
    U, S = A <: Unsigned ? (A, B) : (B, A)
    return sizeof(U) >= sizeof(S) ? U : S
end

# C text the transpiler composed by hand, of a given precedence: a call, a helper, a macro.
# Its type in C is the type it is declared with, which is Julia's.
Term(text::AbstractString, prec::Int, J; c=J, reach=limits(J)) = Term(:text, String(text), Term[], J, c, prec, reach)

# A name, or a number as C writes it. An integer literal is an `int` if it fits one, whatever
# Julia's type for it: `1` is an `Int64` there. `-5` is a minus sign and a `5`.
function atom(text::AbstractString, J)
    v = J isa DataType && J <: Integer ? tryparse(BigInt, text) : nothing
    if v !== nothing
        C = abs(v) <= typemax(Int32) ? Int32 : abs(v) <= typemax(Int64) ? Int64 : UInt64
        return Term(:number, String(text), Term[], J, C, v < 0 ? UNARY : PRIMARY, (v, v))
    end
    return Term(:atom, String(text), Term[], J, J, startswith(text, "-") ? UNARY : PRIMARY, limits(J))
end

paren(t::Term) = Term(:paren, "", [t], t.julia, t.c, PRIMARY, t.reach)

# `(int64_t)x`. The value is kept where it fits, and wraps where it doesn't.
cast(J, t::Term) = Term(:cast, ctype(J), [t], J, J, UNARY, fits(t.reach, J) ? t.reach : limits(J))

call(name::AbstractString, args, J) = Term(:call, String(name), collect(Term, args), J, J, PRIMARY, limits(J))

# Would it be written without brackets as an operand of an operator of precedence `prec`?
# It is bracketed if it binds less tightly, and on the right at equal precedence (left
# associativity). Under a shift or a bitwise operator any other operator is bracketed, and
# `&&` under `||`: C's precedence there is what nobody remembers, a person writes
# `(a & b) | (c << 2)`, and clang warns without the brackets.
bare(t::Term, prec; right::Bool=false) = !(t.prec < prec || (right && t.prec == prec) || (prec in (SHIFT, BAND, BXOR, BOR) && t.prec < UNARY && t.prec != prec) || (prec == LOR && t.prec == LAND))
within(t::Term, prec; right::Bool=false) = bare(t, prec; right) ? string(t) : "($t)"

function Base.print(io::IO, t::Term)
    if t.kind === :binary
        a, b = t.parts
        print(io, within(a, t.prec), " ", t.text, " ", within(b, t.prec; right=!(t.text in ("&&", "||"))))
    elseif t.kind === :prefix
        print(io, t.text, within(t.parts[1], UNARY))
    elseif t.kind === :cast
        print(io, "(", t.text, ")", within(t.parts[1], UNARY))
    elseif t.kind === :paren
        print(io, "(", t.parts[1], ")")
    elseif t.kind === :choice
        # The condition is bracketed unless it is a comparison or a single thing: `(a | b) ? x : y`,
        # `(b * c) ? p : q`, as a person writes it and as clang asks.
        c, a, b = t.parts
        print(io, c.prec >= UNARY || c.prec in (REL, EQ) ? string(c) : "($c)", " ? ", within(a, COND + 1), " : ", within(b, COND + 1))
    elseif t.kind === :call
        print(io, t.text, "(", join(t.parts, ", "), ")")
    else
        print(io, t.text)
    end
end
Base.show(io::IO, t::Term) = print(io, "Term(", string(t), " :: ", t.julia, " in Julia, ", t.c, " in C", t.reach === nothing ? "" : ", $(t.reach[1]) to $(t.reach[2])", ")")

# Is it names, numbers and operators only? Anything else, a call or a choice, is work
# done again each time it is written.
simple(t::Term) = t.kind in (:atom, :number) || t.kind in (:binary, :prefix, :cast, :paren) && all(simple, t.parts) || t.kind === :text && !occursin("(", t.text)

# Does it call nothing, however it is put together?
callfree(t::Term) = t.kind === :call ? false : t.kind === :text ? !occursin(r"\w\(", t.text) : all(callfree, t.parts)

# Does its text begin with a minus sign: `-x`, `-3`, `-x * y`?
leading(t::Term) = t.kind === :prefix ? t.text == "-" : t.kind === :binary ? bare(t.parts[1], t.prec) && leading(t.parts[1]) :
                   t.kind in (:number, :atom, :text) && startswith(t.text, "-")

# The same without it, for `a + -b` written `a - b` and `-(-x)` written `x`.
function positive(t::Term)
    flipped = t.reach === nothing ? nothing : (-t.reach[2], -t.reach[1])
    t.kind === :prefix && return bare(t.parts[1], UNARY) ? t.parts[1] : paren(t.parts[1])
    t.kind === :binary && return Term(:binary, t.text, [positive(t.parts[1]), t.parts[2]], t.julia, t.c, t.prec, flipped)
    return Term(t.kind, t.text[2:end], t.parts, t.julia, t.c, PRIMARY, flipped)
end

# How far `a sym b` can reach, as the numbers they are, before any type wraps it.
function ranged(sym, a::Term, b::Term)
    (a.reach === nothing || b.reach === nothing) && return nothing
    (al, ah), (bl, bh) = a.reach, b.reach
    sym == "+" && return (al + bl, ah + bh)
    sym == "-" && return (al - bh, ah - bl)
    sym == "*" && (p = (al * bl, al * bh, ah * bl, ah * bh); return (min(p...), max(p...)))
    if sym == "/"
        bl > 0 && (q = (div(al, bl), div(al, bh), div(ah, bl), div(ah, bh)); return (min(q...), max(q...)))
        return (-magnitude(a.reach), magnitude(a.reach))            # by anything else: no further than the dividend, either way
    elseif sym == "%"
        m = max(min(magnitude(a.reach), magnitude(b.reach) - 1), 0)         # the dividend's sign, and short of the divisor
        return (al < 0 ? -m : big(0), ah > 0 ? m : big(0))
    elseif sym in ("&", "|", "^")
        al >= 0 && bl >= 0 && sym == "&" && return (big(0), min(ah, bh))
        bits = big(2)^maximum(v -> ndigits(v >= 0 ? v : -v - 1; base=2), (al, ah, bl, bh))       # both fit in this many bits and a sign, so the result does
        return al >= 0 && bl >= 0 ? (big(0), bits - 1) : (-bits, bits - 1)
    elseif sym == ">>"
        return (min(al, 0), max(ah, 0))
    elseif sym == "<<"
        bl == bh && 0 <= bl < 64 && return (al << Int(bl), ah << Int(bl))
        return (big(typemin(Int64)), big(typemax(UInt64)))              # by a count not known: anywhere
    end
    return nothing
end

"""
    arithmetic(sym, prec, a, b, J) -> Term

`a sym b`, whose value in Julia has type `J`, with the casts that make C compute what Julia
does. Julia converts both operands to `J` and computes there. C converts them to a type of its
own choosing (`common`). Where C's is narrower and the value can outgrow it, the first operand
is cast, which makes C's type `J`: `(int64_t)1 << k`, `(int64_t)ms * 1000`. Where Julia's is
narrower than an `int` and the value can outgrow it, the result is cast, which is the wrap
Julia does: `(uint8_t)(a + b)`. With `wrap=false` that last cast is left to the caller, who is
about to make it anyway (`a + b + c` on three `uint8_t` is one cast, not two).
"""
function arithmetic(sym, prec, a::Term, b::Term, J; wrap::Bool=true)
    shift = sym in ("<<", ">>")
    C = shift ? promoted(a.c) : common(a.c, b.c)
    R = ranged(sym, a, b)
    if !(J isa DataType && J <: Base.BitInteger64 && C !== nothing && C <: Integer && R !== nothing)
        return Term(:binary, sym, [a, b], J, C, prec, sym in ("<", "<=", ">", ">=", "==", "!=", "&&", "||") ? limits(Bool) : limits(J))
    end
    sym == "/" && (w = limits(J); R = (max(R[1], w[1]), min(R[2], w[2])))       # a quotient that leaves Julia's type is a DivideError there
    if sizeof(C) < sizeof(J) && !fits(R, C)
        a = cast(J, a)
        C = shift ? J : common(J, b.c)
    end
    t = Term(:binary, sym, [a, b], J, C, prec, fits(R, J) ? R : limits(J))
    return wrap && sizeof(J) < sizeof(C) && !fits(R, J) ? cast(J, t) : t
end

# `-a`, `~a`, `!a`, by the same rule.
function prefix(sym, a::Term, J)
    sym == "!" && a.kind === :prefix && a.text == "!" && return a.parts[1]            # `!(!a)` is `a`: Julia's `!` takes a truth value only
    sym == "!" && return Term(:prefix, sym, [a], Bool, Bool, UNARY, limits(Bool))
    sym == "-" && leading(a) && bare(a, UNARY) && return positive(a)                  # `-(-x)` is `x`, exactly
    C = promoted(a.c)
    R = a.reach === nothing ? nothing : sym == "-" ? (-a.reach[2], -a.reach[1]) : (-a.reach[2] - 1, -a.reach[1] - 1)
    J isa DataType && J <: Base.BitInteger64 && C isa DataType && C <: Integer && R !== nothing || return Term(:prefix, sym, [a], J, C, UNARY, limits(J))
    if sizeof(C) < sizeof(J) && !fits(R, C)
        a = cast(J, a)
        C = J
    end
    t = Term(:prefix, sym, [a], J, C, UNARY, fits(R, J) ? R : limits(J))
    return sizeof(J) < sizeof(C) && !fits(R, J) ? cast(J, t) : t
end

"""
    compared(sym, prec, a, b, i) -> Term

A comparison. Julia compares two numbers as the numbers they are, whatever their types. C
converts both to one type first, and `-1 < 1u` is false there. Where that type doesn't hold
every value either side can have, the side that forces it is cast to one that does:
`(int64_t)u > -1`, and `(double)n < x` for an integer beside a `float`, which is exact only to
2^24. Where no type holds both, a `uint64_t` beside something that can be negative, it is
refused: there is no C operator that means what Julia means.

An integer past 2^53 beside a `double` is rounded to it first, in C. Julia compares exactly.
That one is left as it is, and said in the guide: the exact form is a function's worth of C
at every comparison of an integer with a float.
"""
function compared(sym, prec, a::Term, b::Term, i)
    M = common(a.c, b.c)
    if M !== nothing && M <: Integer && !(fits(a.reach, M) && fits(b.reach, M))
        fits(a.reach, Int64) && fits(b.reach, Int64) ||
            throw(ArgumentError("a comparison between a signed and an unsigned integer ($(a.julia), $(b.julia)): Julia takes them as the numbers they are, C converts the signed one to unsigned first, and a negative one goes wrong. Convert one side so that both are alike, `Int64(u)` or `UInt64(s)` (statement $i)"))
        promoted(a.c) <: Unsigned && (a = cast(Int64, a))
        promoted(b.c) <: Unsigned && (b = cast(Int64, b))
    elseif M === Float32
        inexact(t) = t.reach !== nothing && magnitude(t.reach) > 2^24
        inexact(a) && (a = cast(Float64, a))
        inexact(b) && (b = cast(Float64, b))
    end
    return Term(:binary, sym, [a, b], Bool, Bool, prec, limits(Bool))
end

# `c ? a : b`. C converts the two sides to one type, as it does the operands of `+`.
function choice(c::Term, a::Term, b::Term, J)
    C = common(a.c, b.c)
    if J isa DataType && J <: Base.BitInteger64 && C !== nothing && C <: Integer && !(fits(a.reach, C) && fits(b.reach, C))
        a = cast(J, a)
        C = common(J, b.c)
    end
    reach = a.reach === nothing || b.reach === nothing ? limits(J) : (min(a.reach[1], b.reach[1]), max(a.reach[2], b.reach[2]))
    return Term(:choice, "?", [c, a, b], J, C === nothing ? J : C, COND, reach)
end
