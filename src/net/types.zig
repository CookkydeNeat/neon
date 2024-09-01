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

/// The var_int number implementation
///
/// Mostly an equivalent of a i32 but optimised for small positive integer.
/// See [the wiki](https://wiki.vg/Protocol#VarInt_and_VarLong) for more informations
pub const VarInt = struct {
    buf: [5]u8,
    len: u8,

    const MAX_BYTE_COUNT = 5;
    pub fn new(value: i32) VarInt {
        var result: VarInt = undefined;
        result.len = 0;
        var tempValue = value;

        while (tempValue != 0) {
            result.buf[result.len] = @as(u8, @intCast((tempValue & 0x7F) | 0x80));
            result.len += 1;
            tempValue >>= 7;
        }
        if (result.len > 0) {
            result.buf[result.len - 1] &= 0x7F;
        } else {
            result.buf[0] = 0;
            result.len = 1;
        }
        return result;
    }

    pub fn toBytes(self: *const VarInt) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn fromSlice(data: []const u8) !VarInt {
        var result: VarInt = undefined;
        result.len = 0;

        //Count the number of bytes to copy
        while (true): (result.len+=1) {
            if (result.len > VarInt.MAX_BYTE_COUNT){
                // Too much data, type may be VarLong instead
                return error.IntegerOverflow;
            }
            if (data.len <= result.len) {
                // Not enough data
                return error.InsufficientData;
            }
            if ((data[result.len] & 0x80) ==  0) {
                result.len += 1;
                break;
            }
        }
        @memcpy(result.buf[0..result.len], data[0..result.len]);

        return result;
    }
};

/// The var_long number implementation
///
/// The same number encoding that varint but for 64 bit integers.
/// See [the wiki](https://wiki.vg/Protocol#VarInt_and_VarLong) for more informations
pub const VarLong = struct {
    buf: [10]u8,
    len: u8,

    const MAX_BYTE_COUNT = 10;
    pub fn new(value: i32) VarLong {
        var result: VarLong = undefined;
        result.len = 0;
        var tempValue = value;

        while (tempValue != 0) {
            result.buf[result.len] = @as(u8, @intCast((tempValue & 0x7F) | 0x80));
            result.len += 1;
            tempValue >>= 7;
        }
        if (result.len > 0) {
            result.buf[result.len - 1] &= 0x7F;
        } else {
            result.buf[0] = 0;
            result.len = 1;
        }
        return result;
    }

    pub fn toBytes(self: *const VarLong) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn fromSlice(data: []const u8) !VarLong {
        var result: VarLong = undefined;
        result.len = 0;

        //Count the number of bytes to copy
        while (true): (result.len+=1) {
            if (result.len > VarLong.MAX_BYTE_COUNT){
                // Too much data, type may be VarLong instead
                return error.IntegerOverflow;
            }
            if (data.len <= result.len) {
                // Not enough data
                return error.InsufficientData;
            }
            if ((data[result.len] & 0x80) ==  0) {
                result.len += 1;
                break;
            }
        }
        @memcpy(result.buf[0..result.len], data[0..result.len]);

        return result;
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
    /// Bytes are assumed to be big-endian
    pub inline fn fromSlice(data: []const u8) !Position {
        if(data.len < 8) {
            return error.InsufficientData;
        }

        const bytes: u64 = undefined;
        @memcpy(bytes, data[0..8]);
        const position: Position = @bitCast(bytes);
        return position;
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

    // pub fn intoBytes(self: String,bytes: *Bytes) void {
    //     self.length.intoBytes(bytes);
    //     bytes.data.appendSlice(self.data) catch unreachable;
    // }

    // if needed add string manipulation functions here
};

pub const Identifier = struct {
    namespace: []const u8,
    value: []const u8,

    pub const DefaultNamespace = struct {
        const Namespace = "minecraft";
        pub fn new(value: []const u8) Identifier {
            return Identifier {
                .namespace = Namespace,
                .value = value
            };
        }
    };

    pub const ServerNamespace = struct {
        const Namespace = "neon";
        pub fn new(value: []const u8) Identifier {
            return Identifier {
                .namespace = Namespace,
                .value = value
            };
        }
    };

    pub fn new(namespace: []const u8,value: []const u8) Identifier {
        return Identifier {
            .namespace = namespace,
            .value = value
        };
    }

    // pub fn intoBytes(self: Identifier, bytes: *Bytes) void {
    //     const total_length = self.namespace.len + self.value.len + 1;
    //     const length = VarInt.fromInt(@intCast(total_length));
    //     length.intoBytes(bytes);

    //     bytes.appendSlice(self.namespace) catch unreachable;
    //     bytes.append(':') catch unreachable;
    //     bytes.appendSlice(self.value) catch unreachable;
    // }
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

test "Identifier: intoBytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const eql = std.mem.eql;
    const identifier = Identifier {
        .namespace = "neon",
        .value = "test"
    };
    var bytes = Bytes.init(allocator);
    defer bytes.deinit();
    identifier.intoBytes(&bytes);
    try expect(eql(u8,bytes.data.items,&[_]u8{ 9, 110, 101, 111, 110, 58, 116, 101, 115, 116}));
}
