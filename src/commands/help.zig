const std = @import("std");

const Allocator = std.mem.Allocator;
const string = []const u8;

const ArgsError = @import("../cli.zig").ArgsError;

pub fn help(allocator: Allocator) ArgsError!void {
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

    const help_message = std.mem.join(allocator, "\n", help_messages) catch return ArgsError.JoinError;
    stdout.print("{s}", .{help_message}) catch return ArgsError.PrintError;
}
