const std = @import("std");

const Allocator = std.mem.Allocator;
const URI = std.Uri;
const FileOpenError = std.fs.File.OpenError;
const DirOpenError = std.fs.Dir.OpenError;
const Type = std.builtin.Type;

const Common = @import("common.zig");

const string = []const u8;

const LockStruct = struct {
    version: string,
    url: string,
    sha: string,
    dependencies: std.StringHashMap(string),
};

pub const Lock = struct {
    lock: std.StringHashMap(LockStruct),
};

pub fn readLock() !void {
    if (try Common.fileExists("zarn.json")) return;

    var file = try std.fs.cwd().openFile("zarn.lock", .{});
    defer file.close();

    const allocator = std.heap.page_allocator;
    const contents = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    var entries = std.mem.split(u8, contents, "\n\n");

    var lock = Lock{
        .lock = std.StringHashMap(LockStruct).init(allocator),
    };

    while (entries.next()) |entry| {
        var lines = std.mem.split(u8, entry, "\n");
        var package = lines.next().?;

        var lock_struct = LockStruct{
            .version = undefined,
            .url = undefined,
            .sha = undefined,
            .dependencies = std.StringHashMap(string).init(allocator),
        };

        while (lines.next()) |line| {
            if (line.len == 0) continue;
            switch (line[2]) {
                'v' => {
                    var splits = std.mem.split(u8, line[2..], " ");
                    _ = splits.next();
                    var version = splits.next().?;

                    lock_struct.version = version;
                },
                'r' => {
                    var splits = std.mem.split(u8, line[2..], " ");
                    _ = splits.next();
                    var resolved = splits.next().?;

                    lock_struct.url = resolved;
                },
                'i' => {
                    var splits = std.mem.split(u8, line[2..], " ");
                    _ = splits.next();
                    var integrity = splits.next().?;

                    lock_struct.sha = integrity;
                },
                'd' => continue,
                ' ' => {
                    var splits = std.mem.split(u8, line[4..], " ");
                    var name = splits.next().?;
                    var version = splits.next().?;

                    try lock_struct.dependencies.put(name, version);
                },
                else => unreachable,
            }
        }

        try lock.lock.put(package, lock_struct);
    }
}
