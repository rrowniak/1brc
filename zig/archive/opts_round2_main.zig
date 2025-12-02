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

    var map = std.StringHashMap(StationStats).init(gpa);
    try map.ensureTotalCapacity(10_000);
    defer map.deinit();

    var buffer: [1024 * 1024]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;
    // var count: usize = 0;

    while (reader.takeDelimiterExclusive('\n')) |line| {
        // if (count % 10_000_000 == 0) {
        //     std.debug.print("Progress {d}", .{count});
        // }
        // count += 1;
        var parts = std.mem.splitScalar(u8, line, ';');
        const name = parts.next() orelse continue;
        const temp_str = parts.next() orelse continue;

        const temp = try std.fmt.parseFloat(f64, temp_str);

        if (map.getEntry(name)) |e| {
            var v = e.value_ptr;
            if (temp < v.min) v.min = temp;
            if (temp > v.max) v.max = temp;
            v.sum += temp;
            v.count += 1;
        } else {
            const nname = try gpa.dupe(u8, name);
            try map.put(nname, .{
                .min = temp,
                .max = temp,
                .sum = temp,
                .count = 1,
            });
        }
        reader.toss(1);
    } else |_| {}

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
}

