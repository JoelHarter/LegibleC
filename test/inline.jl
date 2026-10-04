# Single-use scalar values written inside the expression that consumes them, and the
# cases that keep a temp: a repeated operand, a returned value, an order of effects.
module Inline
using Test, StaticArrays, LinearAlgebra
import Main: Case, check, csource

sq(a::Float64) = a * a
hyp(a::Float64, b::Float64) = sqrt(sq(a) + sq(b))
poly(a::Float64, b::Float64, c::Float64) = (d = (a + b) * c / 2; d - (a - b) * (c + 1.0))
cubed(x::SVector{3,Float64}) = norm(x)^3 + sqrt(x[1] + x[2])^2
modded(a::Int64, b::Int64) = mod(a + 1, b) + max(a * 2, b)
signs(a::Float64, b::Float64) = a + (-b) + (a - (-b)) + (-(-a)) + (-b * a)
inloop(v::SVector{3,Float64}, n::Int64) = (s = 0.0; for i in 1:n - 1; s = s + v[i] * sqrt(v[i + 1]); end; s)
folded(x::SVector{3,Float64}, r::Float64) = -x / r^3
cancelled(x::SVector{3,Float64}, s::Float64) = -x / -s
halved(a::Int64, b::Int64) = (a + b) / 2
mutate!(v::MVector{3,Float64}, k::Float64) = (v[1] = k; k)
reads(v::MVector{3,Float64}) = mutate!(v, 1.0) + mutate!(v, 2.0) + v[1]
shout(a::Float64) = (println(a); a)
loud(a::Float64, b::Float64) = shout(a) + shout(b)
cast(a::Int64, b::Int64) = (println(a + b); a)
peek(v::MVector{3,Float64}) = v[1] + mutate!(v, 2.0)
normsum(x::SVector{3,Float64}, v::SVector{3,Float64}) = norm(x + v)
fifth(x::Float64, y::Float64) = x^5 + (x + y)^-4 + (x * y)^-2
longline(alpha::Float64, beta::Float64, gamma::Float64, delta::Float64) =
    alpha * beta + beta * gamma + gamma * delta + delta * alpha + alpha * gamma + beta * delta + alpha + beta + gamma + delta

src = csource("inline", hyp, poly, cubed, modded, signs, inloop, folded, cancelled, halved, reads, loud, cast, peek, normsum, longline, fifth)
@testset "inline" begin
    @test occursin("return sqrt(sq(a) + sq(b));", src)                                # the author named nothing; neither do we
    @test occursin("double d = (a + b) * c / 2;", src) && occursin("return d - (a - b) * (c + 1.0);", src)
    @test occursin("double temp1_x = norm_3(x);", src) && occursin("temp1_x * temp1_x * temp1_x", src)   # a power's base is written twice
    @test occursin("double temp2_x = sqrt(x[0] + x[1]);", src) && occursin("temp2_x * temp2_x", src)
    @test occursin("temp1_a = a + 1;", src) && occursin("temp2_a = a * 2;", src)     # mod and integer max repeat their operands
    @test occursin("a - b + (a + b) + a - b * a", src)                                # signs: `+ -b` is `- b`, `- -b` is `+ b`, `-(-a)` is `a`
    @test occursin("for (int64_t i = 1; i <= n - 1; i++) {", src) && occursin("s += v[i - 1] * sqrt(v[i]);", src)
    @test occursin("div_3_s(x, -(r * r * r), out);", src)                             # a folded sign wraps an expression
    @test occursin("div_3_s(x, s, out);", src)                                        # `-x / -s`: the signs cancel
    @test occursin("(double)(a + b) / 2.0", src)                                      # the cast binds tighter than `+`
    # Effects stay in Julia's order: the first of two writing calls is pinned, the second
    # is written where it is used; a read of what a call writes never moves past it.
    @test occursin("double temp1_v = mutate(v, 1.0);", src) && occursin("double temp2_v = mutate(v, 2.0);", src) && occursin("return temp1_v + temp2_v + v[0];", src)
    @test occursin("double reads(double v[3])", src) && occursin("@param[in,out] v  3-vector", src)     # the callee writes v, so it isn't const here
    @test occursin("double temp1_a = shout(a);", src) && occursin("return temp1_a + shout(b);", src)     # prints stay in order
    @test occursin("double temp1_v = v[0];", src) && occursin("return temp1_v + mutate(v, 2.0);", src)   # the read comes first in Julia
    @test occursin("(long long)(a + b)", src)
    @test occursin("return norm_3(temp1_x_v);", src)                                   # a reduction over an unnamed array
    # Powers other than 2, 3 and -1 go through `powi`, by squaring; an expression base
    # is passed once, so it needs no temp.
    @test occursin("return powi(x, 5) + powi(x + y, -4) + powi(x * y, -2);", src)
    @test occursin("/// a scalar to an integer power, by squaring\n/// returns x^n\nstatic inline double powi(double x, int64_t n) {\n    if (n < 0) {\n        x = 1.0 / x;", src)
    # A long expression wraps at its loosest operators, continuation lines led by the operator.
    @test occursin("    return alpha * beta + beta * gamma_ + gamma_ * delta + delta * alpha + alpha * gamma_\n           + beta * delta + alpha + beta + gamma_ + delta;", src)
    @test all(length(l) <= 100 for l in split(src, "\n") if startswith(l, "    ") && (endswith(l, ";") || endswith(l, "{") || endswith(l, "}")))   # code lines; a quoted Julia line may be longer
end
check("inline", [Case(hyp, 3.0, 4.0), Case(poly, 1.0, 2.0, 3.0), Case(cubed, SVector(1.0, 2.0, 2.0)), Case(modded, 7, 3), Case(modded, -7, 3),
                 Case(signs, 1.5, -2.5), Case(inloop, SVector(1.0, 4.0, 9.0), 3), Case(folded, SVector(1.0, 2.0, 2.0), 2.0),
                 Case(cancelled, SVector(1.0, 2.0, 2.0), 2.0), Case(halved, 7, 2), Case(reads, MVector(0.0, 0.0, 0.0)),
                 Case(peek, MVector(0.5, 0.0, 0.0)), Case(normsum, SVector(1.0, 2.0, 2.0), SVector(1.0, 0.0, 0.0)),
                 Case(longline, 1.0, 2.0, 3.0, 4.0), Case(fifth, 1.5, 0.5)])
end
