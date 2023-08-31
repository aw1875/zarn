const std = @import("std");

const Allocator = std.mem.Allocator;
const string = []const u8;

const ArgsError = @import("../cli.zig").ArgsError;

const Common = @import("../utils/common.zig");
const Config = @import("../Config.zig").Config;
const Git = @import("../utils/git.zig");

fn installAll(allocator: Allocator) ArgsError!void {
    _ = allocator;
    std.log.debug("Installing all modules", .{});
}

fn installModule(allocator: Allocator, module: string) ArgsError!void {
    std.log.debug("Installing module {s}", .{module});

    const module_info = try Git.findModule(allocator, module);
    std.log.debug("{s}", .{module_info.toString()});

    std.log.debug("Getting tarball for {s} {s} on branch {s}", .{
        module_info.sha,
        module_info.name,
        module_info.branch,
    });
    Common.getTarballStream(allocator, module_info) catch return ArgsError.DownloadError;

    std.log.debug("Adding module {s} to zarn.json", .{module_info.name});
    var config = Config.fromJSON(allocator) catch return ArgsError.ConfigMissingError;
    config.addModule(module_info, allocator) catch return ArgsError.ConfigMissingError;
}

pub fn install(allocator: Allocator, module: ?string) ArgsError!void {
    const config_exists = Common.fileExists("zarn.json") catch return ArgsError.ConfigMissingError;
    if (!config_exists) {
        std.log.err("Could not find zarn.json. Please run zarn init first.", .{});
        return;
    }

    if (module) |mod| {
        try installModule(allocator, mod);
    } else {
        try installAll(allocator);
    }
}
