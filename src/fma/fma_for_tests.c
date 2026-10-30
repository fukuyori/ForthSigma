/* Written for FORTH/Sigma: built into the tests only, with sigma_fma.h in front as for the
   CORE-MATH files, so the tests call __builtin_fma as CORE-MATH gets it. */
double sigma_fma_for_tests(double x, double y, double z)
{
	return __builtin_fma(x, y, z);
}
