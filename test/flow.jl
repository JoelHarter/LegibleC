# Control flow recovered from the IR: if/elseif/else, &&, ||, ?:, while, for, break,
# continue, early return, and loops over arrays.
module Flow
using Test, StaticArrays
import Main: Case, check, csource

smaller(a::Float64, b::Float64) = (if a < b; x = a; else; x = b; end; x)
sign_(a::Float64) = (if a < 0.0; y = -1.0; elseif a == 0.0; y = 0.0; else; y = 1.0; end; y)
larger(a::Float64, b::Float64) = a > b ? a : b
quadrant(a::Float64, b::Float64) = (if a > 0.0 && b > 0.0; r = 1.0; elseif a < 0.0 || b < 0.0; r = -1.0; else; r = 0.0; end; r)
bothpos(a::Float64, b::Float64) = a > 0.0 && b > 0.0
guard(x::Float64) = (x < 0.0 && return 0.0; sqrt(x))
triangle(n::Int64) = (s = 0; i = 1; while i <= n; s += i; i += 1; end; s)
oddsum(n::Int64) = (s = 0; i = 0; while true; i += 1; i > n && break; i % 2 == 0 && continue; s += i; end; s)
squares(n::Int64) = (s = 0; for i in 1:n; s += i * i; end; s)
stepped(n::Int64) = (s = 0; for i in 2:3:n; s += i; end; s)
skipper(n::Int64) = (s = 0; for i in 1:n; i == 3 && continue; i > 6 && break; s += i; end; s)
total(v::SVector{3,Float64}) = (s = 0.0; for i in eachindex(v); s += v[i]; end; s)
totalvec(v::Vector{Float64}) = (s = 0.0; for i in 1:length(v); s += v[i]; end; s)
trace(A::SMatrix{3,3,Float64,9}) = (t = 0.0; for i in 1:3; t += A[i, i]; end; t)
gridsum(A::SMatrix{2,3,Float64,6}) = (s = 0.0; for i in 1:2, j in 1:3; s += A[i, j]; end; s)
double1(v::MVector{3,Float64}) = (v[1] = 2.0 * v[2]; v)
basis(n::Float64) = (v = zeros(3); v[1] = n; v)
outer(u::SVector{2,Float64}, v::SVector{3,Float64}) = (M = zeros(2, 3); for i in 1:2, j in 1:3; M[i, j] = u[i] * v[j]; end; M)
sizes(v::SVector{3,Float64}, A::SMatrix{2,3,Float64,6}) = length(v) + size(A, 1) + size(A, 2)
looped(x::SVector{3,Float64}, n::Int64) = (for i in 1:n; x = x * 2.0; end; x)
branched(a::Float64, b::Float64) = (if a > b; c = a - b; a = c * 2.0; else; c = b - a; end; a + c)
rebound(x::SVector{3,Float64}, v::SVector{3,Float64}, dt::Float64) = (v = v + dt * x; x = x + dt * v; x = x / 2.0; [x; v])

v3 = SVector(1.0, 2.0, 3.5)
A3 = SMatrix{3,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0)
A23 = SMatrix{2,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
cases = [Case(smaller, 1.0, 2.0), Case(smaller, 3.0, 2.0), Case(sign_, -3.0), Case(sign_, 0.0), Case(sign_, 2.0),
         Case(larger, 1.0, 2.0), Case(quadrant, 1.0, 1.0), Case(quadrant, -1.0, 2.0), Case(quadrant, 0.0, 0.0),
         Case(bothpos, 1.0, -1.0), Case(guard, -4.0), Case(guard, 4.0), Case(triangle, 10), Case(oddsum, 10),
         Case(squares, 5), Case(stepped, 11), Case(skipper, 10), Case(total, v3), Case(totalvec, [1.0, 2.0, 3.0, 4.0]),
         Case(trace, A3), Case(gridsum, A23), Case(double1, MVector(1.0, 2.0, 3.0)), Case(basis, 2.5),
         Case(outer, SVector(1.0, 2.0), v3), Case(sizes, v3, A23)]
each(v::SVector{3,Float64}) = (s = 0.0; for x in v; s += x * x; end; s)
eachbreak(v::SVector{4,Float64}) = (s = 0.0; for x in v; x > 2.0 && break; s += x; end; s)
halve(x::SVector{3,Float64}) = (n = 0; while sum(x .* x) > 1.0; x = x / 2.0; n += 1; end; n)
# A loop that opens an `if`'s branch; a `break` that ends an inner loop which itself ends an
# outer loop's body; and the `break` of a multi-range `for`, which C has no word for.
function opened(m::Int64)
    if m > 1
        for j in 1:3
            m *= 2
        end
    elseif m < 0
        while m < 0
            m += 5
        end
    end
    return m
end
function innerbreak(n::Int64)
    s = 0
    for i in 1:n
        for j in 1:n
            s += i + j
            j >= i && break
        end
    end
    return s
end
function nestbreak(n::Int64)
    s = 0
    for i in 1:n, j in 1:n
        s += i * j
        s > 10 && break
    end
    return s
end
# A loop's own variable assigned in its body lasts for the pass; the next pass gets the next
# value of the range all the same. And `for x in v` goes on through the array it began with
# when the body gives `v` a new value.
function bumped(n::Int64)
    s = 0
    for k in 1:n
        for j in 1:2
            k += j
        end
        s += k
    end
    return s
end
function bumpedif(n::Int64)
    s = 0
    for k in 1:n
        if k == 2
            k = 10
        end
        s += k
    end
    return s
end
function bumpedeach(v::SVector{3,Float64})
    s = 0.0
    for x in v
        x > 1.5 && (x = 100.0)
        s += x
    end
    return s
end
function rebinding(v::SVector{3,Float64})
    s = 0.0
    for x in v
        v = v .* 2.0
        s += x
    end
    return s + v[1]
end
# `while a && b`, `while a || b`.
function whileand(n::Int64, m::Int64)
    s = 0
    while n > 0 && m > 0
        s += n; n -= 1; m -= 2
    end
    return s
end
function whileor(n::Int64, m::Int64)
    s = 0
    while n > 0 || m > 0
        s += 1; n -= 1; m -= 2
    end
    return s
end
function whilethree(n::Int64, m::Int64)
    s = 0
    while n > 0 && m > 0 && s < 7
        s += n; n -= 1; m -= 1
    end
    return s
end
# A branch that ends in a loop whose body ends in a `break`: the loop is one thing, and its
# `break` is not the branch's own last jump (it was dropped: the loop never left early).
function ifforbreak(m::Int64)
    if m > 1
        for j in 1:10
            m *= 2
            m > 100 && break
        end
    end
    return m
end
function ifforbreak2(n::Int64, p::Bool)
    s = 0
    for i in 1:n
        if p
            for j in 1:n
                s += j
                s > 5 * i && break
            end
        end
    end
    return s
end
# A condition whose parts can't be written as one C condition, with an `else`: the inner
# test's failure belongs to the outer `else`, which a nested `if` would lose. Checked against
# where the lowered code really goes, and refused: each of these answered wrongly before.
function andheavy(a::Bool, x::SVector{3,Float64})
    r = 0.0
    if a && sum(x .* x) > 1.0
        r = 10.0
    else
        r = 20.0
    end
    return r + 1.0
end
orheavy(a::Bool, x::SVector{3,Float64}) = (s = 0.0; if a || sum(x .* x) > 1.0; s += 5.0; end; s)
# The second part needs a line of its own (`mod` writes its operand twice, so `a * b` is a temp),
# and a test that fails must reach the `else`: refused, where the C said 2 for Julia's 1.
function modand(a::Int64, b::Int64)
    if a > 0 && mod(a * b, 3) == 1
        r = 1
    else
        r = 2
    end
    return r
end
# `a && b`, `a || b` and `c ? x : y` as values: one C expression each, where Julia's lowered
# code has a hidden variable stored on both sides of a test. That is also what makes a
# condition that mixes them an ordinary condition.
function andor(a::Bool, b::Bool, c::Bool)
    r = 0
    if a && (b || c)
        r = 1
    else
        r = 2
    end
    return r
end
function orand(a::Bool, b::Bool, c::Bool)
    r = 0
    if (a || b) && c
        r = 1
    else
        r = 2
    end
    return r
end
function andtern(a::Float64, c::Bool, p::Bool, q::Bool)
    if a > 0.0 && (c ? p : q)
        x = 1.0
    else
        x = 2.0
    end
    return x
end
function valor(a::Bool, b::Bool, n::Int64)
    ok = a && (b || n > 3)
    no = a || n > 3
    return ok ? (no ? 1 : 2) : 3
end
nested3(b::Bool, c::Bool, n::Int64) = (x = c ? 1 : (b ? n + 2 : 3); x + 1)
tailor(a::Bool, b::Bool, c::Bool, n::Int64) = a && b || c && n > 2          # the value is read twice: one line, into a temp
ternarg(x::Float64, c::Bool) = sqrt(c ? x : 2.0x) + (x > 1.0 ? 1.0 : -1.0) * x
function ternsq(x::Float64, c::Bool)
    y = (c ? x : x + 1.0)^2                  # `^2` writes its operand twice: one line, into a temp
    k = mod(c ? 7 : -7, 3)
    return y + k
end
function heavyside(a::Bool, x::SVector{3,Float64})
    ok = a && sum(x .* x) > 1.0              # a side with work of its own keeps its `if`
    return ok ? 1 : 2
end
function elseifmix(n::Int64, m::Int64)
    if n > 5 && (m > 2 || m < -2)
        r = 1
    elseif n > 0 || (m > 3 && m < 9)
        r = 2
    else
        r = 3
    end
    return r
end
function whilemix(a::Bool, b::Bool, c::Bool, n::Int64)
    while (a || b) && n > 0
        n -= 1
        n == 2 && !c && continue
        a = !a
    end
    return (a && b) || (c && n > 0) ? 1 : 2
end
function ternloop(n::Int64, a::Float64)
    s = 0.0
    for k in 1:n
        w = k > 2 && a > 0.0 ? a : 2.0a
        s += w * k
        (k == 3 || s > 100.0) && a > 1.0 && break
    end
    return s
end
# A loop's own test is not part of the `if` it opens: both fail to the same place.
function ifwhiletrue(a::Bool, n::Int64)
    s = 0
    if a
        while true
            s += 1
            s > n && break
        end
    end
    return s
end
# A branch Julia has proved never runs: its variable has no type, and needs no declaration.
function constdead(x::Float64)
    if typemax(Float64) == 0.0; y = x + 1.0; end
    return sqrt(x) + 1.0
end
function elsecontinue(n::Int64, p::Bool, a::Bool)
    s = 0
    for k in 1:n
        if p
            if a; s += k; else; continue; end
        end
        s += 100
    end
    return s
end
function andlast(p::Bool, a::Bool, x::Float64)
    if p
        x += 1.0
        a && (x *= 2.0)
    end
    return x
end
# Julia builds a range once, so a bound the body changes is read before the loop: 21, not 6.
shrinking(n::Int64) = (s = 0; for k in 1:n; n -= 1; s += k; end; s)
function drained(v::MVector{3,Int64}); s = 0; for k in 1:v[1]; v[1] -= 1; s += k; end; return s; end
steady(n::Int64) = (s = 0; for k in 1:n; s += k; end; s)                 # a bound nothing changes stays in the header
append!(cases, [Case(each, v3), Case(eachbreak, SVector(1.0, 2.0, 3.0, 4.0)), Case(halve, SVector(4.0, 0.0, 0.0)), Case(halve, SVector(0.5, 0.0, 0.0)),
                Case(shrinking, 6), Case(drained, MVector(3, 0, 0)), Case(steady, 6),
                Case(opened, 5), Case(opened, -7), Case(opened, 1), Case(innerbreak, 4), Case(innerbreak, 1),
                Case(bumped, 3), Case(bumpedif, 3), Case(bumpedeach, v3), Case(rebinding, v3),
                Case(whileand, 5, 4), Case(whileand, 2, 9), Case(whileor, 5, 4), Case(whileor, 0, 0), Case(whilethree, 9, 9),
                Case(ifforbreak, 3), Case(ifforbreak, 1), Case(ifforbreak2, 4, true), Case(ifforbreak2, 4, false)])
bools = (true, false)
append!(cases, [Case(andor, a, b, c) for a in bools for b in bools for c in bools])
append!(cases, [Case(orand, a, b, c) for a in bools for b in bools for c in bools])
append!(cases, [Case(andtern, s, c, p, q) for s in (1.0, -1.0) for c in bools for p in bools for q in bools])
append!(cases, [Case(valor, a, b, n) for a in bools for b in bools for n in (1, 5)])
append!(cases, [Case(tailor, a, b, c, n) for a in bools for b in bools for c in bools for n in (1, 5)])
append!(cases, [Case(whilemix, a, b, c, n) for a in bools for b in bools for c in bools for n in (0, 4)])
append!(cases, [Case(elseifmix, n, m) for n in (9, 3, -2) for m in (0, 5, -5, 20)])
append!(cases, [Case(elsecontinue, 3, p, a) for p in bools for a in bools])
append!(cases, [Case(andlast, p, a, 1.5) for p in bools for a in bools])
append!(cases, [Case(nested3, true, false, 4), Case(nested3, false, true, 4), Case(nested3, false, false, 4),
                Case(ternarg, 0.5, true), Case(ternarg, 2.0, false), Case(ternsq, 1.5, true), Case(ternsq, 1.5, false),
                Case(heavyside, true, v3), Case(heavyside, false, v3), Case(ternloop, 5, 1.5), Case(ternloop, 5, -1.0), Case(ternloop, 5, 40.0),
                Case(ifwhiletrue, true, 3), Case(ifwhiletrue, false, 3), Case(constdead, 4.0)])
@testset "flow text" begin
    @test_throws ArgumentError csource("modand", modand)          # Julia 1, and the C said 2
    chosen = csource("chosen", andor, valor, nested3, tailor, ternsq, whilemix, ternloop, elseifmix)
    @test occursin("if (a && (b || c)) {", chosen) && occursin("} else if (n > 0 || (m > 3 && m < 9)) {", chosen)
    @test occursin("bool ok = a && (b || n > 3);", chosen) && occursin("bool no = a || n > 3;", chosen)
    @test occursin("int64_t x = c ? 1 : (b ? n + 2 : 3);", chosen)
    @test occursin("bool temp1 = a && b;\n    if (temp1) {", chosen)                           # read twice: written once
    @test occursin("double temp1 = c ? x : x + 1.0;\n    double y = temp1 * temp1;", chosen)   # `^2` writes it twice
    @test occursin("while ((a || b) && n > 0) {", chosen) && occursin("if ((a && b) || (c && n > 0)) {", chosen)
    @test occursin("double w = (k > 2 && a > 0.0) ? a : 2.0 * a;", chosen)
    @test_throws ArgumentError csource("nestbreak", nestbreak)                                # refused, where it used to leave one loop: 63 for Julia's 11
    @test_throws ArgumentError csource("andheavy", andheavy)      # Julia 21, and the C said 1
    @test_throws ArgumentError csource("orheavy", orheavy)        # Julia 5, and the C said 10: the body written twice
    loops = csource("flowloops", bumped, whileand, whileor)
    @test occursin("for (int64_t i = 1; i <= n; i++) {\n        int64_t k = i;", loops)                 # the counting is ours, the variable the body's
    @test occursin("while (n > 0 && m > 0) {", loops) && occursin("while (n > 0 || m > 0) {", loops)
    src = csource("flowtext", each, halve, shrinking, drained, steady)
    @test occursin("int64_t temp1_n = n;\n    for (int64_t k = 1; k <= temp1_n; k++) {", src)                  # the bound, read once
    @test occursin("= v[0];\n    for (int64_t k = 1; k <= temp1_v; k++) {", src) && occursin("for (int64_t k = 1; k <= n; k++) {", src)
    @test occursin("for (int64_t i = 0; i < 3; i++) {\n        double x = v[i];", src)   # `for x in v`: an index Julia never named
    @test occursin("while (true) {", src) && occursin("if (!(sum_3(temp1) > 1.0)) {\n            break;", src)   # a header with array work
end
append!(cases, [Case(looped, v3, 3), Case(looped, v3, 0), Case(branched, 3.0, 1.0), Case(branched, 1.0, 3.0), Case(rebound, v3, v3, 0.5)])
check("flow", cases; targets=[smaller, sign_, larger, quadrant, bothpos, guard, triangle, oddsum, squares, stepped, skipper,
                              total, (totalvec, Float64, 4), trace, gridsum, double1, basis, outer, sizes, looped, branched, rebound,
                              each, eachbreak, halve, shrinking, drained, steady, opened, innerbreak,
                              bumped, bumpedif, bumpedeach, rebinding, whileand, whileor, whilethree, ifforbreak, ifforbreak2,
                              andor, orand, andtern, valor, nested3, tailor, ternarg, ternsq, heavyside, elseifmix, whilemix, ternloop,
                              ifwhiletrue, constdead, elsecontinue, andlast])
end
