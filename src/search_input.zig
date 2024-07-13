const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Event = @import("app.zig").Event;

pub const SearchInput = struct {
    text_input: TextInput = undefined,

    pub fn init(allocator: std.mem.Allocator, unicode: *const vaxis.Unicode) SearchInput {
        const text_input = TextInput.init(allocator, unicode);
        return .{
            .text_input = text_input,
        };
    }

    pub fn deinit(search_input: *SearchInput) void {
        search_input.text_input.deinit();
    }

    pub fn handle_event(search_input: *SearchInput, event: Event) !?Event {
        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.tab, .{})) {
                    return Event{
                        .change_active_component = .path_viewer,
                    };
                } else {
                    try search_input.text_input.update(.{ .key_press = key });

                    const str = try search_input.text_input.toOwnedSlice();
                    const new_ev = Event{
                        .change_current_search_term = str,
                    };
                    try search_input.text_input.insertSliceAtCursor(str);

                    return new_ev;
                }
            },
            else => {},
        }
        return null;
    }

    pub fn add_search_input_component(
        search_input: *SearchInput,
        parent: vaxis.Window,
        opts: vaxis.Window.ChildOptions,
    ) !vaxis.Window {
        const child = parent.child(opts);
        search_input.text_input.draw(child);

        return child;
    }
};
