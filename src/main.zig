//! QinLink - Main entry point
//! 
//! This is a placeholder main. Use qinlink-access or qinlink-switch instead.

const std = @import("std");

pub fn main() void {
    const msg =
        \\QinLink - High Performance SD-WAN Solution
        \\
        \\Usage:
        \\  qinlink-access [server_host] [server_port] [device_name]
        \\    Start Access client (default: 127.0.0.1 10000 qinlink0)
        \\
        \\  qinlink-switch [port]
        \\    Start Switch server (default port: 10000)
        \\
        \\Build commands:
        \\  zig build                    # Build all executables
        \\  zig build run-access         # Run Access client
        \\  zig build run-switch         # Run Switch server
        \\  zig build test               # Run tests
        \\
        \\Examples:
        \\  ./zig-out/bin/qinlink-switch 10000
        \\  ./zig-out/bin/qinlink-access 192.168.1.1 10000 tap0
        \\
        \\For more information, visit: https://github.com/iqingba/qinlink
        \\
    ;
    
    _ = std.posix.write(1, msg) catch unreachable;
}
