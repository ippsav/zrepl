const std = @import("std");
const app = @import("app.zig");
const EventLoop = app.EventLoop;
const Event = app.Event;

const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

const EventDebouncer = @This();

mutex: Mutex = .{},
cond: Condition = .{},
should_quit: bool = false,
should_debounce: bool = false,
debounce_time: u64,
event: Event = undefined,

pub fn init(debounce_time: u64, ev: Event) EventDebouncer {
    return .{
        .debounce_time = debounce_time,
        .event = ev,
    };
}

pub fn run(ed: *EventDebouncer, event_loop: *EventLoop) !void {
    while (true) {
        ed.mutex.lock();
        defer ed.mutex.unlock();

        if (ed.should_quit) break;

        if (!ed.should_debounce) {
            ed.cond.wait(&ed.mutex);
            ed.should_debounce = true;
        } else {
            ed.cond.timedWait(&ed.mutex, ed.debounce_time) catch |err| {
                switch (err) {
                    error.Timeout => {
                        event_loop.postEvent(ed.event);
                        ed.should_debounce = false;
                    },
                    else => return err,
                }
            };
        }
    }
}

pub fn signal(ed: *EventDebouncer) void {
    ed.mutex.lock();
    defer ed.mutex.unlock();
    ed.cond.signal();
}

pub fn quit(ed: *EventDebouncer) void {
    ed.mutex.lock();
    defer ed.mutex.unlock();
    ed.should_quit = true;
    ed.cond.signal();
}
