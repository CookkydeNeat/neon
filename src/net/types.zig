const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

/// Errors related to the type parsing from the client
pub const ParserError = error {
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

pub const Position = packed struct {
    //Fields are inverted because low endian systems put them in reverse in memory
    y: i12 = 0,
    z: i26 = 0,
    x: i26 = 0,

    /// Represent the position at (0;0;0)
    pub const origin = Position {};

    /// Create a new position struct
    pub inline fn new(x:i26,y:i12,z:i26) Position {
        return Position {
            .x=x,
            .y=y,
            .z=z
        };
    }

    /// Return a new instance of the same object
    pub fn clone(self: Position) Position {
        return Position.new(self.x, self.y, self.z);
    }

    /// Get a position from an u64
    pub inline fn fromUnsignedLong(number: u64) Position {
        return @bitCast(number);
    }

    /// Get the position from raw bytes.
    /// Bytes are assumed sent in big-endian
    pub inline fn fromBytes(bytes: [8]u8) Position {
        // endianness change
        const unsigned_long: u64 = @bitCast(bytes);
        return Position.fromUnsignedLong(@byteSwap(unsigned_long));
    }

    /// Convert the position into bytes.
    /// Bytes are big endian
    pub inline fn intoBytes(self: Position) [8]u8 {
        // endianness change
        const unigned_long: u64 = @bitCast(self);
        return @bitCast(@byteSwap(unigned_long));
    }

    /// Add both positions together and return a new instance of position
    pub fn add(self: Position,other: Position) Position {
        var position = self.clone();
        position.x += other.x;
        position.y += other.y;
        position.z += other.z;
        return position;
    }

    /// Substract both positions and return a new instance of position
    pub fn sub(self: Position,other: Position) Position {
        return self.add(Position.new(-other.x, -other.y, -other.z));
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

test "Position: origin" {
    const origin = Position.origin;
    try expect(origin.x == 0);
    try expect(origin.y == 0);
    try expect(origin.z == 0);
}

test "Position: new" {
    const pos = Position.new(1, 2, 3);
    try expect(pos.x == 1);
    try expect(pos.y == 2);
    try expect(pos.z == 3);
}

test "Position: clone" {
    const original = Position.new(4, 5, 6);
    const clone = original.clone();

    // Fields should be equal
    try expect(std.meta.eql(original, clone));

    // Pointer should not
    try expect(&original != &clone);
}

test "Position: fromUnsignedLong" {
    const eql = std.meta.eql;

    // Test with 0
    try expect(eql(
        Position.fromUnsignedLong(0),
        Position.new(0, 0, 0)
    ));

    // Example from wiki (see wiki.vg)
    try expect(eql(
        Position.fromUnsignedLong(5046110948485792575),
        Position.new(18357644, 831, -20882616)
    ));
}

test "Position: fromBytes" {
    const eql = std.meta.eql;

    // Test with 0
    try expect(eql(
        Position.fromBytes([_]u8{0,0,0,0,0,0,0,0}),
        Position.new(0, 0, 0)
    ));

    // Example from wiki (see wiki.vg)
    try expect(eql(
        Position.fromBytes([_]u8{70, 7, 99, 44, 21, 180, 131, 63}),
        Position.new(18357644, 831, -20882616)
    ));
}

test "Position: intoBytes" {
    const eql = std.mem.eql;

    // Test with 0
    const origin = Position.origin;
    try expect(eql(u8,&origin.intoBytes(),&[_]u8{0, 0, 0, 0, 0, 0, 0, 0}));

    // Test with wiki example
    const pos = Position.fromUnsignedLong(5046110948485792575);
    try expect(eql(u8,&pos.intoBytes(),&[_]u8{70, 7, 99, 44, 21, 180, 131, 63}));
}

test "Position: add" {
    const eql = std.meta.eql;

    // Adding 0 should change nothing
    try expect(eql(Position.origin,Position.origin.add(Position.origin)));

    try expect(eql(Position.new(0, 0, 1),Position.origin.add(Position.new(0, 0, 1))));

    try expect(eql(
        Position.new(1, 2, 3)
            .add(Position.new(2, 2, 2)),
        Position.new(3, 4, 5)
    ));

    try expect(eql(
        Position.new(9, -5, 43)
            .add(Position.new(-2, 3, 55)),
        Position.new(57, 3, 0)
            .add(Position.new(-50, -5,98))
    ));
}

test "Position: sub" {
    const eql = std.meta.eql;

    // Adding 0 should change nothing
    try expect(eql(Position.origin,Position.origin.sub(Position.origin)));

    try expect(eql(Position.new(0, 0, -1),Position.origin.sub(Position.new(0, 0, 1))));

    try expect(eql(
        Position.new(1, 2, 3)
            .sub(Position.new(2, 2, 2)),
        Position.new(-1, 0, 1)
    ));

    try expect(eql(
        Position.new(9, -5, 43)
            .sub(Position.new(-2, 3, 55)),
        Position.new(57, 3, 0)
            .sub(Position.new(46, 11,12))
    ));
}
