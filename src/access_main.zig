//! QinLink Access Client
//! 
//! Main entry point for the Access client

const std = @import("std");
const qinlink = @import("qinlink");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize logger
    var logger = qinlink.Logger.init(allocator, .info, 1000);
    defer logger.deinit();
    
    logger.info("QinLink Access Client starting...", .{});
    
    // Read configuration from args or use defaults
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    const server_host = if (args.len > 1) args[1] else "127.0.0.1";
    const server_port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 10000;
    const device_name = if (args.len > 3) args[3] else "qinlink0";
    
    logger.info("Server: {s}:{d}", .{ server_host, server_port });
    logger.info("Device: {s}", .{device_name});
    
    // Create and start worker
    var worker = qinlink.access.AccessWorker.init(allocator, server_host, server_port, device_name);
    defer worker.deinit();
    
    worker.setLogger(&logger);
    
    // Start worker
    logger.info("Starting Access worker...", .{});
    try worker.start();
    
    logger.info("Access worker running. Press Ctrl+C to stop.", .{});
    
    // Keep running until interrupted
    // In real implementation, we would wait for signal or run forwarding loops
    std.posix.nanosleep(60, 0); // Sleep for 60 seconds as demo
    
    logger.info("Stopping Access worker...", .{});
    worker.stop();
    
    logger.info("Access client stopped.", .{});
}

