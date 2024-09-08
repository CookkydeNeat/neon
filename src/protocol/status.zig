const std = @import("std");
const String = @import("../net/types.zig").String;
const Allocator = std.mem.Allocator;
// zig fmt: off
pub  const SLPJsonResponse = struct { 
    version: struct {
        name: []const u8 = "1.21.1",
        protocol: i32 = 767,
    } = .{},

    description: struct {
        text: []const u8 = "Hello world !"
    }= .{},

    players: struct {
        max: i32 = 20,
        online: i32 = 0
    } = .{},

    pub const DEFAULT = SLPJsonResponse {};

    // Only works with ArenaAllocator because it's the only allocator able to deallocate everything without memory leaks. 
    // Might want to change this behavior in the future
    pub fn toString(self: *const SLPJsonResponse,all: *const Allocator) !String {
        var array_list = std.ArrayList(u8).init(all.*);
        try std.json.stringify(self, .{}, array_list.writer());
        const string = String.new(array_list.items);
        return string;
    }
};

pub const StatusResponse = struct {
    json_response: String,
};
// zig fmt: on
