//! QinLink Ethernet Protocol
//! 
//! Ethernet frame parsing and handling

const std = @import("std");

/// Ethernet frame type
pub const EtherType = enum(u16) {
    ipv4 = 0x0800,
    arp = 0x0806,
    ipv6 = 0x86DD,
    vlan = 0x8100,
    _,

    pub fn fromInt(value: u16) EtherType {
        return @enumFromInt(value);
    }

    pub fn toInt(self: EtherType) u16 {
        return @intFromEnum(self);
    }
};

/// MAC address (6 bytes)
pub const MacAddr = [6]u8;

/// Ethernet header (14 bytes)
pub const EtherHeader = extern struct {
    dst: MacAddr,
    src: MacAddr,
    ether_type: u16,

    pub fn parse(data: []const u8) ?EtherHeader {
        if (data.len < 14) return null;
        
        var header: EtherHeader = undefined;
        @memcpy(&header.dst, data[0..6]);
        @memcpy(&header.src, data[6..12]);
        header.ether_type = std.mem.readInt(u16, data[12..14], .big);
        
        return header;
    }

    pub fn encode(self: *const EtherHeader, buffer: []u8) void {
        @memcpy(buffer[0..6], &self.dst);
        @memcpy(buffer[6..12], &self.src);
        std.mem.writeInt(u16, buffer[12..14], self.ether_type, .big);
    }

    pub fn getEtherType(self: *const EtherHeader) EtherType {
        return EtherType.fromInt(self.ether_type);
    }

    pub fn isVlan(self: *const EtherHeader) bool {
        return self.ether_type == @intFromEnum(EtherType.vlan);
    }

    pub fn isBroadcast(self: *const EtherHeader) bool {
        return std.mem.eql(u8, &self.dst, &[_]u8{0xFF} ** 6);
    }

    pub fn isMulticast(self: *const EtherHeader) bool {
        return (self.dst[0] & 0x01) == 0x01;
    }
};

/// Ethernet frame
pub const EtherFrame = struct {
    header: EtherHeader,
    payload: []const u8,

    pub fn parse(data: []const u8) ?EtherFrame {
        if (data.len < 14) return null;
        
        const header = EtherHeader.parse(data) orelse return null;
        const payload = data[14..];
        
        return EtherFrame{
            .header = header,
            .payload = payload,
        };
    }

    pub fn size(self: *const EtherFrame) usize {
        return 14 + self.payload.len;
    }
};

/// ARP operation
pub const ArpOp = enum(u16) {
    request = 1,
    reply = 2,
    _,
};

/// ARP packet
pub const ArpPacket = extern struct {
    hw_type: u16,       // Hardware type (Ethernet = 1)
    proto_type: u16,    // Protocol type (IPv4 = 0x0800)
    hw_len: u8,         // Hardware address length (6 for MAC)
    proto_len: u8,      // Protocol address length (4 for IPv4)
    operation: u16,     // ARP operation
    sender_mac: MacAddr,
    sender_ip: [4]u8,
    target_mac: MacAddr,
    target_ip: [4]u8,

    pub fn parse(data: []const u8) ?ArpPacket {
        if (data.len < 28) return null;
        
        var pkt: ArpPacket = undefined;
        pkt.hw_type = std.mem.readInt(u16, data[0..2], .big);
        pkt.proto_type = std.mem.readInt(u16, data[2..4], .big);
        pkt.hw_len = data[4];
        pkt.proto_len = data[5];
        pkt.operation = std.mem.readInt(u16, data[6..8], .big);
        @memcpy(&pkt.sender_mac, data[8..14]);
        @memcpy(&pkt.sender_ip, data[14..18]);
        @memcpy(&pkt.target_mac, data[18..24]);
        @memcpy(&pkt.target_ip, data[24..28]);
        
        return pkt;
    }

    pub fn isRequest(self: *const ArpPacket) bool {
        return self.operation == @intFromEnum(ArpOp.request);
    }

    pub fn isReply(self: *const ArpPacket) bool {
        return self.operation == @intFromEnum(ArpOp.reply);
    }
};

// Utility functions
pub fn formatMac(mac: MacAddr, buffer: *[17]u8) void {
    _ = std.fmt.bufPrint(
        buffer,
        "{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}",
        .{ mac[0], mac[1], mac[2], mac[3], mac[4], mac[5] },
    ) catch unreachable;
}

pub fn parseMac(str: []const u8) ?MacAddr {
    if (str.len != 17) return null;
    
    var mac: MacAddr = undefined;
    var idx: usize = 0;
    
    for (0..6) |i| {
        const hex_str = str[idx .. idx + 2];
        mac[i] = std.fmt.parseInt(u8, hex_str, 16) catch return null;
        idx += 3;
    }
    
    return mac;
}

// Tests
test "EtherHeader parse" {
    const data = [_]u8{
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // dst
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, // src
        0x08, 0x00,                         // type (IPv4)
    };
    
    const header = EtherHeader.parse(&data).?;
    try std.testing.expectEqual(@as(u8, 0x00), header.dst[0]);
    try std.testing.expectEqual(@as(u8, 0xAA), header.src[0]);
    try std.testing.expectEqual(@as(u16, 0x0800), header.ether_type);
}

test "EtherHeader broadcast detection" {
    var header: EtherHeader = undefined;
    header.dst = [_]u8{0xFF} ** 6;
    try std.testing.expect(header.isBroadcast());
    
    header.dst = [_]u8{0x00} ** 6;
    try std.testing.expect(!header.isBroadcast());
}

test "EtherHeader multicast detection" {
    var header: EtherHeader = undefined;
    header.dst = [_]u8{ 0x01, 0x00, 0x5e, 0x00, 0x00, 0x01 };
    try std.testing.expect(header.isMulticast());
    
    header.dst = [_]u8{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55 };
    try std.testing.expect(!header.isMulticast());
}

test "MAC address format" {
    const mac = MacAddr{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
    var buffer: [17]u8 = undefined;
    
    formatMac(mac, &buffer);
    try std.testing.expectEqualStrings("AA:BB:CC:DD:EE:FF", &buffer);
}

test "MAC address parse" {
    const mac_str = "00:11:22:33:44:55";
    const mac = parseMac(mac_str).?;
    
    try std.testing.expectEqual(@as(u8, 0x00), mac[0]);
    try std.testing.expectEqual(@as(u8, 0x11), mac[1]);
    try std.testing.expectEqual(@as(u8, 0x55), mac[5]);
}

