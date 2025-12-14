//! QinLink Utility Functions
//! Common utility functions following Zig idioms and best practices.
//!
//! This module provides:
//! - Random string/data generation
//! - Serialization helpers (JSON/binary)
//! - File I/O utilities
//! - MAC address generation
//! - Time utilities

const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;

pub const error_mod = @import("error.zig");
pub const Error = error_mod.Error;

/// Characters used for random string generation
const letters = "0123456789abcdefghijklmnopqrstuvwxyz";

/// Generate a random string of specified length
/// Caller owns the returned memory
pub fn genString(allocator: Allocator, length: usize) ![]u8 {
    if (length == 0) return error.InvalidLength;

    const buffer = try allocator.alloc(u8, length);
    errdefer allocator.free(buffer);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        break :blk seed;
    });
    const random = prng.random();

    for (buffer) |*byte| {
        byte.* = letters[random.uintLessThan(usize, letters.len)];
    }

    // Ensure first character is a letter, not a digit
    if (length > 0) {
        buffer[0] = letters[10 + random.uintLessThan(usize, 26)];
    }

    return buffer;
}

/// Generate a random Ethernet MAC address
/// Returns a 6-byte array
pub fn genEthAddr() ![6]u8 {
    var addr: [6]u8 = undefined;

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        break :blk seed;
    });
    const random = prng.random();

    random.bytes(&addr);

    // Set locally administered bit and ensure unicast
    addr[0] = (addr[0] & 0xFE) | 0x02;

    return addr;
}

/// Generate a random u32
pub fn genU32() u32 {
    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;

    var prng = std.rand.DefaultPrng.init(seed);
    return prng.random().int(u32);
}

/// Check if file exists
pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Load entire file into memory
/// Caller owns the returned memory
pub fn loadFile(allocator: Allocator, path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return error_mod.fromStdError(err);
    };
    defer file.close();

    const stat = try file.stat();
    const size = stat.size;

    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    const bytes_read = try file.read(buffer);
    if (bytes_read != size) {
        return Error.IoError;
    }

    return buffer;
}

/// Save data to file
pub fn saveFile(path: []const u8, data: []const u8) !void {
    const file = std.fs.cwd().createFile(path, .{}) catch |err| {
        return error_mod.fromStdError(err);
    };
    defer file.close();

    try file.writeAll(data);
}

/// Format MAC address to string (XX:XX:XX:XX:XX:XX)
pub fn formatMacAddr(mac: [6]u8, buffer: *[17]u8) void {
    _ = std.fmt.bufPrint(
        buffer,
        "{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}",
        .{ mac[0], mac[1], mac[2], mac[3], mac[4], mac[5] },
    ) catch unreachable;
}

/// Parse MAC address from string
pub fn parseMacAddr(str: []const u8) ![6]u8 {
    if (str.len != 17) return Error.ParseError;

    var mac: [6]u8 = undefined;
    var idx: usize = 0;

    for (0..6) |i| {
        const hex_str = str[idx .. idx + 2];
        mac[i] = std.fmt.parseInt(u8, hex_str, 16) catch return Error.ParseError;
        idx += 3; // Skip the ':'
    }

    return mac;
}

/// Simple JSON marshaling - placeholder for now
/// In production, use std.json or third-party library
pub fn marshalJson(allocator: Allocator, value: anytype) ![]u8 {
    _ = value;
    return try allocator.dupe(u8, "{}"); // Simplified for now
}

/// Simple JSON unmarshaling - placeholder for now  
pub fn unmarshalJson(comptime T: type, allocator: Allocator, data: []const u8) !T {
    _ = data;
    _ = allocator;
    return error.NotImplemented;
}

/// Get current timestamp in seconds
pub fn timestamp() i64 {
    return std.time.timestamp();
}

/// Get current time in milliseconds
pub fn timestampMs() i64 {
    return std.time.milliTimestamp();
}

test "generate random string" {
    const allocator = std.testing.allocator;

    const str = try genString(allocator, 10);
    defer allocator.free(str);

    try std.testing.expectEqual(@as(usize, 10), str.len);

    // First char should be a letter
    const first = str[0];
    try std.testing.expect((first >= 'a' and first <= 'z'));
}

test "generate MAC address" {
    const mac = try genEthAddr();

    // Check locally administered bit
    try std.testing.expectEqual(@as(u8, 0x02), mac[0] & 0x03);
}

test "MAC address formatting" {
    const mac = [6]u8{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55 };
    var buffer: [17]u8 = undefined;

    formatMacAddr(mac, &buffer);

    try std.testing.expectEqualStrings("00:11:22:33:44:55", &buffer);
}

test "MAC address parsing" {
    const mac_str = "AA:BB:CC:DD:EE:FF";
    const mac = try parseMacAddr(mac_str);

    try std.testing.expectEqual(@as(u8, 0xAA), mac[0]);
    try std.testing.expectEqual(@as(u8, 0xBB), mac[1]);
    try std.testing.expectEqual(@as(u8, 0xFF), mac[5]);
}

test "JSON marshaling" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        value: i32,
    };

    const obj = TestStruct{
        .name = "test",
        .value = 42,
    };

    const json = try marshalJson(allocator, obj);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    // Placeholder returns "{}"
    try std.testing.expectEqualStrings("{}", json);
}

test "file operations" {
    const allocator = std.testing.allocator;
    const test_path = "/tmp/qinlink_test.txt";
    const test_data = "Hello, QinLink!";

    // Save file
    try saveFile(test_path, test_data);
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Check exists
    try std.testing.expect(fileExists(test_path));

    // Load file
    const loaded = try loadFile(allocator, test_path);
    defer allocator.free(loaded);

    try std.testing.expectEqualStrings(test_data, loaded);
}

