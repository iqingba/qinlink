//! QinLink Switch Server
//! 
//! Main entry point for the Switch server

const std = @import("std");
const qinlink = @import("qinlink");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize logger
    var logger = qinlink.Logger.init(allocator, .info, 1000);
    defer logger.deinit();
    
    logger.info("QinLink Switch Server starting...", .{});
    
    // Read configuration from args or use defaults
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    const port: u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 10000;
    
    logger.info("Listening on port: {d}", .{port});
    
    // Create and start worker
    var worker = qinlink.switch_mod.SwitchWorker.init(allocator, port);
    defer worker.deinit();
    
    worker.setLogger(&logger);
    
    // Start server
    logger.info("Starting Switch server...", .{});
    try worker.start();
    
    logger.info("Switch server running. Press Ctrl+C to stop.", .{});
    
    // Keep running until interrupted
    // In real implementation, we would run accept loop here
    std.posix.nanosleep(60, 0); // Sleep for 60 seconds as demo
    
    logger.info("Stopping Switch server...", .{});
    worker.stop();
    
    logger.info("Switch server stopped.", .{});
}

