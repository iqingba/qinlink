//! QinLink Control Protocol
//! 
//! Defines control messages for QinLink protocol

const std = @import("std");
const Allocator = std.mem.Allocator;
const frame = @import("frame.zig");
const Frame = frame.Frame;

/// Control command types
pub const ControlCommand = enum {
    login_req,      // "logi= "
    login_resp,     // "logi: "
    neighbor_req,   // "neig= "
    neighbor_resp,  // "neig: "
    ipaddr_req,     // "ipad= "
    ipaddr_resp,    // "ipad: "
    ping_req,       // "ping= "
    pong_resp,      // "pong: "
    left_req,       // "left= "

    pub fn toString(self: ControlCommand) []const u8 {
        return switch (self) {
            .login_req => "logi= ",
            .login_resp => "logi: ",
            .neighbor_req => "neig= ",
            .neighbor_resp => "neig: ",
            .ipaddr_req => "ipad= ",
            .ipaddr_resp => "ipad: ",
            .ping_req => "ping= ",
            .pong_resp => "pong: ",
            .left_req => "left= ",
        };
    }

    pub fn fromString(str: []const u8) ?ControlCommand {
        if (str.len < 6) return null;
        
        const cmd = str[0..6];
        if (std.mem.eql(u8, cmd, "logi= ")) return .login_req;
        if (std.mem.eql(u8, cmd, "logi: ")) return .login_resp;
        if (std.mem.eql(u8, cmd, "neig= ")) return .neighbor_req;
        if (std.mem.eql(u8, cmd, "neig: ")) return .neighbor_resp;
        if (std.mem.eql(u8, cmd, "ipad= ")) return .ipaddr_req;
        if (std.mem.eql(u8, cmd, "ipad: ")) return .ipaddr_resp;
        if (std.mem.eql(u8, cmd, "ping= ")) return .ping_req;
        if (std.mem.eql(u8, cmd, "pong: ")) return .pong_resp;
        if (std.mem.eql(u8, cmd, "left= ")) return .left_req;
        
        return null;
    }
};

/// Control message
pub const ControlMessage = struct {
    command: ControlCommand,
    data: []const u8,

    pub fn init(command: ControlCommand, data: []const u8) ControlMessage {
        return .{ .command = command, .data = data };
    }

    pub fn encodeToFrame(self: *const ControlMessage, allocator: Allocator) !Frame {
        const cmd_str = self.command.toString();
        const total_len = cmd_str.len + self.data.len;
        
        const buffer = try allocator.alloc(u8, total_len);
        defer allocator.free(buffer);
        
        @memcpy(buffer[0..cmd_str.len], cmd_str);
        @memcpy(buffer[cmd_str.len..], self.data);
        
        return Frame.init(allocator, buffer);
    }

    pub fn decodeFromFrame(f: *const Frame) ?ControlMessage {
        const cmd = ControlCommand.fromString(f.data) orelse return null;
        const data = if (f.data.len > 6) f.data[6..] else &[_]u8{};
        
        return ControlMessage{
            .command = cmd,
            .data = data,
        };
    }
};

// Tests
test "ControlCommand string conversion" {
    const cmd = ControlCommand.login_req;
    try std.testing.expectEqualStrings("logi= ", cmd.toString());
    
    const parsed = ControlCommand.fromString("logi= data");
    try std.testing.expectEqual(ControlCommand.login_req, parsed.?);
}

test "ControlMessage encode/decode" {
    const allocator = std.testing.allocator;
    
    const msg = ControlMessage.init(.ping_req, "test");
    var f = try msg.encodeToFrame(allocator);
    defer f.deinit();
    
    const decoded = ControlMessage.decodeFromFrame(&f).?;
    try std.testing.expectEqual(ControlCommand.ping_req, decoded.command);
    try std.testing.expectEqualStrings("test", decoded.data);
}

