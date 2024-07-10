const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Event = @import("app.zig").Event;
const State = @import("app.zig").State;

const Segment = vaxis.Segment;

const log = std.log.scoped(.result_view);

pub const SelectedPathView = struct {
    file_paths: ?[]const []const u8 = null,
    selected_idx: usize = 0,

    pub fn handle_event(selected_path_view: *SelectedPathView, event: Event) !?Event {
        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.tab, .{})) {
                    return Event{
                        .change_active_component = .search_input,
                    };
                } else if (selected_path_view.file_paths) |paths| {
                    if (key.codepoint == 'j') {
                        selected_path_view.selected_idx = if (selected_path_view.selected_idx == paths.len - 1) 0 else selected_path_view.selected_idx + 1;
                    } else if (key.codepoint == 'k') {
                        selected_path_view.selected_idx = if (selected_path_view.selected_idx == 0) paths.len - 1 else selected_path_view.selected_idx - 1;
                    }
                    return Event{
                        .change_current_selected_path = paths[selected_path_view.selected_idx],
                    };
                }
            },
            else => {},
        }
        return null;
    }

    pub fn add_selected_path_view_component(
        selected_path_view: *SelectedPathView,
        parent: vaxis.Window,
        app_state: *const State,
        opts: vaxis.Window.ChildOptions,
    ) !vaxis.Window {
        const child = parent.child(opts);

        for (0..parent.width) |i| {
            if (i != parent.width - 1) {
                child.writeCell(i, 0, .{ .char = .{ .grapheme = "━" } });
                continue;
            }
            child.writeCell(i, 0, .{ .char = .{ .grapheme = "┫" } });
        }

        if (app_state.search_result.keys().len != 0) {
            selected_path_view.file_paths = app_state.search_result.keys();
        } else {
            selected_path_view.file_paths = null;
        }

        var row_offset: usize = 1;
        if (selected_path_view.file_paths) |paths| {
            for (paths, 0..) |path, i| {
                defer row_offset += 1;
                const is_selected = i == selected_path_view.selected_idx;
                const segment = Segment{
                    .text = path,
                    .style = .{
                        .reverse = is_selected,
                    },
                };

                _ = try child.printSegment(segment, .{
                    .col_offset = 1,
                    .row_offset = row_offset,
                });
            }
        }

        return child;
    }
};
