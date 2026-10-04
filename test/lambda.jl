# A function as a value: handed to another function, made on the spot with what it captured,
# given a name, returned, a struct called as one; and handed to Julia's own, `sum(abs, v)`,
# `map`, `any`, a `do` block, a generator, where it becomes the loop.
module Lambda
using Test, StaticArrays
import Main: Case, check, csource

const V3 = SVector{3,Float64}
const V4 = SVector{4,Float64}

# ---- handed to a function of the author's ----------------------------------------------
f(x) = x^2 - 2.0
df(x) = 2.0x
function newton(f, df, x)
    for i in 1:20
        x -= f(x) / df(x)
    end
    return x
end
root1(x0::Float64) = newton(f, df, x0)                               # two named functions
root2(a::Float64, x0::Float64) = newton(x -> x^2 - a, x -> 2x, x0)   # a capture, and none
root3(a::Float64, b::Float64, x0::Float64) = newton(x -> x^2 - a * b, x -> 2x, x0)
twice(f, x) = f(f(x))
thru(g, x) = twice(g, x) + 1.0                                       # only passed on: Julia compiles no `thru` for it by itself
level(a::Float64, x::Float64) = thru(y -> a * y, x)
several(x::Float64) = twice(f, x) + twice(sin, x) + twice(y -> y + 1, x)
samecapture(a::Float64, x::Float64) = twice(y -> y + a, x) * twice(y -> y * a, x)
rec(f, n::Int, x) = n == 0 ? x : rec(f, n - 1, f(x))
recursive(x::Float64) = rec(y -> y / 2, 3, x)
swap(x::Float64) = twice(t -> (t[2], t[1] + 1), (x, 2x))             # a tuple in and out
function rk4(f, x0, y0, x1, n)
    h = (x1 - x0) / n
    x = x0; y = y0
    for i in 1:n
        k1 = h * f(x, y)
        k2 = h * f(x + h / 2, y + k1 / 2)
        k3 = h * f(x + h / 2, y + k2 / 2)
        k4 = h * f(x + h, y + k3)
        y += (k1 + 2k2 + 2k3 + k4) / 6
        x += h
    end
    return y
end
decay(x, y) = -2.0 * y + x
ode1(y0::Float64) = rk4(decay, 0.0, y0, 1.0, 10)
ode2(y0::Float64, c::Float64) = rk4((x, y) -> -c * y + x, 0.0, y0, 1.0, 10)
ode3(y0::SVector{2,Float64}, w::Float64) = rk4((x, y) -> SVector(y[2], -w * y[1]), 0.0, y0, 1.0, 10)   # arrays through it
integ(f, a, b, n=8) = (h = (b - a) / n; h * sum(k -> f(a + (k - 0.5) * h), 1:n))                     # handed on to `sum`, inside a lambda
quad1(c::Float64) = integ(x -> c * x^2, 0.0, 1.0)
quad2(c::Float64) = integ(sin, 0.0, c, 16)
applied(f, v) = f(v)
regular(v::Vector{Float64}, a::Float64) = applied(w -> w[1] + a, v)

# ---- given a name, returned, captured ----------------------------------------------------
function named(a::Float64, x::Float64)
    g = y -> a * y + 1.0
    return g(x) + g(2x)
end
function namedlong(a::Float64, x::Float64)
    h = function (y)
        z = y + a
        return z * z
    end
    return h(x) - h(a)
end
function namedon(a::Float64, v::V3)
    g = y -> a * y + 1.0
    return sum(g, v) + g(2.0) + twice(g, 1.0)
end
function captures(a::Float64, v::V3)
    g = y -> a * y
    return sum(x -> g(x) + 1, v)                # a function that captured a function
end
function inloop(v::V3)
    s = 0.0
    for k in 1:3
        g = x -> x + k
        s += g(v[k])
    end
    return s
end
line(a::Float64, b::Float64) = x -> a * x + b
useline(a::Float64) = (h = line(a, 2.0); h(3.0))
interp(t::V3, y::V3) = x -> y[1] + (x - t[1]) * (y[2] - y[1]) / (t[2] - t[1])
useinterp(t::V3, y::V3) = (g = interp(t, y); g(0.5) + g(0.25))
called(x::Float64) = (() -> 2x)()

# ---- a struct called as a function ---------------------------------------------------------
struct Poly
    a::Float64
    b::Float64
end
(p::Poly)(x) = p.a * x + p.b
(p::Poly)(x::Float64, y::Float64) = p.a * x + p.b * y
callpoly(p::Poly, x::Float64) = p(x) + p(x, 2.0)
polyroot(p::Poly, x0::Float64) = newton(p, x -> p.a, x0)
polysum(p::Poly, v::V3) = sum(p, v)
polymap(p::Poly, v::V3) = map(p, v)

# ---- handed to Julia's own: the loop --------------------------------------------------------
sq(x) = x * x
sumabs(v::V4) = sum(abs, v)
sumrange(n::Int) = sum(x -> 1 / x^2, 1:n)
sumstep(n::Int) = sum(k -> k^2, 1:2:n)
sumdown(n::Int) = sum(k -> 1 / k, n:-1:1)
sumown(v::V3) = sum(x -> sq(x) + 1, v)
summatrix(A::SMatrix{2,3,Float64,6}) = sum(x -> x^2, A)
sumpower(n::Int, a::Float64, v::V3) = sum(x -> a * x^n, v)
sumindex(v::V3, w::V3) = sum(i -> v[i] * w[i], 1:3)
sumsingle(v::SVector{3,Float32}) = sum(x -> x * 2, v)
sumsmall(v::SVector{3,Int32}) = sum(abs, v)
prodshift(v::V4, a::Float64) = prod(x -> x + a, v)
anyover(v::V4, t::Float64) = any(x -> x > t, v)
allover(v::V4, t::Float64) = all(x -> x > t, v)
anymatrix(A::SMatrix{2,3,Float64,6}, t::Float64) = any(x -> x > t, A)
anysquare(n::Int) = any(k -> k * k == n, 1:n)
prime(n::Int) = all(k -> n % k != 0, 2:n-1)
countodd(v::SVector{4,Int}) = count(isodd, v)
countthird(n::Int) = count(k -> k % 3 == 0, 1:n)
maxof(v::V4) = maximum(x -> x * x - 3x, v)
maxrange(n::Int) = maximum(k -> k * (n - k), 1:n)
minabs(v::SVector{4,Int}) = minimum(abs, v)
mindist(v::V4) = minimum(x -> abs(x - 1), v)
mapsquare(v::V4) = map(x -> x^2, v)
maptwo(a::V3, b::V3) = map((x, y) -> x * y + 1, a, b)
mapown(v::V3) = map(sq, v)
mapmatrix(A::SMatrix{2,2,Float64,4}) = map(x -> 2x, A)
mapfield(p::Poly, v::V3) = map(x -> p.a * x + p.b, v)
mapregular(v::Vector{Float64}) = map(x -> 2x, v)
doblock(v::V3, a::Float64) = map(v) do x
    y = x + a
    y * y
end
generated(v::V4) = sum(x^2 for x in v)
generatedrange(n::Int) = sum(1 / k^2 for k in 1:n)
generatedtwo(v::V3, a::Float64, b::Float64) = sum(a * x + b for x in v)
comprehended(v::V4, a::Float64) = [a * x for x in v]
comprehendedrange(a::Float64) = [a * k for k in 1:4]
dotted(v::V3) = sq.(v)
dottedmany(v::V3, w::V3, a::Float64) = ((s, x, y) -> s * x + y).(a, v, w)
dottedinside(A::SMatrix{2,2,Float64,4}) = sq.(A) .+ 1.0
stored(v::V4) = (s = sum(abs, v); s * 2)
within(v::V4) = sum(abs, v) / count(x -> x > 0, v)
function tested(v::V4, t::Float64)
    if any(x -> x > t, v)
        return 1.0
    end
    return sum(abs, v)
end
function overwritten(n::Int)
    n = sum(k -> k, 1:n)                        # the loop reads the variable it is stored in
    return n
end
function accumulated(v::V3, n::Int)
    s = 0.0
    for k in 1:n
        s += sum(v) do x
            x * k
        end
    end
    return s
end
axpy(a, x, y) = a * x + y
short(v) = length(v) - 1
maxabs(n::Int) = maximum(abs, 1:n)                        # of an empty range Julia says 0, where any other function throws
maxabsof(v::SVector{3,Int}) = maximum(abs, v)
hoisted(v::V3, w::V3, a::Float64) = axpy.(sq(a) + 1, v, w)       # the number beside the arrays is worked out once
upto(v::V4) = sum(k -> v[k], 1:short(v))                  # and so is a range's end
inexpression(v::V3, a::Float64) = a * sum(x -> x^2, v) + maximum(abs, v)
printed(A::SMatrix{2,2,Float64,4}) = sum(x -> (println(x); x), A)
shared(t::MVector{3,Float64}) = x -> x + t[1]
useshared(t::MVector{3,Float64}) = (g = shared(t); g(1.0))
function shown(v::V3)
    foreach(println, v)
    foreach(v) do x
        println(2x)
    end
    return sq(v[1]) + sum(x -> (println(x); x), v)        # what the function prints stays in order
end

v3 = SVector(1.0, -2.0, 3.0); w3 = SVector(0.5, 4.0, -1.0); v4 = SVector(1.5, -2.0, 3.0, -0.5); i4 = SVector(1, -2, 3, 5)
A23 = SMatrix{2,3}(1.0, 2.0, -3.0, 4.0, 5.0, -6.0); A22 = SMatrix{2,2}(1.0, 2.0, 3.0, 4.0)

@testset "handed to a function" begin
    src = check("handed", [Case(root1, 1.0), Case(root2, 3.0, 1.0), Case(root3, 3.0, 2.0, 1.0), Case(level, 2.0, 3.0), Case(several, 0.5),
                           Case(samecapture, 2.0, 3.0), Case(recursive, 8.0), Case(swap, 1.5), Case(ode1, 1.0), Case(ode2, 1.0, 2.0),
                           Case(ode3, SVector(1.0, 0.0), 2.0), Case(quad1, 3.0), Case(quad2, 2.0)])
    # The function is called by name, and the function it was handed to says which it was compiled for.
    @test occursin("double newton_f_df(double x) {", src) && occursin("x -= f(x) / df(x);", src)
    # What a lambda captured comes in where the lambda was, and goes first to the lambda's own function.
    @test occursin("return newton_fun1_fun2(a, x0);", src) && occursin("double newton_fun1_fun2(double f_a, double x) {", src)
    @test occursin(r"x -= fun1\(f_a, x\) / fun2\(x\);", src) && occursin("double fun1(double a, double x) {", src) && occursin("double fun2(double x) {", src)
    @test occursin("double fun3(double a, double b, double x) {", src)
    # A lambda handed on to `sum` inside the function it was handed to is still written in the loop.
    @test occursin("temp1 += sin(a + (k - 0.5) * h);", src) && occursin(r"temp1 \+= fun\d+\(f_c, a \+ \(k - 0\.5\) \* h\);", src)
    # A function only passed on is still known all the way down.
    @test occursin(r"double thru_fun\d+\(double g_a, double x\) \{", src) && occursin(r"return twice_fun\d+\(g_a, x\) \+ 1\.0;", src)
    # Julia's own function is named as Julia names it.
    @test occursin("double twice_sin(double x) {", src) && occursin("return sin(sin(x));", src)
    @test !occursin("(*", src)                                   # no function pointer anywhere
    check("handedregular", [Case(regular, [1.0, 2.0, 3.0], 2.0)]; targets=[(regular, Float64, 3, Float64)])
end

@testset "named, returned, captured" begin
    src = check("heldfunction", [Case(named, 2.0, 3.0), Case(namedlong, 2.0, 3.0), Case(namedon, 2.0, v3), Case(captures, 2.0, v3), Case(inloop, v3),
                                 Case(useline, 1.5), Case(useinterp, v3, w3), Case(called, 2.5)])
    # A lambda given a name is that name, and making it is no C: its captures are the variables themselves.
    @test occursin("return g(a, x) + g(a, 2 * x);", src) && occursin("double g(double a, double y) {", src)
    @test occursin(r"double h\(double a, double y\) \{\n(    //[^\n]*\n)*    double z = y \+ a;", src)
    # A returned function is the struct of what it captured; calling it spreads the struct again.
    @test occursin(r"/// what the function fun\d+ captured: a, b\ntypedef struct \{\n    double a;\n    double b;\n\} fun\d+_t;", csource("heldtext", useline))
    @test occursin(r"fun\d+_t h_? = line\(a, 2\.0\);", src) && occursin(r"return fun\d+\(h_?\.a, h_?\.b, 3\.0\);", src)
    @test occursin(r"return \(fun\d+_t\)\{a, b\};", src)
    @test occursin(r"memcpy\(result\.t, t, sizeof\(double\[3\]\)\);", src)        # an array captured is copied into it
end

@testset "a struct called" begin
    src = check("calledstruct", [Case(callpoly, Poly(2.0, 1.0), 3.0), Case(polyroot, Poly(2.0, 1.0), 3.0), Case(polysum, Poly(2.0, 1.0), v3), Case(polymap, Poly(2.0, 1.0), v3)])
    @test occursin("double Poly_call(Poly p, double x) {", src) && occursin("double Poly_call_F64_F64(Poly p, double x, double y) {", src)
    @test occursin("return Poly_call(p, x) + Poly_call_F64_F64(p, x, 2.0);", src)
    @test occursin("result += Poly_call(p, v[i]);", src)
end

@testset "handed to Julia's own" begin
    src = check("folded", [Case(sumabs, v4), Case(sumrange, 50), Case(sumstep, 9), Case(sumdown, 9), Case(sumown, v3), Case(summatrix, A23),
                           Case(sumpower, 3, 2.0, v3), Case(sumindex, v3, w3), Case(sumsingle, SVector(1f0, 2f0, 3.5f0)),
                           Case(sumsmall, SVector(Int32(1), Int32(-2), Int32(3))), Case(prodshift, v4, 0.5),
                           Case(anyover, v4, 2.0), Case(anyover, v4, 5.0), Case(allover, v4, -3.0), Case(allover, v4, 0.0),
                           Case(anymatrix, A23, 4.5), Case(anymatrix, A23, 9.0), Case(anysquare, 16), Case(anysquare, 15),
                           Case(prime, 13), Case(prime, 15), Case(countodd, i4), Case(countthird, 10), Case(maxof, v4), Case(maxrange, 7),
                           Case(minabs, i4), Case(mindist, v4), Case(mapsquare, v4), Case(maptwo, v3, w3), Case(mapown, v3), Case(mapmatrix, A22),
                           Case(mapfield, Poly(2.0, 1.0), v3), Case(doblock, v3, 0.5), Case(generated, v4), Case(generatedrange, 30),
                           Case(generatedtwo, v3, 2.0, 1.0), Case(comprehended, v4, 2.0), Case(comprehendedrange, 2.0), Case(dotted, v3),
                           Case(dottedmany, v3, w3, 2.0), Case(dottedinside, A22), Case(stored, v4), Case(within, v4),
                           Case(tested, v4, 2.0), Case(tested, v4, 5.0), Case(overwritten, 5), Case(accumulated, v3, 3)])
    # One loop where the call was, the function written in its body: a lambda of one expression as that expression.
    @test occursin("    double result = 0.0;\n    for (int64_t i = 0; i < 4; i++) {\n        result += fabs(v[i]);\n    }\n    return result;", src)
    @test occursin("    for (int64_t x = 1; x <= n; x++) {\n        result += 1.0 / (double)(x * x);\n    }", src)      # a range goes by the lambda's own name
    @test occursin("for (int64_t k = 1; k <= n; k += 2) {", src) && occursin("for (int64_t k = n; k >= 1; k += -1) {", src)
    @test occursin("        if (v[i] > t) {\n            result = true;\n            break;\n        }", src)
    @test occursin("for (int64_t i = 0; i < 2 && !result; i++) {\n        for (int64_t j = 0; j < 3 && !result; j++) {\n            result = A[i][j] > t;", src)
    @test occursin("double result = -INFINITY;", src) && occursin("result = maxN(result, v[i] * v[i] - 3 * v[i]);", src)
    @test occursin("out[i] = v[i] * v[i];", src) && occursin("out[i] = a[i] * b[i] + 1;", src) && occursin("out[k - 1] = a * k;", src)
    # The variable the value is stored in is where the loop works, unless the loop reads it.
    @test occursin("    double s = 0.0;\n    for (int64_t i = 0; i < 4; i++) {\n        s += fabs(v[i]);\n    }\n    return s * 2;", src)
    @test occursin(r"int64_t temp1 = 0;\n    for \(int64_t k = 1; k <= n_?\w*; k\+\+\) \{\n        temp1 \+= k;\n    \}", src)
    # A `do` block of several lines is a function, called in the loop; its lines are shown with it and not twice.
    @test occursin(r"out\[i\] = fun\d+\(a, v\[i\]\);", src) && count("y = x + a", src) == 2
    @test count(r"\ndouble fun\d+\(", src) == 1                                # the one function; a lambda written in place is none, and takes no number
    check("foldedregular", [Case(mapregular, [1.0, 2.0, 3.0])]; targets=[(mapregular, Float64, 3)])
    src = check("foldededge", [Case(maxabs, 0), Case(maxabs, 3), Case(maxabsof, SVector(1, -5, 3)), Case(hoisted, v3, w3, 2.0), Case(upto, v4), Case(inexpression, v3, 2.0)])
    @test occursin("int64_t result = 1 > n ? 0 : INT64_MIN;", src)
    @test occursin("        int64_t temp1 = llabs(v[i]);\n        result = result > temp1 ? result : temp1;", src)      # written twice, worked out once
    @test occursin("    double temp1 = sq(a) + 1;\n    for (int64_t i = 0; i < 3; i++) {\n        out[i] = axpy(temp1, v[i], w[i]);", src)
    @test occursin(r"int64_t temp1 = short\w*\(v\);\n    for \(int64_t k = 1; k <= temp1; k\+\+\) \{", src)
    @test occursin("double temp1 = 0.0;", src) && occursin("return a * temp1 + temp2;", src)                   # a temp is named for what it went over
    # A function that prints goes over a matrix in Julia's order, down each column; one that only computes, in C's.
    @test occursin("    for (int64_t j = 0; j < 2; j++) {\n        for (int64_t i = 0; i < 2; i++) {\n            result += fun1(A[i][j]);", csource("printed", printed))
    shown_ = csource("shown", shown)
    @test occursin("        printf(\"%g\\n\", v[i]);", shown_)
    @test occursin(r"double temp1 = sq\(v\[0\]\);\n    double temp2 = 0\.0;", shown_)       # `sq` runs before the loop prints
end

# What isn't written, said plainly.
function boxed(x::Float64)
    s = 0.0
    add = y -> (s += y)
    add(x); add(2x)
    return s
end
function acrossbranch(c::Bool)
    s = 0.0
    for k in 1:3
        g = x -> x + k
        if c
            s += g(1.0)
        else
            s += g(2.0)
        end
    end
    return s
end
function writescapture!(out::MVector{3,Float64}, a::Float64)
    foreach(i -> (out[i] = a * i), 1:3)
    return out
end
struct Holder
    f::Function
end
heldany(h::Holder, x::Float64) = h.f(x)
stored2(x::Float64) = sum(g(x) for g in (sin, cos))

@testset "function refused" begin
    refusal(f) = try csource("refused", f); "" catch e; sprint(showerror, e) end
    @test occursin("`s` is used inside a function written here and assigned again", refusal(boxed))
    @test occursin("made inside a loop and used across a branch", refusal(acrossbranch))
    @test occursin("`out` is an array captured by the function", refusal(writescapture!))
    @test occursin("the struct `Holder` holds a function in its field `f`", refusal(heldany))
    @test occursin("the function `sin` is kept as a value here", refusal(stored2))
    @test occursin("captured `t`, an array that can be written into", refusal(useshared))
end
end
