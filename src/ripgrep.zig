const std = @import("std");
const json = std.json;

pub const RgSummary = struct {
    data: struct {
        elapsed_total: struct {
            human: []const u8,
            nanos: u64,
            secs: u64,
        },
        stats: struct {
            bytes_printed: u64,
            bytes_searched: u64,
            elapsed: struct {
                human: []const u8,
                nanos: u64,
                secs: u64,
            },
            matched_lines: u64,
            matches: u64,
            searches: u64,
            searches_with_match: u64,
        },
    },
    type: []const u8,
};

pub const RgMatch = struct {
    type: []const u8,
    data: struct {
        path: struct {
            text: []const u8,
        },
        lines: struct {
            text: []const u8,
        },
        line_number: u64,
        absolute_offset: u64,
        submatches: []const struct {
            match: struct {
                text: []const u8,
            },
            start: u64,
            end: u64,
        },
    },
};

pub const RgBegin = struct {
    type: []const u8,
    data: struct {
        path: struct {
            text: []const u8,
        },
    },
};

pub const RgEnd = struct {
    type: []const u8,
    data: struct {
        path: struct {
            text: []const u8,
        },
        binary_offset: ?u0,
        stats: struct {
            elapsed: struct {
                secs: u64,
                nanos: u64,
                human: []const u8,
            },
            searches: u64,
            searches_with_match: u64,
            bytes_searched: u64,
            bytes_printed: u64,
            matched_lines: u64,
            matches: u64,
        },
    },
};

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

    const reader = child.stdout.?.reader();
    return try reader.readAllAlloc(allocator, std.math.maxInt(u64));
}

pub const Submatch = struct {
    match: struct {
        text: []const u8,
    },
    start: u64,
    end: u64,
};

pub const RgResult = struct {
    text: []const u8,
    absolute_offset: u64,
    line_number: u64,
    submatches: []const Submatch,

    pub fn deinit(result: RgResult, allocator: std.mem.Allocator) void {
        allocator.free(result.text);
        for (result.submatches) |submatch| {
            allocator.free(submatch.match.text);
        }
        allocator.free(result.submatches);
    }
};

pub fn parse_ripgrep_result(result: []const u8, map: *std.StringHashMapUnmanaged([]const RgResult), allocator: std.mem.Allocator) !void {
    var lines = std.mem.tokenizeScalar(u8, result, '\n');

    const Step = enum {
        begin_step,
        end_step,
        match_step,
        summary_step,
    };

    var curr_step: Step = .begin_step;
    var prev_step: Step = .begin_step;

    var curr_path: ?[]const u8 = null;
    var rg_results = std.ArrayListUnmanaged(RgResult){};
    defer rg_results.deinit(allocator);

    var def: usize = 0;
    while (lines.peek()) |peeked_line| {
        def += 1;
        switch (curr_step) {
            .begin_step => {
                const begin = json.parseFromSlice(RgBegin, allocator, peeked_line, .{}) catch |err| {
                    if (err == error.ParseFromValueError) return error.UnexpectedRgValue;
                    if (prev_step == .end_step) {
                        curr_step = .summary_step;
                        continue;
                    } else if (prev_step == .begin_step) {
                        curr_step = .summary_step;
                        continue;
                    }
                    return err;
                };
                defer begin.deinit();
                curr_path = try allocator.dupe(u8, begin.value.data.path.text);
                prev_step = curr_step;
                curr_step = .match_step;
            },
            .match_step => {
                const match = json.parseFromSlice(RgMatch, allocator, peeked_line, .{}) catch |err| {
                    if (err == error.UnknownField) {
                        if (prev_step == .begin_step) return error.UnexpectedRgValue;
                        if (prev_step == .match_step) {
                            curr_step = .end_step;
                            continue;
                        }
                    }
                    return err;
                };
                defer {
                    match.deinit();
                    prev_step = .match_step;
                }
                const text = try allocator.dupe(u8, match.value.data.lines.text);
                const submatches = try allocator.alloc(Submatch, match.value.data.submatches.len);
                for (match.value.data.submatches, 0..) |submatch, i| {
                    const match_text = try allocator.dupe(u8, submatch.match.text);
                    submatches[i] = .{
                        .match = .{
                            .text = match_text,
                        },
                        .start = submatch.start,
                        .end = submatch.end,
                    };
                }
                const rg_result: RgResult = .{
                    .text = text,
                    .absolute_offset = match.value.data.absolute_offset,
                    .submatches = submatches,
                    .line_number = match.value.data.line_number,
                };
                try rg_results.append(allocator, rg_result);
            },
            .end_step => {
                const end = json.parseFromSlice(RgEnd, allocator, peeked_line, .{}) catch |err| {
                    if (err == error.UnknownField) {
                        if (prev_step == .match_step) return error.UnexpectedRgValue;
                        continue;
                    }
                    return err;
                };
                defer end.deinit();
                const results = try rg_results.toOwnedSlice(allocator);
                rg_results.clearAndFree(allocator);
                if (curr_path) |path| {
                    try map.put(allocator, path, results);
                    curr_path = null;
                }
                prev_step = curr_step;
                curr_step = .begin_step;
            },
            .summary_step => {
                // We don't summary for now
                break;
            },
        }
        // Advance iterator
        _ = lines.next();
    }
}
// Example of a query
// {"type":"begin","data":{"path":{"text":"src/result_view.zig"}}}
// {"type":"match","data":{"path":{"text":"src/result_view.zig"},"lines":{"text":"        var remaining = str[0..str.len];\n"},"line_number":97,"absolute_offset":3005,"submatches":[{"match":{"text":"main"},"start":14,"end":18}]}}
// {"type":"match","data":{"path":{"text":"src/result_view.zig"},"lines":{"text":"        while (remaining.len > 0) {\n"},"line_number":100,"absolute_offset":3085,"submatches":[{"match":{"text":"main"},"start":17,"end":21}]}}
// {"type":"match","data":{"path":{"text":"src/result_view.zig"},"lines":{"text":"            const line_len: usize = @min(remaining.len, container.width - 15);\n"},"line_number":101,"absolute_offset":3121,"submatches":[{"match":{"text":"main"},"start":43,"end":47}]}}
