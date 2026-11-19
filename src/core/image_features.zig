//! Build-specific preflight, separate from the target-independent wire codec.
const defs = @import("defs.zig");
pub fn validateWord(word: defs.Word, index: usize, builtin_count: usize) defs.RuntimeError!void {
    // Disabled base words keep reserved, nameless slots and stable execution tokens.
    if (index >= builtin_count and word.kind == .builtin and defs.isExcludedBuiltin(word.builtin)) return error.InvalidImage;
}
pub fn validateOperation(op: defs.Op) defs.RuntimeError!void {
    if (op.kind != .builtin) return;
    if (op.value < 0 or op.value >= @typeInfo(defs.Builtin).@"enum".field_names.len) return error.InvalidImage;
    if (defs.isExcludedBuiltin(@fromBackingInt(@intCast(op.value)))) return error.InvalidImage;
}
