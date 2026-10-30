# CORE-MATH (correctly rounded math functions)

`FSIN`, `FCOS`, `FTAN`, `FEXP`, and `FLN` call `cr_sin`, `cr_cos`, `cr_tan`, `cr_exp`, and `cr_log` from these files, and `FASIN`, `FACOS`, `FATAN`, `FATAN2`, `FSINH`, `FCOSH`, `FTANH`, `FASINH`, `FACOSH`, `FATANH`, `FEXPM1`, `FLNP1`, `FLOG`, `FALOG`, and `F**` call `cr_asin`, `cr_acos`, `cr_atan`, `cr_atan2`, `cr_sinh`, `cr_cosh`, `cr_tanh`, `cr_asinh`, `cr_acosh`, `cr_atanh`, `cr_expm1`, `cr_log1p`, `cr_log10`, `cr_exp10`, and `cr_pow`, so that their results are correctly rounded and the same on every operating system. The original gforth in Linux gets the same results from glibc's libm in nearly every case.

- Project: CORE-MATH, <https://core-math.gitlabpages.inria.fr/>
- Taken from the GitHub mirror <https://github.com/lntue/core-math>, commit `e0a3599597503f2af90311c82e2ca92dc06c789a` (2025-04-11), `src/binary64/{sin,cos,tan,exp,log}/` and `src/binary64/log/dint.h` (in this folder), and the `.c` and `.h` files of `src/binary64/{asin,acos,atan,atan2,sinh,cosh,tanh,asinh,acosh,atanh,expm1,log1p,log10,exp10,pow}/` (one folder each here, since their `dint.h` files differ).
- The files are unmodified. Each keeps its copyright notice and the MIT permission notice, which apply to that file.
- `build.zig` puts `../fma/sigma_fma.h` in front of each file, so that `__builtin_fma` uses musl's `fma` when the CPU has no FMA instruction (see [../fma/README.md](../fma/README.md)).
