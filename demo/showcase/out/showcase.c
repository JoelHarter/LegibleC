#include <math.h>
#include "helper.h"
#include "showcase.h"

step_t step(double x, double xdot, double omega0, double zeta, double Deltat) {
    // @showcase.jl:7: ẍ = -2ζ * ω₀ * ẋ - ω₀^2 * x
    double xddot = -2 * zeta * omega0 * xdot - omega0 * omega0 * x;

    // @showcase.jl:8: ẋ += Δt * ẍ
    xdot += Deltat * xddot;

    // @showcase.jl:9: x += Δt * ẋ
    x += Deltat * xdot;

    // @showcase.jl:10: return x, ẋ
    return (step_t){x, xdot};
}

double energy(double m, const double r[3], const double v[3], double mu) {
    // @showcase.jl:14: m * ((v ⋅ v) / 2 - μ / norm(r))
    return m * (dot_3(v, v) / 2 - mu / norm_3(r));
}

double rms(const double y[4], const double yhat[4]) {
    // @showcase.jl:18: e = y .- ŷ
    double e[4];
    subP_4_4(y, yhat, e);

    // @showcase.jl:19: return √(sum(e .^ 2) / length(e))
    double temp1[4];
    pow2P_4(e, temp1);
    return sqrt(sum_4(temp1) / 4);
}

double wrap(double theta) {
    // @showcase.jl:24: θ > π && return θ - 2π
    if (theta > M_PI) {
        return theta - 2 * M_PI;
    }

    // @showcase.jl:25: θ ≤ -π && return θ + 2π
    if (theta <= -M_PI) {
        return theta + 2 * M_PI;
    }

    // @showcase.jl:26: return θ
    return theta;
}
