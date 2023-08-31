const std = @import("std");

const Allocator = std.mem.Allocator;
const URI = std.Uri;
const FileOpenError = std.fs.File.OpenError;
const DirOpenError = std.fs.Dir.OpenError;
const Type = std.builtin.Type;

const string = []const u8;

pub fn folderExists(comptime path: []const u8) !bool {
    var folder = std.fs.cwd().openDir(path, .{}) catch |e| {
        switch (e) {
            DirOpenError.FileNotFound => return false,
            else => {
                std.log.debug("error: {s}", .{@errorName(e)});
                return true;
            },
        }
    };
    folder.close();

    return true;
}

pub fn fileExists(comptime path: []const u8) !bool {
    const file = std.fs.cwd().openFile(path, .{}) catch |e| {
        switch (e) {
            FileOpenError.FileNotFound => return false,
            else => {
                std.log.debug("error: {s}", .{@errorName(e)});
                return true;
            },
        }
    };
    file.close();

    return true;
}

fn createTmpDir() !std.fs.Dir {
    if (try folderExists(".tmp") == false) {
        try std.fs.cwd().makeDir(".tmp");
    }

    return try std.fs.cwd().openDir(".tmp", .{});
}

fn moveToModules(old_dir: std.fs.Dir, old_path: string, new_path: string) !void {
    if (try folderExists("modules") == false) {
        try std.fs.cwd().makeDir("modules");
    }

    try old_dir.rename(old_path, new_path);
}

pub fn getTarballStream(allocator: Allocator, module: anytype) !void {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const uri = URI.parse(module.tarball_url) catch return error.InvalidUrl;

    // Create Request
    var request = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
    defer request.deinit();

    try request.start();
    try request.wait();

    if (request.response.status != .ok) {
        std.log.err("Failed to download tarball for \"{s}\". Response: \"{s}\"", .{ module.name, request.response.status.phrase() orelse "unknown" });
        return error.RequestNotOk;
    }

    // Download to .tmp
    const tmp_dir = try createTmpDir();
    var br = std.io.bufferedReaderSize(std.crypto.tls.max_ciphertext_record_len, request.reader());
    var gzip = try std.compress.gzip.decompress(allocator, br.reader());
    defer gzip.deinit();
    try std.tar.pipeToFileSystem(tmp_dir, gzip.reader(), .{ .mode_mode = .ignore });

    // Move to modules dir
    const old_path = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ module.author, module.name, module.sha[0..7] });
    const new_path = try std.fmt.allocPrint(allocator, "../modules/{s}", .{module.name});
    std.log.debug("Moving {s} to {s}", .{ old_path, new_path });
    try moveToModules(tmp_dir, old_path, new_path);

    // Delete .tmp
    try std.fs.cwd().deleteDir(".tmp");
}

pub fn sedToBuild(allocator: Allocator) !void {
    _ = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{
            "sed",
            "-i",
            "1a const modules = @import(\"modules.zig\").modules;",
            "build.zig",
        },
        .cwd = ".",
    }) catch |err| {
        std.log.err("Failed to execute command {any}", .{err});
        return;
    };

    _ = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{
            "sed",
            "-i",
            "/b.addExecutable/,/});/{/});/a \\\\    inline for (modules) |mod| exe.addModule(mod.name, b.addModule(mod.name, .{ .source_file = .{ .path = mod.path } }));\n}",
            "build.zig",
        },
        .cwd = ".",
    }) catch |err| {
        std.log.err("Failed to execute command {any}", .{err});
        return;
    };
}
