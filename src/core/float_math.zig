const std = @import("std");

// Correctly rounded functions from CORE-MATH (src/core-math), so that results are the
// same on every system; the original gforth in Linux gets them from glibc nearly always.
pub extern fn cr_sin(x: f64) f64;

pub extern fn cr_cos(x: f64) f64;

pub extern fn cr_tan(x: f64) f64;

pub extern fn cr_exp(x: f64) f64;

pub extern fn cr_log(x: f64) f64;

/// CORE-MATH answers infinity and NaN with an all-ones NaN; x - x gives the CPU's
/// default NaN for infinity and keeps a NaN argument, as glibc and gforth do.
pub fn trig(function: *const fn (f64) callconv(.c) f64, x: f64) f64 {
    if (std.math.isNan(x) or std.math.isInf(x)) return x - x;
    return function(x);
}
