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
# A default argument: Julia makes the short method, which calls the long one through itself.
agm(x::Float64, y::Float64, e::Int64=5) = (for k in 1:e; x, y = (x + y) / 2, sqrt(x * y); end; x)
callsagm(x::Float64) = agm(x, 2.0) + agm(x, 3.0, 2)
@testset "default argument" begin
    check("default", [Case(callsagm, 1.0), Case(agm, 1.0, 2.0)]; targets=[callsagm])
    src = csource("defaulttext", callsagm)
    @test occursin("return agm_F64_F64_I64(x, y, 5);", src)
end
# Abstract parameter types and `where {T}`: Julia compiles a method for the types it is called
# with, and that instance is what is transpiled, so the target says which. `T` used as a
# value, `one(T)`, is a type known when transpiled.
absreal(x::Real, y::Real) = x * 2 + y
absvec(v::AbstractVector{Float64}) = v[1] + sum(v)
absarray(A::AbstractMatrix{<:Real}) = A[1, 2] + A[2, 1]
generic(x::T, y::T) where {T<:AbstractFloat} = x / y + one(T)
# Macros that change nothing the code computes: `@inbounds`, `@fastmath`, `@inline`. `@simd`
# rewrites its loop, and is refused by name with the advice to leave it out.
function inbounds(v::SVector{4,Float64})
    s = 0.0
    @inbounds for k in 1:4
        s += v[k]
    end
    return s
end
fastmath(x::Float64, y::Float64) = @fastmath x * y + sqrt(x)
@inline inlined(x::Float64) = x + 1.0
hints(x::Float64) = inlined(x) * 2.0
function simd(v::SVector{4,Float64})
    s = 0.0
    @simd for k in 1:4
        s += v[k]
    end
    return s
end
@testset "abstract types and macros" begin
    check("absreal", [Case(absreal, 1.5, 2)]; targets=[(absreal, Float64, Int64)])
    check("absint", [Case(absreal, 3, 4)]; targets=[(absreal, Int64, Int64)])
    check("absvec", [Case(absvec, SVector(1.0, -2.0, 3.5))]; targets=[(absvec, SVector{3,Float64})])
    check("absarray", [Case(absarray, SMatrix{2,3}(1.0, 2.0, 3.0, 4.0, 5.0, 6.0))]; targets=[(absarray, SMatrix{2,3,Float64,6})])
    check("generic", [Case(generic, 3.0, 2.0)]; targets=[(generic, Float64, Float64)])
    check("generic32", [Case(generic, 3.0f0, 2.0f0)]; targets=[(generic, Float32, Float32)])
    check("macros", [Case(inbounds, SVector(1.0, 2.0, 3.0, 4.0)), Case(fastmath, 2.0, 3.0), Case(hints, 2.0)])
    src = csource("macrostext", inbounds, fastmath)
    @test occursin("return x * y + sqrt(x);", src) && !occursin("void", replace(src, r"^void .*$"m => ""))
    msg = sprint(showerror, try csource("simd", simd) catch e; e end)
    @test occursin("`@simd` rewrites its loop", msg) && occursin("Leave it out", msg)
end
end
