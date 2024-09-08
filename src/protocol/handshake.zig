const types = @import("../net/types.zig");
const VarInt = types.VarInt;
const String = types.String;
const State = @import("enums.zig").State;
// zig fmt: off
pub const Handshaking = struct { 
    protocol_version: VarInt, 
    server_addr: String, 
    server_port: u16, 
    next_state: State 
};
// zig fmt: on
