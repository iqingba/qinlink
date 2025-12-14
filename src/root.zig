//! QinLink Library Root

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

// Export config modules
pub const config = @import("config/config.zig");

// Export application modules
pub const access = @import("access/worker.zig");
pub const switch_mod = @import("switch/worker.zig");

// Re-export commonly used types
pub const Error = error_mod.Error;
pub const Logger = logger.Logger;
pub const Frame = frame.Frame;
pub const AccessWorker = access.AccessWorker;
pub const SwitchWorker = switch_mod.SwitchWorker;

test {
    std.testing.refAllDecls(@This());
}
