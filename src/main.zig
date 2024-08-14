const std = @import("std");
const endianness = @import("builtin").target.cpu.arch.endian();
const net = std.net;
const print = std.debug.print;
const types = @import("net/types.zig");

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

/// Imagine having to implement the String type
const String = struct {
    len: types.VarInt,
    data: []u8,

    pub fn fromBytes(bytes: []u8) types.ParserError!String {
        const length = try types.VarInt.fromBytes(bytes);
        const data = bytes[length.length..];
        return String{ .len = length, .data = data };
    }
};

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

    const one = types.VarInt.fromBytes(message) catch types.VarInt.zero;
    const two = types.VarInt.fromBytes(message[one.length..]) catch types.VarInt.zero;

    print("{} Send packet with id {x}\n", .{ client.address, two.value });
}
