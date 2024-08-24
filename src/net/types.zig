const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const Allocator = std.mem.Allocator;

/// Errors related to the type parsing from the client
pub const ParserError = error {
    /// Not enough data providen for the type to be parsed
    InsufficientData,
    /// The number is too big to fit in an integer
    IntegerOverflow
};

pub const Bytes = struct {
    allocator: Allocator,
    data: std.ArrayList(u8),
    pub fn init(allocator: Allocator) Bytes {
        const data = std.ArrayList(u8).init(allocator);
        return Bytes {
            .allocator = allocator,
            .data = data
        };
    }

    pub fn deinit(self: Bytes) void {
        self.data.deinit();
    }
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
    /// with a limit of MAX_BYTE_COUNT items
    pub fn intoBytes(self: VarInt, bytes: *Bytes) void {
        var value = self.value; // copy value to modify it
        var i: usize = 0;
        while (true) : (i += 1) {
            var part: u8 = @intCast(value & 0x7F);
            defer bytes.*.data.append(part) catch unreachable;

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
        return;
    }
};

/// The var_long number implementation
///
/// The same number encoding that varint but for 64 bit integers.
/// See [the wiki](https://wiki.vg/Protocol#VarInt_and_VarLong) for more informations
pub const VarLong = struct {
    value: i64,
    length: usize,

    /// The value zero as a var_long
    pub const zero = VarLong{ .value = 0, .length = 1 };

    /// A var_int takes a maximum of 5 bytes, a var_long would use 10
    const MAX_BYTE_COUNT = 10;

    /// Get a var_long from an integer
    pub fn fromInt(value: i64) VarLong {
        // We have to determine the byte length of the var_long representation
        // Case 1: zero
        if (value == 0) {
            return VarLong.zero;
        }

        // Case 2: negative numbers
        if (value < 0) {
            // Minecraft don't use the Zigzag algorithm for var_int numbers so they always get the maximum number of bytes
            return VarLong{ .value = value, .length = VarLong.MAX_BYTE_COUNT };
        }

        // Case 3: positive numbers
        var length: usize = 0;
        var value_copy: i64 = value;
        while (value_copy > 0) : (length += 1) {
            // shift 7 bytes until nothing is left
            value_copy >>= 7;
        }

        return VarLong{ .value = value, .length = length };
    }

    /// Get a var_long from an array of bytes
    pub fn fromBytes(bytes: []u8) ParserError!VarLong {
        var result: i64 = 0;
        var position: u6 = 0;
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
            const segment: i64 = (@as(i64, byte) & 0x7F) << position;
            result |= segment;

            // Break if MSB is not set
            if (byte & 0x80 == 0) {
                break;
            }
        }
        return VarLong{ .value = result, .length = index + 1 };
    }

    /// Convert the var_long into binary
    /// with a limit of MAX_BYTE_COUNT items
    pub fn intoBytes(self: VarLong, bytes: *Bytes) void {
        var value = self.value; // copy value to modify it
        var i: usize = 0;
        while (true) : (i += 1) {
            var part: u8 = @intCast(value & 0x7F);
            defer bytes.*.data.append(part) catch unreachable;

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
        return;
    }
};

/// The minecraft position type
/// It is composed of a i64 broken into 3 parts representing the x;y;z coordinates
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
    pub inline fn intoBytes(self: Position, bytes: *Bytes) void {
        // endianness change
        const unigned_long: u64 = @bitCast(self);
        const bin_pos: [8]u8 = @bitCast(@byteSwap(unigned_long));
        bytes.data.appendSlice(&bin_pos) catch unreachable;
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

pub const String = struct {
    length: VarInt,
    data: []const u8,

    /// Convert a string into a VarInt prefixed string used in the
    pub inline fn new(data: []const u8) String {
        const length = VarInt.fromInt(@intCast(data.len));
        return String {.length = length,.data=data};
    }

    /// Get a string from raw bytes
    pub fn fromBytes(bytes: []u8) ParserError!String {
        const length = try VarInt.fromBytes(bytes);
        return String.new(bytes[length.length..(length.length+@as(usize,@intCast(length.value)))]);
    }

    pub fn intoBytes(self: String,bytes: *Bytes) void {
        self.length.intoBytes(bytes);
        bytes.data.appendSlice(self.data) catch unreachable;
    }

    // if needed add string manipulation functions here
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // intoBytes: 0
    const v_1 = VarInt.fromInt(0);
    var b_1 = Bytes.init(allocator);
    defer b_1.deinit();
    v_1.intoBytes(&b_1);
    try expect(b_1.data.items.len == 1);
    try expect(std.mem.eql(u8, b_1.data.items, &[_]u8{ 0 }));

    // intoBytes: 25565
    const v_2 = VarInt.fromInt(25565);
    var b_2 = Bytes.init(allocator);
    defer b_2.deinit();
    v_2.intoBytes(&b_2);
    try expect(b_2.data.items.len == 3);
    try expect(std.mem.eql(u8, b_2.data.items, &[_]u8{ 221, 199, 1 }));

    // intoBytes: 255
    const v_3 = VarInt.fromInt(255);
    var b_3 = Bytes.init(allocator);
    defer b_3.deinit();
    v_3.intoBytes(&b_3);
    try expect(b_3.data.items.len == 2);
    try expect(std.mem.eql(u8, b_3.data.items, &[_]u8{ 255, 1 }));

    // intoBytes: -1
    const v_4 = VarInt.fromInt(-1);
    var b_4 = Bytes.init(allocator);
    defer b_4.deinit();
    v_4.intoBytes(&b_4);
    try expect(b_4.data.items.len == 5);
    try expect(std.mem.eql(u8, b_4.data.items, &[_]u8{ 255, 255, 255, 255, 15 }));

    // intoBytes: -2147483648
    const v_5 = VarInt.fromInt(-2147483648);
    var b_5 = Bytes.init(allocator);
    defer b_5.deinit();
    v_5.intoBytes(&b_5);
    try expect(b_5.data.items.len == 5);
    try expect(std.mem.eql(u8, b_5.data.items, &[_]u8{ 128, 128, 128, 128, 8 }));
}

test "VarLong: fromInt" {
    // fromInt(0)
    try expect(VarLong.fromInt(0).value == 0);
    try expect(VarLong.fromInt(0).length == 1);

    // fromInt(1)
    try expect(VarLong.fromInt(1).value == 1);
    try expect(VarLong.fromInt(1).length == 1);

    // fromInt(127)
    try expect(VarLong.fromInt(127).value == 127);
    try expect(VarLong.fromInt(127).length == 1);

    // fromInt(128)
    try expect(VarLong.fromInt(128).value == 128);
    try expect(VarLong.fromInt(128).length == 2);

    // fromInt(2147483647)
    try expect(VarLong.fromInt(2147483647).value == 2147483647);
    try expect(VarLong.fromInt(2147483647).length == 5);

    // fromInt(9223372036854775807)
    try expect(VarLong.fromInt(9223372036854775807).value == 9223372036854775807);
    try expect(VarLong.fromInt(9223372036854775807).length == 9);

    // fromInt(-1)
    try expect(VarLong.fromInt(-1).value == -1);
    try expect(VarLong.fromInt(-1).length == 10);
}

test "VarLong: fromBytes" {
    // fromBytes(0)
    var value = [_]u8{ 0, 0, 0, 0, 0 };
    try expect((try VarLong.fromBytes(&value)).value == 0);
    try expect((try VarLong.fromBytes(&value)).length == 1);

    // fromBytes(1)
    value = [_]u8{ 1, 0, 0, 0, 0 };
    try expect((try VarLong.fromBytes(&value)).value == 1);
    try expect((try VarLong.fromBytes(&value)).length == 1);

    // fromBytes(127)
    value = [_]u8{ 127, 0, 0, 0, 0 };
    try expect((try VarLong.fromBytes(&value)).value == 127);
    try expect((try VarLong.fromBytes(&value)).length == 1);

    // fromBytes(128)
    value = [_]u8{ 128, 1, 0, 0, 0 };
    try expect((try VarLong.fromBytes(&value)).value == 128);
    try expect((try VarLong.fromBytes(&value)).length == 2);

    // fromBytes(2147483647)
    value = [_]u8{ 255, 255, 255, 255, 7 };
    try expect((try VarLong.fromBytes(&value)).value == 2_147_483_647);
    try expect((try VarLong.fromBytes(&value)).length == 5);

    // fromBytes(-1)
    var val = [_]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 };
    try expect((try VarLong.fromBytes(&val)).value == -1);
    try expect((try VarLong.fromBytes(&val)).length == 10);

    // fromBytes(6) (With buffer size less than 5)
    var smol_buffer = [_]u8{6};
    try expect((try VarLong.fromBytes(&smol_buffer)).value == 6);
    try expect((try VarLong.fromBytes(&smol_buffer)).length == 1);

    // Insufficient data error (we set the MSB but don't provide with the following byte)
    var missing = [_]u8{128};
    try expectError(ParserError.InsufficientData, VarInt.fromBytes(&missing));

    // Overflow (We provide with a number bigger than what an i64 can hold)
    var bigger = [_]u8{ 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 1 };
    try expectError(ParserError.IntegerOverflow, VarInt.fromBytes(&bigger));

    // Should still work if we provide extra unrelated data
    var long_buffer = [_]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 127, 23, 46, 23 };
    try expect((try VarLong.fromBytes(&long_buffer)).value == 9_223_372_036_854_775_807);
    try expect((try VarLong.fromBytes(&long_buffer)).length == 9);
}

test "VarLong: intoBytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // intoBytes: 0
    const v_1 = VarLong.fromInt(0);
    var b_1 = Bytes.init(allocator);
    defer b_1.deinit();
    v_1.intoBytes(&b_1);
    try expect(b_1.data.items.len == 1);
    try expect(std.mem.eql(u8, b_1.data.items, &[_]u8{ 0 }));

    // intoBytes: 25565
    const v_2 = VarLong.fromInt(25565);
    var b_2 = Bytes.init(allocator);
    defer b_2.deinit();
    v_2.intoBytes(&b_2);
    try expect(b_2.data.items.len == 3);
    try expect(std.mem.eql(u8, b_2.data.items, &[_]u8{ 221, 199, 1 }));


    // intoBytes: 255
    const v_3 = VarLong.fromInt(255);
    var b_3 = Bytes.init(allocator);
    defer b_3.deinit();
    v_3.intoBytes(&b_3);
    try expect(b_3.data.items.len == 2);
    try expect(std.mem.eql(u8, b_3.data.items, &[_]u8{ 255, 1 }));

    // intoBytes: -1
    const v_4 = VarLong.fromInt(-1);
    var b_4 = Bytes.init(allocator);
    defer b_4.deinit();
    v_4.intoBytes(&b_4);
    try expect(b_4.data.items.len == 10);
    try expect(std.mem.eql(u8, b_4.data.items, &[_]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 15 }));

    // intoBytes: -2147483648
    const v_5 = VarLong.fromInt(-2147483648);
    var b_5 = Bytes.init(allocator);
    defer b_5.deinit();
    v_5.intoBytes(&b_5);
    try expect(b_5.data.items.len == 10);
    try expect(std.mem.eql(u8, b_5.data.items, &[_]u8{ 128, 128, 128, 128, 248, 255, 255, 255, 255, 15 }));
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with 0
    const origin = Position.origin;
    var b_1 = Bytes.init(allocator);
    defer b_1.deinit();
    origin.intoBytes(&b_1);
    try expect(eql(u8, b_1.data.items, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }));

    // Test with wiki example
    const pos = Position.fromUnsignedLong(5046110948485792575);
    var b_2 = Bytes.init(allocator);
    defer b_2.deinit();
    pos.intoBytes(&b_2);
    try expect(eql(u8, b_2.data.items, &[_]u8{ 70, 7, 99, 44, 21, 180, 131, 63 }));
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

test "String: new" {
    const string = String.new("Hello world!");
    try expect(std.mem.eql(u8, string.data, "Hello world!"));
    try expect(string.length.value == 12);
}

test "String: fromBytes" {
    var bytes = [_]u8{3,72,101,121};
    const string = try String.fromBytes(&bytes);
    try expect(std.mem.eql(u8, string.data, "Hey"));
    try expect(string.length.value == 3);
}

test "String: intoBytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const eql = std.mem.eql;

    var string = String.new("Hey");
    var b_1 = Bytes.init(allocator);
    defer b_1.deinit();
    string.intoBytes(&b_1);
    try expect(eql(u8, b_1.data.items, &[_]u8{ 3, 72 ,101 ,121 }));

    var empty = String.new("");
    empty.intoBytes(&b_1);
    try expect(eql(u8, b_1.data.items, &[_]u8{ 3, 72 ,101 ,121, 0 }));
}
