const std = @import("std");
const net = std.net;
const print = std.debug.print;
const types = @import("net/types.zig");
const io = @import("net/io.zig");

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
    const String = types.String;
    const VarInt = types.VarInt;
    // zig fmt: off
    const StatusRequest = struct {};
    const PingRequest = struct {
        payload: i64
    };

    const State = enum(u8) {
        Handshaking,
        Status,
        Login,
        Transfer,
        Configuration,
        Play
    };

    const Handshaking = struct {
        protocol_version: VarInt, 
        server_addr: String, 
        server_port: u16, 
        next_state: State 
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
        var status = State.Handshaking;

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
                                const handshake = try packet.read(Handshaking);
                                print("{} sent packet with value {any}.\n", .{ client.address, handshake });
                                status = State.Status;
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
                                // zig fmt: off
                                const SLP = struct { 
                                    version: struct {
                                        name: []const u8,
                                        protocol: i32,
                                    },
                                    description: struct {
                                        text: []const u8
                                    },
                                    players: struct {
                                        max: i32,
                                        online: i32
                                    }
                                };

                                const slp = SLP{ 
                                    .version = .{ 
                                        .name = "1.21.1", 
                                        .protocol = 767 
                                    },
                                    .description = .{
                                        .text = "Hello world !"
                                    },
                                    .players = .{
                                        .max = 69,
                                        .online = 9999999
                                    }
                                };
                                // zig fmt: on

                                var buf: [1024]u8 = undefined;
                                var fba = std.heap.FixedBufferAllocator.init(&buf);
                                var string = std.ArrayList(u8).init(fba.allocator());
                                try std.json.stringify(slp, .{}, string.writer());
                                const mString = String.new(string.items);
                                var writer = try io.PacketWriter.init(&allocator);
                                defer writer.deinit();
                                try writer.appendSlice(mString.toBytes()[0]);
                                try writer.appendSlice(mString.toBytes()[1]);
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
