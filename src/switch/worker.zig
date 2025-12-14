//! QinLink Switch Server Worker
//! 
//! Manages Switch server and client connections

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

const tcp = @import("../lib/tcp.zig");
const TcpServer = tcp.TcpServer;
const TcpClient = tcp.TcpClient;
const TcpConfig = tcp.TcpConfig;

const frame_mod = @import("../protocol/frame.zig");
const Frame = frame_mod.Frame;

const logger_mod = @import("../lib/logger.zig");
const Logger = logger_mod.Logger;

const control_mod = @import("../protocol/control.zig");
const ControlMessage = control_mod.ControlMessage;
const ControlCommand = control_mod.ControlCommand;

const ethernet_mod = @import("../protocol/ethernet.zig");
const MacAddr = ethernet_mod.MacAddr;

/// Client session information
pub const ClientSession = struct {
    id: []const u8,
    username: []const u8,
    network: []const u8,
    connected_at: i64,
    client: TcpClient,
    mac_addr: ?MacAddr,
    mutex: Thread.Mutex,
    
    pub fn init(allocator: Allocator, id: []const u8, username: []const u8, network: []const u8, client: TcpClient) !ClientSession {
        return ClientSession{
            .id = try allocator.dupe(u8, id),
            .username = try allocator.dupe(u8, username),
            .network = try allocator.dupe(u8, network),
            .connected_at = 0,
            .client = client,
            .mac_addr = null,
            .mutex = Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *ClientSession, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.username);
        allocator.free(self.network);
        self.client.close();
    }
    
    pub fn send(self: *ClientSession, data: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return try self.client.send(data);
    }
};

/// Client information (for client management)
pub const ClientInfo = struct {
    id: []const u8,
    username: []const u8,
    network: []const u8,
    connected_at: i64,
    
    pub fn init(allocator: Allocator, id: []const u8, username: []const u8, network: []const u8) !ClientInfo {
        return ClientInfo{
            .id = try allocator.dupe(u8, id),
            .username = try allocator.dupe(u8, username),
            .network = try allocator.dupe(u8, network),
            .connected_at = 0,
        };
    }
    
    pub fn deinit(self: *ClientInfo, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.username);
        allocator.free(self.network);
    }
};

/// MAC address to client ID mapping
const MacTable = std.StringHashMap([]const u8);

/// Switch worker
pub const SwitchWorker = struct {
    allocator: Allocator,
    clients: std.StringHashMap(ClientInfo),
    sessions: std.StringHashMap(ClientSession),
    mac_table: MacTable,
    running: std.atomic.Value(bool),
    
    // Server
    server: ?TcpServer,
    port: u16,
    
    // Logging
    logger: ?*Logger,
    
    // Synchronization
    mutex: Thread.Mutex,
    
    pub fn init(allocator: Allocator, port: u16) SwitchWorker {
        return .{
            .allocator = allocator,
            .clients = std.StringHashMap(ClientInfo).init(allocator),
            .sessions = std.StringHashMap(ClientSession).init(allocator),
            .mac_table = MacTable.init(allocator),
            .running = std.atomic.Value(bool).init(false),
            .server = null,
            .port = port,
            .logger = null,
            .mutex = Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *SwitchWorker) void {
        self.stop();
        
        // Clean up clients
        var it = self.clients.iterator();
        while (it.next()) |entry| {
            var client = entry.value_ptr.*;
            client.deinit(self.allocator);
        }
        self.clients.deinit();
        
        // Clean up sessions
        var sit = self.sessions.iterator();
        while (sit.next()) |entry| {
            var session = entry.value_ptr.*;
            session.deinit(self.allocator);
        }
        self.sessions.deinit();
        
        // Clean up MAC table
        var mit = self.mac_table.iterator();
        while (mit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.mac_table.deinit();
    }
    
    /// Set logger
    pub fn setLogger(self: *SwitchWorker, logger: *Logger) void {
        self.logger = logger;
    }
    
    /// Start the switch server
    pub fn start(self: *SwitchWorker) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        if (self.logger) |logger| {
            logger.info("Starting Switch server on port {d}", .{self.port});
        }
        
        // Create server
        const tcp_config = TcpConfig.default();
        var server = TcpServer.init(self.allocator, self.port, tcp_config);
        try server.listen();
        
        self.server = server;
        self.running.store(true, .monotonic);
        
        if (self.logger) |logger| {
            logger.info("Switch server started successfully", .{});
        }
        
        // In real implementation, we would spawn accept loop thread here
    }
    
    /// Stop the switch server
    pub fn stop(self: *SwitchWorker) void {
        self.running.store(false, .monotonic);
        
        if (self.server) |*server| {
            server.stop();
            self.server = null;
        }
        
        if (self.logger) |logger| {
            logger.info("Switch server stopped", .{});
        }
    }
    
    /// Accept new client connection
    pub fn acceptClient(self: *SwitchWorker) !void {
        const server = &(self.server orelse return error.NotRunning);
        
        // Accept connection
        const client = try server.accept();
        
        if (self.logger) |logger| {
            logger.info("New client connected", .{});
        }
        
        // TODO: Authenticate client
        // For now, create a simple client ID
        const client_id = "client-unknown";
        
        const session = try ClientSession.init(
            self.allocator,
            client_id,
            "guest",
            "default",
            client,
        );
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.sessions.put(try self.allocator.dupe(u8, client_id), session);
    }
    
    /// Add a client (for testing)
    pub fn addClient(self: *SwitchWorker, client: ClientInfo) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.clients.put(client.id, client);
    }
    
    /// Remove a client
    pub fn removeClient(self: *SwitchWorker, id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.clients.fetchRemove(id)) |entry| {
            var client = entry.value;
            client.deinit(self.allocator);
        }
        
        if (self.sessions.fetchRemove(id)) |entry| {
            var session = entry.value;
            session.deinit(self.allocator);
        }
    }
    
    /// Get client count
    pub fn clientCount(self: *SwitchWorker) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.clients.count();
    }
    
    /// Get session count
    pub fn sessionCount(self: *SwitchWorker) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.sessions.count();
    }
    
    /// Forward frame to specific client by ID
    pub fn forwardToClient(self: *SwitchWorker, client_id: []const u8, data: []const u8) !void {
        self.mutex.lock();
        const session_ptr = self.sessions.getPtr(client_id);
        self.mutex.unlock();
        
        if (session_ptr) |session| {
            _ = try session.send(data);
            
            if (self.logger) |logger| {
                logger.debug("Forwarded {d} bytes to client {s}", .{ data.len, client_id });
            }
        } else {
            return error.ClientNotFound;
        }
    }
    
    /// Forward frame to client by MAC address
    pub fn forwardToMac(self: *SwitchWorker, dst_mac: MacAddr, data: []const u8) !void {
        // Convert MAC to string for lookup
        var mac_str: [18]u8 = undefined;
        _ = try std.fmt.bufPrint(&mac_str, "{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}", .{
            dst_mac[0], dst_mac[1], dst_mac[2],
            dst_mac[3], dst_mac[4], dst_mac[5],
        });
        
        self.mutex.lock();
        const client_id = self.mac_table.get(&mac_str);
        self.mutex.unlock();
        
        if (client_id) |cid| {
            try self.forwardToClient(cid, data);
        } else {
            // MAC not found, broadcast to all clients in same network
            if (self.logger) |logger| {
                logger.debug("MAC not found, broadcasting", .{});
            }
            try self.broadcast("default", data);
        }
    }
    
    /// Broadcast frame to all clients in network
    pub fn broadcast(self: *SwitchWorker, network: []const u8, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const session = entry.value_ptr;
            
            // Check if client is in the same network
            if (std.mem.eql(u8, session.network, network)) {
                _ = session.send(data) catch |err| {
                    if (self.logger) |logger| {
                        logger.warn("Failed to send to client {s}: {}", .{ session.id, err });
                    }
                };
            }
        }
        
        if (self.logger) |logger| {
            logger.debug("Broadcasted {d} bytes to network {s}", .{ data.len, network });
        }
    }
    
    /// Handle incoming frame from client
    pub fn handleFrame(self: *SwitchWorker, client_id: []const u8, frame_data: []const u8) !void {
        // Decode frame
        var frame = try Frame.decode(self.allocator, frame_data);
        defer frame.deinit();
        
        if (frame.isControl()) {
            try self.handleControlFrame(client_id, frame.getData());
            return;
        }
        
        // Parse Ethernet header to get destination MAC
        const data = frame.getData();
        if (data.len < 14) {
            return error.InvalidFrame;
        }
        
        const dst_mac: MacAddr = data[0..6].*;
        const src_mac: MacAddr = data[6..12].*;
        
        // Learn source MAC
        try self.learnMac(src_mac, client_id);
        
        // Check if broadcast
        const is_broadcast = std.mem.eql(u8, &dst_mac, &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
        
        if (is_broadcast) {
            // Broadcast to all except sender
            try self.broadcastExcept(client_id, "default", frame_data);
        } else {
            // Unicast to specific MAC
            try self.forwardToMac(dst_mac, frame_data);
        }
    }
    
    /// Learn MAC address mapping
    fn learnMac(self: *SwitchWorker, mac: MacAddr, client_id: []const u8) !void {
        var mac_str: [18]u8 = undefined;
        _ = try std.fmt.bufPrint(&mac_str, "{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}", .{
            mac[0], mac[1], mac[2],
            mac[3], mac[4], mac[5],
        });
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const mac_key = try self.allocator.dupe(u8, &mac_str);
        const cid = try self.allocator.dupe(u8, client_id);
        
        try self.mac_table.put(mac_key, cid);
        
        if (self.logger) |logger| {
            logger.debug("Learned MAC {s} -> {s}", .{ mac_key, client_id });
        }
    }
    
    /// Handle control frame
    fn handleControlFrame(self: *SwitchWorker, client_id: []const u8, data: []const u8) !void {
        const msg = try ControlMessage.decode(data);
        
        if (self.logger) |logger| {
            logger.debug("Received control message from {s}: {}", .{ client_id, msg.command });
        }
        
        switch (msg.command) {
            .login_req => {
                try self.handleLogin(client_id, msg.data);
            },
            .ping_req => {
                try self.handlePing(client_id);
            },
            else => {},
        }
    }
    
    /// Handle login request
    fn handleLogin(self: *SwitchWorker, client_id: []const u8, credentials: []const u8) !void {
        _ = credentials;
        
        if (self.logger) |logger| {
            logger.info("Client {s} authenticated", .{client_id});
        }
        
        // Send login response
        const login_resp = ControlMessage{
            .command = .login_resp,
            .data = "OK",
        };
        
        var buffer: [4096]u8 = undefined;
        const encoded = try login_resp.encode(&buffer);
        
        try self.forwardToClient(client_id, encoded);
    }
    
    /// Handle ping request
    fn handlePing(self: *SwitchWorker, client_id: []const u8) !void {
        const pong_resp = ControlMessage{
            .command = .pong_resp,
            .data = "",
        };
        
        var buffer: [4096]u8 = undefined;
        const encoded = try pong_resp.encode(&buffer);
        
        try self.forwardToClient(client_id, encoded);
    }
    
    /// Broadcast to all clients except one
    fn broadcastExcept(self: *SwitchWorker, except_id: []const u8, network: []const u8, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const session = entry.value_ptr;
            
            // Skip sender
            if (std.mem.eql(u8, session.id, except_id)) {
                continue;
            }
            
            // Check network
            if (std.mem.eql(u8, session.network, network)) {
                _ = session.send(data) catch |err| {
                    if (self.logger) |logger| {
                        logger.warn("Failed to send to client {s}: {}", .{ session.id, err });
                    }
                };
            }
        }
    }
};

// Tests
test "SwitchWorker init" {
    const allocator = std.testing.allocator;
    
    var worker = SwitchWorker.init(allocator, 10000);
    defer worker.deinit();
    
    try std.testing.expect(!worker.running.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), worker.clientCount());
}

test "SwitchWorker client management" {
    const allocator = std.testing.allocator;
    
    var worker = SwitchWorker.init(allocator, 10000);
    defer worker.deinit();
    
    const client = try ClientInfo.init(allocator, "client1", "user1", "network1");
    try worker.addClient(client);
    
    try std.testing.expectEqual(@as(usize, 1), worker.clientCount());
    
    worker.removeClient("client1");
    try std.testing.expectEqual(@as(usize, 0), worker.clientCount());
}

test "ClientInfo lifecycle" {
    const allocator = std.testing.allocator;
    
    var client = try ClientInfo.init(allocator, "test-id", "test-user", "default");
    defer client.deinit(allocator);
    
    try std.testing.expectEqualStrings("test-id", client.id);
    try std.testing.expectEqualStrings("test-user", client.username);
    try std.testing.expectEqualStrings("default", client.network);
}

test "SwitchWorker lifecycle" {
    const allocator = std.testing.allocator;
    
    var worker = SwitchWorker.init(allocator, 0);
    defer worker.deinit();
    
    try std.testing.expect(!worker.running.load(.monotonic));
    try std.testing.expectEqual(@as(u16, 0), worker.port);
}
