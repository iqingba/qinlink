//! QinLink Access Client Worker
//! 
//! Manages the Access client connection and data forwarding

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const posix = std.posix;

const tcp = @import("../lib/tcp.zig");
const TcpClient = tcp.TcpClient;
const TcpConfig = tcp.TcpConfig;

const frame_mod = @import("../protocol/frame.zig");
const Frame = frame_mod.Frame;

const taper_mod = @import("../network/taper.zig");
const Taper = taper_mod.Taper;
const TapConfig = taper_mod.TapConfig;

const logger_mod = @import("../lib/logger.zig");
const Logger = logger_mod.Logger;

const control_mod = @import("../protocol/control.zig");
const ControlMessage = control_mod.ControlMessage;
const ControlCommand = control_mod.ControlCommand;

/// Access worker state
pub const WorkerState = enum {
    init,
    connecting,
    connected,
    authenticating,
    ready,
    disconnected,
};

/// Access client worker
pub const AccessWorker = struct {
    state: WorkerState,
    allocator: Allocator,
    running: std.atomic.Value(bool),
    
    // Network components
    tcp_client: ?TcpClient,
    tap_device: ?Taper,
    
    // Configuration
    server_host: []const u8,
    server_port: u16,
    device_name: []const u8,
    
    // Logging
    logger: ?*Logger,
    
    // Thread handles
    rx_thread: ?Thread,
    tx_thread: ?Thread,
    mutex: Thread.Mutex,

    pub fn init(allocator: Allocator, server_host: []const u8, server_port: u16, device_name: []const u8) AccessWorker {
        return .{
            .state = .init,
            .allocator = allocator,
            .running = std.atomic.Value(bool).init(false),
            .tcp_client = null,
            .tap_device = null,
            .server_host = server_host,
            .server_port = server_port,
            .device_name = device_name,
            .logger = null,
            .rx_thread = null,
            .tx_thread = null,
            .mutex = Thread.Mutex{},
        };
    }

    pub fn deinit(self: *AccessWorker) void {
        self.stop();
        
        if (self.tcp_client) |*client| {
            client.close();
        }
        
        if (self.tap_device) |*tap| {
            tap.close();
        }
    }

    /// Set logger
    pub fn setLogger(self: *AccessWorker, logger: *Logger) void {
        self.logger = logger;
    }

    /// Start the worker
    pub fn start(self: *AccessWorker) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        // Create TAP device
        if (self.logger) |logger| {
            logger.info("Creating TAP device: {s}", .{self.device_name});
        }
        
        const tap_config = TapConfig{
            .name = self.device_name,
            .device_type = .tap,
            .mtu = 1500,
        };
        
        var tap = try Taper.open(tap_config);
        errdefer tap.close();
        
        try tap.setUp();
        self.tap_device = tap;
        
        if (self.logger) |logger| {
            logger.info("TAP device created successfully", .{});
        }
        
        // Connect to Switch
        self.state = .connecting;
        if (self.logger) |logger| {
            logger.info("Connecting to Switch: {s}:{d}", .{ self.server_host, self.server_port });
        }
        
        const tcp_config = TcpConfig.default();
        var client = TcpClient.init(self.allocator, tcp_config);
        try client.connect(self.server_host, self.server_port);
        self.tcp_client = client;
        
        self.state = .connected;
        if (self.logger) |logger| {
            logger.info("Connected to Switch", .{});
        }
        
        // Send authentication
        self.state = .authenticating;
        try self.authenticate();
        
        self.state = .ready;
        self.running.store(true, .monotonic);
        
        if (self.logger) |logger| {
            logger.info("Access worker ready", .{});
        }
        
        // Start forwarding threads
        // Note: In real implementation, we would spawn threads here
        // For now, we just mark as ready
    }

    /// Stop the worker
    pub fn stop(self: *AccessWorker) void {
        self.running.store(false, .monotonic);
        self.state = .disconnected;
        
        if (self.logger) |logger| {
            logger.info("Access worker stopped", .{});
        }
    }

    /// Check if worker is running
    pub fn isRunning(self: *AccessWorker) bool {
        return self.running.load(.monotonic);
    }

    /// Get current state
    pub fn getState(self: *AccessWorker) WorkerState {
        return self.state;
    }

    /// Authenticate with Switch
    fn authenticate(self: *AccessWorker) !void {
        const client = &(self.tcp_client orelse return error.NotConnected);
        
        // Create login request
        const login_msg = ControlMessage{
            .command = .login_req,
            .data = "user:password",
        };
        
        var buffer: [4096]u8 = undefined;
        const encoded = try login_msg.encode(&buffer);
        
        // Send login request
        _ = try client.send(encoded);
        
        if (self.logger) |logger| {
            logger.info("Sent authentication request", .{});
        }
        
        // Wait for response (simplified, no actual read here)
        // In real implementation, we would read and parse response
    }

    /// Handle incoming frame from Switch
    pub fn handleFrameFromSwitch(self: *AccessWorker, data: []const u8) !void {
        const tap = &(self.tap_device orelse return error.NoDevice);
        
        // Decode frame
        var frame = try Frame.decode(self.allocator, data);
        defer frame.deinit();
        
        // Check if it's a control frame
        if (frame.isControl()) {
            try self.handleControlFrame(frame.getData());
            return;
        }
        
        // Write data to TAP device
        const frame_data = frame.getData();
        _ = try tap.write(frame_data);
        
        if (self.logger) |logger| {
            logger.debug("Forwarded {d} bytes to TAP device", .{frame_data.len});
        }
    }

    /// Handle control frame
    fn handleControlFrame(self: *AccessWorker, data: []const u8) !void {
        const msg = try ControlMessage.decode(data);
        
        if (self.logger) |logger| {
            logger.debug("Received control message: {}", .{msg.command});
        }
        
        switch (msg.command) {
            .login_resp => {
                if (self.logger) |logger| {
                    logger.info("Login successful", .{});
                }
            },
            .ping_req => {
                try self.sendPong();
            },
            else => {},
        }
    }

    /// Send pong response
    fn sendPong(self: *AccessWorker) !void {
        const client = &(self.tcp_client orelse return error.NotConnected);
        
        const pong_msg = ControlMessage{
            .command = .pong_resp,
            .data = "",
        };
        
        var buffer: [4096]u8 = undefined;
        const encoded = try pong_msg.encode(&buffer);
        
        _ = try client.send(encoded);
    }

    /// Send frame to Switch (read from TAP)
    pub fn sendFrameToSwitch(self: *AccessWorker, data: []const u8) !void {
        const client = &(self.tcp_client orelse return error.NotConnected);
        
        // Create frame
        var frame = try Frame.init(self.allocator, data, false);
        defer frame.deinit();
        
        // Encode and send
        const encoded = frame.encode();
        _ = try client.send(encoded);
        
        if (self.logger) |logger| {
            logger.debug("Sent {d} bytes to Switch", .{data.len});
        }
    }

    /// Read from TAP device (blocking)
    pub fn readFromTap(self: *AccessWorker, buffer: []u8) !usize {
        const tap = &(self.tap_device orelse return error.NoDevice);
        return try tap.read(buffer);
    }

    /// Forward loop: TAP -> Switch
    pub fn forwardTapToSwitch(self: *AccessWorker) !void {
        var buffer: [2048]u8 = undefined;
        
        while (self.running.load(.monotonic)) {
            const n = self.readFromTap(&buffer) catch |err| {
                if (err == error.WouldBlock) {
                    continue;
                }
                return err;
            };
            
            if (n > 0) {
                try self.sendFrameToSwitch(buffer[0..n]);
            }
        }
    }

    /// Forward loop: Switch -> TAP
    pub fn forwardSwitchToTap(self: *AccessWorker) !void {
        const client = &(self.tcp_client orelse return error.NotConnected);
        var buffer: [4096]u8 = undefined;
        
        while (self.running.load(.monotonic)) {
            const n = client.receive(&buffer) catch |err| {
                if (err == error.WouldBlock) {
                    continue;
                }
                return err;
            };
            
            if (n > 0) {
                try self.handleFrameFromSwitch(buffer[0..n]);
            }
        }
    }
};

// Tests
test "AccessWorker structure" {
    const allocator = std.testing.allocator;
    
    var worker = AccessWorker.init(allocator, "127.0.0.1", 10000, "test0");
    defer worker.deinit();
    
    try std.testing.expectEqual(WorkerState.init, worker.getState());
    try std.testing.expect(!worker.isRunning());
    try std.testing.expectEqual(@as(u16, 10000), worker.server_port);
}

test "AccessWorker state machine" {
    const allocator = std.testing.allocator;
    
    var worker = AccessWorker.init(allocator, "127.0.0.1", 10000, "test0");
    defer worker.deinit();
    
    const states = [_]WorkerState{ .init, .connecting, .connected, .ready, .disconnected };
    for (states) |state| {
        worker.state = state;
        try std.testing.expectEqual(state, worker.getState());
    }
}

test "AccessWorker lifecycle" {
    const allocator = std.testing.allocator;
    
    var worker = AccessWorker.init(allocator, "127.0.0.1", 10000, "test0");
    defer worker.deinit();
    
    try std.testing.expect(!worker.isRunning());
    
    worker.running.store(true, .monotonic);
    try std.testing.expect(worker.isRunning());
    
    worker.stop();
    try std.testing.expect(!worker.isRunning());
    try std.testing.expectEqual(WorkerState.disconnected, worker.getState());
}
