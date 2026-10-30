//! Correctly rounded math functions from CORE-MATH (src/core-math).

const std = @import("std");

// Correctly rounded functions from CORE-MATH (src/core-math), so that results are the
// same on every system; the original gforth in Linux gets them from glibc nearly always.
pub extern fn cr_sin(x: f64) f64;

pub extern fn cr_cos(x: f64) f64;

pub extern fn cr_tan(x: f64) f64;

pub extern fn cr_exp(x: f64) f64;

pub extern fn cr_log(x: f64) f64;

pub extern fn cr_asin(x: f64) f64;

pub extern fn cr_acos(x: f64) f64;

pub extern fn cr_atan(x: f64) f64;

pub extern fn cr_atan2(y: f64, x: f64) f64;

pub extern fn cr_sinh(x: f64) f64;

pub extern fn cr_cosh(x: f64) f64;

pub extern fn cr_tanh(x: f64) f64;

pub extern fn cr_asinh(x: f64) f64;

pub extern fn cr_acosh(x: f64) f64;

pub extern fn cr_atanh(x: f64) f64;

pub extern fn cr_expm1(x: f64) f64;

pub extern fn cr_log1p(x: f64) f64;

pub extern fn cr_log10(x: f64) f64;

pub extern fn cr_exp10(x: f64) f64;

pub extern fn cr_pow(x: f64, y: f64) f64;

/// CORE-MATH answers infinity and NaN with an all-ones NaN; x - x gives the CPU's
/// default NaN for infinity and keeps a NaN argument, as glibc and gforth do.
pub fn trig(function: *const fn (f64) callconv(.c) f64, x: f64) f64 {
    if (std.math.isNan(x) or std.math.isInf(x)) return x - x;
    return function(x);
}

/// Which NaN an argument outside the domain gives. The original gforth (glibc on x86-64)
/// gives a positive NaN for FASIN, FACOS, and FLOG and the CPU's default NaN, as 0/0
/// gives it, for the other functions; CORE-MATH's sign differs for some of them.
pub const DomainNan = enum { positive, default };

/// A function of one argument; a NaN argument comes back as CORE-MATH returns it.
pub fn unary(function: *const fn (f64) callconv(.c) f64, x: f64, comptime domain: DomainNan) f64 {
    const result = function(x);
    if (!std.math.isNan(result) or std.math.isNan(x)) return result;
    return domainNan(x, domain);
}

/// F** (pow); a NaN argument comes back as CORE-MATH returns it.
pub fn power(x: f64, y: f64) f64 {
    const result = cr_pow(x, y);
    if (!std.math.isNan(result) or std.math.isNan(x) or std.math.isNan(y)) return result;
    return domainNan(x, .default);
}

fn domainNan(x: f64, comptime domain: DomainNan) f64 {
    if (domain == .positive) return std.math.nan(f64);
    // 0/0 at run time, so that it is the CPU's default NaN (for an infinite x, x - x is
    // already that NaN); x is not NaN here.
    const zero = x - x;
    return zero / zero;
}

/// FROUND: to the nearest integer, ties to even, keeping the sign of zero (-0.4 gives
/// -0), as gforth does.
pub fn roundHalfEven(x: f64) f64 {
    // From 2^52 on every double is an integer; infinity and NaN come back unchanged.
    if (!(@abs(x) < 0x1p52)) return x;
    const shift = std.math.copysign(@as(f64, 0x1p52), x);
    return std.math.copysign((x + shift) - shift, x);
}
