# Calls between transpiled functions (callees brought in on demand, recursion, unused
# results, void) and calls into C.
module Call
using Test, StaticArrays
import Main: Case, check, csource

const V3 = SVector{3,Float64}

sq(x::Float64) = x * x
hyp(a::Float64, b::Float64) = sqrt(sq(a) + sq(b))
twice(v::V3) = 2.0 * v
quad(v::V3) = twice(twice(v))
fact(n::Int64) = n <= 1 ? 1 : n * fact(n - 1)
mixed(v::V3, s::Float64) = hyp(v[1], s) * twice(v)
cbrt64(x::Float64) = ccall(:cbrt, Float64, (Float64,), x)
cbrt32(x::Float32) = @ccall cbrtf(x::Cfloat)::Cfloat
nothing1(x::Float64) = nothing
function discard(v::V3)
    twice(v)
    return nothing
end
total(v::V3) = ccall(:mysum, Float64, (Ptr{Float64}, Cint), v, 3)

v = SVector(1.0, 2.0, 3.0)
src = check("call", [Case(hyp, 3.0, 4.0), Case(quad, v), Case(fact, 10), Case(mixed, v, 4.0), Case(cbrt64, 27.0),
                     Case(cbrt32, 8.0f0), Case(nothing1, 1.0), Case(discard, v)])
@testset "call text" begin
    @test occursin("void twice(const double v[3], double out[restrict 3])", src)   # brought in by quad
    @test occursin("#include <math.h>", src)                                       # cbrt is math.h's
    @test occursin("void nothing1(double x)", src)
end
@testset "ccall prototype" begin
    src = csource("foreign", total)
    @test occursin("double mysum(const double *, int32_t);", src)
    @test occursin("mysum(v, 3)", src)
end
end
