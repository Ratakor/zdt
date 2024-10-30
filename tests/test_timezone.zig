//! test timezone from a users's perspective (no internal functionality)

const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Tz = zdt.Timezone;
const UTCoffset = zdt.UTCoffset;
const ZdtError = zdt.ZdtError;

const log = std.log.scoped(.test_timezone);

test "utc" {
    const utc = UTCoffset.UTC;
    try testing.expect(utc.seconds_east == 0);
    try testing.expectEqualStrings(utc.designation(), "UTC");

    const utc_now = Datetime.nowUTC();
    try testing.expectEqualStrings(utc_now.utc_offset.?.designation(), "UTC");

    try testing.expectEqualStrings(utc_now.tzName(), "UTC");
    try testing.expectEqualStrings(utc_now.tzAbbreviation(), "Z");
}

test "offset from seconds" {
    var off = try UTCoffset.fromSeconds(999, "hello world");
    try testing.expect(std.mem.eql(u8, off.designation(), "hello "));

    var err: zdt.ZdtError!zdt.UTCoffset = UTCoffset.fromSeconds(-99999, "invalid");
    try testing.expectError(ZdtError.InvalidOffset, err);
    err = UTCoffset.fromSeconds(99999, "invalid");
    try testing.expectError(ZdtError.InvalidOffset, err);

    off = try UTCoffset.fromSeconds(3600, "UTC+1");
    const dt = try Datetime.fromFields(.{ .year = 1970, .tz_options = .{ .utc_offset = off } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);

    const dt_unix = try Datetime.fromUnix(0, Duration.Resolution.second, .{ .utc_offset = off });
    try testing.expect(dt_unix.unix_sec == 0);
    try testing.expect(dt_unix.hour == 1);

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    const string = "1970-01-01T00:00:00+01:00";
    const directive = "%Y-%m-%dT%H:%M:%S%:z";
    try dt.toString(directive, buf.writer());
    try testing.expectEqualStrings(string, buf.items);
}

test "mem error" {
    const allocator = testing.failing_allocator;
    const err = Tz.fromTzdata("UTC", allocator);
    try testing.expectError(ZdtError.TZifUnreadable, err);
}

test "tz deinit is mem-safe" {
    // special case: UTC - actually has nothing to de-init; just the name data needs to be cleared
    const tz_utc = Tz.UTC;
    tz_utc.deinit();

    const tzinfo = try Tz.fromTzdata("Asia/Tokyo", testing.allocator);
    var dt = try Datetime.fromFields(.{ .year = 2027, .tz_options = .{ .tz = &tzinfo } });
    const off = dt.utc_offset.?;
    tzinfo.deinit();

    try testing.expect(std.meta.eql(off, dt.utc_offset.?));
    try testing.expectEqual(off.seconds_east, dt.utc_offset.?.seconds_east);
    // calling dt.tzName() or dt.tzAbbreviation() with a deinitialized timezone
    // is undefined behavior

    // removing the tzinfo from the datetime is "safe"
    dt = try dt.tzLocalize(null);
    try testing.expectEqualStrings("", dt.tzAbbreviation());
    try testing.expectEqualStrings("", dt.tzName());
}

test "tzfile tz manifests in Unix time" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expect(dt.tz != null);
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
}

test "local tz db, from specified or default prefix" {
    // NOTE : Windows does not use the IANA db, so we cannot test a 'local' prefix
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const db = Tz.tzdb_prefix;
    // log.warn("system tzdb prefix: {s}", .{db});
    const tzinfo = try Tz.fromSystemTzdata("Europe/Berlin", db, testing.allocator);
    defer tzinfo.deinit();

    const dt = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expect(dt.tz != null);
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
}

test "embedded tzdata" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expect(dt.tz != null);
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());

    const err = Tz.fromTzdata("Not/Defined", testing.allocator);
    try testing.expectError(ZdtError.TzUndefined, err);
}

test "invalid tzfile name" {
    const db = Tz.tzdb_prefix;
    // log.warn("tz db: {s}", .{db});
    var err = Tz.fromSystemTzdata("this is not a tzname", db, testing.allocator);
    try testing.expectError(ZdtError.InvalidIdentifier, err);
    err = Tz.fromSystemTzdata("../test", db, testing.allocator);
    try testing.expectError(ZdtError.InvalidIdentifier, err);
    err = Tz.fromSystemTzdata("*=!?:.", db, testing.allocator);
    try testing.expectError(ZdtError.InvalidIdentifier, err);
}

test "local tz" {
    var now = try Datetime.now(null);
    try testing.expect(now.tz == null);
    try testing.expect(now.utc_offset == null);

    const tzinfo = try Tz.tzLocal(testing.allocator);
    defer tzinfo.deinit();
    now = try Datetime.now(.{ .tz = &tzinfo });

    try testing.expect(now.tz != null);
    try testing.expect(!std.mem.eql(u8, now.tzName(), ""));
    try testing.expect(!std.mem.eql(u8, now.tzAbbreviation(), ""));
}

test "DST transitions" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    // DST off --> DST on (missing datetime), 2023-03-26
    var dt_std = try Datetime.fromUnix(1679792399, Duration.Resolution.second, .{ .tz = &tzinfo });
    var dt_dst = try Datetime.fromUnix(1679792400, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expect(!dt_std.utc_offset.?.is_dst);
    try testing.expect(dt_dst.utc_offset.?.is_dst);

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    try dt_std.toString("%Y-%m-%dT%H:%M:%S%:z", buf.writer());
    try testing.expectEqualStrings("2023-03-26T01:59:59+01:00", buf.items);
    buf.clearAndFree();

    try dt_dst.toString("%Y-%m-%dT%H:%M:%S%:z", buf.writer());
    try testing.expectEqualStrings("2023-03-26T03:00:00+02:00", buf.items);
    buf.clearAndFree();

    // DST on --> DST off (duplicate datetime), 2023-10-29
    dt_dst = try Datetime.fromUnix(1698541199, Duration.Resolution.second, .{ .tz = &tzinfo });
    dt_std = try Datetime.fromUnix(1698541200, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expect(dt_dst.utc_offset.?.is_dst);
    try testing.expect(!dt_std.utc_offset.?.is_dst);

    try dt_dst.toString("%Y-%m-%dT%H:%M:%S%:z", buf.writer());
    try testing.expectEqualStrings("2023-10-29T02:59:59+02:00", buf.items);
    buf.clearAndFree();

    try dt_std.toString("%Y-%m-%dT%H:%M:%S%:z", buf.writer());
    try testing.expectEqualStrings("2023-10-29T02:00:00+01:00", buf.items);
    buf.clearAndFree();
}

test "wall diff vs. abs diff" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    // DST off --> DST on (missing datetime), 2023-03-26
    const dt_std = try Datetime.fromUnix(
        1679792399000000001,
        Duration.Resolution.nanosecond,
        .{ .tz = &tzinfo },
    );
    const dt_dst = try Datetime.fromUnix(
        1679792400000000002,
        Duration.Resolution.nanosecond,
        .{ .tz = &tzinfo },
    );
    try testing.expect(!dt_std.utc_offset.?.is_dst);
    try testing.expect(dt_dst.utc_offset.?.is_dst);

    const diff_abs = dt_std.diff(dt_dst); // just 1 sec and 1 nanosec
    const diff_wall = try dt_std.diffWall(dt_dst); // 1 hour, 1 sec and 1 nanosec
    try testing.expectEqual(
        @as(i128, -1000000001),
        diff_abs.toTimespanMultiple(Duration.Timespan.nanosecond),
    );
    try testing.expectEqual(
        @as(i128, -3601000000001),
        diff_wall.toTimespanMultiple(Duration.Timespan.nanosecond),
    );
}

test "tz has name and abbreviation" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());

    dt = try Datetime.fromFields(.{ .year = 2023, .month = 8, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());

    dt = try Datetime.fromUnix(1672527600, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());

    dt = try Datetime.fromUnix(1690840800, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());
}

test "longest tz name" {
    const tzinfo = try Tz.fromTzdata("America/Argentina/ComodRivadavia", testing.allocator);
    defer tzinfo.deinit();
    const dt = try Datetime.fromFields(.{ .year = 2023, .month = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("America/Argentina/ComodRivadavia", dt.tzName());
}

test "early LMT, late CET" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 1880, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("LMT", dt.tzAbbreviation());

    // NOTE: this might fail in 10 years from 2024...
    dt = try Datetime.fromFields(.{ .year = 2039, .month = 8, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
}

test "tz name and abbr correct after localize" {
    const tz_ny = try Tz.fromTzdata("America/New_York", testing.allocator);
    defer tz_ny.deinit();

    var now_local: Datetime = try Datetime.now(.{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expect(now_local.tzAbbreviation().len > 0);

    now_local = try Datetime.now(null);
    try testing.expect(now_local.tzAbbreviation().len == 0);
    now_local = try now_local.tzLocalize(.{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expect(now_local.tzAbbreviation().len > 0);

    const t = std.time.nanoTimestamp();
    now_local = try Datetime.fromUnix(@intCast(t), Duration.Resolution.nanosecond, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expect(now_local.tzAbbreviation().len > 0);

    const t2 = std.time.timestamp();
    now_local = try Datetime.fromUnix(t2, Duration.Resolution.second, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expect(now_local.tzAbbreviation().len > 0);

    const t3: i32 = 0;
    now_local = try Datetime.fromUnix(t3, Duration.Resolution.second, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expectEqualStrings("EST", now_local.tzAbbreviation());

    const t4: i32 = 1690840800;
    now_local = try Datetime.fromUnix(t4, Duration.Resolution.second, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expectEqualStrings("EDT", now_local.tzAbbreviation());
}

test "tz name and abbr correct after conversion" {
    const tz_berlin = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tz_berlin.deinit();
    const tz_denver = try Tz.fromTzdata("America/Denver", testing.allocator);
    defer tz_denver.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .tz_options = .{ .tz = &tz_berlin } });
    var converted: Datetime = try dt.tzConvert(.{ .tz = &tz_denver });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("America/Denver", converted.tzName());
    try testing.expectEqualStrings("MST", converted.tzAbbreviation());

    dt = try Datetime.fromFields(.{ .year = 2023, .month = 8, .tz_options = .{ .tz = &tz_berlin } });
    converted = try dt.tzConvert(.{ .tz = &tz_denver });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());
    try testing.expectEqualStrings("America/Denver", converted.tzName());
    try testing.expectEqualStrings("MDT", converted.tzAbbreviation());
}

test "non-existent datetime" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectError(ZdtError.NonexistentDatetime, dt);

    const tzinfo_ = try Tz.fromTzdata("America/Denver", testing.allocator);
    defer tzinfo_.deinit();
    dt = Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 12, .hour = 2, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo_ } });
    try testing.expectError(ZdtError.NonexistentDatetime, dt);
}

test "ambiguous datetime" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);

    const tzinfo_ = try Tz.fromTzdata("America/Denver", testing.allocator);
    defer tzinfo_.deinit();
    dt = Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo_ } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);
}

test "ambiguous datetime / DST fold" {
    const tz_berlin = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tz_berlin.deinit();

    // DST on, offset 7200 s
    var dt_early = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .dst_fold = 0, .tz_options = .{ .tz = &tz_berlin } });
    // DST off, offset 3600 s
    var dt_late = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .dst_fold = 1, .tz_options = .{ .tz = &tz_berlin } });
    try testing.expectEqual(7200, dt_early.utc_offset.?.seconds_east);
    try testing.expectEqual(3600, dt_late.utc_offset.?.seconds_east);

    const tz_mountain = try Tz.fromTzdata("America/Denver", testing.allocator);
    defer tz_mountain.deinit();
    dt_early = try Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .dst_fold = 0, .tz_options = .{ .tz = &tz_mountain } });
    dt_late = try Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .dst_fold = 1, .tz_options = .{ .tz = &tz_mountain } });
    try testing.expectEqual(-21600, dt_early.utc_offset.?.seconds_east);
    try testing.expectEqual(-25200, dt_late.utc_offset.?.seconds_east);
}

test "tz without transitions at UTC+9" {
    const tzinfo = try Tz.fromTzdata("Asia/Tokyo", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
    dt = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 12, .hour = 2, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
    dt = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
    dt = try Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
}

test "make datetime aware" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt_naive = try Datetime.fromUnix(0, Duration.Resolution.second, null);
    try testing.expect(dt_naive.utc_offset == null);
    try testing.expect(dt_naive.tz == null);

    const dt_aware = try dt_naive.tzLocalize(.{ .tz = &tzinfo });
    try testing.expect(dt_aware.tz != null);
    try testing.expect(dt_aware.unix_sec != dt_naive.unix_sec);
    try testing.expect(dt_aware.unix_sec == -3600);
    try testing.expect(dt_aware.year == dt_naive.year);
    try testing.expect(dt_aware.day == dt_naive.day);
    try testing.expect(dt_aware.hour == dt_naive.hour);

    const naive_again = try dt_aware.tzLocalize(null);
    try testing.expect(std.meta.eql(dt_naive, naive_again));
}

test "replace tz in aware datetime" {
    const tz_Berlin = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tz_Berlin.deinit();

    const dt_utc = Datetime.epoch;
    const dt_berlin = try dt_utc.tzLocalize(.{ .tz = &tz_Berlin });

    try testing.expect(dt_berlin.utc_offset != null);
    try testing.expect(dt_berlin.unix_sec != dt_utc.unix_sec);
    try testing.expect(dt_berlin.unix_sec == -3600);
    try testing.expect(dt_berlin.year == dt_utc.year);
    try testing.expect(dt_berlin.day == dt_utc.day);
    try testing.expect(dt_berlin.hour == dt_utc.hour);
}

test "replace tz fails for non-existent datetime in target tz" {
    const tz_Berlin = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tz_Berlin.deinit();

    const dt_utc = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 2, .tz_options = .{ .utc_offset = UTCoffset.UTC } });
    const err = dt_utc.tzLocalize(.{ .tz = &tz_Berlin });

    try testing.expectError(ZdtError.NonexistentDatetime, err);
}

test "convert time zone" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt_naive = try Datetime.fromUnix(42, Duration.Resolution.nanosecond, null);
    const err = dt_naive.tzConvert(.{ .tz = &tzinfo });
    try testing.expectError(ZdtError.TzUndefined, err);

    const dt_Berlin = try Datetime.fromUnix(42, Duration.Resolution.nanosecond, .{ .tz = &tzinfo });

    const tzinfo_ = try Tz.fromTzdata("America/New_York", testing.allocator);
    defer tzinfo_.deinit();
    const dt_NY = try dt_Berlin.tzConvert(.{ .tz = &tzinfo_ });

    try testing.expect(dt_Berlin.unix_sec == dt_NY.unix_sec);
    try testing.expect(dt_Berlin.nanosecond == dt_NY.nanosecond);
    try testing.expect(dt_Berlin.hour != dt_NY.hour);
}

test "floor to date changes UTC offset" {
    const tzinfo = try Tz.fromTzdata("Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 5, .tz_options = .{ .tz = &tzinfo } });
    var dt_floored = try dt.floorTo(Duration.Timespan.day);
    try testing.expectEqual(@as(u8, 0), dt_floored.hour);
    try testing.expectEqual(@as(u8, 0), dt_floored.minute);
    try testing.expectEqual(@as(u8, 0), dt_floored.second);
    try testing.expectEqual(@as(i32, 3600), dt.utc_offset.?.seconds_east);
    try testing.expectEqual(@as(i32, 7200), dt_floored.utc_offset.?.seconds_east);

    dt = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 3, .tz_options = .{ .tz = &tzinfo } });
    dt_floored = try dt.floorTo(Duration.Timespan.day);
    try testing.expectEqual(@as(u8, 0), dt_floored.hour);
    try testing.expectEqual(@as(u8, 0), dt_floored.minute);
    try testing.expectEqual(@as(u8, 0), dt_floored.second);
    try testing.expectEqual(@as(i32, 7200), dt.utc_offset.?.seconds_east);
    try testing.expectEqual(@as(i32, 3600), dt_floored.utc_offset.?.seconds_east);
}

test "load a lot of zones" {
    const zones = [_][]const u8{
        "America/La_Paz",
        "Pacific/Saipan",
        "Asia/Muscat",
        "Pacific/Gambier",
        "Asia/Kolkata",
        "Asia/Anadyr",
        "Asia/Baku",
        "Africa/Maseru",
        "Europe/Brussels",
        "Indian/Mahe",
        "Africa/Abidjan",
        "Etc/GMT-1",
        "America/Guyana",
        "Mexico/BajaNorte",
        "Antarctica/Davis",
        "Europe/Malta",
        "Africa/Libreville",
        "Singapore",
        "America/Aruba",
        "Australia/Broken_Hill",
        "Asia/Yekaterinburg",
        "Europe/Sarajevo",
        "Europe/Warsaw",
        "Antarctica/Mawson",
        "Europe/Zurich",
        "Atlantic/Reykjavik",
        "Africa/Porto-Novo",
        "Asia/Vientiane",
        "America/Argentina/San_Juan",
        "Etc/GMT+3",
        "America/Maceio",
        "America/Manaus",
        "Poland",
        "US/Central",
        "Pacific/Auckland",
        "GMT0",
        "Asia/Kashgar",
        "Asia/Barnaul",
        "Etc/GMT-10",
        "Asia/Phnom_Penh",
        "America/Metlakatla",
        "America/Nome",
        "America/Anguilla",
        "Iceland",
        "America/Whitehorse",
        "Asia/Kuwait",
        "Asia/Almaty",
        "America/Indiana/Winamac",
        "America/Eirunepe",
        "Africa/Asmara",
        "Etc/GMT0",
        "Asia/Ujung_Pandang",
        "Jamaica",
        "Asia/Famagusta",
        "Asia/Jerusalem",
        "Australia/Yancowinna",
        "Brazil/DeNoronha",
        "America/St_Thomas",
        "EST",
        "America/Jujuy",
        "Pacific/Tongatapu",
        "America/Araguaina",
        "Australia/Queensland",
        "Pacific/Marquesas",
        "Europe/Mariehamn",
        "Europe/Belfast",
        "Africa/Malabo",
        "Europe/London",
        "Asia/Dacca",
        "America/Rainy_River",
        "US/Arizona",
        "America/Jamaica",
        "Asia/Pontianak",
        "Canada/Mountain",
        "America/Cordoba",
        "CST6CDT",
        "America/Tegucigalpa",
        "America/Pangnirtung",
        "GMT",
        "Atlantic/Canary",
        "America/Panama",
        "Africa/Mbabane",
        "Europe/Zagreb",
        "America/Coral_Harbour",
        "Australia/South",
        "Eire",
        "America/Chihuahua",
        "Africa/Johannesburg",
        "Asia/Aden",
        "Asia/Aqtobe",
        "America/St_Vincent",
        "Australia/Hobart",
        "Australia/Melbourne",
        "Asia/Saigon",
        "Europe/Copenhagen",
        "GMT+0",
        "America/Montserrat",
        "America/Fort_Wayne",
        "America/North_Dakota/Center",
        "America/Cuiaba",
        "Asia/Chita",
        "Europe/Simferopol",
        "Pacific/Wake",
        "Asia/Aqtau",
        "America/Recife",
        "Africa/Banjul",
        "Africa/Nairobi",
        "Asia/Yangon",
        "Asia/Novokuznetsk",
        "Asia/Ashgabat",
        "America/Belem",
        "PRC",
        "America/Cayenne",
        "Africa/Harare",
        "Asia/Magadan",
        "Atlantic/Faroe",
        "America/Atikokan",
        "Africa/Timbuktu",
        "Australia/Lord_Howe",
        "Europe/Rome",
        "Europe/Bucharest",
        "Africa/Tripoli",
        "Pacific/Honolulu",
        "America/Thule",
        "America/Merida",
        "Asia/Krasnoyarsk",
        "Atlantic/St_Helena",
        "America/Guayaquil",
        "Etc/GMT+9",
        "Asia/Irkutsk",
        "US/Hawaii",
        "America/Argentina/Ushuaia",
        "Europe/Kirov",
        "Asia/Kathmandu",
        "Europe/Luxembourg",
        "Africa/Ouagadougou",
        "America/Argentina/Catamarca",
        "Africa/Cairo",
        "America/Porto_Acre",
        "Europe/San_Marino",
        "Asia/Ho_Chi_Minh",
        "America/Cambridge_Bay",
        "Chile/Continental",
        "Pacific/Pago_Pago",
        "America/Fortaleza",
        "America/Port-au-Prince",
        "Africa/Gaborone",
        "Africa/Freetown",
        "America/Kralendijk",
        "America/Argentina/ComodRivadavia",
        "Atlantic/South_Georgia",
        "Europe/Bratislava",
        "Cuba",
        "Australia/Victoria",
        "Pacific/Apia",
        "NZ",
        "Pacific/Pohnpei",
        "America/North_Dakota/Beulah",
        "Australia/North",
        "US/Eastern",
        "NZ-CHAT",
        "Indian/Kerguelen",
        "America/Rankin_Inlet",
        "America/Creston",
        "Asia/Tbilisi",
        "America/Marigot",
        "Etc/GMT-2",
        "America/Winnipeg",
        "Europe/Oslo",
        "America/Tijuana",
        "Chile/EasterIsland",
        "America/Sitka",
        "America/Curacao",
        "Asia/Tokyo",
        "Brazil/East",
        "Asia/Dubai",
        "Africa/Juba",
        "Asia/Tehran",
        "America/Halifax",
        "Australia/Lindeman",
        "America/Blanc-Sablon",
        "Europe/Budapest",
        "Asia/Jayapura",
        "Pacific/Palau",
        "Hongkong",
        "America/Atka",
        "Asia/Atyrau",
        "Africa/Djibouti",
        "Atlantic/Stanley",
        "America/Santarem",
        "Antarctica/Casey",
        "America/Dominica",
        "Africa/Bangui",
        "Asia/Novosibirsk",
        "Europe/Guernsey",
        "Pacific/Yap",
        "Australia/Tasmania",
        "Africa/Lagos",
        "Etc/GMT-13",
        "Etc/GMT-9",
        "Canada/Central",
        "America/Ojinaga",
        "America/Costa_Rica",
        "Asia/Dhaka",
        "Asia/Amman",
        "Africa/Monrovia",
        "Asia/Qyzylorda",
        "Europe/Skopje",
        "Asia/Nicosia",
        "America/Ciudad_Juarez",
        "Israel",
        "Etc/GMT+5",
        "Africa/Kampala",
        "Asia/Calcutta",
        "Europe/Volgograd",
        "Asia/Beirut",
        "Australia/Perth",
        "America/Guatemala",
        "America/Indiana/Petersburg",
        "America/Paramaribo",
        "Asia/Baghdad",
        "Australia/Currie",
        "Pacific/Truk",
        "America/Porto_Velho",
        "Indian/Comoro",
        "Pacific/Midway",
        "Pacific/Easter",
        "Canada/Yukon",
        "America/Indiana/Vincennes",
        "Etc/GMT-5",
        "America/Punta_Arenas",
        "Mexico/BajaSur",
        "America/Ensenada",
        "America/Inuvik",
        "Australia/ACT",
        "EET",
        "America/Los_Angeles",
        "Asia/Srednekolymsk",
        "Zulu",
        "Europe/Jersey",
        "Europe/Zaporozhye",
        "America/Cancun",
        "Pacific/Tahiti",
        "Europe/Istanbul",
        "Africa/Maputo",
        "Asia/Kabul",
        "Europe/Busingen",
        "America/Detroit",
        "America/Argentina/Tucuman",
        "Asia/Qatar",
        "Europe/Saratov",
        "Europe/Belgrade",
        "America/Dawson",
        "Asia/Ulan_Bator",
        "Indian/Christmas",
        "Europe/Ulyanovsk",
        "Pacific/Guadalcanal",
        "Canada/Atlantic",
        "Africa/Ceuta",
        "Etc/GMT-4",
        "America/Antigua",
        "Antarctica/Vostok",
        "America/Mazatlan",
        "US/Michigan",
        "Australia/Eucla",
        "Africa/Addis_Ababa",
        "Africa/Lubumbashi",
        "Asia/Thimphu",
        "Antarctica/Syowa",
        "Europe/Ljubljana",
        "Asia/Urumqi",
        "America/St_Johns",
        "America/Godthab",
        "Europe/Riga",
        "Asia/Katmandu",
        "Pacific/Funafuti",
        "America/Moncton",
        "ROK",
        "Pacific/Chuuk",
        "Factory",
        "America/Swift_Current",
        "America/Goose_Bay",
        "Europe/Vatican",
        "America/Tortola",
        "America/Argentina/Cordoba",
        "America/Boa_Vista",
        "Africa/Sao_Tome",
        "Pacific/Nauru",
        "America/Argentina/Buenos_Aires",
        "Canada/Newfoundland",
        "Antarctica/McMurdo",
        "PST8PDT",
        "Australia/Brisbane",
        "Europe/Paris",
        "Africa/Khartoum",
        "Etc/GMT-3",
        "America/Catamarca",
        "Europe/Uzhgorod",
        "Pacific/Bougainville",
        "America/Noronha",
        "America/Guadeloupe",
        "Europe/Lisbon",
        "America/Kentucky/Monticello",
        "Asia/Harbin",
        "Europe/Kiev",
        "America/Cayman",
        "Pacific/Kanton",
        "America/Martinique",
        "America/Santa_Isabel",
        "America/Lower_Princes",
        "Pacific/Port_Moresby",
        "America/Thunder_Bay",
        "Asia/Dili",
        "Iran",
        "America/Hermosillo",
        "Europe/Samara",
        "America/Matamoros",
        "America/Bogota",
        "Europe/Tiraspol",
        "Atlantic/Jan_Mayen",
        "Africa/Accra",
        "America/Boise",
        "Libya",
        "Africa/Bissau",
        "WET",
        "Asia/Bangkok",
        "America/Puerto_Rico",
        "Asia/Pyongyang",
        "Etc/GMT-0",
        "Africa/Dar_es_Salaam",
        "America/Argentina/Salta",
        "Etc/GMT-6",
        "America/Shiprock",
        "America/Anchorage",
        "Atlantic/Azores",
        "America/St_Lucia",
        "America/Grenada",
        "Asia/Tomsk",
        "Asia/Colombo",
        "Europe/Athens",
        "America/Rosario",
        "Australia/Sydney",
        "Europe/Tallinn",
        "Asia/Singapore",
        "Europe/Astrakhan",
        "Africa/Windhoek",
        "Europe/Podgorica",
        "Africa/Douala",
        "Asia/Gaza",
        "Canada/Pacific",
        "Pacific/Rarotonga",
        "America/Rio_Branco",
        "Asia/Bahrain",
        "Pacific/Norfolk",
        "Pacific/Noumea",
        "Europe/Kaliningrad",
        "Greenwich",
        "US/Samoa",
        "Africa/Bujumbura",
        "America/Dawson_Creek",
        "Pacific/Niue",
        "America/Argentina/La_Rioja",
        "America/Glace_Bay",
        "Atlantic/Bermuda",
        "Asia/Hovd",
        "America/Campo_Grande",
        "Asia/Istanbul",
        "Asia/Tel_Aviv",
        "Australia/Adelaide",
        "America/Danmarkshavn",
        "Asia/Ulaanbaatar",
        "Pacific/Pitcairn",
        "Pacific/Guam",
        "Pacific/Samoa",
        "Asia/Qostanay",
        "America/Nipigon",
        "Africa/Nouakchott",
        "Asia/Bishkek",
        "GB",
        "Etc/GMT-7",
        "America/Yellowknife",
        "Indian/Antananarivo",
        "America/Belize",
        "Asia/Karachi",
        "Asia/Taipei",
        "Africa/Brazzaville",
        "Asia/Choibalsan",
        "GB-Eire",
        "Etc/GMT+0",
        "Asia/Sakhalin",
        "America/Mendoza",
        "Africa/Lusaka",
        "Canada/Saskatchewan",
        "America/St_Kitts",
        "Indian/Mayotte",
        "Europe/Isle_of_Man",
        "Indian/Cocos",
        "America/Grand_Turk",
        "W-SU",
        "America/Kentucky/Louisville",
        "Africa/Kigali",
        "America/Vancouver",
        "Europe/Prague",
        "Etc/GMT+6",
        "Africa/Blantyre",
        "Asia/Chungking",
        "Asia/Oral",
        "Pacific/Fiji",
        "Indian/Maldives",
        "Australia/LHI",
        "Australia/NSW",
        "US/Mountain",
        "Pacific/Chatham",
        "Africa/Kinshasa",
        "America/North_Dakota/New_Salem",
        "Europe/Nicosia",
        "Asia/Riyadh",
        "Pacific/Enderbury",
        "Africa/Casablanca",
        "Etc/UCT",
        "US/Indiana-Starke",
        "Universal",
        "Pacific/Wallis",
        "MST7MDT",
        "Asia/Khandyga",
        "Europe/Dublin",
        "America/Adak",
        "America/Monterrey",
        "Asia/Chongqing",
        "Europe/Minsk",
        "Antarctica/Macquarie",
        "Asia/Omsk",
        "America/Bahia",
        "Asia/Rangoon",
        "US/Aleutian",
        "Etc/GMT+12",
        "America/Indiana/Marengo",
        "Africa/Tunis",
        "Europe/Vaduz",
        "Portugal",
        "HST",
        "America/Santo_Domingo",
        "Pacific/Kosrae",
        "Etc/GMT+7",
        "Etc/GMT-12",
        "Asia/Dushanbe",
        "America/Indiana/Knox",
        "Pacific/Kiritimati",
        "America/Louisville",
        "America/Argentina/Mendoza",
        "Europe/Chisinau",
        "Etc/GMT+1",
        "Africa/Algiers",
        "Asia/Kuala_Lumpur",
        "Asia/Hebron",
        "America/Phoenix",
        "America/Caracas",
        "Asia/Manila",
        "Asia/Jakarta",
        "America/Edmonton",
        "Africa/Bamako",
        "Pacific/Tarawa",
        "America/Fort_Nelson",
        "America/St_Barthelemy",
        "Australia/Darwin",
        "Asia/Yerevan",
        "Asia/Yakutsk",
        "Europe/Tirane",
        "Navajo",
        "Etc/GMT+4",
        "Africa/Niamey",
        "Europe/Sofia",
        "Pacific/Fakaofo",
        "Antarctica/Palmer",
        "Asia/Thimbu",
        "Europe/Madrid",
        "US/East-Indiana",
        "Africa/Dakar",
        "Etc/Zulu",
        "Pacific/Kwajalein",
        "America/Argentina/Rio_Gallegos",
        "Etc/GMT-8",
        "GMT-0",
        "America/Nassau",
        "Europe/Berlin",
        "Europe/Vilnius",
        "Brazil/West",
        "Etc/GMT+11",
        "America/Menominee",
        "Etc/UTC",
        "America/Scoresbysund",
        "Pacific/Johnston",
        "America/Sao_Paulo",
        "America/Port_of_Spain",
        "Kwajalein",
        "America/Buenos_Aires",
        "Indian/Reunion",
        "Asia/Makassar",
        "America/Toronto",
        "Antarctica/DumontDUrville",
        "America/Indianapolis",
        "Asia/Brunei",
        "Asia/Kamchatka",
        "Etc/GMT+10",
        "CET",
        "Atlantic/Faeroe",
        "Atlantic/Cape_Verde",
        "Pacific/Galapagos",
        "US/Alaska",
        "Pacific/Ponape",
        "America/Resolute",
        "Turkey",
        "Europe/Moscow",
        "America/El_Salvador",
        "Antarctica/South_Pole",
        "Asia/Vladivostok",
        "America/Asuncion",
        "Asia/Samarkand",
        "Indian/Chagos",
        "Atlantic/Madeira",
        "Europe/Kyiv",
        "Asia/Macao",
        "MET",
        "EST5EDT",
        "Europe/Stockholm",
        "Africa/Asmera",
        "Japan",
        "America/Bahia_Banderas",
        "Asia/Damascus",
        "Europe/Helsinki",
        "America/Denver",
        "America/Iqaluit",
        "America/Managua",
        "Pacific/Majuro",
        "Etc/GMT+8",
        "America/Indiana/Tell_City",
        "America/Lima",
        "America/Nuuk",
        "Etc/GMT-14",
        "Africa/El_Aaiun",
        "America/Miquelon",
        "Africa/Ndjamena",
        "America/Indiana/Vevay",
        "Etc/GMT-11",
        "US/Pacific",
        "Asia/Seoul",
        "America/Barbados",
        "America/Regina",
        "UTC",
        "Etc/GMT+2",
        "Africa/Luanda",
        "America/Montreal",
        "Africa/Mogadishu",
        "America/Chicago",
        "Antarctica/Troll",
        "Egypt",
        "Asia/Ust-Nera",
        "ROC",
        "Pacific/Efate",
        "Asia/Macau",
        "Asia/Shanghai",
        "America/Mexico_City",
        "Etc/Greenwich",
        "America/Yakutat",
        "America/Virgin",
        "Africa/Conakry",
        "Etc/Universal",
        "Australia/Canberra",
        "MST",
        "Asia/Kuching",
        "America/Montevideo",
        "America/Indiana/Indianapolis",
        "Asia/Tashkent",
        "America/Havana",
        "Canada/Eastern",
        "Europe/Andorra",
        "America/Argentina/San_Luis",
        "Europe/Gibraltar",
        "Europe/Amsterdam",
        "Etc/GMT",
        "Europe/Monaco",
        "America/Knox_IN",
        "America/New_York",
        "Indian/Mauritius",
        "America/Juneau",
        "UCT",
        "Asia/Hong_Kong",
        "America/Santiago",
        "Europe/Vienna",
        "Brazil/Acre",
        "Mexico/General",
        "Australia/West",
        "America/Argentina/Jujuy",
        "Africa/Lome",
        "Antarctica/Rothera",
        "Asia/Ashkhabad",
        "Arctic/Longyearbyen",
    };

    inline for (zones) |zone| {
        const tz_a = try Tz.fromTzdata(zone, testing.allocator);
        const dt_a = try Datetime.fromUnix(1, Duration.Resolution.second, .{ .tz = &tz_a });
        try testing.expect(dt_a.utc_offset != null);
        try testing.expectEqualStrings(zone, dt_a.tzName());
        tz_a.deinit();

        if (builtin.os.tag != .windows) {
            const tz_b = try Tz.fromSystemTzdata(zone, Tz.tzdb_prefix, testing.allocator);
            const dt_b = try Datetime.fromUnix(1, Duration.Resolution.second, .{ .tz = &tz_b });
            try testing.expect(dt_b.utc_offset != null);
            try testing.expectEqualStrings(zone, dt_b.tzName());
            tz_b.deinit();
        }
    }
}

// the following test is auto-generated by gen_test_tzones.py. do not edit this line and below.

test "conversion between random time zones" {
    var tz_a = try Tz.fromTzdata("Asia/Choibalsan", std.testing.allocator);
    var tz_b = try Tz.fromTzdata("Etc/GMT+1", std.testing.allocator);

    var dt_a = try Datetime.fromUnix(-816207319, Duration.Resolution.second, .{ .tz = &tz_a });
    var dt_b = try Datetime.fromUnix(1921722761, Duration.Resolution.second, .{ .tz = &tz_b });
    var dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    var s_b = std.ArrayList(u8).init(testing.allocator);
    var s_c = std.ArrayList(u8).init(testing.allocator);
    defer s_b.deinit();
    defer s_c.deinit();

    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("2030-11-24T11:52:41+08:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1944-02-20T02:44:41-01:00:00", s_c.items);

    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Asia/Baghdad", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Grenada", std.testing.allocator);
    dt_a = try Datetime.fromUnix(1942114456, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1893647018, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1909-12-29T21:53:58+02:57:36", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("2031-07-18T00:14:16-04:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Etc/GMT+11", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Etc/GMT-0", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1128113058, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(1223021131, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("2008-10-02T21:05:31-11:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1934-04-03T03:15:42+00:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Australia/Melbourne", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Pacific/Wallis", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-485869856, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1894391592, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1909-12-21T14:06:48+10:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1954-08-10T00:09:04+12:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Costa_Rica", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Etc/GMT+11", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-999522008, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(719055854, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1992-10-14T03:44:14-06:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1938-04-29T23:59:52-11:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Atlantic/South_Georgia", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Asia/Sakhalin", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1389478107, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-195234029, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1963-10-25T06:19:31-02:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1925-12-21T10:51:33+09:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Inuvik", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Punta_Arenas", std.testing.allocator);
    dt_a = try Datetime.fromUnix(794111713, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1262529920, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1929-12-29T09:14:40+00:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1995-03-01T23:35:13-03:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Edmonton", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Etc/GMT", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1846174622, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(364596200, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1981-07-21T14:43:20-06:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1911-07-02T05:42:58+00:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Port-au-Prince", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Asia/Manila", std.testing.allocator);
    dt_a = try Datetime.fromUnix(1967326856, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(142696408, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1974-07-10T08:53:28-05:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("2032-05-05T07:40:56+08:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Antigua", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Nassau", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-865972273, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-639392452, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1949-09-27T10:59:08-04:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1942-07-24T00:08:47-04:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Indiana/Tell_City", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Etc/Greenwich", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1571932065, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-782078436, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1945-03-20T22:59:24-05:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1920-03-10T08:12:15+00:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Brazil/East", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Indiana/Tell_City", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1516539100, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(986091715, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("2001-03-31T23:21:55-03:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1921-12-11T05:08:20-06:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Danmarkshavn", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/La_Paz", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1215106914, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-487293440, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1954-07-23T21:42:40-03:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1931-07-01T01:45:30-04:32:36", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Europe/Podgorica", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Asia/Aden", std.testing.allocator);
    dt_a = try Datetime.fromUnix(1367598722, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1473054982, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1923-04-28T19:03:38+01:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("2013-05-03T19:32:02+03:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Australia/Brisbane", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Poland", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-260468215, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1511958403, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1922-02-02T21:33:17+10:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1961-09-30T09:43:05+02:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Menominee", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Africa/Malabo", std.testing.allocator);
    dt_a = try Datetime.fromUnix(824105261, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(477126985, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1985-02-13T01:16:25-06:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1996-02-12T07:07:41+01:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Australia/Perth", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Asia/Oral", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-444856409, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-2017440120, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1906-01-27T07:58:00+08:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1955-11-27T09:46:31+05:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Asia/Tehran", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Etc/GMT0", std.testing.allocator);
    dt_a = try Datetime.fromUnix(2081029752, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(230882752, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1977-04-26T10:35:52+04:30:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("2035-12-11T23:49:12+00:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Nuuk", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Asia/Barnaul", std.testing.allocator);
    dt_a = try Datetime.fromUnix(1751368983, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(693621470, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1991-12-24T21:37:50-03:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("2025-07-01T18:23:03+07:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Africa/Windhoek", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Australia/Tasmania", std.testing.allocator);
    dt_a = try Datetime.fromUnix(715858672, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-373086081, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1958-03-06T22:58:39+02:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1992-09-07T19:37:52+10:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Indian/Cocos", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Pacific/Pohnpei", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-293022949, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1445358615, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1924-03-14T13:59:45+06:30:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1960-09-18T23:44:11+11:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Indiana/Vincennes", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Europe/San_Marino", std.testing.allocator);
    dt_a = try Datetime.fromUnix(560485083, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(2064615505, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("2035-06-04T20:18:25-04:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1987-10-06T03:18:03+01:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Australia/Canberra", std.testing.allocator);
    tz_b = try Tz.fromTzdata("Antarctica/Vostok", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-1010224506, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(579644539, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1988-05-15T06:22:19+10:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1937-12-27T14:04:54+00:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("Asia/Urumqi", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Panama", std.testing.allocator);
    dt_a = try Datetime.fromUnix(42640281, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1385885032, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1926-01-31T21:46:28+05:50:20", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1971-05-09T07:31:21-05:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("America/Menominee", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Yellowknife", std.testing.allocator);
    dt_a = try Datetime.fromUnix(1094749082, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(775994453, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1994-08-04T05:00:53-05:00:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("2004-09-09T10:58:02-06:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();

    tz_a = try Tz.fromTzdata("NZ-CHAT", std.testing.allocator);
    tz_b = try Tz.fromTzdata("America/Miquelon", std.testing.allocator);
    dt_a = try Datetime.fromUnix(-44705548, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(788932013, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", s_b.writer());
    try testing.expectEqualStrings("1995-01-01T17:31:53+13:45:00", s_b.items);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", s_c.writer());
    try testing.expectEqualStrings("1968-08-01T09:47:32-04:00:00", s_c.items);
    tz_a.deinit();
    tz_b.deinit();
    s_b.clearAndFree();
    s_c.clearAndFree();
}
