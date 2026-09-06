#include <math.h>
#include "sincos.h"

void rotate(const double v[2], double theta, double out[restrict 2]) {
    // @sincos.jl:8: s, c = sincos(θ)
    double s = sin(theta);
    double c = cos(theta);

    // @sincos.jl:9: return SVector(c * v[1] - s * v[2], s * v[1] + c * v[2])
    out[0] = c * v[0] - s * v[1];
    out[1] = s * v[0] + c * v[1];
}

void heading(float theta, float out[restrict 2]) {
    // @sincos.jl:14: s, c = sincos(θ)
    float s = sinf(theta);
    float c = cosf(theta);

    // @sincos.jl:15: return SVector(c, s)
    out[0] = c;
    out[1] = s;
}

void orbit(double r, double omega, double t, double out[restrict 2]) {
    // @sincos.jl:20: s, c = sincos(ω * t)
    double s = sin(omega * t);
    double c = cos(omega * t);

    // @sincos.jl:21: return SVector(r * c, r * s)
    out[0] = r * c;
    out[1] = r * s;
}
