const std = @import("std");

pub fn ripgrep_term(term: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var child = std.process.Child.init(
        &.{
            "rg",
            "--json",
            term,
        },
        allocator,
    );
    child.stdout_behavior = .Pipe;

    _ = try child.spawn();

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var buffered_writer = std.io.bufferedWriter(result.writer());

    var buf: [4096]u8 = undefined;

    const reader = child.stdout.?.reader();

    while (true) {
        const size = try reader.read(&buf);

        const bytes_write = try buffered_writer.write(buf[0..size]);
        std.debug.assert(bytes_write == size);

        if (size < buf.len) break;
    }

    try buffered_writer.flush();

    return try result.toOwnedSlice();
}
