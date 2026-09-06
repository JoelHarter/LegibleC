# demo

Worked examples that show what the transpiler does, for people deciding
whether to use it. Nothing here is a test — `test/` proves it works; this
folder shows it off. Each example is a folder with a small Julia file that
reads as a physicist or engineer would write it, and an empty `out/`. Run
the file — `julia showcase.jl` in its folder — and `out/` fills with the C:
a header a caller includes, the functions, the helpers. The comment at the
top of each file says what to look at.

- [orbit/](orbit/orbit.jl) — one step of gravity and a least-squares fit:
  arrays, a reduction, reassignment with the copy comment, the step comments.
- [showcase/](showcase/showcase.jl) — a damped oscillator step, an energy,
  an RMS, an angle wrap: Unicode names, `+=`, a tuple returned as the
  function's own struct, `&& return` as an `if`.
- [sincos/](sincos/sincos.jl) — `s, c = sincos(θ)` in three settings: one
  Julia line becoming two C lines, `sinf` for `Float32`, an expression
  argument carried into both.

More candidates are in `doc/dev/todo.md`.
