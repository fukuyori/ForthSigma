# fma for CPUs without an FMA instruction

The CORE-MATH functions in `src/core-math/` call `__builtin_fma`. On a CPU without an FMA instruction (the baseline x86-64 that the release builds target) that becomes a call to the C library's `fma`, and the one linked into the Windows build returns NaN when the product underflows: `FCOS` gave NaN and `FSIN` and `FTAN` lost the last bit for some tiny arguments. `build.zig` therefore includes `sigma_fma.h` in front of every CORE-MATH file, which sends `__builtin_fma` to musl's `fma` when the CPU has no FMA instruction. With an FMA instruction nothing changes.

- `fma.c`: musl's `src/math/fma.c`, taken unmodified from the musl sources bundled with Zig 0.16.0 (`lib/libc/musl/src/math/fma.c`, SHA-256 `f15e2db8c727f6cb3886dbc8817bebfcd7afff155b284be409fb961e0b985894`). It is built with `-Dfma=sigma_fma_software` so that it does not replace the C library's `fma`. musl is under the MIT license; see [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
- `atomic.h` and `sigma_fma.h`: written for this project. `atomic.h` supplies the one function `fma.c` needs from musl's internal header of that name. `sigma_fma.h` keeps the sign of a product that underflows to zero when the addend is zero, as the FMA instruction does.

Over 20 million cases (random bit patterns, products that underflow, near cancellation, and special values), this `fma` gave the same results as the FMA instruction on Windows and on Linux (musl).
