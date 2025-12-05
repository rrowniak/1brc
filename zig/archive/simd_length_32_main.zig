const std = @import("std");

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    const file = try std.fs.cwd().openFile("measurements.txt", .{});
    defer file.close();

    // Data structure: station -> stats
    const StationStats = struct {
        min: f64,
        max: f64,
        sum: f64,
        count: u64,
    };

    var map = std.HashMapUnmanaged([]const u8, StationStats, HashCtx, 80){};
    try map.ensureTotalCapacity(gpa, 10_000);
    defer map.deinit(gpa);

    const buffer: []u8 = try gpa.alloc(u8, 4 * 1024 * 1024);
    var file_reader = file.reader(buffer);
    const reader = &file_reader.interface;

    // var stats = Stats.init();
    // SEMI      ; 0x3B 0b00111011 
    // NEW LINE \n 0x08 0b00001000

    while (true) {
        var name: []const u8 = undefined;
        var temp: f64 = undefined;
        const VEC_L: usize = 32;
        if (reader.bufferedLen() >= VEC_L) {
            @branchHint(.likely);
            const Vsimd = @Vector(VEC_L, u8);
            const vec: Vsimd = reader.buffered()[0..VEC_L].*;
            if (std.simd.firstIndexOfValue(vec, '\n')) |off| {
                @branchHint(.likely);
                const offset = @as(usize, off);
                const sep = std.simd.firstIndexOfValue(vec, ';').?;
                name = reader.buffered()[0..sep];
                const temp_str = reader.buffered()[sep+1..offset];
                temp = parse_f64_fast(temp_str);
                reader.toss(offset+1);
            } else {
                const line = reader.takeDelimiterExclusive('\n') catch break;
                var parts = std.mem.splitScalar(u8, line, ';');
                name = parts.next() orelse continue;
                const temp_str = parts.next() orelse continue;

                // temp = try std.fmt.parseFloat(f64, temp_str);
                temp = parse_f64_fast(temp_str);
                reader.toss(1);
            }
        } else {
            const line = reader.takeDelimiterExclusive('\n') catch break;
            var parts = std.mem.splitScalar(u8, line, ';');
            name = parts.next() orelse continue;
            const temp_str = parts.next() orelse continue;

            // temp = try std.fmt.parseFloat(f64, temp_str);
            temp = parse_f64_fast(temp_str);
            reader.toss(1);
        }

        // stats.add(name);

        if (map.getEntry(name)) |e| {
            var v = e.value_ptr;
            if (temp < v.min) v.min = temp;
            if (temp > v.max) v.max = temp;
            v.sum += temp;
            v.count += 1;
        } else {
            const nname = try gpa.dupe(u8, name);
            try map.put(gpa, nname, .{
                .min = temp,
                .max = temp,
                .sum = temp,
                .count = 1,
            });
        }
    } 

    // Collect keys for sorted output
    var keys = try std.ArrayList([]const u8).initCapacity(gpa, map.count());
    defer keys.deinit(gpa);

    var it = map.iterator();
    while (it.next()) |entry| {
        try keys.append(gpa, entry.key_ptr.*);
    }

    std.sort.heap([]const u8, keys.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);

    // Print results
    const out = std.debug;
    out.print("{{", .{});

    for (keys.items, 0..) |k, i| {
        const v = map.get(k).?;
        const avg = v.sum / @as(f64, @floatFromInt(v.count));

        out.print(
            "{s}={d:.1}/{d:.1}/{d:.1}",
            .{ k, v.min, avg, v.max },
        );

        if (i + 1 < keys.items.len)
            out.print(", ", .{});
    }

    out.print("}}\n", .{});

    // stats.print();
}

fn parse_f64_fast(str: []const u8) f64 {
    // possibilities: 0.0, 10.0, -0.0, -10.0
    var s = str;
    if (str[0] == '-') {
        s = str[1..];
    }
    var v: u8 = 0;
    if (s[1] == '.') {
        v = s[0] - '0';
    } else {
        v = 10 * (s[0] - '0') + s[1] - '0';
    }
    return build_f64(s.len == str.len, v, s[s.len-1] - '0');
}

pub fn build_f64(sign: bool, int: u8, frac: u8) f64 {
    // int  is 0–99
    // frac is 0–9

    const value_int = @as(usize, @as(usize, int) * 10 + frac); // 0–999
    const value = @as(f64, @floatFromInt(value_int)) * 0.1;

    return if (sign) value else -value;
}

const HashCtx = struct {
    pub fn hash(self: @This(), s: []const u8) u64 {
        _ = self;
        // const slen = @min(s.len, 8);
        // return std.hash.Wyhash.hash(0, s[0..slen]);
        return std.hash.Wyhash.hash(0, s);
    }
    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        // return @call(.never_inline, eql_, .{a, b});
        // const alen = @min(a.len, 8);
        // const blen = @min(b.len, 8);
        // return eql_(a[0..alen], b[0..blen]);
        return eql_(a, b);
        // return std.mem.eql(u8, a, b);
    }
};

pub fn eql_(a: []const u8, b: []const u8) bool {
    // return std.mem.eql(u8, a, b);
    if (a.len != b.len){
        @branchHint(.unlikely);
        return false; 
    } 
    
    // if (a.len <= 12) {
    //     @branchHint(.likely);
    //     if (a.len < 4) {
    //         @branchHint(.unlikely);
    //         const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
    //         return x == 0;
    //     }
    //     var x: u32 = 0;
    //     const mid = ((a.len - 1) >> 3) << 2;
    //     for ([_]usize{ 0, mid, a.len - 4}) |n| {
    //         x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
    //     }
    //     return x == 0;
    // }

    if (a.len <= 16) {
        @branchHint(.likely);
        // @branchHint(.unlikely);
        if (a.len < 4) {
            @branchHint(.unlikely);
            const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
            return x == 0;
        }
        var x: u32 = 0;
        for ([_]usize{ 0, a.len - 4, (a.len / 8) * 4, a.len - 4 - ((a.len / 8) * 4) }) |n| {
            x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
        }
        return x == 0;
    }
    const Scan = if (std.simd.suggestVectorLength(u8)) |vec_size|
        struct {
            pub const size = vec_size;
            pub const Chunk = @Vector(size, u8);
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return @reduce(.Or, chunk_a != chunk_b);
            }
        };
    
    inline for (1..6) |s| {
        const n = 16 << s;
        if (n <= Scan.size and a.len <= n) {
            const V = @Vector(n / 2, u8);
            var x = @as(V, a[0 .. n / 2].*) ^ @as(V, b[0 .. n / 2].*);
            x |= @as(V, a[a.len - n / 2 ..][0 .. n / 2].*) ^ @as(V, b[a.len - n / 2 ..][0 .. n / 2].*);
            const zero: V = @splat(0);
            return !@reduce(.Or, x != zero);
        }
    }
    // Compare inputs in chunks at a time (excluding the last chunk).
    for (0..(a.len - 1) / Scan.size) |i| {
        const a_chunk: Scan.Chunk = @bitCast(a[i * Scan.size ..][0..Scan.size].*);
        const b_chunk: Scan.Chunk = @bitCast(b[i * Scan.size ..][0..Scan.size].*);
        if (Scan.isNotEqual(a_chunk, b_chunk)) return false;
    }

    // Compare the last chunk using an overlapping read (similar to the previous size strategies).
    const last_a_chunk: Scan.Chunk = @bitCast(a[a.len - Scan.size ..][0..Scan.size].*);
    const last_b_chunk: Scan.Chunk = @bitCast(b[a.len - Scan.size ..][0..Scan.size].*);
    return !Scan.isNotEqual(last_a_chunk, last_b_chunk);
    // return std.mem.eql(u8, a, b);
}

const Stats = struct {
    histogram: [21]usize,
    min: usize,
    max: usize,

    fn init() @This() {
        return .{
            .histogram = [21]usize{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
            .min = std.math.maxInt(usize),
            .max = 0,
        };
    }

    fn add(self: *@This(), str: []const u8) void {
        const l = str.len;
        self.min = if (self.min > l) l else self.min;
        self.max = if (self.max < l) l else self.max;
        const i = if (l >= self.histogram.len) self.histogram.len - 1 else l;
        self.histogram[i] += 1;
    }

    fn print(self: @This()) void {
        std.debug.print("\nStats{s}", .{"\n"});
        for (self.histogram, 0..) |h, i| {
            std.debug.print("histogram[{d}] = {d}\n", .{i, h});
        }
        std.debug.print("min = {d}\n", .{self.min});
        std.debug.print("max = {d}\n", .{self.max});
    }
};


