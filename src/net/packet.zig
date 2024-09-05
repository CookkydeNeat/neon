const std = @import("std");
const types = @import("types.zig");
const cmp = @import("./../utils/cmp.zig");
const VarInt = types.VarInt;
const VarLong = types.VarLong;
const String = types.String;
const Position = types.Position;

pub const PacketWriter = struct {
    buffer: std.ArrayList(u8),

    const DEFAULT_CAPACITY = 2 * types.VarInt.MAX_BYTE_COUNT + 16;

    pub fn init(allocator: *const std.mem.Allocator) !PacketWriter {
        var buffer = try std.ArrayList(u8).initCapacity(allocator.*, DEFAULT_CAPACITY);

        // Make some space for two VarInts
        try buffer.appendNTimes(0, 2 * types.VarInt.MAX_BYTE_COUNT);
        return PacketWriter{ .buffer = buffer };
    }

    pub fn setID(self: *PacketWriter, ID: i32) !void {
        // Get ID as varint
        const idVarInt = VarInt.new(ID);
        const idBytes = idVarInt.toBytes();

        // Copy ID at the start of the buffer but padding left
        const indexStart = 5 + (5 - idBytes.len);
        const indexEnd = indexStart + idBytes.len;
        @memcpy(self.buffer.items[indexStart..indexEnd], idBytes);

        // Calculate packet length (data + id) and repeat the same process than above
        const packetLength: usize = self.buffer.items.len - indexStart;
        const packetLengthVarInt = VarInt.new(@intCast(packetLength));
        const packetLengthBytes = packetLengthVarInt.toBytes();

        const packetStart = indexStart - packetLengthBytes.len;
        @memcpy(self.buffer.items[packetStart..indexStart], packetLengthBytes);

        // Remove useless data
        // IDK if it would be useful to deallocate it, couldn't find a way to do it
        self.buffer.items = self.buffer.items[packetStart..];
    }

    pub fn write(self: *PacketWriter, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Int => {
                try self.appendSlice(std.mem.asBytes(&@byteSwap(value)));
            },
            else => @compileError("Type " ++ @typeName(T) ++ " cannot be written !"),
        }
    }

    pub fn deinit(self: *PacketWriter) void {
        self.buffer.deinit();
    }

    pub fn appendSlice(self: *PacketWriter, data: []const u8) !void {
        try self.buffer.appendSlice(data);
    }

    pub fn getSlice(self: *PacketWriter) []u8 {
        return self.buffer.items;
    }
};

pub const PacketReader = struct {
    buffer: []const u8,
    offset: usize,

    pub fn init(data: []const u8) PacketReader {
        return PacketReader{ .buffer = data, .offset = 0 };
    }

    /// Read the given type
    /// For integers use big endian
    /// note: Don't use with u8 or fewer, the std have a bug, see [#20409](https://github.com/ziglang/zig/issues/20409)
    pub fn read(self: *PacketReader, comptime T: type) !T {
        if (T == u8) {
            @compileError("This function can't be used on u8. Will be fixed in 0.14");
        }
        switch (@typeInfo(T)) {
            .Int => |int_info| {
                const read_length = @as(usize, @divExact(int_info.bits, 8));
                const data = try self.readExact(read_length);
                const integer: T = std.mem.readVarInt(T, data, std.builtin.Endian.big);

                return integer;
            },
            .Float => |float_info| {
                const read_length = @as(usize, @divExact(float_info.bits, 8));
                const data = try self.readExact(read_length);
                const float: T = @bitCast(std.mem.readVarInt(std.meta.Int(.unsigned, float_info.bits), data, std.builtin.Endian.big));

                return float;
            },
            .Struct => |struct_info| {
                switch (T) {
                    VarInt => return self.readVarInt(),
                    VarLong => return self.readVarInt(),
                    String => return self.readString(),
                    Position => return self.readPosition(),
                    else => {
                        var struct_decl: T = undefined;
                        const fields = struct_info.fields;
                        inline for (fields) |field| {
                            @field(struct_decl, field.name) = try self.read(field.type);
                        }
                        return struct_decl;
                    },
                }
            },
            .Enum => {
                const var_int = try self.readVarInt();
                const integer = try var_int.getValue();
                const enum_value: T = @enumFromInt(integer);
                return enum_value;
            },
            //TODO work with floats
            else => @compileError("Type " ++ @typeName(T) ++ " cannot be read !"),
        }
    }

    pub fn readHeader(self: *PacketReader) !PacketHeader {
        return self.read(PacketHeader);
    }

    fn readVarInt(self: *PacketReader) !VarInt {
        const remaining = cmp.min(usize, self.buffer.len - self.offset, VarInt.MAX_BYTE_COUNT);
        const data = try self.readExact(remaining);
        const var_int = try VarInt.fromSlice(data);
        self.offset -= remaining - var_int.len;
        return var_int;
    }

    fn readVarLong(self: *PacketReader) !VarInt {
        const remaining = cmp.min(usize, self.buffer.len - self.offset, VarLong.MAX_BYTE_COUNT);
        const data = try self.readExact(remaining);
        const var_long = try VarLong.fromSlice(data);
        self.offset -= remaining - var_long.len;
        return var_long;
    }

    fn readPosition(self: *PacketReader) !Position {
        const data = try self.readExact(8);
        const position = Position.fromSlice(data);
        return position;
    }

    inline fn readString(self: *PacketReader) !String {
        const string = try String.fromSlice(self.buffer[self.offset..]);
        self.offset += string.length.len;
        self.offset += string.data.len;

        return string;
    }

    fn readExact(self: *PacketReader, size: usize) ![]const u8 {
        // Check if we still have enough data
        if (size > self.buffer.len - self.offset) {
            return error.InsufficientData;
        }
        defer self.offset += size;
        return self.buffer[self.offset .. self.offset + size];
    }
};

pub const PacketHeader = struct { length: VarInt, id: VarInt };
