const std = @import("std");

const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const Git = @import("git.zig").Git;

const string = []const u8;

pub fn printHelp(allocator: Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    const help_messages: []const string = &.{
        "zarn [command]",
        "\r",
        "Usage:",
        "\r",
        "zarn init",
        "zarn install [package]",
        "\r",
    };

    const help = try std.mem.join(allocator, "\n", help_messages);

    try stdout.print("{s}", .{help});
}

pub fn initProject(allocator: Allocator) !void {
    const dir = try std.fs.cwd().openIterableDir(".", .{});
    var iterator = dir.iterate();

    var found_build: bool = false;

    while (try iterator.next()) |path| {
        if (std.mem.eql(u8, path.name, "build.zig")) {
            found_build = true;
            break;
        }
    }

    if (!found_build) {
        std.log.err("Could not find build.zig in the current directory", .{});
        return;
    }

    // TODO: Get info dynamically
    const config = common.Config.init("zarn", "0.0.1", "MIT", "A package manager for Zig", "aw1875", "src/main.zig");
    const init_json = try config.toJSON(allocator);

    if (try common.fileExists("zarn.json") == true) {
        std.log.err("zarn.json already exists", .{});
    } else {
        const init_file = try std.fs.cwd().createFile("zarn.json", .{});
        defer init_file.close();

        _ = try init_file.write(init_json);
    }
}

pub fn installPackage(allocator: Allocator, url: string) !void {
    std.log.info("Installing package from {s}", .{url});
    var git = try Git.getGitDetails(allocator, url);
    if (git.repo_details == null) return error.GitRepoMissingDetails;

    std.log.info("Getting tarball for branch {s}", .{git.repo_details.?.branch});
    try common.getTarballStream(allocator, git);

    var config = try common.Config.getConfig(allocator);
    try config.addDependency(git.repo_details.?.repo, git.repo_details.?.tarball_url, allocator);

    std.log.info("{s} installed", .{git.repo_details.?.repo});
}

pub fn removePackage(allocator: Allocator, name: string) !void {
    std.log.info("Removing package {s}", .{name});
    var config = try common.Config.getConfig(allocator);
    try config.removeDependency(name, allocator);
    try common.removeLib(name);
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    const process_args = try std.process.argsAlloc(allocator);
    const args = process_args[1..];
    defer allocator.free(process_args);

    if (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        try printHelp(allocator);
    } else {
        if (std.mem.eql(u8, args[0], "init")) {
            try initProject(allocator);
        } else if (std.mem.eql(u8, args[0], "install")) {
            switch (args.len) {
                2 => try installPackage(allocator, args[1]),
                else => try printHelp(allocator),
            }
        } else if (std.mem.eql(u8, args[0], "remove")) {
            switch (args.len) {
                2 => try removePackage(allocator, args[1]),
                else => try printHelp(allocator),
            }
        }
    }
}
