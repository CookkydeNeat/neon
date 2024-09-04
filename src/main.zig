const std = @import("std");
const net = std.net;
const print = std.debug.print;
const types = @import("net/types.zig");
const packets = @import("net/packet.zig");

pub fn main() !void {
    // This code reads the first packet sent by a client
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();
    // Listen on localhost:25565
    // 25565 being the default minecraft server port
    const loopback = try net.Ip4Address.parse("127.0.0.1", 25565);
    const localhost = net.Address{ .in = loopback };
    var server = try localhost.listen(.{});
    defer server.deinit();

    const addr = server.listen_address;
    print("Listening on port:{}...\n", .{addr.getPort()});

    var writer = try packets.PacketWriter.init(&allocator);
    const var_int = types.VarInt.new(25565);
    try writer.appendSlice(var_int.toBytes());
    try writer.setID(0xFFFF);
    print("{d}\n", .{writer.getSlice()});
    defer writer.deinit();

    const test_data = [_]u8{ 65, 70, 0, 0, 0, 1 };
    const TestPacket = struct {
        a: f32,
        b: struct {
            r: u16,
        },
    };
    _ = TestPacket; // autofix
    var reader = packets.PacketReader.init(&test_data);
    print("{any}\n", .{try reader.readType(types.VarInt)});

    // try listen(&server,allocator);

}

pub fn listen(server: *std.net.Server, allocator: std.mem.Allocator) !void {
    while (true) {
        var client = try server.accept();
        defer client.stream.close();

        print("Connection received! {} is sending data.\n", .{client.address});

        const message = try client.stream.reader().readAllAlloc(allocator, 1024);
        defer allocator.free(message);

        const one = types.VarInt.fromSlice(message) catch types.VarInt.DEFAULT;
        const two = types.VarInt.fromSlice(message[one.len..]) catch types.VarInt.DEFAULT;

        print("{} Send packet with id {x}\n", .{ client.address, try two.getValue() });
    }
}

test {
    // IDK what this code does but without it tests won't run
    @import("std").testing.refAllDecls(@This());
}
