# Option

Every keyword option of `transpile`.

| option | default | what it does |
|---|---|---|
| `outfile` | `"juliatranspiled"` | the file name; `.c` is added if missing |
| `outpath` | `pwd()` | the folder |
| `source` | `true` | copy each Julia line above its C as `// file.jl:12: …`; comments are always carried, this controls the code lines |
| `precise` | `false` | print floats with every digit (`%.17g`) instead of `%g` |
| `portable` | `false` | define `LEGIBLEC_PI` and `LEGIBLEC_E` at the top of the file instead of using `M_PI` and `M_E`, which are POSIX rather than ISO C |
| `width` | `100` | the longest line; a long scalar expression wraps at its loosest operators |
| `templimit` | `40` | the longest name a temporary may be given before its descriptive suffix is dropped |
| `tempsuffix` | `true` | temporaries carry what they were computed from, `temp1_a_b = a + b`; off, they are `temp1`, `temp2`, … |
| `staticarray` | `true` | every array is fixed-size; `false` is refused until dynamic arrays exist |
| `spelling` | `Dict()` | your own C spellings for characters in names — see [name.md](name.md) |
