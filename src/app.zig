const std = @import("std");
const ripgrep = @import("ripgrep.zig");
const vaxis = @import("vaxis");
const header = @import("header.zig");
const sidebar = @import("sidebar.zig");
const search_input = @import("search_input.zig");
const result_view = @import("result_view.zig");

const Cell = vaxis.Cell;
const log = std.log.scoped(.app);

// Our Event. This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    dispatch_search: []const u8,
};

const ActiveLayout = enum {
    main,
};

const ActiveComponent = enum {
    none,
    search_input,
};

pub const State = struct {
    current_search_term: []const u8 = "",
    search_result: std.StringHashMapUnmanaged([]const ripgrep.RgResult) = .{},

    pub fn deinit(state: *State, allocator: std.mem.Allocator) void {
        allocator.free(state.current_search_term);
        state.clear_search_result(allocator);
        state.search_result.deinit(allocator);
    }

    pub fn clear_search_result(state: *State, allocator: std.mem.Allocator) void {
        var it = state.search_result.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            for (kv.value_ptr.*) |*result| {
                result.deinit(allocator);
            }
        }
    }
};

pub const App = struct {
    vx: vaxis.Vaxis,
    tty: vaxis.Tty,
    event_loop: vaxis.Loop(Event) = undefined,
    state: State = .{},
    allocator: std.mem.Allocator,

    active_component: ActiveComponent = .none,

    pub fn init(allocator: std.mem.Allocator) !App {
        const vx = try vaxis.init(allocator, .{});
        const tty = try vaxis.Tty.init();

        return .{
            .vx = vx,
            .tty = tty,
            .allocator = allocator,
        };
    }

    pub fn start(app: *App) !void {
        app.event_loop = .{
            .tty = &app.tty,
            .vaxis = &app.vx,
        };
        try app.event_loop.init();

        try app.event_loop.start();
        defer app.event_loop.stop();

        try app.vx.enterAltScreen(app.tty.anyWriter());

        // Components
        const header_component = header.Header{};
        var sidebar_component = sidebar.Sidebar{};

        var search_input_component = search_input.SearchInput.init(app.allocator, &app.vx.unicode);
        defer search_input_component.deinit();

        var result_view_component = result_view.ResultView{};

        app.active_component = .search_input;

        while (true) {
            const event = app.event_loop.nextEvent();
            if (event == .key_press and event.key_press.codepoint == 'c' and event.key_press.mods.ctrl) break;
            switch (event) {
                .winsize => |ws| {
                    try app.vx.resize(app.allocator, app.tty.anyWriter(), ws);
                },
                .dispatch_search => |str| {
                    app.state.clear_search_result(app.allocator);
                    app.allocator.free(app.state.current_search_term);

                    app.state.current_search_term = str;

                    if (str.len != 0) {
                        app.event_loop.stop();
                        const result = try ripgrep.ripgrep_term(app.state.current_search_term, app.allocator);
                        try app.event_loop.start();
                        try ripgrep.parse_ripgrep_result(result, &app.state.search_result, app.allocator);
                    }
                },
                else => {
                    switch (app.active_component) {
                        .search_input => {
                            const result = try search_input_component.handle_event(event);
                            if (result) |ev| app.event_loop.postEvent(ev);
                        },
                        else => {},
                    }
                },
            }

            const win = app.vx.window();
            win.clear();

            const intersection: Cell = .{ .char = .{ .grapheme = "┳" } };

            const header_child = try header_component.add_header_component(win, .{});
            const sidebar_child = try sidebar_component.add_sidebar_component(
                win,
                win.width * 30 / 100,
                .{
                    .y_off = header_child.height,
                },
            );
            win.writeCell(sidebar_child.width - 1, header_child.height - 1, intersection);

            const search_input_child = try search_input_component.add_search_input_component(sidebar_child, .{
                .x_off = sidebar_child.width / 2 - 50 / 2,
                .width = .{ .limit = 50 },
                .height = .{ .limit = 3 },
                .border = .{
                    .where = .all,
                    .style = .{
                        .fg = .{
                            .rgb = .{ 255, 255, 255 },
                        },
                    },
                },
            });
            _ = search_input_child;

            _ = try result_view_component.add_result_view_component(
                win,
                &app.state,
                .{
                    .x_off = sidebar_child.width + 1,
                    .y_off = header_child.height,
                },
                app.allocator,
            );
            defer result_view_component.clear_allocated_lines(app.allocator);

            // Render the screen
            try app.vx.render(app.tty.anyWriter());
        }
    }

    pub fn deinit(app: *App) void {
        app.state.deinit(app.allocator);
        app.vx.deinit(app.allocator, app.tty.anyWriter());
        app.tty.deinit();
    }
};
