# A very Julian source, to see what comes out the other side. Run it to produce out/ next to it. Look at: ẋ and ω₀ as xdot and omega0, `+=`, the tuple as step_t, `θ > π && return` as an if.
using LegibleC
using StaticArrays, LinearAlgebra

"""
    step(x, ẋ, ω₀, ζ, Δt) -> x, ẋ

One semi-implicit Euler step of the damped oscillator

    ẍ + 2ζ ω₀ ẋ + ω₀² x = 0

with natural frequency `ω₀` and damping ratio `ζ`: `ζ < 1` rings, `ζ = 1` is critical,
`ζ > 1` creeps back. Returns the new position and velocity.
"""
function step(x::Float64, ẋ::Float64, ω₀::Float64, ζ::Float64, Δt::Float64)
    ẍ = -2ζ * ω₀ * ẋ - ω₀^2 * x   # the equation of motion, solved for ẍ

    # Velocity first, then position with the new velocity: symplectic, so the
    # undamped oscillator neither gains nor loses energy over a long run.
    ẋ += Δt * ẍ
    x += Δt * ẋ
    return x, ẋ
end

"""
    energy(m, r, v, μ)

Total energy of a particle of mass `m` at position `r` with velocity `v` in a gravity
well of strength `μ` (the product `G M`): kinetic plus potential, `m (v²/2 - μ/|r|)`.
Negative for a bound orbit, positive for an escape.
"""
energy(m::Float64, r::SVector{3,Float64}, v::SVector{3,Float64}, μ::Float64) = m * ((v ⋅ v) / 2 - μ / norm(r))

"Root-mean-square of the residuals `y .- ŷ`: the typical size of a miss."
function rms(y::SVector{4,Float64}, ŷ::SVector{4,Float64})
    e = y .- ŷ
    return √(sum(e .^ 2) / length(e))
end

"Bring `θ` into (-π, π], the way an angle is usually kept."
function wrap(θ::Float64)
    # One turn each way is enough: the angles that come here never stray further.
    θ > π && return θ - 2π
    θ ≤ -π && return θ + 2π
    return θ
end

transpile(step, energy, rms, wrap; outpath=@__DIR__, outfile="showcase")
