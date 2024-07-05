const vaxis = @import("vaxis");
const OffsetOptions = @import("types.zig").OffsetOptions;

pub const Sidebar = struct {
    pub fn add_sidebar_component(sidebar: Sidebar, parent: vaxis.Window, width: usize, opts: ?OffsetOptions) !vaxis.Window {
        _ = sidebar;
        const opts_or_default = opts orelse OffsetOptions{};
        const sidebar_child = parent.child(.{
            .x_off = opts_or_default.x_off,
            .y_off = opts_or_default.y_off,
            .height = .{ .limit = parent.height - opts_or_default.y_off },
            .width = .{ .limit = width },
        });

        const border_char: vaxis.Cell = .{
            .char = .{ .grapheme = "┃" },
        };
        for (0..sidebar_child.height) |i| {
            sidebar_child.writeCell(sidebar_child.width - 1, i, border_char);
        }

        return sidebar_child;
    }
};
