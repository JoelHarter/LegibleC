#include <stdint.h>
#include <stdbool.h>
#include <math.h>

void rotate(const double v[2], double theta, double out[restrict 2]);
void heading(float theta, float out[restrict 2]);
void orbit(double r, double omega, double t, double out[restrict 2]);

/**
 * Rotate the 2-vector `v` by the angle `θ`.
 *
 * Julia signature: rotate(v::SVector{2, Float64}, θ::Float64), sincos.jl:7
 * @param[in]  v      2-vector
 * @param[in]  theta  scalar
 * @param[out] out    2-vector, the return value
 */
void rotate(const double v[2], double theta, double out[restrict 2]) {
    // sincos.jl:8: s, c = sincos(θ)
    double s = sin(theta);
    double c = cos(theta);

    // sincos.jl:9: return SVector(c * v[1] - s * v[2], s * v[1] + c * v[2])
    out[0] = c * v[0] - s * v[1];
    out[1] = s * v[0] + c * v[1];
}

/**
 * Unit vector at angle `θ` from the x-axis, in single precision.
 *
 * Julia signature: heading(θ::Float32), sincos.jl:13
 * @param[in]  theta  scalar
 * @param[out] out    2-vector, the return value
 */
void heading(float theta, float out[restrict 2]) {
    // sincos.jl:14: s, c = sincos(θ)
    float s = sinf(theta);
    float c = cosf(theta);

    // sincos.jl:15: return SVector(c, s)
    out[0] = c;
    out[1] = s;
}

/**
 * Position on a circle of radius `r` after turning through `ω` for `t` seconds.
 *
 * Julia signature: orbit(r::Float64, ω::Float64, t::Float64), sincos.jl:19
 * @param[in]  r      scalar
 * @param[in]  omega  scalar
 * @param[in]  t      scalar
 * @param[out] out    2-vector, the return value
 */
void orbit(double r, double omega, double t, double out[restrict 2]) {
    // sincos.jl:20: s, c = sincos(ω * t)
    double s = sin(omega * t);
    double c = cos(omega * t);

    // sincos.jl:21: return SVector(r * c, r * s)
    out[0] = r * c;
    out[1] = r * s;
}
