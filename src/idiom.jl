# Scalar functions that are one C expression of their arguments: one row each. The row says
# what it applies to, by the result's type and the arguments', and the C, with `{a}`, `{b}`,
# `{c}` for the arguments. Adding such a function is adding its row: `test/grid.jl` reads this
# table, and tries every row on every combination of number types the day it is added.
#
# Also in the C: `{T}` the result's C type, `{U}` the unsigned type of the first argument's
# width, `{1}` the result type's one, `{pi}` the macro for π, and `{m:sqrt}` a `math.h` name
# in the variant of the result, `sqrtf` on a `float`, `csqrt` on a complex.
#
# `{h}` is a helper's name, for the few that are a small function of their own (`helper`).
#
# An argument that the C writes twice is an argument evaluated twice, so such a row's
# arguments are never written in place (`duplicates` reads that off the row).
struct Idiom
    f::Any                  # the function, or `:Module => :name` for one in a package that isn't loaded here
    applies::Function       # (result type, argument types) -> Bool
    c::String
    operand::Int            # the precedence the arguments are written at
    prec::Int               # the precedence of the whole
    header::String
    helper::Any             # (helpers, first argument's type) -> the helper's name, or `nothing`
end
Idiom(f, applies, c, operand, prec, header="") = Idiom(f, applies, c, operand, prec, header, nothing)

# What `math.h` takes: a result that is floating or complex, or a complex argument.
mathematical(T, A) = (T <: Union{Float32, Float64, ComplexF32, ComplexF64} || any(X -> X <: Complex, A)) && all(X -> X <: Number, A)
real64(X) = X <: Union{Base.BitInteger64, Bool, Float32, Float64}

const idioms = Idiom[
    # `math.h`, by the same names. Julia rounds half to even, and so does `rint`.
    [Idiom(getfield(Base, g), mathematical, "{m:$g}({a})", 0, PRIMARY, "math.h") for g in
        (:sqrt, :cbrt, :sin, :cos, :tan, :asin, :acos, :atan, :sinh, :cosh, :tanh, :exp, :exp2, :expm1, :log, :log2, :log10, :log1p, :floor, :ceil, :trunc)]...,
    Idiom(Base.round,    mathematical, "{m:rint}({a})", 0, PRIMARY, "math.h"),
    Idiom(Base.abs,      (T, A) -> T <: Union{Float32, Float64}, "{m:fabs}({a})", 0, PRIMARY, "math.h"),
    Idiom(Base.atan,     mathematical, "{m:atan2}({a}, {b})", 0, PRIMARY, "math.h"),
    # `SpecialFunctions`' own, known by name since the package isn't loaded here: what `math.h` has.
    Idiom(:SpecialFunctions => :gamma,    (T, A) -> T <: Union{Float32, Float64} && real64(A[1]), "{m:tgamma}({a})", 0, PRIMARY, "math.h"),
    Idiom(:SpecialFunctions => :loggamma, (T, A) -> T <: Union{Float32, Float64} && real64(A[1]), "{m:lgamma}({a})", 0, PRIMARY, "math.h"),
    Idiom(:SpecialFunctions => :erf,      (T, A) -> T <: Union{Float32, Float64} && real64(A[1]), "{m:erf}({a})", 0, PRIMARY, "math.h"),
    Idiom(:SpecialFunctions => :erfc,     (T, A) -> T <: Union{Float32, Float64} && real64(A[1]), "{m:erfc}({a})", 0, PRIMARY, "math.h"),
    Idiom(Base.hypot,    mathematical, "{m:hypot}({a}, {b})", 0, PRIMARY, "math.h"),
    Idiom(Base.copysign, (T, A) -> T <: Union{Float32, Float64} && all(real64, A), "{m:copysign}({a}, {b})", 0, PRIMARY, "math.h"),
    # `abs` of an integer: nothing to do for one that can't be negative, else `stdlib.h`'s by
    # width. `abs` returns an `int`, and Julia's `abs(Int8(-128))` wraps back to -128.
    Idiom(Base.abs,      (T, A) -> T === Int64, "llabs({a})", 0, PRIMARY, "stdlib.h"),
    Idiom(Base.abs,      (T, A) -> T === Int32, "abs({a})", 0, PRIMARY, "stdlib.h"),
    Idiom(Base.abs,      (T, A) -> T <: Union{Int8, Int16}, "({T})abs({a})", 0, UNARY, "stdlib.h"),
    # Classification of a floating value: macros that take any floating type, so no `f` forms.
    [Idiom(getfield(Base, g), (T, A) -> A[1] <: Union{Float32, Float64}, "$g({a})", 0, PRIMARY, "math.h") for g in (:isnan, :isinf, :isfinite, :signbit)]...,
    # Characters: the `ctype.h` classes and cases. Julia's classes are Unicode-aware and C's are
    # ASCII; for the ASCII characters `char` can hold they agree, the grid having tried all 128.
    [Idiom(g, (T, A) -> A[1] === Char, "$name({a})", 0, PRIMARY, "ctype.h") for (g, name) in
        ((Base.isdigit, "isdigit"), (Base.isletter, "isalpha"), (Base.isspace, "isspace"), (Base.isuppercase, "isupper"), (Base.islowercase, "islower"),
         (Base.isnumeric, "isdigit"), (Base.iscntrl, "iscntrl"), (Base.isprint, "isprint"), (Base.isxdigit, "isxdigit"))]...,
    # Except here. To Julia `\$ + < = > ^ \` | ~` are symbols, not punctuation; to C they are punctuation.
    Idiom(Base.ispunct,   (T, A) -> A[1] === Char, "ispunct({a}) && !strchr(\"\$+<=>^`|~\", {a})", 0, LAND, "ctype.h string.h"),
    Idiom(Base.isascii,   (T, A) -> A[1] === Char, "(unsigned char){a} < 128", UNARY, REL),
    Idiom(Base.uppercase, (T, A) -> A[1] === Char, "(char)toupper({a})", 0, UNARY, "ctype.h"),
    Idiom(Base.lowercase, (T, A) -> A[1] === Char, "(char)tolower({a})", 0, UNARY, "ctype.h"),
    Idiom(Base.isodd,   (T, A) -> A[1] <: Base.BitInteger64,                         "{a} % 2 != 0", MUL, EQ),
    Idiom(Base.iseven,  (T, A) -> A[1] <: Base.BitInteger64,                         "{a} % 2 == 0", MUL, EQ),
    # `inv(x)` is `one(x) / x`, a float whatever `x` is.
    Idiom(Base.inv,     (T, A) -> T <: Union{Float32, Float64} && A[1] <: Union{Base.BitInteger64, Float32, Float64}, "{1} / {a}", MUL, MUL),
    Idiom(Base.inv,     (T, A) -> T === ComplexF64 && A[1] === ComplexF64, "1.0 / {a}", MUL, MUL),
    Idiom(Base.inv,     (T, A) -> T === ComplexF32 && A[1] === ComplexF32, "1.0f / {a}", MUL, MUL),
    # Julia's own definitions: `x * (π / 180)`, `x * (180 / π)`, with π rounded to the type first.
    Idiom(Base.deg2rad, (T, A) -> T === Float64 && A[1] === Float64,        "{a} * ({pi} / 180)", MUL, MUL),
    Idiom(Base.rad2deg, (T, A) -> T === Float64 && A[1] === Float64,        "{a} * (180 / {pi})", MUL, MUL),
    Idiom(Base.eps,     (T, A) -> A[1] <: Union{Float32, Float64},          "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> ulphelper!(h, E)),
    # Both values are computed in Julia; they are arguments. C computes the one it takes,
    # which is the same thing only for values with no effect: one with an effect is
    # computed beforehand (`conditional`).
    Idiom(Base.ifelse,  (T, A) -> A[1] === Bool && T <: Union{Base.BitInteger64, Bool, Float32, Float64}, "{a} ? {b} : {c}", 4, 3),
    Idiom(Base.gcd,     (T, A) -> A[1] <: Base.BitInteger64 && A[1] === A[2],        "{h}({a}, {b})", 0, PRIMARY, "", (h, E) -> integerhelper!(h, :gcd, E)),
    Idiom(Base.lcm,     (T, A) -> A[1] <: Base.BitInteger64 && A[1] === A[2],        "{h}({a}, {b})", 0, PRIMARY, "", (h, E) -> integerhelper!(h, :lcm, E)),
    Idiom(Base.isqrt,   (T, A) -> A[1] <: Base.BitInteger64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> integerhelper!(h, :isqrt, E)),
    # `n!` from a table, as Julia's is: 20! is the last that fits.
    Idiom(Base.factorial, (T, A) -> A[1] <: Base.BitInteger64,                       "{h}({a})", 0, PRIMARY, "stdio.h stdlib.h", (h, E) -> factorialhelper!(h, E)),
    Idiom(Base.sind,    (T, A) -> A[1] === Float64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> degreehelper!(h, :sind)),
    Idiom(Base.cosd,    (T, A) -> A[1] === Float64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> degreehelper!(h, :cosd)),
    Idiom(Base.tand,    (T, A) -> A[1] === Float64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> degreehelper!(h, :tand)),
]

# Is `f` the function this row is for: the function itself, or one of that name in that package?
named(r::Idiom, f) = r.f isa Pair ? f isa Function && nameof(f) === r.f[2] && nameof(parentmodule(f)) === r.f[1] : r.f === f

function idiom(f, T, A)
    T isa DataType && all(X -> X isa DataType, A) || return nothing       # a union of number types is no one C type
    k = findfirst(r -> named(r, f) && length(A) == count(p -> occursin(p, r.c), ("{a}", "{b}", "{c}")) && r.applies(T, A), idioms)
    return k === nothing ? nothing : idioms[k]
end

# Does the row write this argument more than once?
twice(r::Idiom, k) = count("{" * "abc"[k] * "}", r.c) > 1
# Is this argument computed only when C's `? :` takes its side?
conditional(r::Idiom, k) = r.f === Base.ifelse && k > 1

function written(sc::Scope, r::Idiom, T, args)
    foreach(h -> push!(sc.headers, h), split(r.header))
    if r.f === Base.ifelse
        c, a, b = (expression(sc, x) for x in args)
        side(t) = t.prec == LOR ? paren(t) : t
        return choice(c, side(a), side(b), T)
    end
    A = valuetype(sc, args[1])
    text = r.c
    for (k, a) in enumerate(args)
        o = r.operand == 0 ? string(expression(sc, a)) : operand(sc, a, r.operand; right=true)
        text = replace(text, "{" * "abc"[k] * "}" => o)
    end
    r.helper === nothing || (text = replace(text, "{h}" => r.helper(sc.helpers, A)))
    if (m = match(r"\{m:(\w+)\}", text)) !== nothing
        k = findfirst(a -> valuetype(sc, a) <: Complex, args)             # a complex argument names its own: `cabs` of a complex gives a real
        V = k !== nothing ? valuetype(sc, args[k]) : T <: AbstractFloat ? T : A
        text = replace(text, m.match => mathname(V, m[1]))
    end
    occursin("{T}", text) && (text = replace(text, "{T}" => ctype(T)))
    occursin("{U}", text) && (text = replace(text, "{U}" => ctype(unsigned(A))))
    occursin("{1}", text) && (text = replace(text, "{1}" => value(sc, one(T))))
    occursin("{pi}", text) && (text = replace(text, "{pi}" => value(sc, π)))
    return text, r.prec
end
