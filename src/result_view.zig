const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Event = @import("app.zig").Event;
const log = std.log.scoped(.result_view);
const State = @import("app.zig").State;

const Segment = vaxis.Segment;

pub const ResultView = struct {

    // pub fn handle_event(search_input: *SearchInput, event: Event) !?Event {
    //     switch (event) {
    //         .key_press => |key| {
    //             if (key.matches(vaxis.Key.enter, .{})) {
    //                 return Event{
    //                     .dispatch_search = try search_input.text_input.toOwnedSlice(),
    //                 };
    //             }
    //             try search_input.text_input.update(.{ .key_press = key });
    //         },
    //         else => {},
    //     }
    //     return null;
    // }
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
        // if (result.len == 0) return child;
        // if (app_state)

        const mapped_result = app_state.search_result;

        // const result = rg_begin.value.data.path.text;
        var value_iterator = mapped_result.valueIterator();

        var row_offset: usize = 1;

        while (value_iterator.next()) |value| {
            for (value.*) |result| {
                const line_number_str = try std.fmt.allocPrint(allocator, "{d}: ", .{result.line_number});
                try result_view.line_numbers.append(allocator, line_number_str);

                print_line_number(&child, line_number_str, row_offset);

                row_offset += try print_line(
                    &child,
                    result.text,
                    row_offset,
                );
            }
        }

        return child;
    }

    fn print_line_number(container: *const vaxis.Window, line_number: []const u8, row_offset: usize) void {
        const cell = vaxis.Cell{
            .char = .{
                .grapheme = line_number,
            },
            .style = .{
                .fg = .{
                    .index = 45,
                },
            },
        };
        container.writeCell(5, row_offset, cell);
    }

    fn print_line(
        container: *const vaxis.Window,
        str: []const u8,
        offset: usize,
    ) !usize {
        var remaining = str[0..str.len];
        var lines_written: usize = 0;

        while (remaining.len > 0) {
            const line_len: usize = @min(remaining.len, container.width - 15);
            defer {
                lines_written += 1;
                remaining = remaining[line_len..];
            }

            const segment = Segment{
                .text = remaining[0..line_len],
            };

            _ = try container.printSegment(segment, .{
                .col_offset = 10,
                .row_offset = offset + lines_written,
            });
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
};
