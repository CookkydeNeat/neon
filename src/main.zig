const std = @import("std");
const net = std.net;
const print = std.debug.print;
const types = @import("net/types.zig");

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
