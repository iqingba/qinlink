//! QinLink Thread-Safe Data Structures
//! Provides thread-safe wrappers around common data structures.
//!
//! Features:
//! - Thread-safe HashMap (string -> string)
//! - Thread-safe HashMap (string -> generic)
//! - Atomic counters and statistics
//! - Lock-free operations where possible

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

/// Thread-safe string-to-string map
pub const SafeStrStr = struct {
    map: std.StringHashMap([]const u8),
    mutex: Mutex,
    allocator: Allocator,

    /// Initialize a new thread-safe string map
    pub fn init(allocator: Allocator) SafeStrStr {
        return .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .mutex = Mutex{},
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *SafeStrStr) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free all keys and values
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    /// Set a key-value pair (copies both key and value)
    pub fn set(self: *SafeStrStr, key: []const u8, value: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Duplicate key and value
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        // Check if key already exists and free old value
        if (self.map.get(key)) |old_value| {
            self.allocator.free(old_value);
            // Find and free the old key
            var it = self.map.keyIterator();
            while (it.next()) |k| {
                if (std.mem.eql(u8, k.*, key)) {
                    self.allocator.free(k.*);
                    break;
                }
            }
        }

        try self.map.put(key_copy, value_copy);
    }

    /// Get a value by key (returns a copy)
    pub fn get(self: *SafeStrStr, key: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.get(key)) |value| {
            return self.allocator.dupe(u8, value) catch return null;
        }
        return null;
    }

    /// Check if key exists
    pub fn has(self: *SafeStrStr, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.contains(key);
    }

    /// Delete a key-value pair
    pub fn del(self: *SafeStrStr, key: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
    }

    /// Get the number of items
    pub fn count(self: *SafeStrStr) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.count();
    }

    /// Clear all items
    pub fn clear(self: *SafeStrStr) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.clearRetainingCapacity();
    }
};

/// Thread-safe string-to-generic map
pub fn SafeStrMap(comptime V: type) type {
    return struct {
        const Self = @This();

        map: std.StringHashMap(V),
        mutex: Mutex,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return .{
                .map = std.StringHashMap(V).init(allocator),
                .mutex = Mutex{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Free all keys
            var it = self.map.keyIterator();
            while (it.next()) |key| {
                self.allocator.free(key.*);
            }
            self.map.deinit();
        }

        pub fn set(self: *Self, key: []const u8, value: V) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const key_copy = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_copy);

            // Free old key if exists
            if (self.map.contains(key)) {
                var it = self.map.keyIterator();
                while (it.next()) |k| {
                    if (std.mem.eql(u8, k.*, key)) {
                        self.allocator.free(k.*);
                        break;
                    }
                }
            }

            try self.map.put(key_copy, value);
        }

        pub fn get(self: *Self, key: []const u8) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.map.get(key);
        }

        pub fn del(self: *Self, key: []const u8) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.map.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
            }
        }

        pub fn count(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.map.count();
        }
    };
}

/// Thread-safe integer counter
pub const SafeCounter = struct {
    value: std.atomic.Value(i64),

    pub fn init(initial: i64) SafeCounter {
        return .{
            .value = std.atomic.Value(i64).init(initial),
        };
    }

    pub fn get(self: *SafeCounter) i64 {
        return self.value.load(.monotonic);
    }

    pub fn set(self: *SafeCounter, val: i64) void {
        self.value.store(val, .monotonic);
    }

    pub fn inc(self: *SafeCounter) i64 {
        return self.value.fetchAdd(1, .monotonic) + 1;
    }

    pub fn dec(self: *SafeCounter) i64 {
        return self.value.fetchSub(1, .monotonic) - 1;
    }

    pub fn add(self: *SafeCounter, delta: i64) i64 {
        if (delta >= 0) {
            return self.value.fetchAdd(@intCast(delta), .monotonic) + delta;
        } else {
            return self.value.fetchSub(@intCast(-delta), .monotonic) + delta;
        }
    }
};

/// Thread-safe statistics tracker
pub const SafeStats = struct {
    rx_packets: SafeCounter,
    tx_packets: SafeCounter,
    rx_bytes: SafeCounter,
    tx_bytes: SafeCounter,
    errors: SafeCounter,

    pub fn init() SafeStats {
        return .{
            .rx_packets = SafeCounter.init(0),
            .tx_packets = SafeCounter.init(0),
            .rx_bytes = SafeCounter.init(0),
            .tx_bytes = SafeCounter.init(0),
            .errors = SafeCounter.init(0),
        };
    }

    pub fn recordRx(self: *SafeStats, bytes: i64) void {
        _ = self.rx_packets.inc();
        _ = self.rx_bytes.add(bytes);
    }

    pub fn recordTx(self: *SafeStats, bytes: i64) void {
        _ = self.tx_packets.inc();
        _ = self.tx_bytes.add(bytes);
    }

    pub fn recordError(self: *SafeStats) void {
        _ = self.errors.inc();
    }

    pub fn getRxPackets(self: *SafeStats) i64 {
        return self.rx_packets.get();
    }

    pub fn getTxPackets(self: *SafeStats) i64 {
        return self.tx_packets.get();
    }

    pub fn getRxBytes(self: *SafeStats) i64 {
        return self.rx_bytes.get();
    }

    pub fn getTxBytes(self: *SafeStats) i64 {
        return self.tx_bytes.get();
    }

    pub fn getErrors(self: *SafeStats) i64 {
        return self.errors.get();
    }
};

// Tests
test "SafeStrStr basic operations" {
    const allocator = std.testing.allocator;

    var map = SafeStrStr.init(allocator);
    defer map.deinit();

    try map.set("key1", "value1");
    try map.set("key2", "value2");

    try std.testing.expectEqual(@as(usize, 2), map.count());
    try std.testing.expect(map.has("key1"));
    try std.testing.expect(!map.has("key3"));

    if (map.get("key1")) |value| {
        defer allocator.free(value);
        try std.testing.expectEqualStrings("value1", value);
    } else {
        try std.testing.expect(false);
    }

    map.del("key1");
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "SafeStrMap with integers" {
    const allocator = std.testing.allocator;

    var map = SafeStrMap(i32).init(allocator);
    defer map.deinit();

    try map.set("count", 42);
    try map.set("total", 100);

    try std.testing.expectEqual(@as(i32, 42), map.get("count").?);
    try std.testing.expectEqual(@as(usize, 2), map.count());

    map.del("count");
    try std.testing.expectEqual(@as(?i32, null), map.get("count"));
}

test "SafeCounter operations" {
    var counter = SafeCounter.init(0);

    try std.testing.expectEqual(@as(i64, 0), counter.get());

    _ = counter.inc();
    try std.testing.expectEqual(@as(i64, 1), counter.get());

    _ = counter.add(10);
    try std.testing.expectEqual(@as(i64, 11), counter.get());

    _ = counter.dec();
    try std.testing.expectEqual(@as(i64, 10), counter.get());
}

test "SafeStats tracking" {
    var stats = SafeStats.init();

    stats.recordRx(1500);
    stats.recordRx(1500);
    stats.recordTx(500);
    stats.recordError();

    try std.testing.expectEqual(@as(i64, 2), stats.getRxPackets());
    try std.testing.expectEqual(@as(i64, 3000), stats.getRxBytes());
    try std.testing.expectEqual(@as(i64, 1), stats.getTxPackets());
    try std.testing.expectEqual(@as(i64, 500), stats.getTxBytes());
    try std.testing.expectEqual(@as(i64, 1), stats.getErrors());
}

