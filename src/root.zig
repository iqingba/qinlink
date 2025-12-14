//! QinLink Library Root
//! This is the root module for the QinLink library

const std = @import("std");

// Export library modules
pub const error_mod = @import("lib/error.zig");
pub const utils = @import("lib/utils.zig");
pub const logger = @import("lib/logger.zig");
pub const safe = @import("lib/safe.zig");
pub const socket = @import("lib/socket.zig");

// Export protocol modules
pub const frame = @import("protocol/frame.zig");

// Re-export commonly used types
pub const Error = error_mod.Error;
pub const Logger = logger.Logger;
pub const Frame = frame.Frame;

test {
    // Run all tests
    std.testing.refAllDecls(@This());
}
