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
| `long`, `printf` | `long_`, `printf_` | a C reserved word gets `_` |
| `omega` and `ω` together | `omega`, `omega_` | a collision gets `_` |

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
