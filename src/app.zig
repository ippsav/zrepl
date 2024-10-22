const std = @import("std");
const ripgrep = @import("ripgrep.zig");
const vaxis = @import("vaxis");
const header = @import("header.zig");
const sidebar = @import("sidebar.zig");
const search_input = @import("search_input.zig");
const result_view = @import("result_view.zig");
const selected_path_view = @import("selected_path_view.zig");
const EventDebouncer = @import("debouncer.zig");

const Cell = vaxis.Cell;
const log = std.log.scoped(.app);

// Our Event. This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    dispatch_search: void,
    change_current_search_term: []const u8,
    change_active_component: ActiveComponent,
    change_current_selected_path: []const u8,
};

pub const EventLoop = vaxis.Loop(Event);

const ActiveLayout = enum {
    main,
};

const ActiveComponent = enum {
    none,
    search_input,
    path_viewer,
};

pub const State = struct {
    active_component: ActiveComponent = ActiveComponent.search_input,

    current_search_term: []const u8 = "",
    search_result: std.StringArrayHashMapUnmanaged([]const ripgrep.RgResult) = .{},
    current_selected_path: []const u8 = "",

    pub fn deinit(state: *State, allocator: std.mem.Allocator) void {
        allocator.free(state.current_search_term);
        state.clear_search_result(allocator);
        state.search_result.deinit(allocator);
    }

    pub fn clear_search_result(state: *State, allocator: std.mem.Allocator) void {
        defer state.search_result.clearAndFree(allocator);
        var it = state.search_result.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            for (kv.value_ptr.*) |result| {
                result.deinit(allocator);
            }
            allocator.free(kv.value_ptr.*);
        }
        state.current_selected_path = "";
    }
};

pub const App = struct {
    vx: vaxis.Vaxis,
    tty: vaxis.Tty,
    event_loop: EventLoop = undefined,
    state: State = .{},
    allocator: std.mem.Allocator,

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

        var selected_path_view_component = selected_path_view.SelectedPathView{};

        app.state.active_component = .search_input;

        var search_debouncer = EventDebouncer.init(
            400 * std.time.ns_per_ms,
            Event{
                .dispatch_search = {},
            },
        );

        _ = try std.Thread.spawn(
            .{},
            EventDebouncer.run,
            .{
                &search_debouncer,
                &app.event_loop,
            },
        );

        while (true) {
            const event = app.event_loop.nextEvent();
            if (event == .key_press and event.key_press.codepoint == 'c' and event.key_press.mods.ctrl) {
                search_debouncer.quit();
                break;
            }
            switch (event) {
                .winsize => |ws| {
                    try app.vx.resize(app.allocator, app.tty.anyWriter(), ws);
                },
                .dispatch_search => {
                    if (app.state.search_result.count() > 0) app.state.clear_search_result(app.allocator);
                    app.state.current_selected_path = "";

                    selected_path_view_component.selected_idx = 0;

                    if (app.state.current_search_term.len != 0) {
                        app.event_loop.stop();
                        const result = try ripgrep.ripgrep_term(app.state.current_search_term, app.allocator);
                        defer app.allocator.free(result);
                        try app.event_loop.start();
                        try ripgrep.parse_ripgrep_result(
                            result,
                            &app.state.search_result,
                            app.allocator,
                        );
                        if (app.state.search_result.count() > 0) {
                            app.state.current_selected_path = app.state.search_result.keys()[0];
                        }
                    }
                },
                .change_current_search_term => |str| {
                    search_debouncer.signal();
                    app.allocator.free(app.state.current_search_term);
                    app.state.current_search_term = str;
                },
                .change_active_component => |component| {
                    app.state.active_component = component;
                },
                .change_current_selected_path => |path| {
                    app.state.current_selected_path = path;
                },
                else => {
                    switch (app.state.active_component) {
                        .search_input => {
                            const result = try search_input_component.handle_event(event);
                            if (result) |ev| app.event_loop.postEvent(ev);
                        },
                        .path_viewer => {
                            const result = try selected_path_view_component.handle_event(event);
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
                @min(50, win.width * 30 / 100),
                .{
                    .y_off = header_child.height,
                },
            );
            win.writeCell(sidebar_child.width - 1, header_child.height - 1, intersection);

            const search_input_child = try search_input_component.add_search_input_component(sidebar_child, .{
                .width = .{ .limit = sidebar_child.width * 98 / 100 },
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

            // divider

            _ = try selected_path_view_component.add_selected_path_view_component(
                sidebar_child,
                &app.state,
                .{
                    .y_off = 9,
                },
            );

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
