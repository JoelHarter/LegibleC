#ifndef SINCOS_H
#define SINCOS_H

#include <stdint.h>
#include <stdbool.h>

/**
 * Rotate the 2-vector `v` by the angle `θ`.
 *
 * Julia signature: rotate(v::SVector{2, Float64}, θ::Float64) @sincos.jl:7
 * @param[in]  v      2-vector
 * @param[in]  theta  scalar
 * @param[out] out    2-vector, the return value
 */
void rotate(const double v[2], double theta, double out[restrict 2]);

/**
 * Unit vector at angle `θ` from the x-axis, in single precision.
 *
 * Julia signature: heading(θ::Float32) @sincos.jl:13
 * @param[in]  theta  scalar
 * @param[out] out    2-vector, the return value
 */
void heading(float theta, float out[restrict 2]);

/**
 * Position on a circle of radius `r` after turning through `ω` for `t` seconds.
 *
 * Julia signature: orbit(r::Float64, ω::Float64, t::Float64) @sincos.jl:19
 * @param[in]  r      scalar
 * @param[in]  omega  scalar
 * @param[in]  t      scalar
 * @param[out] out    2-vector, the return value
 */
void orbit(double r, double omega, double t, double out[restrict 2]);

#endif
