const std = @import("std");
const endianness = @import("builtin").target.cpu.arch.endian();
const net = std.net;
const print = std.debug.print;

const ParserError = error{ MissingData, InvalidData };

/// Experimental VarInt implementation
///
/// See [the wiki](https://wiki.vg/Protocol#VarInt_and_VarLong) for more informations
const VarInt = struct {
    value: i32,
    length: usize,

    const zero = VarInt{ .value = 0, .length = 1 };

    pub fn fromBytes(bytes: []u8) ParserError!VarInt {
        const VarIntLength = 5;
        var result: i32 = 0;
        var position: u5 = 0;
        var index: usize = 0;
        while (true) : (index += 1) {
            if (index >= VarIntLength) {
                // VarInt should not be longer than 5 bytes
                return ParserError.InvalidData;
            }

            if (index >= bytes.len) {
                // No more data but last byte still had the MSB set
                return ParserError.MissingData;
            }

            const byte = bytes[index];
            const segment: i32 = (@as(i32, byte) & 0x7F) << position;
            result |= segment;
            position += 7;

            // Break if MSB is not set
            if (byte & 0x80 == 0) {
                break;
            }
        }
        return VarInt{ .value = result, .length = index + 1 };
    }
};

/// Experimental Position implementation
///
/// See [the wiki](https://wiki.vg/Protocol#Position) for more informations
const Position = packed struct {
    x: i26,
    z: i26,
    y: i12,

    pub fn fromRaw(number: u64) Position {
        const position: Endian_Position() = @bitCast(number);
        return Position{ .x = position.x, .z = position.z, .y = position.y };
    }

    pub fn fromBytes(bytes: [8]u8) Position {
        return Position.fromRaw(@bitCast(bytes));
    }

    pub fn intoBytes(self: Position) [8]u8 {
        const ordered_position_type = packed struct {
            y: i12,
            z: i26,
            x: i26,
        };

        const ordered_position = ordered_position_type{ .y = self.y, .z = self.z, .x = self.x };

        return @bitCast(ordered_position);
    }

    fn Endian_Position() type {
        // Is all of this really useful ?
        // Few computers nowadays are big endian
        // I only added this because I want the main struct to have this particular order
        switch (endianness) {
            std.builtin.Endian.little => {
                return packed struct {
                    y: i12,
                    z: i26,
                    x: i26,
                };
            },
            std.builtin.Endian.big => {
                return packed struct {
                    x: i26,
                    z: i26,
                    y: i12,
                };
            },
        }
    }
};

/// Debug function
pub fn printStructAsBytes(comptime T: type, instance: T) void {
    const byteSlice: [*]const u8 = @ptrCast(&instance);

    const aa = byteSlice[0..@sizeOf(T)];
    for (aa) |byte| {
        std.debug.print("{b:0>8}", .{byte});
    }
    std.debug.print("\n", .{});
}

/// Imagine having to implement the String type
const String = struct {
    len: VarInt,
    data: []u8,

    pub fn fromBytes(bytes: []u8) ParserError!String {
        const length = try VarInt.fromBytes(bytes);
        const data = bytes[length.length..];
        return String{ .len = length, .data = data };
    }
};

// The following code is not even working I was testing things
const Handshake = struct { protocol_version: VarInt, server_address: String, server_port: u16, next_state: VarInt };

pub fn readType(comptime T: type, data: []u8) ParserError!T {
    _ = data; // compilation fix, fuk u compiler I do what I want
}

// Hell nah
pub fn readPacket(comptime T: type, data: []u8) ParserError!T {
    inline for (std.meta.fields(T)) |field| {
        const inst = field.type.fromBytes(data);
        print("{}\n", .{inst});
    }
    data[0] = 1;
    return ParserError.InvalidData;
}

pub fn main() !void {
    // This code reads the first packet sent by a client
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Listen on localhost:25565
    // 25565 being the default minecraft server port
    const loopback = try net.Ip4Address.parse("127.0.0.1", 25565);
    const localhost = net.Address{ .in = loopback };
    var server = try localhost.listen(.{});
    defer server.deinit();

    const addr = server.listen_address;
    print("Listening on port:{}...\n", .{addr.getPort()});

    var client = try server.accept();
    defer client.stream.close();

    print("Connection received! {} is sending data.\n", .{client.address});

    const message = try client.stream.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(message);

    const one = VarInt.fromBytes(message) catch VarInt.zero;
    const two = VarInt.fromBytes(message[one.length..]) catch VarInt.zero;
    _ = try readPacket(Handshake, message[one.length + two.length ..]);

    print("{} Send packet with id {x}\n", .{ client.address, two.value });
}
