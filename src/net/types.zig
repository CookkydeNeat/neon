const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

/// Errors related to the type parsing from the client
pub const ParserError = error{
    /// Not enough data providen for the type to be parsed
    InsufficientData,
    /// The number is too big to fit in an integer
    IntegerOverflow
};

/// The var_int number implementation
///
/// Mostly an equivalent of a i32 but optimised for small positive integer.
/// See [the wiki](https://wiki.vg/Protocol#VarInt_and_VarLong) for more informations
pub const VarInt = struct {
    value: i32,
    length: usize,

    /// The value zero as a var_int
    pub const zero = VarInt{ .value = 0, .length = 1 };

    /// A var_int takes a maximum of 5 bytes, a var_long would use 10
    const MAX_BYTE_COUNT = 5;

    /// Get a var_int from an integer
    pub fn fromInt(value: i32) VarInt {
        // We have to determine the byte length of the var_int representation
        // Case 1: zero
        if (value == 0) {
            return VarInt.zero;
        }

        // Case 2: negative numbers
        if (value < 0) {
            // Minecraft don't use the Zigzag algorithm for var_int numbers so they always get the maximum number of bytes
            return VarInt{ .value = value, .length = VarInt.MAX_BYTE_COUNT };
        }

        // Case 3: positive numbers
        var length: usize = 0;
        var value_copy: i32 = value;
        while (value_copy > 0) : (length += 1) {
            // shift 7 bytes until nothing is left
            value_copy >>= 7;
        }

        return VarInt{ .value = value, .length = length };
    }

    /// Get a var_int from an array of bytes
    pub fn fromBytes(bytes: []u8) ParserError!VarInt {
        var result: i32 = 0;
        var position: u5 = 0;
        var index: usize = 0;
        while (true) : ({
            index += 1;
            if (index >= MAX_BYTE_COUNT) {
                // VarInt should not be longer than 5 bytes
                return ParserError.IntegerOverflow;
            }

            // Update position after index because we could get an overflow
            position += 7;
        }) {
            if (index >= bytes.len) {
                // No more data but last byte still had the MSB set
                return ParserError.InsufficientData;
            }

            const byte = bytes[index];
            const segment: i32 = (@as(i32, byte) & 0x7F) << position;
            result |= segment;

            // Break if MSB is not set
            if (byte & 0x80 == 0) {
                break;
            }
        }
        return VarInt{ .value = result, .length = index + 1 };
    }

    /// Convert the var_int into binary
    /// The result is a [BoundedArray](https://ziglang.org/documentation/master/std/#std.bounded_array.BoundedArray)
    /// with a limit of MAX_BYTE_COUNT items
    pub fn intoBytes(self: VarInt) std.BoundedArray(u8, MAX_BYTE_COUNT) {
        var bytes = std.BoundedArray(u8, MAX_BYTE_COUNT).init(0) catch unreachable;
        var value = self.value; // copy value to modify it
        var i: usize = 0;
        while (true) : (i += 1) {
            var part = value & 0x7F;
            defer bytes.append(@intCast(part)) catch unreachable;

            value >>= 7;
            if (value == 0) {
                break;
            } else {
                part |= 0x80;
            }

            if (i >= MAX_BYTE_COUNT - 1) {
                part &= 0x0F;
                break;
            }
        }
        return bytes;
    }
};

test "VarInt: fromInt" {
    // fromInt(0)
    try expect(VarInt.fromInt(0).value == 0);
    try expect(VarInt.fromInt(0).length == 1);

    // fromInt(1)
    try expect(VarInt.fromInt(1).value == 1);
    try expect(VarInt.fromInt(1).length == 1);

    // fromInt(127)
    try expect(VarInt.fromInt(127).value == 127);
    try expect(VarInt.fromInt(127).length == 1);

    // fromInt(128)
    try expect(VarInt.fromInt(128).value == 128);
    try expect(VarInt.fromInt(128).length == 2);

    // fromInt(2147483647)
    try expect(VarInt.fromInt(2147483647).value == 2147483647);
    try expect(VarInt.fromInt(2147483647).length == 5);

    // fromInt(-1)
    try expect(VarInt.fromInt(-1).value == -1);
    try expect(VarInt.fromInt(-1).length == 5);
}

test "VarInt: fromBytes" {
    // fromBytes(0)
    var value = [_]u8{ 0, 0, 0, 0, 0 };
    try expect((try VarInt.fromBytes(&value)).value == 0);
    try expect((try VarInt.fromBytes(&value)).length == 1);

    // fromBytes(1)
    value = [_]u8{ 1, 0, 0, 0, 0 };
    try expect((try VarInt.fromBytes(&value)).value == 1);
    try expect((try VarInt.fromBytes(&value)).length == 1);

    // fromBytes(127)
    value = [_]u8{ 127, 0, 0, 0, 0 };
    try expect((try VarInt.fromBytes(&value)).value == 127);
    try expect((try VarInt.fromBytes(&value)).length == 1);

    // fromBytes(128)
    value = [_]u8{ 128, 1, 0, 0, 0 };
    try expect((try VarInt.fromBytes(&value)).value == 128);
    try expect((try VarInt.fromBytes(&value)).length == 2);

    // fromBytes(2147483647)
    value = [_]u8{ 255, 255, 255, 255, 7 };
    try expect((try VarInt.fromBytes(&value)).value == 2_147_483_647);
    try expect((try VarInt.fromBytes(&value)).length == 5);

    // fromBytes(-1)
    value = [_]u8{ 255, 255, 255, 255, 15 };
    try expect((try VarInt.fromBytes(&value)).value == -1);
    try expect((try VarInt.fromBytes(&value)).length == 5);

    // fromBytes(6) (With buffer size less than 5)
    var smol_buffer = [_]u8{6};
    try expect((try VarInt.fromBytes(&smol_buffer)).value == 6);
    try expect((try VarInt.fromBytes(&smol_buffer)).length == 1);

    // Insufficient data error (we set the MSB but don't provide with the following byte)
    var missing = [_]u8{128};
    try expectError(ParserError.InsufficientData, VarInt.fromBytes(&missing));

    // Overflow (We provide with a number bigger than what an i32 can hold)
    var bigger = [_]u8{ 128, 128, 128, 128, 128, 1 };
    try expectError(ParserError.IntegerOverflow, VarInt.fromBytes(&bigger));

    // Should still work if we provide extra unrelated data
    var long_buffer = [_]u8{ 255, 255, 255, 255, 7, 45, 23, 66 };
    try expect((try VarInt.fromBytes(&long_buffer)).value == 2_147_483_647);
    try expect((try VarInt.fromBytes(&long_buffer)).length == 5);
}

test "VarInt: intoBytes" {
    // intoBytes: 0
    const v_1 = VarInt.fromInt(0);
    try expect(v_1.intoBytes().len == 1);
    try expect(std.mem.eql(u8, &v_1.intoBytes().buffer, &[_]u8{ 0, 0, 0, 0, 0 }));

    // intoBytes: 25565
    const v_2 = VarInt.fromInt(25565);
    try expect(v_2.intoBytes().len == 3);
    try expect(std.mem.eql(u8, &v_2.intoBytes().buffer, &[_]u8{ 221, 199, 1, 0, 0 }));

    // intoBytes: 255
    const v_3 = VarInt.fromInt(255);
    try expect(v_3.intoBytes().len == 2);
    try expect(std.mem.eql(u8, &v_3.intoBytes().buffer, &[_]u8{ 255, 1, 0, 0, 0 }));

    // intoBytes: -1
    const v_4 = VarInt.fromInt(-1);
    try expect(v_4.intoBytes().len == 5);
    try expect(std.mem.eql(u8, &v_4.intoBytes().buffer, &[_]u8{ 255, 255, 255, 255, 15 }));

    // intoBytes: -2147483648
    const v_5 = VarInt.fromInt(-2147483648);
    try expect(v_5.intoBytes().len == 5);
    try expect(std.mem.eql(u8, &v_5.intoBytes().buffer, &[_]u8{ 128, 128, 128, 128, 8 }));
}
