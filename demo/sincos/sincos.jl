# sincos: `s, c = sincos(x)` comes out as `sin(x)` and `cos(x)` written separately.
# Run it to produce out/ next to it. Look at: one Julia line becoming two C lines, sinf for Float32, the argument carried into both.
using LegibleC
using StaticArrays

"Rotate the 2-vector `v` by the angle `θ`."
function rotate(v::SVector{2,Float64}, θ::Float64)
    s, c = sincos(θ)
    return SVector(c * v[1] - s * v[2], s * v[1] + c * v[2])
end

"Unit vector at angle `θ` from the x-axis, in single precision."
function heading(θ::Float32)
    s, c = sincos(θ)
    return SVector(c, s)
end

"Position on a circle of radius `r` after turning through `ω` for `t` seconds."
function orbit(r::Float64, ω::Float64, t::Float64)
    s, c = sincos(ω * t)
    return SVector(r * c, r * s)
end

transpile(rotate, heading, orbit; outpath=@__DIR__, outfile="sincos")
