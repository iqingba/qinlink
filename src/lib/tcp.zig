//! QinLink TCP Socket Implementation
//! 
//! Simplified TCP client and server for Zig 0.16

const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

pub const SocketStats = struct {
    tx_bytes: i64 = 0,
    rx_bytes: i64 = 0,
    tx_packets: i64 = 0,
    rx_packets: i64 = 0,
    
    pub fn recordSend(self: *SocketStats, bytes: usize) void {
        self.tx_bytes += @intCast(bytes);
        self.tx_packets += 1;
    }
    
    pub fn recordReceive(self: *SocketStats, bytes: usize) void {
        self.rx_bytes += @intCast(bytes);
        self.rx_packets += 1;
    }
};

pub const TcpConfig = struct {
    timeout_ms: u32 = 60000,
    read_buffer_size: usize = 4096,
    write_buffer_size: usize = 4096,
    keepalive: bool = true,
    
    pub fn default() TcpConfig {
        return .{};
    }
};

/// TCP Client
pub const TcpClient = struct {
    fd: ?posix.fd_t,
    config: TcpConfig,
    stats: SocketStats,
    mutex: Thread.Mutex,
    allocator: Allocator,
    
    pub fn init(allocator: Allocator, config: TcpConfig) TcpClient {
        return .{
            .fd = null,
            .config = config,
            .stats = SocketStats{},
            .mutex = Thread.Mutex{},
            .allocator = allocator,
        };
    }
    
    pub fn connect(self: *TcpClient, host: []const u8, port: u16) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.fd != null) {
            return error.AlreadyConnected;
        }
        
        // Parse IPv4 address
        var ip_parts: [4]u8 = undefined;
        var iter = std.mem.splitScalar(u8, host, '.');
        var i: usize = 0;
        while (iter.next()) |part| : (i += 1) {
            if (i >= 4) return error.InvalidAddress;
            ip_parts[i] = try std.fmt.parseInt(u8, part, 10);
        }
        if (i != 4) return error.InvalidAddress;
        
        // Create sockaddr_in
        const addr = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = @byteSwap(port),
            .addr = @bitCast(ip_parts),
            .zero = [_]u8{0} ** 8,
        };
        
        // Create socket
        const fd = try posix.socket(
            posix.AF.INET,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );
        errdefer posix.close(fd);
        
        // Connect
        const sockaddr: posix.sockaddr = @bitCast(addr);
        try posix.connect(fd, &sockaddr, @sizeOf(posix.sockaddr.in));
        
        self.fd = fd;
    }
    
    pub fn close(self: *TcpClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.fd) |fd| {
            posix.close(fd);
            self.fd = null;
        }
    }
    
    pub fn send(self: *TcpClient, data: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const fd = self.fd orelse return error.NotConnected;
        
        const sent = try posix.send(fd, data, 0);
        self.stats.recordSend(sent);
        return sent;
    }
    
    pub fn receive(self: *TcpClient, buffer: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const fd = self.fd orelse return error.NotConnected;
        
        const received = try posix.recv(fd, buffer, 0);
        if (received == 0) {
            return error.ConnectionClosed;
        }
        
        self.stats.recordReceive(received);
        return received;
    }
    
    pub fn isConnected(self: *TcpClient) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.fd != null;
    }
    
    pub fn getStats(self: *TcpClient) SocketStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }
};

/// TCP Server
pub const TcpServer = struct {
    fd: ?posix.fd_t,
    port: u16,
    config: TcpConfig,
    allocator: Allocator,
    running: std.atomic.Value(bool),
    
    pub fn init(allocator: Allocator, port: u16, config: TcpConfig) TcpServer {
        return .{
            .fd = null,
            .port = port,
            .config = config,
            .allocator = allocator,
            .running = std.atomic.Value(bool).init(false),
        };
    }
    
    pub fn listen(self: *TcpServer) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        // Create socket
        const fd = try posix.socket(
            posix.AF.INET,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );
        errdefer posix.close(fd);
        
        // Create sockaddr_in for 0.0.0.0:port
        const addr = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = @byteSwap(self.port),
            .addr = 0, // INADDR_ANY
            .zero = [_]u8{0} ** 8,
        };
        
        // Bind
        const sockaddr: posix.sockaddr = @bitCast(addr);
        try posix.bind(fd, &sockaddr, @sizeOf(posix.sockaddr.in));
        
        // Listen
        try posix.listen(fd, 128);
        
        self.fd = fd;
        self.running.store(true, .monotonic);
    }
    
    pub fn accept(self: *TcpServer) !TcpClient {
        const fd = self.fd orelse return error.NotListening;
        
        var client_addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        
        const client_fd = try posix.accept(fd, &client_addr, &addr_len, 0);
        
        var client = TcpClient.init(self.allocator, self.config);
        client.fd = client_fd;
        return client;
    }
    
    pub fn stop(self: *TcpServer) void {
        self.running.store(false, .monotonic);
        
        if (self.fd) |fd| {
            posix.close(fd);
            self.fd = null;
        }
    }
    
    pub fn isRunning(self: *TcpServer) bool {
        return self.running.load(.monotonic);
    }
};

// Tests
test "TcpClient init" {
    const allocator = std.testing.allocator;
    const config = TcpConfig{};
    
    var client = TcpClient.init(allocator, config);
    defer client.close();
    
    try std.testing.expect(!client.isConnected());
}

test "TcpServer init" {
    const allocator = std.testing.allocator;
    const config = TcpConfig{};
    
    var server = TcpServer.init(allocator, 0, config);
    defer server.stop();
    
    try std.testing.expect(!server.isRunning());
}

test "SocketStats" {
    var stats = SocketStats{};
    
    stats.recordSend(100);
    stats.recordReceive(200);
    
    try std.testing.expectEqual(@as(i64, 100), stats.tx_bytes);
    try std.testing.expectEqual(@as(i64, 200), stats.rx_bytes);
    try std.testing.expectEqual(@as(i64, 1), stats.tx_packets);
    try std.testing.expectEqual(@as(i64, 1), stats.rx_packets);
}

test "TcpConfig default" {
    const config = TcpConfig.default();
    try std.testing.expectEqual(@as(u32, 60000), config.timeout_ms);
    try std.testing.expectEqual(@as(usize, 4096), config.read_buffer_size);
}
