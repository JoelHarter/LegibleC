#ifndef SHOWCASE_H
#define SHOWCASE_H

/// the return value of step: x and xdot, as one struct since C returns one value
typedef struct {
    double x;
    double xdot;
} step_t;

/**
 * One semi-implicit Euler step of a damped oscillator with natural frequency `ω₀` and damping ratio `ζ`.
 *
 * Julia signature: step(x::Float64, ẋ::Float64, ω₀::Float64, ζ::Float64, Δt::Float64) @showcase.jl:6
 * @param[in] x       scalar
 * @param[in] xdot    scalar
 * @param[in] omega0  scalar
 * @param[in] zeta    scalar
 * @param[in] Deltat  scalar
 */
step_t step(double x, double xdot, double omega0, double zeta, double Deltat);

/**
 * Total energy of a particle of mass `m` at `r` moving at `v`, in a gravity well of strength `μ`.
 *
 * Julia signature: energy(m::Float64, r::SVector{3, Float64}, v::SVector{3, Float64}, μ::Float64) @showcase.jl:14
 * @param[in] m   scalar
 * @param[in] r   3-vector
 * @param[in] v   3-vector
 * @param[in] mu  scalar
 */
double energy(double m, const double r[3], const double v[3], double mu);

/**
 * Root-mean-square of the residuals `y .- ŷ`.
 *
 * Julia signature: rms(y::SVector{4, Float64}, ŷ::SVector{4, Float64}) @showcase.jl:17
 * @param[in] y     4-vector
 * @param[in] yhat  4-vector
 */
double rms(const double y[4], const double yhat[4]);

/**
 * Bring `θ` into (-π, π], the way an angle is usually kept.
 *
 * Julia signature: wrap(θ::Float64) @showcase.jl:23
 * @param[in] theta  scalar
 */
double wrap(double theta);

#endif
