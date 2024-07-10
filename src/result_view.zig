const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Event = @import("app.zig").Event;
const State = @import("app.zig").State;
const rg = @import("ripgrep.zig");
const RgResult = rg.RgResult;
const Submatch = rg.Submatch;

const Segment = vaxis.Segment;

const log = std.log.scoped(.result_view);

pub const ResultView = struct {
    line_numbers: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(result_view: *ResultView, allocator: std.mem.Allocator) void {
        result_view.clear_allocated_lines(allocator);
        result_view.line_numbers.deinit(allocator);
    }

    pub fn clear_allocated_lines(result_view: *ResultView, allocator: std.mem.Allocator) void {
        for (result_view.line_numbers.items) |line| {
            allocator.free(line);
        }
        result_view.line_numbers.clearAndFree(allocator);
    }

    pub fn add_result_view_component(
        result_view: *ResultView,
        parent: vaxis.Window,
        app_state: *const State,
        opts: vaxis.Window.ChildOptions,
        allocator: std.mem.Allocator,
    ) !vaxis.Window {
        const child = parent.child(opts);
        const mapped_result = app_state.search_result;

        result_view.clear_allocated_lines(allocator);

        if (mapped_result.get(app_state.current_selected_path)) |search_results| {
            var row_offset: usize = 1;

            for (search_results) |result| {
                const line_number_str = try std.fmt.allocPrint(allocator, "{d}: ", .{result.line_number});
                try result_view.line_numbers.append(allocator, line_number_str);

                try print_line_number(&child, line_number_str, row_offset);

                row_offset += try print_line(
                    &child,
                    &result,
                    row_offset,
                    allocator,
                );
            }
        }

        return child;
    }

    fn print_line_number(container: *const vaxis.Window, line_number: []const u8, row_offset: usize) !void {
        const segment = Segment{
            .text = line_number,
            .style = .{
                .fg = .{
                    .index = 45,
                },
            },
        };
        _ = try container.printSegment(segment, .{
            .col_offset = 5,
            .row_offset = row_offset,
        });
    }

    fn print_line(
        container: *const vaxis.Window,
        result: *const RgResult,
        offset: usize,
        allocator: std.mem.Allocator,
    ) !usize {
        var text = result.text;
        var line_len: usize = @min(text.len, container.width - 15);
        var str_offset: usize = 0;
        var lines_written: usize = 0;
        var submatches_offset: usize = 0;

        var segments = std.ArrayList(Segment).init(allocator);
        defer segments.deinit();

        while (str_offset < text.len) {
            defer {
                lines_written += 1;
                str_offset += line_len;
                line_len = @min(text[line_len..].len, container.width - 15);
                segments.clearRetainingCapacity();
            }

            submatches_offset = try populate_segments(
                &segments,
                result.submatches[submatches_offset..],
                text,
                str_offset,
                str_offset + line_len,
            );

            var col_offset: usize = 10;
            for (segments.items) |segment| {
                _ = try container.printSegment(segment, .{
                    .col_offset = col_offset,
                    .row_offset = offset + lines_written,
                });
                col_offset += segment.text.len;
            }
        }

        const seperator = Segment{
            .text = "-",
        };

        for (0..container.width - 1) |i| {
            _ = try container.printSegment(seperator, .{
                .col_offset = i,
                .row_offset = offset + lines_written,
            });
        }

        return lines_written + 1;
    }

    fn populate_segments(
        segments: *std.ArrayList(Segment),
        submatches: []const Submatch,
        str: []const u8,
        offset: usize,
        limit: usize,
    ) !usize {
        if (submatches.len == 0 or submatches[0].start >= limit) {
            try segments.append(.{
                .text = str[offset..limit],
            });
            return 0;
        }

        var last_end: usize = offset;
        var submatch_found: usize = 0;

        for (submatches) |submatch| {
            if (submatch.start > limit) break;

            if (submatch.start > last_end) {
                try segments.append(.{
                    .text = str[last_end..submatch.start],
                });
            }

            try segments.append(.{
                .text = str[submatch.start..submatch.end],
                .style = .{
                    .reverse = true,
                },
            });

            submatch_found += 1;
            last_end = submatch.end;
        }

        if (last_end < str.len) {
            try segments.append(.{
                .text = str[last_end..],
            });
        }

        return submatch_found;
    }
};
