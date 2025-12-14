//! QinLink Error Handling Module
//! Provides standard error types and utilities for the QinLink project.
//!
//! This module follows Zig best practices for error handling:
//! - Use error sets for compile-time type safety
//! - Provide descriptive error types
//! - Support error context and formatting

const std = @import("std");
const fmt = std.fmt;

/// Core error set for QinLink operations
pub const Error = error{
    // Network errors
    ConnectionFailed,
    ConnectionClosed,
    ConnectionTimeout,
    BindFailed,
    ListenFailed,
    AcceptFailed,
    SendFailed,
    ReceiveFailed,

    // Protocol errors
    InvalidFrame,
    InvalidMagic,
    FrameTooLarge,
    FrameTooSmall,
    ParseError,
    EncodeError,
    DecodeError,

    // Authentication errors
    AuthenticationFailed,
    Unauthorized,
    InvalidCredentials,
    TokenExpired,

    // Device errors
    DeviceNotFound,
    DeviceAlreadyExists,
    DeviceCreateFailed,
    DeviceOpenFailed,
    DeviceCloseFailed,

    // Configuration errors
    InvalidConfiguration,
    ConfigurationNotFound,
    ConfigurationParseError,

    // Resource errors
    OutOfMemory,
    BufferTooSmall,
    ResourceExhausted,

    // System errors
    PermissionDenied,
    FileNotFound,
    IoError,

    // General errors
    Unknown,
};

/// Error context for debugging and logging
pub const ErrorContext = struct {
    error_type: Error,
    message: []const u8,
    timestamp: i64,

    pub fn init(err: Error, message: []const u8) ErrorContext {
        return .{
            .error_type = err,
            .message = message,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn format(
        self: ErrorContext,
        comptime fmt_str: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt_str;
        _ = options;
        try writer.print("[{d}] {s}: {s}", .{
            self.timestamp,
            @errorName(self.error_type),
            self.message,
        });
    }
};

/// Create an error with context message
pub fn newError(err: Error, comptime format_str: []const u8, args: anytype) Error {
    // For now, just return the error
    // In a full implementation, we could log the formatted message
    _ = format_str;
    _ = args;
    return err;
}

/// Convert standard library errors to QinLink errors
pub fn fromStdError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => Error.OutOfMemory,
        error.AccessDenied => Error.PermissionDenied,
        error.FileNotFound => Error.FileNotFound,
        error.ConnectionResetByPeer => Error.ConnectionClosed,
        error.ConnectionTimedOut => Error.ConnectionTimeout,
        error.BrokenPipe => Error.ConnectionClosed,
        else => Error.Unknown,
    };
}

/// Check if an error is a network-related error
pub fn isNetworkError(err: Error) bool {
    return switch (err) {
        Error.ConnectionFailed,
        Error.ConnectionClosed,
        Error.ConnectionTimeout,
        Error.BindFailed,
        Error.ListenFailed,
        Error.AcceptFailed,
        Error.SendFailed,
        Error.ReceiveFailed,
        => true,
        else => false,
    };
}

/// Check if an error is recoverable
pub fn isRecoverable(err: Error) bool {
    return switch (err) {
        Error.ConnectionTimeout,
        Error.ReceiveFailed,
        Error.SendFailed,
        => true,
        else => false,
    };
}

test "error creation" {
    const err = newError(Error.ConnectionFailed, "Failed to connect to {s}:{d}", .{ "127.0.0.1", 8080 });
    try std.testing.expectEqual(Error.ConnectionFailed, err);
}

test "error conversion" {
    const std_err = error.OutOfMemory;
    const qinlink_err = fromStdError(std_err);
    try std.testing.expectEqual(Error.OutOfMemory, qinlink_err);
}

test "network error check" {
    try std.testing.expect(isNetworkError(Error.ConnectionFailed));
    try std.testing.expect(!isNetworkError(Error.ParseError));
}

test "recoverable error check" {
    try std.testing.expect(isRecoverable(Error.ConnectionTimeout));
    try std.testing.expect(!isRecoverable(Error.AuthenticationFailed));
}

