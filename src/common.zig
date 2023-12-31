const std = @import("std");

const Allocator = std.mem.Allocator;
const FileOpenError = std.fs.File.OpenError;
const DirOpenError = std.fs.Dir.OpenError;

const Git = @import("git.zig").Git;
const string = []const u8;

const Module = struct {
    name: string,
    path: string,
};

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

    fn addModule(dependencies: []Dependency, allocator: Allocator) !void {
        // Handle modules
        var modules = std.ArrayList(Module).init(allocator);
        defer modules.deinit();

        for (dependencies) |dep| {
            const path = try std.fmt.allocPrint(allocator, "modules/{s}/src/main.zig", .{dep.name});
            try modules.append(Module{ .name = dep.name, .path = path });
        }

        const modules_file = try std.fs.cwd().createFile("modules.zig", .{ .truncate = true });
        defer modules_file.close();
        try modules_file.seekTo(0);

        _ = try modules_file.write("const Module = struct { name: []const u8, path: []const u8 };\npub const modules: []const Module = &[_]Module{");

        for (modules.items) |module| {
            _ = try modules_file.write(try std.fmt.allocPrint(allocator, "Module{{ .name = \"{s}\", .path = \"{s}\" }},", .{ module.name, module.path }));
        }

        _ = try modules_file.write("};");
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

        // Handle modules
        try addModule(new_config.dependencies, allocator);
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

        // Handle modules
        try addModule(new_config.dependencies, allocator);
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

    // Move to modules dir
    const old_path = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ git.repo_details.?.author, git.repo_details.?.repo, git.sha[0..7] });
    const new_path = try std.fmt.allocPrint(allocator, "../modules/{s}", .{git.repo_details.?.repo});
    std.log.debug("Moving {s} to {s}", .{ old_path, new_path });
    try moveToModules(tmp_dir, old_path, new_path);

    // Delete .tmp
    try deleteTmpDir();
}

pub fn removeLib(name: string) !void {
    var folder = try std.fs.cwd().openDir("modules", .{});
    try folder.deleteTree(name);
}

fn moveToModules(old_dir: std.fs.Dir, old_path: string, new_path: string) !void {
    if (try folderExists("modules") == false) {
        try std.fs.cwd().makeDir("modules");
    }

    try old_dir.rename(old_path, new_path);
}

fn openModulesDir() !std.fs.Dir {
    return try std.fs.cwd().openDir("modules", .{});
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

pub fn sedToBuild(allocator: Allocator) !void {
    const deps_file = try std.fs.cwd().createFile("modules.zig", .{ .truncate = true });
    defer deps_file.close();
    try deps_file.seekTo(0);

    _ = try deps_file.write("const Module = struct { name: []const u8, path: []const u8 };\npub const modules: []const Module = &[_]Module{};");

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
