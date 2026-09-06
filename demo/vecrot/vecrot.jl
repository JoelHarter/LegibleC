# A quaternion as a scalar part and a vector part, with only `*` and `'` defined, and a vector rotated by one. Run it to produce out/ next to it. Look at: the struct with an array field, `Base.:*` on it coming out as `mul_Quat_Quat` with the dot and cross products as helpers, `q'` as `adjoint_Quat(q)` calling `conj_Quat(q)`, `q * p * q'` as two calls, and `sincos` as its two lines.
using LegibleC
using StaticArrays
using LinearAlgebra: ⋅, ×

"A quaternion `w + v`: a scalar part `w` and a vector part `v = (x, y, z)`."
struct Quat
    w::Float64
    v::SVector{3,Float64}
end

"The Hamilton product in vector form: the scalar part is `a.w b.w - a.v ⋅ b.v`, the vector part `a.w b.v + b.w a.v + a.v × b.v`."
Base.:*(a::Quat, b::Quat) = Quat(a.w * b.w - a.v ⋅ b.v, a.w * b.v + b.w * a.v + a.v × b.v)

"The conjugate: the vector part negated. For a unit quaternion, the inverse rotation."
Base.conj(q::Quat) = Quat(q.w, -q.v)

"`q'` is the conjugate, as for a complex number."
Base.adjoint(q::Quat) = conj(q)

"The unit quaternion for a rotation by `θ` about the unit vector `axis`."
function axisangle(axis::SVector{3,Float64}, θ::Float64)
    s, c = sincos(θ / 2)
    return Quat(c, s * axis)
end

"Rotate `v` by the unit quaternion `q`: the vector part of `q v q'`."
vecrot(q::Quat, v::SVector{3,Float64}) = (q * Quat(0.0, v) * q').v

transpile(vecrot, axisangle; outpath=@__DIR__, outfile="vecrot")
