//! QinLink TAP/TUN Device Interface
//! 
//! Platform-independent interface for TAP/TUN devices

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Device type
pub const DeviceType = enum {
    tap,  // Layer 2 (Ethernet frames)
    tun,  // Layer 3 (IP packets)
};

/// Device configuration
pub const TapConfig = struct {
    name: []const u8,
    device_type: DeviceType = .tap,
    mtu: u32 = 1500,
    persist: bool = false,
};

/// TAP/TUN device interface
pub const Taper = struct {
    fd: std.posix.fd_t,
    name: [16]u8,
    device_type: DeviceType,
    mtu: u32,

    /// Open/create a TAP/TUN device (platform-specific)
    pub fn open(config: TapConfig) !Taper {
        // Use platform-specific implementation
        if (@import("builtin").os.tag == .linux) {
            const tap_linux = @import("tap_linux.zig");
            return tap_linux.openTap(config);
        }
        return error.NotImplemented;
    }

    /// Close the device
    pub fn close(self: *Taper) void {
        std.posix.close(self.fd);
    }

    /// Read data from device
    pub fn read(self: *Taper, buffer: []u8) !usize {
        return std.posix.read(self.fd, buffer);
    }

    /// Write data to device
    pub fn write(self: *Taper, data: []const u8) !usize {
        return std.posix.write(self.fd, data);
    }

    /// Set device up
    pub fn setUp(self: *Taper) !void {
        if (@import("builtin").os.tag == .linux) {
            const tap_linux = @import("tap_linux.zig");
            return tap_linux.setInterfaceUp(&self.name);
        }
        return error.NotImplemented;
    }

    /// Set device down
    pub fn setDown(self: *Taper) !void {
        _ = self;
        return error.NotImplemented;
    }

    /// Set IP address
    pub fn setAddr(self: *Taper, addr: []const u8, netmask: []const u8) !void {
        if (@import("builtin").os.tag == .linux) {
            const tap_linux = @import("tap_linux.zig");
            _ = netmask;
            return tap_linux.setInterfaceAddr(&self.name, addr);
        }
        return error.NotImplemented;
    }

    /// Set MTU
    pub fn setMtu(self: *Taper, mtu: u32) !void {
        if (@import("builtin").os.tag == .linux) {
            const tap_linux = @import("tap_linux.zig");
            try tap_linux.setInterfaceMtu(&self.name, mtu);
            self.mtu = mtu;
            return;
        }
        return error.NotImplemented;
    }
};

// Tests
test "TapConfig defaults" {
    const config = TapConfig{
        .name = "tap0",
    };
    
    try std.testing.expectEqual(DeviceType.tap, config.device_type);
    try std.testing.expectEqual(@as(u32, 1500), config.mtu);
    try std.testing.expect(!config.persist);
}

test "DeviceType enum" {
    const tap = DeviceType.tap;
    const tun = DeviceType.tun;
    
    try std.testing.expect(tap != tun);
}

