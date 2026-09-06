#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include "mathhelper.h"

typedef struct {
    double x;
    double xdot;
} step_t;
step_t step(double x, double xdot, double omega0, double zeta, double Deltat);
double energy(double m, const double r[3], const double v[3], double mu);
double rms(const double y[4], const double yhat[4]);
double wrap(double theta);

/**
 * One semi-implicit Euler step of a damped oscillator with natural frequency `ω₀` and damping ratio `ζ`.
 *
 * Julia signature: step(x::Float64, ẋ::Float64, ω₀::Float64, ζ::Float64, Δt::Float64), showcase.jl:6
 * @param[in] x       scalar
 * @param[in] xdot    scalar
 * @param[in] omega0  scalar
 * @param[in] zeta    scalar
 * @param[in] Deltat  scalar
 */
step_t step(double x, double xdot, double omega0, double zeta, double Deltat) {
    // showcase.jl:7: ẍ = -2ζ * ω₀ * ẋ - ω₀^2 * x
    double xddot = -2 * zeta * omega0 * xdot - omega0 * omega0 * x;

    // showcase.jl:8: ẋ += Δt * ẍ
    xdot += Deltat * xddot;

    // showcase.jl:9: x += Δt * ẋ
    x += Deltat * xdot;

    // showcase.jl:10: return x, ẋ
    return (step_t){x, xdot};
}

/**
 * Total energy of a particle of mass `m` at `r` moving at `v`, in a gravity well of strength `μ`.
 *
 * Julia signature: energy(m::Float64, r::SVector{3, Float64}, v::SVector{3, Float64}, μ::Float64), showcase.jl:14
 * @param[in] m   scalar
 * @param[in] r   3-vector
 * @param[in] v   3-vector
 * @param[in] mu  scalar
 */
double energy(double m, const double r[3], const double v[3], double mu) {
    // showcase.jl:14: energy(m::Float64, r::SVector{3,Float64}, v::SVector{3,Float64}, μ::Float64) = m * ((v ⋅ v) / 2 - μ / norm(r))
    return m * (dot_3(v, v) / 2 - mu / norm_3(r));
}

/**
 * Root-mean-square of the residuals `y .- ŷ`.
 *
 * Julia signature: rms(y::SVector{4, Float64}, ŷ::SVector{4, Float64}), showcase.jl:17
 * @param[in] y     4-vector
 * @param[in] yhat  4-vector
 */
double rms(const double y[4], const double yhat[4]) {
    // showcase.jl:18: e = y .- ŷ
    double e[4];
    subP_4_4(y, yhat, e);

    // showcase.jl:19: return √(sum(e .^ 2) / length(e))
    double temp1[4];
    pow2P_4(e, temp1);
    return sqrt(sum_4(temp1) / 4);
}

/**
 * Bring `θ` into (-π, π], the way an angle is usually kept.
 *
 * Julia signature: wrap(θ::Float64), showcase.jl:23
 * @param[in] theta  scalar
 */
double wrap(double theta) {
    // showcase.jl:24: θ > π && return θ - 2π
    if (theta > M_PI) {
        return theta - 2 * M_PI;
    }

    // showcase.jl:25: θ ≤ -π && return θ + 2π
    if (theta <= -M_PI) {
        return theta + 2 * M_PI;
    }

    // showcase.jl:26: return θ
    return theta;
}
