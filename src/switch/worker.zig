//! QinLink Switch Server Worker
//! 
//! Manages Switch server and client connections

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Client information
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
            .connected_at = 0, // Placeholder timestamp
        };
    }
    
    pub fn deinit(self: *ClientInfo, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.username);
        allocator.free(self.network);
    }
};

/// Switch worker
pub const SwitchWorker = struct {
    allocator: Allocator,
    clients: std.StringHashMap(ClientInfo),
    running: std.atomic.Value(bool),
    
    pub fn init(allocator: Allocator) SwitchWorker {
        return .{
            .allocator = allocator,
            .clients = std.StringHashMap(ClientInfo).init(allocator),
            .running = std.atomic.Value(bool).init(false),
        };
    }
    
    pub fn deinit(self: *SwitchWorker) void {
        var it = self.clients.iterator();
        while (it.next()) |entry| {
            var client = entry.value_ptr.*;
            client.deinit(self.allocator);
        }
        self.clients.deinit();
    }
    
    /// Start the switch
    pub fn start(self: *SwitchWorker) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        self.running.store(true, .monotonic);
        
        // TODO: Implement server logic
        // 1. Create bridge
        // 2. Start listening for connections
        // 3. Accept clients
        // 4. Forward frames between clients
    }
    
    /// Stop the switch
    pub fn stop(self: *SwitchWorker) void {
        self.running.store(false, .monotonic);
    }
    
    /// Add a client
    pub fn addClient(self: *SwitchWorker, client: ClientInfo) !void {
        try self.clients.put(client.id, client);
    }
    
    /// Remove a client
    pub fn removeClient(self: *SwitchWorker, id: []const u8) void {
        if (self.clients.fetchRemove(id)) |entry| {
            var client = entry.value;
            client.deinit(self.allocator);
        }
    }
    
    /// Get client count
    pub fn clientCount(self: *SwitchWorker) usize {
        return self.clients.count();
    }
    
    /// Forward frame to specific client
    pub fn forwardToClient(self: *SwitchWorker, client_id: []const u8, data: []const u8) !void {
        _ = self;
        _ = client_id;
        _ = data;
        // TODO: Forward frame to client
    }
    
    /// Broadcast frame to all clients in network
    pub fn broadcast(self: *SwitchWorker, network: []const u8, data: []const u8) !void {
        _ = self;
        _ = network;
        _ = data;
        // TODO: Broadcast to all clients in same network
    }
};

// Tests
test "SwitchWorker init" {
    const allocator = std.testing.allocator;
    
    var worker = SwitchWorker.init(allocator);
    defer worker.deinit();
    
    try std.testing.expect(!worker.running.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), worker.clientCount());
}

test "SwitchWorker client management" {
    const allocator = std.testing.allocator;
    
    var worker = SwitchWorker.init(allocator);
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

