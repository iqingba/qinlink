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
pub const control = @import("protocol/control.zig");
pub const ethernet = @import("protocol/ethernet.zig");

// Export network modules
pub const taper = @import("network/taper.zig");
pub const bridge = @import("network/bridge.zig");

// Re-export commonly used types
pub const Error = error_mod.Error;
pub const Logger = logger.Logger;
pub const Frame = frame.Frame;
pub const ControlMessage = control.ControlMessage;
pub const EtherFrame = ethernet.EtherFrame;
pub const Taper = taper.Taper;
pub const Bridge = bridge.Bridge;

test {
    // Run all tests
    std.testing.refAllDecls(@This());
}
