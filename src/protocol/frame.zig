//! QinLink Frame Protocol
//! 
//! Defines the framing protocol for QinLink data transmission.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Frame magic number
pub const FRAME_MAGIC: u16 = 0xFFFF;

/// Frame header size
pub const FRAME_HEADER_SIZE: usize = 4;

/// Maximum frame size
pub const FRAME_MAX_SIZE: usize = 65535;

/// Frame errors
pub const FrameError = error{
    FrameTooLarge,
    FrameTooSmall,
    InvalidMagic,
    BufferTooSmall,
};

/// Frame structure
pub const Frame = struct {
    magic: u16,
    length: u16,
    data: []u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, data: []const u8) !Frame {
        if (data.len > FRAME_MAX_SIZE - FRAME_HEADER_SIZE) {
            return FrameError.FrameTooLarge;
        }

        const data_copy = try allocator.dupe(u8, data);
        return Frame{
            .magic = FRAME_MAGIC,
            .length = @intCast(data.len),
            .data = data_copy,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.data);
    }

    pub fn encode(self: *const Frame, buffer: []u8) !usize {
        const total_size = FRAME_HEADER_SIZE + self.data.len;
        if (buffer.len < total_size) {
            return FrameError.BufferTooSmall;
        }

        std.mem.writeInt(u16, buffer[0..2], self.magic, .big);
        std.mem.writeInt(u16, buffer[2..4], self.length, .big);
        @memcpy(buffer[4 .. 4 + self.data.len], self.data);

        return total_size;
    }

    pub fn decode(allocator: Allocator, buffer: []const u8) !Frame {
        if (buffer.len < FRAME_HEADER_SIZE) {
            return FrameError.FrameTooSmall;
        }

        const magic = std.mem.readInt(u16, buffer[0..2], .big);
        if (magic != FRAME_MAGIC) {
            return FrameError.InvalidMagic;
        }

        const length = std.mem.readInt(u16, buffer[2..4], .big);
        const expected_size = FRAME_HEADER_SIZE + length;
        if (buffer.len < expected_size) {
            return FrameError.FrameTooSmall;
        }

        const data = try allocator.dupe(u8, buffer[4 .. 4 + length]);
        return Frame{
            .magic = magic,
            .length = length,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn isControl(self: *const Frame) bool {
        if (self.data.len < 5) return false;
        return (self.data[4] == '=' or self.data[4] == ':');
    }
};

// Tests
test "Frame encode/decode" {
    const allocator = std.testing.allocator;
    const test_data = "Hello";
    
    var frame = try Frame.init(allocator, test_data);
    defer frame.deinit();

    var buffer: [256]u8 = undefined;
    const size = try frame.encode(&buffer);
    
    var decoded = try Frame.decode(allocator, buffer[0..size]);
    defer decoded.deinit();

    try std.testing.expectEqualStrings(test_data, decoded.data);
}

test "Frame invalid magic" {
    const allocator = std.testing.allocator;
    var buffer: [10]u8 = undefined;
    
    std.mem.writeInt(u16, buffer[0..2], 0x0000, .big);
    std.mem.writeInt(u16, buffer[2..4], 6, .big);
    
    const result = Frame.decode(allocator, &buffer);
    try std.testing.expectError(FrameError.InvalidMagic, result);
}

test "Frame control detection" {
    const allocator = std.testing.allocator;
    
    var control = try Frame.init(allocator, "logi= test");
    defer control.deinit();
    try std.testing.expect(control.isControl());
    
    var data = try Frame.init(allocator, "data");
    defer data.deinit();
    try std.testing.expect(!data.isControl());
}
