# Scalar arithmetic, division rules, powers, integer operations, conversions, math.
module Scalar
using Test, StaticArrays
import Main: Case, check

arith(a::Float64, b::Float64, c::Float64) = (d = (a + b) * c / 2)
unary(x::Int64) = -x + 2 * x
nary(a::Float64, b::Float64, c::Float64, d::Float64) = a + b + c + d
reassign(a::Float64) = (d = a; d = d + 1.0; d = d * d; d - 3.0)
intint(a::Int64, b::Int64) = a / b
literal() = 5 / 2
halfint(a::Int64) = a / 2
mixed(a::Float64, b::Int64) = a / b
narrow(a::Int32, b::Int32) = a / b
single(a::Float32, b::Int32) = a / b
smooth(x::Float64) = sqrt(abs(x)) + x^2 + x^0.5 + max(x, 1.0) + 2 * pi + exp(-x) * sin(x)
intmath(a::Int64, b::Int64) = a ÷ b + a % b + a^3 + mod(a, b) + abs(a) + max(a, b)
convert_(a::Int64, x::Float64) = Float64(a) + Int64(round(x)) + trunc(Int64, x) + round(x)
strictly(a::Float64, b::Float64) = a != b && !(a >= b)
either(a::Bool, b::Bool) = !a || b
ldiv(a::Float64, b::Float64) = a \ b
cube(x::Float64) = x^3 + x^-1
bits(a::Int64, b::Int64) = (a & b) | (a << 2) ⊻ (b >> 1)

check("scalar", [Case(arith, 1.0, 2.0, 3.0), Case(unary, 7), Case(nary, 1.0, 2.0, 3.0, 4.0), Case(reassign, 2.0),
                 Case(intint, 7, 2), Case(literal), Case(halfint, 7), Case(mixed, 7.0, 2), Case(narrow, Int32(7), Int32(2)),
                 Case(single, 7.0f0, Int32(2)), Case(smooth, 1.7), Case(intmath, 7, 3), Case(intmath, -7, 3),
                 Case(convert_, 3, 2.6), Case(strictly, 1.0, 2.0), Case(strictly, 2.0, 1.0), Case(either, true, false),
                 Case(ldiv, 4.0, 1.0), Case(cube, 2.0), Case(bits, 12, 10)])
end
