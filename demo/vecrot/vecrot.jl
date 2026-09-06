# A quaternion with only multiplication defined, and a vector rotated by one. Run it to produce out/ next to it. Look at: the struct by value, `Base.:*` on it coming out as `mul`, `q * p * conjugate(q)` as two calls, and `sincos` as its two lines.
using LegibleC
using StaticArrays

"A quaternion `w + xi + yj + zk`."
struct Quaternion
    w::Float64
    x::Float64
    y::Float64
    z::Float64
end

"The Hamilton product."
Base.:*(a::Quaternion, b::Quaternion) = Quaternion(
    a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)

"The conjugate: for a unit quaternion, the inverse rotation."
conjugate(q::Quaternion) = Quaternion(q.w, -q.x, -q.y, -q.z)

"The unit quaternion for a rotation by `θ` about the unit vector `axis`."
function axisangle(axis::SVector{3,Float64}, θ::Float64)
    s, c = sincos(θ / 2)
    return Quaternion(c, s * axis[1], s * axis[2], s * axis[3])
end

"Rotate `v` by the unit quaternion `q`: `q v q̄`."
function vecrot(q::Quaternion, v::SVector{3,Float64})
    p = q * Quaternion(0.0, v[1], v[2], v[3]) * conjugate(q)
    return SVector(p.x, p.y, p.z)
end

transpile(vecrot, axisangle; outpath=@__DIR__, outfile="vecrot")
