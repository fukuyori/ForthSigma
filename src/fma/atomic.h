/* Written for FORTH/Sigma: stands in for musl's internal atomic.h, of which fma.c needs
   only a_clz_64 (the count of leading zero bits of a nonzero 64-bit value). */
static inline int a_clz_64(unsigned long long x)
{
	return __builtin_clzll(x);
}
