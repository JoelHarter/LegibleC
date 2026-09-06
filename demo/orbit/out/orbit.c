#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include "mathhelper.h"

void orbit(const double x[3], const double v[3], double dt, double out[restrict 6]);
double fit(const double X[4][2], const double y[4]);

/**
 * Position and velocity after one step of gravity toward the origin.
 *
 * Julia signature: orbit(x::SVector{3, Float64}, v::SVector{3, Float64}, dt::Float64), orbit.jl:8
 * @param[in]  x    3-vector
 * @param[in]  v    3-vector
 * @param[in]  dt   scalar
 * @param[out] out  6-vector, the return value
 */
void orbit(const double x[3], const double v[3], double dt, double out[restrict 6]) {
    // copy x and v to prevent modification within this function
    double x_[3];
    memcpy(x_, x, sizeof x_);
    double v_[3];
    memcpy(v_, v, sizeof v_);

    // orbit.jl:9: r = norm(x)
    double r = norm_3(x_);

    // orbit.jl:10: a = -x / r^3
    double a[3];
    div_3_s(x_, -(r * r * r), a);

    // orbit.jl:11: v = v + dt * a
    double temp1_dt_a[3];
    mul_s_3(dt, a, temp1_dt_a);  // temp1_dt_a = dt * a
    add_3(v_, temp1_dt_a, v_);  // v_ = v_ + temp1_dt_a

    // orbit.jl:12: x = x + dt * v
    double temp2_dt_v[3];
    mul_s_3(dt, v_, temp2_dt_v);  // temp2_dt_v = dt * v_
    add_3(x_, temp2_dt_v, x_);  // x_ = x_ + temp2_dt_v

    // orbit.jl:13: return [x; v]
    memcpy(out, x_, sizeof(double[3]));
    memcpy(&out[3], v_, sizeof(double[3]));
}

/**
 * Least-squares fit of y ≈ X β, and the squared residual.
 *
 * Julia signature: fit(X::SMatrix{4, 2, Float64, 8}, y::SVector{4, Float64}), orbit.jl:17
 * @param[in] X  4×2-matrix
 * @param[in] y  4-vector
 */
double fit(const double X[4][2], const double y[4]) {
    // orbit.jl:18: β = (X' * X) \ (X' * y)
    double temp1_X[2][2];
    mul_T4x2_4x2(X, X, temp1_X);  // temp1_X = Xᵀ * X
    double temp2_X_y[2];
    mul_T4x2_4(X, y, temp2_X_y);  // temp2_X_y = Xᵀ * y
    double beta[2];
    solve_2x2_2(temp1_X, temp2_X_y, beta);  // beta = temp1_X \ temp2_X_y

    // orbit.jl:19: e = y - X * β
    double temp3_X_beta[4];
    mul_4x2_2(X, beta, temp3_X_beta);  // temp3_X_beta = X * beta
    double e[4];
    sub_4(y, temp3_X_beta, e);  // e = y - temp3_X_beta

    // orbit.jl:20: return dot(e, e)
    return dot_4(e, e);
}
