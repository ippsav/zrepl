const vaxis = @import("vaxis");
const OffsetOptions = @import("types.zig").OffsetOptions;

const header_text = "zrepl v 0.0.1";

pub const Header = struct {
    pub fn add_header_component(header: *const Header, parent: vaxis.Window, opts: ?OffsetOptions) !vaxis.Window {
        _ = header;
        const opts_or_default = opts orelse OffsetOptions{};
        const header_child = parent.child(.{
            .x_off = opts_or_default.x_off,
            .y_off = opts_or_default.y_off,
            .height = .{ .limit = parent.height * 3 / 100 },
            .width = .{ .limit = parent.width },
        });

        const segment: vaxis.Segment = .{
            .text = header_text,
        };
        _ = try header_child.printSegment(segment, .{
            .col_offset = header_child.width / 2 - header_text.len / 2,
            .row_offset = header_child.height * 20 / 100,
        });

        const h_cell: vaxis.Cell = .{
            .char = .{ .grapheme = "━" },
        };
        for (0..header_child.width) |i| {
            header_child.writeCell(i, header_child.height - 1, h_cell);
        }

        return header_child;
    }
};
