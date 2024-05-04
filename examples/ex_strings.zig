const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Timezone = zdt.Timezone;
const str = zdt.stringIO;

pub fn main() !void {
    println("---> datetime example", .{});
    println("OS / architecture: {s} / {s}", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
    println("Zig version: {s}", .{builtin.zig_version_string});

    // the easiest input format is probably ISO8601. This can directly
    // be parsed; schema is infered at runtime.
    println("", .{});
    println("---> (usage) ISO8601: parse some allowed formats", .{});
    const date_only = "2014-08-23";
    var parsed = try str.parseISO8601(date_only);
    assert(parsed.hour == 0);
    println("parsed '{s}'\n  to {s}", .{ date_only, parsed });
    // the default string representation of a zdt.Datetime instance is always ISO8601

    // we can have fractional seconds:
    const datetime_with_frac = "2014-08-23 12:15:56.123456789";
    parsed = try str.parseISO8601(datetime_with_frac);
    assert(parsed.nanosecond == 123456789);
    println("parsed '{s}'\n  to {s}", .{ datetime_with_frac, parsed });

    // we can also have a leap second, and a time zone specifier (Z == UTC):
    const leap_datetime = "2016-12-31T23:59:60Z";
    parsed = try str.parseISO8601(leap_datetime);
    assert(parsed.second == 60);
    assert(std.meta.eql(parsed.tzinfo.?, Timezone.UTC));
    println("parsed '{s}'\n  to {s}", .{ leap_datetime, parsed });

    // The format might be less-standard, so we need to provide parsing directives
    // à la strptime (zdt as of v0.1.20 has a subset of those).
    println("", .{});
    println("---> (usage): parse some non-standard format", .{});
    const dayfirst_dtstr = "23.7.2021, 9:45h";
    parsed = try str.parseToDatetime("%d.%m.%Y, %H:%Mh", dayfirst_dtstr);
    assert(parsed.day == 23);
    println("parsed '{s}'\n  to {s}", .{ dayfirst_dtstr, parsed });

    // We can also go the other way around. Since the output is a runtime-known
    // and we don't want to loose bytes in temporary memory, we use an allocator.
    println("", .{});
    println("---> (usage): format datetime to string", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var s = std.ArrayList(u8).init(allocator);
    defer s.deinit();
    // the formatting directive is comptime-known:
    try str.formatToString(s.writer(), "%a, %b %d %Y, %H:%Mh", parsed);
    println("formatted {s}\n  to '{s}'", .{ parsed, s.items });
}

fn println(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    nosuspend stdout.print(fmt ++ "\n", args) catch return;
}
