/* Written for FORTH/Sigma: included in front of every CORE-MATH file (see build.zig).

   CORE-MATH calls __builtin_fma. With an FMA instruction that is the instruction.
   Without one, the C library's fma would be called, and the one linked on Windows
   returns NaN when the product underflows, so FCOS gave NaN for some tiny arguments.
   musl's fma (fma.c in this folder, built as sigma_fma_software) is used instead. */
#if !defined(__FMA__) && !defined(__ARM_FEATURE_FMA)
double sigma_fma_software(double x, double y, double z);

static inline double sigma_fma(double x, double y, double z)
{
	/* musl's fma returns x*y + z for a zero z, which turns a product that underflows to
	   -0 into +0; the FMA instruction keeps the sign of the product. */
	if (z == 0) {
		double p = x * y;
		return p == 0 && x != 0 && y != 0 ? p : p + z;
	}
	return sigma_fma_software(x, y, z);
}

#define __builtin_fma sigma_fma
#endif
