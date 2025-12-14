//! Linux TAP/TUN Device Implementation
//! 
//! Uses /dev/net/tun and ioctl for device operations

const std = @import("std");
const posix = std.posix;
const taper = @import("taper.zig");
const Taper = taper.Taper;
const TapConfig = taper.TapConfig;
const DeviceType = taper.DeviceType;

// Linux-specific constants
const IFF_TUN = 0x0001;
const IFF_TAP = 0x0002;
const IFF_NO_PI = 0x1000;
const IFF_UP = 0x0001;
const TUNSETIFF = 0x400454ca;
const SIOCSIFFLAGS = 0x8914;
const SIOCSIFADDR = 0x8916;
const SIOCSIFNETMASK = 0x891c;
const SIOCSIFMTU = 0x8922;

// ifreq structure for ioctl
const ifreq = extern struct {
    ifr_name: [16]u8,
    ifr_data: extern union {
        ifr_flags: c_int,
        ifr_mtu: c_int,
        ifr_addr: std.posix.sockaddr,
    },
};

/// Open TAP/TUN device on Linux
pub fn openTap(config: TapConfig) !Taper {
    // Open /dev/net/tun
    const fd = try posix.open(
        "/dev/net/tun",
        .{ .ACCMODE = .RDWR, .CLOEXEC = true },
        0,
    );
    errdefer posix.close(fd);

    // Prepare ifreq structure
    var ifr: ifreq = std.mem.zeroes(ifreq);
    
    // Copy device name
    var idx: usize = 0;
    while (idx < config.name.len and idx < 15) : (idx += 1) {
        ifr.ifr_name[idx] = config.name[idx];
    }
    if (idx < 16) {
        ifr.ifr_name[idx] = 0;
    }

    // Set flags based on device type
    const device_flag: c_int = switch (config.device_type) {
        .tap => IFF_TAP,
        .tun => IFF_TUN,
    };
    ifr.ifr_data.ifr_flags = IFF_NO_PI | device_flag;

    // Create device via ioctl
    const result = std.c.ioctl(fd, TUNSETIFF, @intFromPtr(&ifr));
    if (result < 0) {
        return error.DeviceCreateFailed;
    }

    // Get actual device name
    var dev_name: [16]u8 = undefined;
    @memcpy(&dev_name, &ifr.ifr_name);

    return Taper{
        .fd = fd,
        .name = dev_name,
        .device_type = config.device_type,
        .mtu = config.mtu,
    };
}

/// Set interface up
pub fn setInterfaceUp(device_name: []const u8) !void {
    // Open socket for ioctl
    const sock = try posix.socket(
        posix.AF.INET,
        posix.SOCK.DGRAM,
        0,
    );
    defer posix.close(sock);

    var ifr: ifreq = std.mem.zeroes(ifreq);
    const name_len: usize = @min(device_name.len, 15);
    var idx: usize = 0;
    while (idx < name_len) : (idx += 1) {
        ifr.ifr_name[idx] = device_name[idx];
    }
    
    // Get current flags
    var result = std.c.ioctl(sock, SIOCSIFFLAGS, @intFromPtr(&ifr));
    if (result < 0) {
        return error.IoError;
    }

    // Set UP flag
    ifr.ifr_data.ifr_flags |= IFF_UP;
    result = std.c.ioctl(sock, SIOCSIFFLAGS, @intFromPtr(&ifr));
    if (result < 0) {
        return error.IoError;
    }
}

/// Set interface address
pub fn setInterfaceAddr(device_name: []const u8, addr: []const u8) !void {
    _ = device_name;
    _ = addr;
    // TODO: Parse IP address and set via ioctl
    // For now, return NotImplemented
    return error.NotImplemented;
}

/// Set interface MTU
pub fn setInterfaceMtu(device_name: []const u8, mtu: u32) !void {
    const sock = try posix.socket(
        posix.AF.INET,
        posix.SOCK.DGRAM,
        0,
    );
    defer posix.close(sock);

    var ifr: ifreq = std.mem.zeroes(ifreq);
    const name_len: usize = @min(device_name.len, 15);
    var idx: usize = 0;
    while (idx < name_len) : (idx += 1) {
        ifr.ifr_name[idx] = device_name[idx];
    }
    
    ifr.ifr_data.ifr_mtu = @intCast(mtu);
    
    const result = std.c.ioctl(sock, SIOCSIFMTU, @intFromPtr(&ifr));
    if (result < 0) {
        return error.IoError;
    }
}

// Tests (需要root权限)
test "TAP device structure" {
    // 只测试结构定义，不实际创建设备
    const config = TapConfig{
        .name = "test0",
        .device_type = .tap,
        .mtu = 1500,
    };
    
    try std.testing.expectEqualStrings("test0", config.name);
    try std.testing.expectEqual(DeviceType.tap, config.device_type);
}

