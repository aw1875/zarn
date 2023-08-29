const std = @import("std");

const Allocator = std.mem.Allocator;
const FileOpenError = std.fs.File.OpenError;
const DirOpenError = std.fs.Dir.OpenError;

const Git = @import("git.zig").Git;
const string = []const u8;

const Dependency = struct {
    name: string,
    url: string,
};

pub const Config = struct {
    name: string,
    version: string = "0.0.1",
    license: string = "MIT",
    description: string,
    author: string,
    main: string = "src/main.zig",
    dependencies: []Dependency = &.{},

    pub fn init(name: string, version: ?string, license: ?string, description: string, author: string, main: ?string) Config {
        return .{
            .name = name,
            .version = version.?,
            .license = license.?,
            .description = description,
            .author = author,
            .main = main.?,
        };
    }

    pub fn getConfig(allocator: Allocator) !Config {
        const config_file = try std.fs.cwd().openFile("zarn.json", .{});
        const source = try config_file.reader().readAllAlloc(allocator, std.math.maxInt(usize));

        return try std.json.parseFromSliceLeaky(Config, allocator, source[0..], .{});
    }

    pub fn toJSON(self: Config, allocator: Allocator) !string {
        var buffer = std.ArrayListUnmanaged(u8){};
        try std.json.stringify(self, .{ .whitespace = .indent_4 }, buffer.writer(allocator));

        return buffer.items;
    }

    pub fn addDependency(self: Config, name: string, url: string, allocator: Allocator) !void {
        var current_deps = self.dependencies;
        var deps = std.ArrayList(Dependency).init(allocator);
        defer deps.deinit();

        for (current_deps) |dep| {
            try deps.append(dep);
        }

        try deps.append(Dependency{ .name = name, .url = url });

        const new_config = Config{
            .name = self.name,
            .version = self.version,
            .license = self.license,
            .description = self.description,
            .author = self.author,
            .main = self.main,
            .dependencies = deps.items,
        };

        const file = try std.fs.cwd().openFile("zarn.json", .{ .mode = .write_only });
        defer file.close();
        try file.seekTo(0);
        _ = try file.write(try new_config.toJSON(allocator));
    }

    pub fn removeDependency(self: Config, name: string, allocator: Allocator) !void {
        var current_deps = self.dependencies;
        var deps = std.ArrayList(Dependency).init(allocator);
        defer deps.deinit();

        for (current_deps) |dep| {
            if (!std.mem.eql(u8, dep.name, name)) {
                try deps.append(dep);
            }
        }

        const new_config = Config{
            .name = self.name,
            .version = self.version,
            .license = self.license,
            .description = self.description,
            .author = self.author,
            .main = self.main,
            .dependencies = deps.items,
        };

        const file = try std.fs.cwd().createFile("zarn.json", .{ .truncate = true });
        defer file.close();
        try file.seekTo(0);
        _ = try file.write(try new_config.toJSON(allocator));
    }
};

inline fn join(comptime path: []const u8) []const u8 {
    var cwd: [std.os.PATH_MAX]u8 = undefined;
    _ = std.os.realpath(".", &cwd) catch @panic("Failed to get current working directory");
    const joined_path = &cwd ++ "/" ++ path;

    return comptime joined_path;
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

pub fn getTarballStream(allocator: Allocator, git: Git) !void {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(git.repo_details.?.tarball_url);

    // Request
    var request = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
    defer request.deinit();

    try request.start();
    try request.wait();

    if (request.response.status != .ok) {
        std.log.err("Failed to download tarball from GitHub", .{});
        return error.RequestNotOk;
    }

    // Download to .tmp
    const tmp_dir = try createTmpDir();
    var br = std.io.bufferedReaderSize(std.crypto.tls.max_ciphertext_record_len, request.reader());
    var gzip = try std.compress.gzip.decompress(allocator, br.reader());
    defer gzip.deinit();
    try std.tar.pipeToFileSystem(tmp_dir, gzip.reader(), .{ .mode_mode = .ignore });

    // Move to libs dir
    const old_path = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ git.repo_details.?.author, git.repo_details.?.repo, git.sha[0..7] });
    const new_path = try std.fmt.allocPrint(allocator, "../libs/{s}", .{git.repo_details.?.repo});
    std.log.info("Moving {s} to {s}", .{ old_path, new_path });
    try moveToLibs(tmp_dir, old_path, new_path);

    // Delete .tmp
    try deleteTmpDir();
}

pub fn removeLib(name: string) !void {
    var folder = try std.fs.cwd().openDir("libs", .{});
    try folder.deleteTree(name);
}

fn moveToLibs(old_dir: std.fs.Dir, old_path: string, new_path: string) !void {
    if (try folderExists("libs") == false) {
        try std.fs.cwd().makeDir("libs");
    }

    try old_dir.rename(old_path, new_path);
}

fn openLibsDir() !std.fs.Dir {
    return try std.fs.cwd().openDir("libs", .{});
}

fn createTmpDir() !std.fs.Dir {
    if (try folderExists(".tmp") == false) {
        try std.fs.cwd().makeDir(".tmp");
    }

    return try std.fs.cwd().openDir(".tmp", .{});
}

fn deleteTmpDir() !void {
    try std.fs.cwd().deleteDir(".tmp");
}
