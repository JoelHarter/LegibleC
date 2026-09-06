#ifndef LEGIBLEC_MATHHELPER_H
#define LEGIBLEC_MATHHELPER_H

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

/// 3-vector addition
/// out = a + b
static inline void add_3(const double a[3], const double b[3], double out[3]) {
    for (int i = 0; i < 3; i++) {
        out[i] = a[i] + b[i];
    }
}

/// 2×2-matrix determinant
/// returns det(A)
static inline double det_2x2(const double A[2][2]) {
    return A[0][0] * A[1][1] - A[0][1] * A[1][0];
}

/// 3-vector / scalar division
/// out = a / b
static inline void div_3_s(const double a[3], double b, double out[3]) {
    for (int i = 0; i < 3; i++) {
        out[i] = a[i] / b;
    }
}

/// 4-vector dot product
/// returns a ⋅ b
static inline double dot_4(const double a[4], const double b[4]) {
    double sum = 0.0;
    for (int k = 0; k < 4; k++) {
        sum += a[k] * b[k];
    }
    return sum;
}

/// 4×2-matrix * 2-vector multiplication
/// out = A * b
static inline void mul_4x2_2(const double A[4][2], const double b[2], double out[restrict 4]) {
    for (int i = 0; i < 4; i++) {
        out[i] = 0.0;
        for (int k = 0; k < 2; k++) {
            out[i] += A[i][k] * b[k];
        }
    }
}

/// transposed 4×2-matrix * 4-vector multiplication
/// out = Aᵀ * b
static inline void mul_T4x2_4(const double A[4][2], const double b[4], double out[restrict 2]) {
    for (int i = 0; i < 2; i++) {
        out[i] = 0.0;
        for (int k = 0; k < 4; k++) {
            out[i] += A[k][i] * b[k];
        }
    }
}

/// transposed 4×2-matrix * 4×2-matrix multiplication
/// out = Aᵀ * B
static inline void mul_T4x2_4x2(const double A[4][2], const double B[4][2], double out[restrict 2][2]) {
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            out[i][j] = 0.0;
        }
        for (int k = 0; k < 4; k++) {
            for (int j = 0; j < 2; j++) {
                out[i][j] += A[k][i] * B[k][j];
            }
        }
    }
}

/// scalar * 3-vector multiplication
/// out = a * b
static inline void mul_s_3(double a, const double b[3], double out[3]) {
    for (int i = 0; i < 3; i++) {
        out[i] = a * b[i];
    }
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

/// 4-vector subtraction
/// out = a - b
static inline void sub_4(const double a[4], const double b[4], double out[4]) {
    for (int i = 0; i < 4; i++) {
        out[i] = a[i] - b[i];
    }
}

/// 2×2-matrix \ 2-vector solve by Cramer's rule
/// out = A \ b
static inline void solve_2x2_2(const double A[2][2], const double b[2], double out[restrict 2]) {
    double d = det_2x2(A);
    out[0] = (A[1][1] * b[0] - A[0][1] * b[1]) / d;
    out[1] = (A[0][0] * b[1] - A[1][0] * b[0]) / d;
}

#endif
