

pub fn writeU32(output: []u8, value: anytype) void {
    const number: u32 = @intCast(value);
    output[0] = @truncate(number);
    output[1] = @truncate(number >> 8);
    output[2] = @truncate(number >> 16);
    output[3] = @truncate(number >> 24);
}

pub fn readU32(input: []const u8) u32 {
    return @as(u32, input[0]) | (@as(u32, input[1]) << 8) | (@as(u32, input[2]) << 16) | (@as(u32, input[3]) << 24);
}
