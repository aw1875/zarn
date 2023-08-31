const std = @import("std");

const Allocator = std.mem.Allocator;
const string = []const u8;

const Config = @import("Config.zig").Config;
const GitError = @import("utils/git.zig").GitError;

pub const ArgsError = GitError || error{
    JoinError,
    PrintError,
    MissingModuleName,

    ConfigMissingError,

    DownloadError,

    UnknownCommandError,
};

const Commands = struct {
    const commands = std.ComptimeStringMap(*const fn (Allocator, ?string) ArgsError!void, .{
        .{ "add", @import("commands/install.zig").install },
        .{ "init", init },
        .{ "help", help },
        .{ "install", @import("commands/install.zig").install },
    });

    pub fn runCommand(allocator: Allocator, command: string, args: ?string) !void {
        const cmd = Commands.commands.get(command).?;
        cmd(allocator, args) catch return ArgsError.UnknownCommandError;
    }

    fn help(allocator: Allocator, _: ?string) ArgsError!void {
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

    fn init(allocator: Allocator, _: ?string) ArgsError!void {
        var config = Config.init("zarn", "0.0.1", "MIT", "A package manager for Zig", "aw1875", "src/main.zig", allocator);
        config.toJSON(allocator) catch return ArgsError.UnknownCommandError;
    }
};

pub fn ArgsHandler() !void {
    const allocator = std.heap.page_allocator;
    const process_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, process_args);

    const args = process_args[1..];

    switch (args.len) {
        0 => try Commands.runCommand(allocator, "install", null),
        1 => try Commands.runCommand(allocator, args[0], null),
        else => {
            if (Commands.commands.get(args[0])) |command| {
                const cmd_args = std.mem.join(allocator, " ", args[1..]) catch return ArgsError.JoinError;
                command(allocator, cmd_args) catch return ArgsError.UnknownCommandError;
                // try Commands.runCommand(allocator, "help", try std.mem.join(allocator, " ", args[1..]));
            }
        },
    }
}
