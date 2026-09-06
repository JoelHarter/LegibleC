# Two small physics-style functions, to see the step comments in action: a Julia line
# that becomes several C operations gets one comment per operation, in the C names.
# Run it to produce out/ next to it. Look at: the step comments, the copy of x and v, `-(r * r * r)`, the fit reading as the normal equations.
using LegibleC
using StaticArrays, LinearAlgebra

"Position and velocity after one step of gravity toward the origin."
function orbit(x::SVector{3,Float64}, v::SVector{3,Float64}, dt::Float64)
    r = norm(x)
    a = -x / r^3
    v = v + dt * a
    x = x + dt * v
    return [x; v]
end

"Least-squares fit of y ≈ X β, and the squared residual."
function fit(X::SMatrix{4,2,Float64,8}, y::SVector{4,Float64})
    β = (X' * X) \ (X' * y)
    e = y - X * β
    return dot(e, e)
end

transpile(orbit, fit; outpath=@__DIR__, outfile="orbit")
