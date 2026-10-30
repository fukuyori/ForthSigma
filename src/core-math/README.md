# CORE-MATH (correctly rounded math functions)

`FSIN`, `FCOS`, `FTAN`, `FEXP`, and `FLN` call `cr_sin`, `cr_cos`, `cr_tan`, `cr_exp`, and `cr_log` from these files, so that their results are correctly rounded and the same on every operating system. The original gforth in Linux gets the same results from glibc's libm in nearly every case.

- Project: CORE-MATH, <https://core-math.gitlabpages.inria.fr/>
- Taken from the GitHub mirror <https://github.com/lntue/core-math>, commit `e0a3599597503f2af90311c82e2ca92dc06c789a` (2025-04-11), `src/binary64/{sin,cos,tan,exp,log}/` and `src/binary64/log/dint.h`.
- The files are unmodified. Each keeps its copyright notice and the MIT permission notice, which apply to that file.
