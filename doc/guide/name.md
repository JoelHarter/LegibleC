# Name

How Julia names come out in C, and how to choose your own spellings.

Every Julia name that reaches the C is converted first, so the output uses
the names you wrote:

| Julia | C | rule |
|---|---|---|
| `omega`, `x1` | the same | ASCII letters, digits and `_` are kept |
| `ω`, `Ω`, `ħ`, `∂`, `∞` | `omega`, `Omega`, `hbar`, `partial`, `infty` | the name you type after `\` to get the character — Julia's own completion table |
| `x₁`, `x²` | `x1`, `x2` | subscripts and superscripts become plain |
| `ẋ`, `x̂`, `x⃗`, `x′` | `xdot`, `xhat`, `xvec`, `xprime` | accents and primes are named and appended |
| `🤠` | `facewithcowboyhat` | emoji are in the table too |
| `bump!` | `bump` | the `!` is dropped |
| `long`, `printf`, `write` | `long_`, `printf_`, `write_` | a word of C's or of libc's gets `_` |
| `omega` and `ω` together | `omega`, `omega_` | the one spelled that way in the Julia keeps the name, whichever comes first |
| `let x = x + 1`, `for i in 1:i` | `x_local`, `i_local` | the new variable's first value reads the old one of the same name, so it can't share it |
| an array parameter `x` you reassign | `x_local` | the function works on a copy, so the caller's array is untouched |
| a function you call `add_3` | `add_3_` | that is the name of a generated helper, whether or not your program needs it |

**Your names are kept wherever C allows it.** Two loops can each have their
`k` and `w`; a `let a` beside an outer `a` keeps its name, in a block of its
own; a parameter `g` beside a global `g` you don't use stays `g`. A name only
changes where C would otherwise resolve something differently from Julia.
Two functions or globals that both come out as one C name, with neither
spelled that way in the Julia (`φ` and `ϕ`), are refused: rename one, or give
it a spelling of its own, below.

**Modules.** A name from another module carries the module's path:
`Physics.c` is `Physics_c`, `Earth.Orbit.a` is `Earth_Orbit_a`, functions
and struct types the same. Names from the module you call `@transpile` in
(or the `scope` you pass) stay bare, and `Main` never adds a prefix.

**Your own spellings.** When the built-in spelling isn't the word you want,
give yours:

```julia
transpile(field; spelling=Dict('ħ' => "hred", '∂' => "d", 'ε' => "eps"))
```

Each key is a single character that Julia allows in a name, other than an
ASCII letter, digit or `_`, which are always themselves. Each value is the
C text to use for it: letters, digits and `_`, nothing else. The dictionary
applies to every name in the call — variables, functions, types, fields —
and is consulted both for the character as written and for what it
decomposes into, so `'ε' => "eps"` also covers the lunate `ϵ`, and the
collision rule tells the two apart. Anything not in your dictionary is
spelled as above.

The full rules, including how a function at several signatures is named
and how temporaries get their names, are in [naming.md](../naming.md).
