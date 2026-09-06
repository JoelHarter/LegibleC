#ifndef ORBIT_H
#define ORBIT_H

/**
 * Position and velocity after one step of gravity toward the origin.
 *
 * Julia signature: orbit(x::SVector{3, Float64}, v::SVector{3, Float64}, dt::Float64) @orbit.jl:8
 * @param[in]  x    3-vector
 * @param[in]  v    3-vector
 * @param[in]  dt   scalar
 * @param[out] out  6-vector, the return value
 */
void orbit(const double x[3], const double v[3], double dt, double out[restrict 6]);

/**
 * Least-squares fit of y ≈ X β, and the squared residual.
 *
 * Julia signature: fit(X::SMatrix{4, 2, Float64, 8}, y::SVector{4, Float64}) @orbit.jl:17
 * @param[in] X  4×2-matrix
 * @param[in] y  4-vector
 */
double fit(const double X[4][2], const double y[4]);

#endif  // ORBIT_H
