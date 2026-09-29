# A quaternion as a scalar part and a vector part, with only `*` and `'` defined, and a vector rotated by one. Run it to produce out/ next to it. Look at: the struct with an array field, `Base.:*` on it coming out as `mul_Quat_Quat` with the dot and cross products as helpers, `q'` as `adjoint_Quat(q)` calling `conj_Quat(q)`, `q * p * q'` as two calls, and `sincos` as its two lines.
using LegibleC
using StaticArrays
using LinearAlgebra: ⋅, ×, norm

"A quaternion `w + v`: a scalar part `w` and a vector part `v = (x, y, z)`."
struct Quat
    w::Float64
    v::SVector{3,Float64}
end

"""
    a * b

The Hamilton product, in scalar-and-vector form:

    (a b).w = a.w b.w - a.v ⋅ b.v
    (a b).v = a.w b.v + b.w a.v + a.v × b.v

Not commutative: the cross product flips sign when the factors swap.
"""
Base.:*(a::Quat, b::Quat) = Quat(a.w * b.w - a.v ⋅ b.v, a.w * b.v + b.w * a.v + a.v × b.v)

"The conjugate: the vector part negated. For a unit quaternion, the inverse rotation."
Base.conj(q::Quat) = Quat(q.w, -q.v)

# So `q'` reads as the conjugate, the way it does for a complex number.
Base.adjoint(q::Quat) = conj(q)

"""
    rotor(r)

The unit quaternion for the rotation vector `r`: a rotation about `r`'s direction by
`r`'s length, `(cos(θ/2), sin(θ/2) r/θ)`. Half the angle, since a quaternion turns a
vector through twice its own angle when applied as `q v q'`.
"""
function rotor(r::SVector{3,Float64})
    θ = norm(r)
    s, c = sincos(θ / 2)
    return Quat(c, (θ > 0 ? s / θ : 0.5) * r)   # sin(θ/2) / θ, which is 1/2 at θ = 0
end

"Rotate `v` by the unit quaternion `q`: the vector part of the sandwich `q v q'`, `v` taken as a pure quaternion."
vecrot(q::Quat, v::SVector{3,Float64}) = (q * Quat(0.0, v) * q').v

transpile(vecrot, rotor; outpath=@__DIR__, outfile="vecrot")
