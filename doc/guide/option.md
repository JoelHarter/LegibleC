# Option

Every keyword option of `transpile`.

| option | default | what it does |
|---|---|---|
| `outfile` | `"juliatranspiled"` | the file name; `.c` is added if missing |
| `helper` | `"helper"` | the name of the helper files, `helper.h` and `helper.c`; give each `transpile` call into one `out/` its own, and each keeps its helpers |
| `split` | `false` | every function in a file of its own, named after it, listed or not, with its header; every struct in a header of its own; a function's return struct with the function. `<outfile>.h` then holds the globals and includes every other header, so a caller can still include one file; `<outfile>.c` holds the mutable globals, and is written only when there are any. Names that differ only in case, `point` and `Point`, share a file named in lowercase |
| `outpath` | `pwd()` | the folder |
| `source` | `true` | copy each Julia line above its C as `// @file.jl:12: …`; comments are always carried, this controls the code lines |
| `precise` | `false` | print floats with every digit (`%.17g`) instead of `%g` |
| `portable` | `false` | define `LEGIBLEC_PI` and `LEGIBLEC_E` at the top of the file instead of using `M_PI` and `M_E`, which are POSIX rather than ISO C. Off, a file that uses `M_PI` or `M_E` still defines it under `#ifndef`, since glibc's `<math.h>` leaves them out under a strict `-std=c11` |
| `c23floattypes` | `false` | write `Float64` and `Float32` as C23's `_Float64` and `_Float32` instead of `double` and `float` |
| `bool` | `Bool` | the C type for a `Bool`: `Bool` for C's `bool`, or one of Julia's integer types for that integer wherever a `Bool` appears, names included; the C then writes `0` and `1` and reads any nonzero value as true |
| `width` | `100` | the longest line; a long scalar expression wraps at its loosest operators |
| `templimit` | `40` | the longest name a temporary may be given before its descriptive suffix is dropped |
| `tempsuffix` | `true` | temporaries carry what they were computed from, `temp1_a_b = a + b`; off, they are `temp1`, `temp2`, … |
| `staticarray` | `true` | every array is fixed-size; `false` is refused until dynamic arrays exist |
| `spelling` | `Dict()` | your own C spellings for characters in names — see [name.md](name.md) |
| `scope` | `Main` | the module a keyword variable's name is looked up in, to decide `const`; `@transpile` sets it to the module the call is written in |
| any other keyword | | a variable to include, named after the keyword — see [target.md](target.md) |
