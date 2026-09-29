# Two small physics-style functions, to see the step comments in action: a Julia line
# that becomes several C operations gets one comment per operation, in the C names.
# Run it to produce out/ next to it. Look at: the step comments, the copy of x and v, `-(r * r * r)`, the fit reading as the normal equations.
using LegibleC
using StaticArrays, LinearAlgebra

"""
    orbit(x, v, dt) -> [x; v]

Position and velocity after one step of gravity toward the origin, with the
gravitational parameter taken as 1: the acceleration is `-x / |x|³`. The step is
semi-implicit Euler — the velocity is updated first, and the position moves with the
new velocity — which keeps the orbit from spiralling the way plain Euler does.
"""
function orbit(x::SVector{3,Float64}, v::SVector{3,Float64}, dt::Float64)
    # Newton's law for a unit central mass.
    r = norm(x)
    a = -x / r^3

    # Velocity first, then position with the new velocity.
    v = v + dt * a
    x = x + dt * v
    return [x; v]   # the state as one vector, for an integrator to carry
end

"""
    fit(X, y) -> ‖y - X β‖²

Least-squares fit of `y ≈ X β` through the normal equations, `Xᵀ X β = Xᵀ y`, and the
squared residual of the fit. Fine for a well-conditioned `X` this small; a QR
factorization would be the choice for anything larger or nearly singular.
"""
function fit(X::SMatrix{4,2,Float64,8}, y::SVector{4,Float64})
    β = (X' * X) \ (X' * y)   # the normal equations
    e = y - X * β              # what the fit leaves unexplained
    return dot(e, e)
end

transpile(orbit, fit; outpath=@__DIR__, outfile="orbit")
