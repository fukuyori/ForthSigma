# Third-party notices

FORTH/Sigma includes the following third-party code. The MIT License in [LICENSE](LICENSE) covers the code written for this project; the code below keeps its own copyright and license.

## CORE-MATH

Correctly rounded math functions in `src/core-math/`, used by `FSIN`, `FCOS`, `FTAN`, `FEXP`, `FLN`, `FASIN`, `FACOS`, `FATAN`, `FATAN2`, `FSINH`, `FCOSH`, `FTANH`, `FASINH`, `FACOSH`, `FATANH`, `FEXPM1`, `FLNP1`, `FLOG`, `FALOG`, and `F**`. Project: <https://core-math.gitlabpages.inria.fr/>. Details in [src/core-math/README.md](src/core-math/README.md).

```text
sin.c, cos.c, tan.c: Copyright (c) 2022-2025 Paul Zimmermann and Tom Hubrecht
exp.c: Copyright (c) 2022-2025 Alexei Sibidanov.
log.c: Copyright (c) 2022 INRIA and CERN. Authors: Paul Zimmermann and Tom Hubrecht.
dint.h: Copyright (c) 2022 CERN. Author: Tom Hubrecht
asin/asin.c: Copyright (c) 2022-2025 Alexei Sibidanov.
acos/acos.c: Copyright (c) 2024-2025 Alexei Sibidanov.
atan/atan.c: Copyright (c) 2023 Alexei Sibidanov.
atan2/atan2.c: Copyright (c) 2024-2025 Paul Zimmermann and Alexei Sibidanov
atan2/tint.h: Copyright (c) 2023-2024 Paul Zimmermann and Alexei Sibidanov
sinh/sinh.c, cosh/cosh.c, tanh/tanh.c, atanh/atanh.c, acosh/acosh.c: Copyright (c) 2023 Alexei Sibidanov.
asinh/asinh.c: Copyright (c) 2023-2025 Alexei Sibidanov.
expm1/expm1.c: Copyright (c) 2024 Alexei Sibidanov.
log1p/log1p.c: Copyright (c) 2024-2025 Alexei Sibidanov.
log1p/dint.h, log10/dint.h: Copyright (c) 2022 CERN. Author: Tom Hubrecht
log10/log10.c: Copyright (c) 2022-2025 INRIA and CERN. Authors: Paul Zimmermann and Tom Hubrecht.
exp10/exp10.c: Copyright (c) 2023-2025 Alexei Sibidanov.
pow/pow.c, pow/pow.h: Copyright (c) 2022-2025 CERN and Inria. Authors: Tom Hubrecht and Paul Zimmermann
pow/dint.h, pow/qint.h: Copyright (c) 2022, 2023 CERN and Inria. Authors: Tom Hubrecht and Paul Zimmermann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## musl

`fma` in `src/fma/fma.c`, used by the CORE-MATH functions when the CPU has no FMA instruction. Taken unmodified from the musl sources bundled with Zig 0.16.0. Project: <https://musl.libc.org/>. Details in [src/fma/README.md](src/fma/README.md).

```text
Copyright © 2005-2020 Rich Felker, et al.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
