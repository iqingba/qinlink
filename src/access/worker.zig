//! QinLink Access Client Worker
//! 
//! Manages the Access client connection and data forwarding

const std = @import("std");
const Allocator = std.mem.Allocator;

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

    pub fn init(allocator: Allocator) AccessWorker {
        return .{
            .state = .init,
            .allocator = allocator,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *AccessWorker) void {
        _ = self;
        // Cleanup resources
    }

    /// Start the worker
    pub fn start(self: *AccessWorker) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        self.running.store(true, .monotonic);
        self.state = .connecting;
        
        // TODO: Implement connection logic
        // 1. Create TAP device
        // 2. Connect to Switch
        // 3. Authenticate
        // 4. Start forwarding loop
    }

    /// Stop the worker
    pub fn stop(self: *AccessWorker) void {
        self.running.store(false, .monotonic);
        self.state = .disconnected;
    }

    /// Check if worker is running
    pub fn isRunning(self: *AccessWorker) bool {
        return self.running.load(.monotonic);
    }

    /// Get current state
    pub fn getState(self: *AccessWorker) WorkerState {
        return self.state;
    }

    /// Handle incoming frame from Switch
    pub fn handleFrame(self: *AccessWorker, data: []const u8) !void {
        _ = self;
        _ = data;
        // TODO: Process frame and write to TAP device
    }

    /// Send frame to Switch
    pub fn sendFrame(self: *AccessWorker, data: []const u8) !void {
        _ = self;
        _ = data;
        // TODO: Read from TAP and send to Switch
    }
};

// Tests
test "AccessWorker init" {
    const allocator = std.testing.allocator;
    
    var worker = AccessWorker.init(allocator);
    defer worker.deinit();
    
    try std.testing.expectEqual(WorkerState.init, worker.getState());
    try std.testing.expect(!worker.isRunning());
}

test "AccessWorker state transitions" {
    const allocator = std.testing.allocator;
    
    var worker = AccessWorker.init(allocator);
    defer worker.deinit();
    
    try std.testing.expectEqual(WorkerState.init, worker.state);
    
    worker.state = .connecting;
    try std.testing.expectEqual(WorkerState.connecting, worker.state);
    
    worker.state = .ready;
    try std.testing.expectEqual(WorkerState.ready, worker.state);
}

test "AccessWorker running flag" {
    const allocator = std.testing.allocator;
    
    var worker = AccessWorker.init(allocator);
    defer worker.deinit();
    
    try std.testing.expect(!worker.isRunning());
    
    worker.running.store(true, .monotonic);
    try std.testing.expect(worker.isRunning());
    
    worker.stop();
    try std.testing.expect(!worker.isRunning());
}

