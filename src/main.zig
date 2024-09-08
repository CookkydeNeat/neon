const std = @import("std");
const net = std.net;
const print = std.debug.print;
const types = @import("net/types.zig");
const io = @import("net/io.zig");
const proto_handshake = @import("protocol/handshake.zig");
const proto_status = @import("protocol/status.zig");
const enums = @import("protocol/enums.zig");

pub fn main() !void {
    // This code reads the first packet sent by a client
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const all = gpa.allocator();
    // Listen on localhost:25565
    // 25565 being the default minecraft server port
    const loopback = try net.Ip4Address.parse("127.0.0.1", 25565);
    const localhost = net.Address{ .in = loopback };
    var server = try localhost.listen(.{});
    defer server.deinit();

    const addr = server.listen_address;
    print("Listening on port:{}...\n", .{addr.getPort()});

    try listen(&server, all);
}

pub fn listen(server: *std.net.Server, allocator: std.mem.Allocator) !void {
    // zig fmt: off
    const StatusRequest = struct {};
    const PingRequest = struct {
        payload: i64
    };
    // zig fmt: on

    const reader = io.PacketReader;
    const TIMEOUT_DURATION = std.time.ns_per_s * 5; // Timeout of 5 seconds

    while (true) {
        // Accept a new client connection
        var client = try server.accept();
        defer client.stream.close(); // Ensure the stream is closed when done

        print("Connection received! {} is sending data.\n", .{client.address});

        var start_time = std.time.timestamp();
        var timed_out = false;
        var status = enums.State.Handshaking;

        while (true) {
            // Check if the connection has timed out
            const current_time = std.time.timestamp();
            if (current_time - start_time > TIMEOUT_DURATION) {
                print("Client {} timed out due to inactivity.\n", .{client.address});
                timed_out = true;
                break; // Exit inner loop due to timeout
            }

            // Allocate buffer for reading data
            const buffer = try allocator.alloc(u8, 1024);
            defer allocator.free(buffer);

            // Perform a non-blocking read (this should return an error or 0 if no data is available)
            const bytes_read = client.stream.reader().read(buffer) catch |err| {
                if (err == error.WouldBlock) {
                    // No data available, continue waiting
                    std.time.sleep(100 * std.time.ns_per_ms); // Wait 100ms before retrying
                    continue;
                } else {
                    return err; // Handle other read errors
                }
            };

            // If no data is read, the client has closed the connection
            if (bytes_read == 0) {
                print("Client {} disconnected.\n", .{client.address});
                break; // Exit the inner loop and close the connection
            }

            // Process the buffer (only up to the number of bytes actually read)
            print("Received {d} bytes from client {}.\n", .{ bytes_read, client.address });

            var packet = reader.init(buffer[0..bytes_read]); // Pass only valid data

            while (packet.offset < bytes_read) {
                const header = try packet.readHeader();

                print("Header: {any}\n", .{header});
                switch (status) {
                    .Handshaking => {
                        switch (try header.id.getValue()) {
                            0 => {
                                const handshake = try packet.read(proto_handshake.Handshaking);
                                print("{} sent packet with value {any}.\n", .{ client.address, handshake });
                                status = enums.State.Status;
                                print("Going into Status state\n", .{});
                            },
                            else => {
                                print("Unknown packet id {any} (should be 0)\n", .{header.id});
                            },
                        }
                    },
                    .Status => {
                        switch (try header.id.getValue()) {
                            0 => {
                                const ping = try packet.read(StatusRequest);
                                print("{} sent packet with value {any}.\n", .{ client.address, ping });
                                var arena = std.heap.ArenaAllocator.init(allocator);
                                const response = proto_status.SLPJsonResponse.DEFAULT;
                                const string = try response.toString(&arena.allocator());
                                defer arena.deinit();
                                var writer = try io.PacketWriter.init(&allocator);
                                defer writer.deinit();
                                const status_response = proto_status.StatusResponse{ .json_response = string };
                                try writer.write(status_response);
                                try writer.setID(0x00);
                                try client.stream.writeAll(writer.getSlice());
                                print("Sent status\n", .{});
                            },
                            1 => {
                                const ping = try packet.read(PingRequest);
                                print("{} sent packet with value {any}.\n", .{ client.address, ping });
                                var writer = try io.PacketWriter.init(&allocator);
                                defer writer.deinit();
                                try writer.write(ping.payload);
                                try writer.setID(0x01);
                                try client.stream.writeAll(writer.getSlice());
                                print("Sent pong\n", .{});
                            },
                            else => {
                                print("Unimplemented packet id {any}\n", .{header.id});
                            },
                        }
                    },
                    else => {
                        print("Unimplemented status {any}\n", .{status});
                    },
                }
            }

            // Reset start_time as data was received successfully, resetting the timeout window
            start_time = std.time.timestamp();
        }

        if (timed_out) {
            // Handle timeout (optional logging or additional steps if needed)
            print("Client {} was disconnected due to timeout.\n", .{client.address});
        }
    }
}

test {
    // IDK what this code does but without it tests won't run
    @import("std").testing.refAllDecls(@This());
}
