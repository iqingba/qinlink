//! QinLink Logging System
//! Thread-safe logging with multiple log levels and file output support.
//!
//! Features:
//! - Multiple log levels (DEBUG, INFO, WARN, ERROR, FATAL)
//! - File and console output
//! - Thread-safe operations
//! - Timestamp support
//! - Message history buffer

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

/// Log levels from lowest to highest priority
pub const LogLevel = enum(u8) {
    debug = 10,
    info = 20,
    warn = 30,
    err = 40,
    fatal = 99,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    pub fn fromInt(value: u8) ?LogLevel {
        return switch (value) {
            10 => .debug,
            20 => .info,
            30 => .warn,
            40 => .err,
            99 => .fatal,
            else => null,
        };
    }
};

/// Log message structure
pub const LogMessage = struct {
    level: LogLevel,
    timestamp: i64,
    message: []const u8,

    pub fn format(
        self: LogMessage,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{d}] {s}: {s}", .{
            self.timestamp,
            self.level.toString(),
            self.message,
        });
    }
};

/// Main logger structure
pub const Logger = struct {
    level: LogLevel,
    file: ?std.fs.File,
    mutex: Thread.Mutex,
    allocator: Allocator,
    history: std.ArrayList(LogMessage),
    max_history: usize,
    msg_counter: i64, // Simple counter for message ordering

    /// Initialize a new logger
    pub fn init(allocator: Allocator, level: LogLevel, max_history: usize) Logger {
        return .{
            .level = level,
            .file = null,
            .mutex = Thread.Mutex{},
            .allocator = allocator,
            .history = std.ArrayList(LogMessage){},
            .max_history = max_history,
            .msg_counter = 0,
        };
    }

    /// Clean up logger resources
    pub fn deinit(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file) |file| {
            file.close();
        }

        // Free all message strings in history
        for (self.history.items) |msg| {
            self.allocator.free(msg.message);
        }
        self.history.deinit(self.allocator);
    }

    /// Set output file for logging
    pub fn setFile(self: *Logger, path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Close existing file if any
        if (self.file) |file| {
            file.close();
        }

        // Open new file in append mode
        self.file = try std.fs.cwd().createFile(path, .{
            .read = false,
            .truncate = false,
        });
    }

    /// Log a message with specified level
    pub fn log(
        self: *Logger,
        level: LogLevel,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) {
            return; // Below minimum log level
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        self.msg_counter += 1;
        const timestamp = self.msg_counter;
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;

        // Write to console
        const stderr = std.posix.STDERR_FILENO;
        var buf: [512]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "[{d}] {s}: {s}\n", .{
            timestamp,
            level.toString(),
            message,
        }) catch return;
        _ = std.posix.write(stderr, formatted) catch {};

        // Write to file if configured
        if (self.file) |file| {
            var file_buf: [512]u8 = undefined;
            const file_formatted = std.fmt.bufPrint(&file_buf, "[{d}] {s}: {s}\n", .{
                timestamp,
                level.toString(),
                message,
            }) catch return;
            _ = file.write(file_formatted) catch {};
        }

        // Add to history (with rotation)
        if (self.history.items.len >= self.max_history) {
            const oldest = self.history.orderedRemove(0);
            self.allocator.free(oldest.message);
        }

        self.history.append(self.allocator, .{
            .level = level,
            .timestamp = timestamp,
            .message = message,
        }) catch {};
    }

    /// Convenience methods for different log levels
    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    pub fn fatal(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.fatal, fmt, args);
    }

    /// Get log history
    pub fn getHistory(self: *Logger) []const LogMessage {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.history.items;
    }
};

/// Global logger instance (optional convenience)
var global_logger: ?*Logger = null;
var global_mutex: Thread.Mutex = Thread.Mutex{};

/// Set global logger
pub fn setGlobalLogger(logger: *Logger) void {
    global_mutex.lock();
    defer global_mutex.unlock();
    global_logger = logger;
}

/// Get global logger
pub fn getGlobalLogger() ?*Logger {
    global_mutex.lock();
    defer global_mutex.unlock();
    return global_logger;
}

/// Global convenience logging functions
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.debug(fmt, args);
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.info(fmt, args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.warn(fmt, args);
    }
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.err(fmt, args);
    }
}

pub fn fatal(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.fatal(fmt, args);
    }
}

// Tests
test "logger creation and basic logging" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator, .info, 100);
    defer logger.deinit();

    logger.info("Test message: {d}", .{42});
    logger.warn("Warning message", .{});
    logger.err("Error message", .{});

    const history = logger.getHistory();
    try std.testing.expectEqual(@as(usize, 3), history.len);
}

test "log level filtering" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator, .warn, 100);
    defer logger.deinit();

    logger.debug("Should not appear", .{});
    logger.info("Should not appear", .{});
    logger.warn("Should appear", .{});
    logger.err("Should appear", .{});

    const history = logger.getHistory();
    try std.testing.expectEqual(@as(usize, 2), history.len);
}

test "log history rotation" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator, .info, 3);
    defer logger.deinit();

    logger.info("Message 1", .{});
    logger.info("Message 2", .{});
    logger.info("Message 3", .{});
    logger.info("Message 4", .{}); // Should rotate out Message 1

    const history = logger.getHistory();
    try std.testing.expectEqual(@as(usize, 3), history.len);
}

test "log level enum" {
    try std.testing.expectEqual(LogLevel.debug, LogLevel.fromInt(10).?);
    try std.testing.expectEqual(LogLevel.info, LogLevel.fromInt(20).?);
    try std.testing.expectEqual(LogLevel.fatal, LogLevel.fromInt(99).?);
    try std.testing.expectEqual(@as(?LogLevel, null), LogLevel.fromInt(50));
    
    try std.testing.expectEqualStrings("DEBUG", LogLevel.debug.toString());
    try std.testing.expectEqualStrings("INFO", LogLevel.info.toString());
}

test "global logger" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator, .info, 100);
    defer logger.deinit();

    setGlobalLogger(&logger);
    
    info("Global test message", .{});
    
    const history = logger.getHistory();
    try std.testing.expectEqual(@as(usize, 1), history.len);
}

