# Scalar functions that are one C expression of their arguments: one row each. The row says
# what it applies to, by the result's type and the arguments', and the C, with `{a}`, `{b}`,
# `{c}` for the arguments. Adding such a function is adding its row and a test.
#
# Also in the C: `{T}` the result's C type, `{U}` the unsigned type of the first argument's
# width, `{1}` the result type's one, `{pi}` the macro for π.
#
# `{h}` is a helper's name, for the few that are a small function of their own (`helper`).
#
# An argument that the C writes twice is an argument evaluated twice, so such a row's
# arguments are never written in place (`duplicates` reads that off the row).
struct Idiom
    f::Any
    applies::Function       # (result type, argument types) -> Bool
    c::String
    operand::Int            # the precedence the arguments are written at
    prec::Int               # the precedence of the whole
    header::String
    helper::Any             # (helpers, first argument's type) -> the helper's name, or `nothing`
end
Idiom(f, applies, c, operand, prec, header="") = Idiom(f, applies, c, operand, prec, header, nothing)

const idioms = Idiom[
    Idiom(Base.isodd,   (T, A) -> A[1] <: Base.BitInteger64,                         "{a} % 2 != 0", MUL, EQ),
    Idiom(Base.iseven,  (T, A) -> A[1] <: Base.BitInteger64,                         "{a} % 2 == 0", MUL, EQ),
    # `inv(x)` is `one(x) / x`, a float whatever `x` is.
    Idiom(Base.inv,     (T, A) -> T <: Union{Float32, Float64} && A[1] <: Union{Base.BitInteger64, Float32, Float64}, "{1} / {a}", MUL, MUL),
    # Julia's own definitions: `x * (π / 180)`, `x * (180 / π)`, with π rounded to the type first.
    Idiom(Base.deg2rad, (T, A) -> T === Float64 && A[1] === Float64,        "{a} * ({pi} / 180)", MUL, MUL),
    Idiom(Base.rad2deg, (T, A) -> T === Float64 && A[1] === Float64,        "{a} * (180 / {pi})", MUL, MUL),
    # `>>>` brings in zeros: C's `>>` on the unsigned type of the same width.
    Idiom(Base.:>>>,    (T, A) -> A[1] <: Signed && A[1] <: Base.BitInteger64 && A[2] <: Base.BitInteger64, "({T})(({U}){a} >> {b})", SHIFT, UNARY),
    Idiom(Base.:>>>,    (T, A) -> A[1] <: Unsigned && A[1] <: Base.BitInteger64 && A[2] <: Base.BitInteger64, "{a} >> {b}", SHIFT, SHIFT),
    Idiom(Base.eps,     (T, A) -> A[1] <: Union{Float32, Float64},          "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> ulphelper!(h, E)),
    # Both values are computed in Julia; they are arguments. C computes the one it takes,
    # which is the same thing only for values with no effect: one with an effect is
    # computed beforehand (`conditional`).
    Idiom(Base.ifelse,  (T, A) -> A[1] === Bool && T <: Union{Base.BitInteger64, Bool, Float32, Float64}, "{a} ? {b} : {c}", 4, 3),
    Idiom(Base.gcd,     (T, A) -> A[1] <: Base.BitInteger64 && A[1] === A[2],        "{h}({a}, {b})", 0, PRIMARY, "", (h, E) -> integerhelper!(h, :gcd, E)),
    Idiom(Base.lcm,     (T, A) -> A[1] <: Base.BitInteger64 && A[1] === A[2],        "{h}({a}, {b})", 0, PRIMARY, "", (h, E) -> integerhelper!(h, :lcm, E)),
    Idiom(Base.isqrt,   (T, A) -> A[1] <: Base.BitInteger64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> integerhelper!(h, :isqrt, E)),
    Idiom(Base.sind,    (T, A) -> A[1] === Float64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> degreehelper!(h, :sind)),
    Idiom(Base.cosd,    (T, A) -> A[1] === Float64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> degreehelper!(h, :cosd)),
    Idiom(Base.tand,    (T, A) -> A[1] === Float64,                         "{h}({a})", 0, PRIMARY, "math.h", (h, E) -> degreehelper!(h, :tand)),
]

function idiom(f, T, A)
    k = findfirst(r -> r.f === f && length(A) == count(p -> occursin(p, r.c), ("{a}", "{b}", "{c}")) && r.applies(T, A), idioms)
    return k === nothing ? nothing : idioms[k]
end

# Does the row write this argument more than once?
twice(r::Idiom, k) = count("{" * "abc"[k] * "}", r.c) > 1
# Is this argument computed only when C's `? :` takes its side?
conditional(r::Idiom, k) = r.f === Base.ifelse && k > 1

function written(sc::Scope, r::Idiom, T, args)
    isempty(r.header) || push!(sc.headers, r.header)
    A = valuetype(sc, args[1])
    text = r.c
    for (k, a) in enumerate(args)
        text = replace(text, "{" * "abc"[k] * "}" => r.operand == 0 ? expression(sc, a)[1] : operand(sc, a, r.operand; right=true))
    end
    r.helper === nothing || (text = replace(text, "{h}" => r.helper(sc.helpers, A)))
    occursin("{T}", text) && (text = replace(text, "{T}" => ctype(T)))
    occursin("{U}", text) && (text = replace(text, "{U}" => ctype(unsigned(A))))
    occursin("{1}", text) && (text = replace(text, "{1}" => value(sc, one(T))))
    occursin("{pi}", text) && (text = replace(text, "{pi}" => value(sc, π)))
    return text, r.prec
end
