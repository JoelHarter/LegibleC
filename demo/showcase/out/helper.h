#ifndef LEGIBLEC_HELPER_H
#define LEGIBLEC_HELPER_H

#include <math.h>

/// 3-vector dot product
/// returns a ⋅ b
static inline double dot_3(const double a[3], const double b[3]) {
    double sum = 0.0;
    for (int k = 0; k < 3; k++) {
        sum += a[k] * b[k];
    }
    return sum;
}

/// 3-vector norm
/// returns norm(a)
static inline double norm_3(const double a[3]) {
    double sum = 0.0;
    for (int i = 0; i < 3; i++) {
        sum += a[i] * a[i];
    }
    return sqrt(sum);
}

/// 4-vector element-wise square
/// out = a .^ 2
static inline void pow2P_4(const double a[4], double out[4]) {
    for (int i = 0; i < 4; i++) {
        out[i] = a[i] * a[i];
    }
}

/// 4-vector element-wise subtraction
/// out = a .- b
static inline void subP_4_4(const double a[4], const double b[4], double out[4]) {
    for (int i = 0; i < 4; i++) {
        out[i] = a[i] - b[i];
    }
}

/// 4-vector sum
/// returns sum(a)
static inline double sum_4(const double a[4]) {
    double sum = 0.0;
    for (int i = 0; i < 4; i++) {
        sum += a[i];
    }
    return sum;
}

#endif
