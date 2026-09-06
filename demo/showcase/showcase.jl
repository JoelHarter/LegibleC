# A very Julian source, to see what comes out the other side. Run it to produce out/ next to it. Look at: ẋ and ω₀ as xdot and omega0, `+=`, the tuple as step_t, `θ > π && return` as an if.
using LegibleC
using StaticArrays, LinearAlgebra

"One semi-implicit Euler step of a damped oscillator with natural frequency `ω₀` and damping ratio `ζ`."
function step(x::Float64, ẋ::Float64, ω₀::Float64, ζ::Float64, Δt::Float64)
    ẍ = -2ζ * ω₀ * ẋ - ω₀^2 * x
    ẋ += Δt * ẍ
    x += Δt * ẋ
    return x, ẋ
end

"Total energy of a particle of mass `m` at `r` moving at `v`, in a gravity well of strength `μ`."
energy(m::Float64, r::SVector{3,Float64}, v::SVector{3,Float64}, μ::Float64) = m * ((v ⋅ v) / 2 - μ / norm(r))

"Root-mean-square of the residuals `y .- ŷ`."
function rms(y::SVector{4,Float64}, ŷ::SVector{4,Float64})
    e = y .- ŷ
    return √(sum(e .^ 2) / length(e))
end

"Bring `θ` into (-π, π], the way an angle is usually kept."
function wrap(θ::Float64)
    θ > π && return θ - 2π
    θ ≤ -π && return θ + 2π
    return θ
end

transpile(step, energy, rms, wrap; outpath=@__DIR__, outfile="showcase")
