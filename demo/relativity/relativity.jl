# A few constants defined in a module, and two relativistic corrections that use some of them. Run it to produce out/ next to it. Look at: only the constants the functions read come out, `SI.c` and `SI.G`, as `SI_c` and `SI_G` with their values; the six others are never mentioned; `schwarzschild` comes along because `dilation` calls it; `x^2` as `x * x`.
using LegibleC

"Physical constants in SI units, CODATA 2018."
module SI
const c = 299_792_458.0       # speed of light, m/s
const G = 6.674_30e-11        # gravitational constant, m³/(kg s²)
const h = 6.626_070_15e-34    # Planck constant, J s
const ħ = h / 2π              # reduced Planck constant, J s
const k_B = 1.380_649e-23     # Boltzmann constant, J/K
const e = 1.602_176_634e-19   # elementary charge, C
const M_earth = 5.972_2e24    # mass of the Earth, kg
const R_earth = 6.371_0e6     # mean radius of the Earth, m
end

"The Lorentz factor `γ` for a speed `v`: moving clocks run slow by this."
lorentz(v::Float64) = 1 / sqrt(1 - v^2 / SI.c^2)

"The Schwarzschild radius of a mass `M`."
schwarzschild(M::Float64) = 2SI.G * M / SI.c^2

"Gravitational time dilation at a distance `r` from a mass `M`: a clock there runs at this rate relative to one far away."
dilation(M::Float64, r::Float64) = sqrt(1 - schwarzschild(M) / r)

transpile(lorentz, dilation; outpath=@__DIR__, outfile="relativity")
