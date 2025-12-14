//! QinLink Configuration Structures
//! 
//! Common configuration types for Access and Switch

const std = @import("std");

/// Network interface configuration
pub const InterfaceConfig = struct {
    name: []const u8 = "tap0",
    mtu: u32 = 1500,
    address: ?[]const u8 = null,
    netmask: ?[]const u8 = null,
};

/// Connection configuration
pub const ConnectionConfig = struct {
    protocol: []const u8 = "tcp",  // tcp, udp, ws, wss
    address: []const u8,
    port: u16,
    timeout: u32 = 60,  // seconds
};

/// Access client configuration
pub const AccessConfig = struct {
    alias: []const u8 = "client",
    connection: ConnectionConfig,
    interface: InterfaceConfig = .{},
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    network: ?[]const u8 = null,
    request_addr: bool = true,
};

/// Switch server configuration
pub const SwitchConfig = struct {
    alias: []const u8 = "switch",
    listen: ConnectionConfig,
    networks: std.StringHashMap(NetworkConfig),
    
    pub fn init(allocator: std.mem.Allocator) SwitchConfig {
        return .{
            .alias = "switch",
            .listen = ConnectionConfig{
                .address = "0.0.0.0",
                .port = 10000,
            },
            .networks = std.StringHashMap(NetworkConfig).init(allocator),
        };
    }
    
    pub fn deinit(self: *SwitchConfig) void {
        self.networks.deinit();
    }
};

/// Network configuration for Switch
pub const NetworkConfig = struct {
    name: []const u8,
    bridge: []const u8,
    subnet: ?[]const u8 = null,
    netmask: ?[]const u8 = null,
};

// Tests
test "AccessConfig defaults" {
    const config = AccessConfig{
        .connection = .{
            .address = "10.0.0.1",
            .port = 10000,
        },
    };
    
    try std.testing.expectEqualStrings("client", config.alias);
    try std.testing.expectEqual(@as(u32, 60), config.connection.timeout);
    try std.testing.expect(config.request_addr);
}

test "SwitchConfig init" {
    const allocator = std.testing.allocator;
    
    var config = SwitchConfig.init(allocator);
    defer config.deinit();
    
    try std.testing.expectEqualStrings("switch", config.alias);
    try std.testing.expectEqual(@as(u16, 10000), config.listen.port);
}

test "InterfaceConfig defaults" {
    const config = InterfaceConfig{};
    
    try std.testing.expectEqualStrings("tap0", config.name);
    try std.testing.expectEqual(@as(u32, 1500), config.mtu);
    try std.testing.expectEqual(@as(?[]const u8, null), config.address);
}

