const std = @import("std");

const Allocator = std.mem.Allocator;
const JSON = std.json;

const string = []const u8;

const ModuleInfo = @import("utils/git.zig").ModuleInfo;
const Common = @import("utils/common.zig");

pub const Config = struct {
    name: string,
    version: string = "0.0.1",
    license: string = "MIT",
    description: string,
    author: string,
    main: string = "src/main.zig",
    dependencies: std.StringHashMap(string),

    pub fn init(name: string, version: ?string, license: ?string, description: string, author: string, main: ?string, allocator: Allocator) Config {
        var config = .{
            .name = name,
            .version = version.?,
            .license = license.?,
            .description = description,
            .author = author,
            .main = main.?,
            .dependencies = std.StringHashMap(string).init(allocator),
        };

        // Add to modules.zig
        const modules_file = std.fs.cwd().createFile("modules.zig", .{ .truncate = true }) catch |e| {
            std.log.err("Failed to create modules.zig: {s}", .{@errorName(e)});
            return config;
        };

        defer modules_file.close();
        modules_file.seekTo(0) catch |e| {
            std.log.err("Failed to create modules.zig: {s}", .{@errorName(e)});
            return config;
        };

        _ = modules_file.write("const Module = struct { name: []const u8, path: []const u8 };\npub const modules: []const Module = &[_]Module{};") catch |e| {
            std.log.err("Failed to create modules.zig: {s}", .{@errorName(e)});
            return config;
        };

        Common.sedToBuild(allocator) catch |e| {
            std.log.err("Failed to modify build.zig: {s}", .{@errorName(e)});
            return config;
        };

        return config;
    }

    pub fn toJSON(self: *Config, allocator: Allocator) !void {
        const file = try std.fs.cwd().createFile("zarn.json", .{ .truncate = true });
        defer file.close();
        try file.seekTo(0);

        _ = try file.write("{\n");
        const fields: []const std.builtin.Type.StructField = comptime std.meta.fields(@TypeOf(self.*));

        inline for (fields) |field| {
            if (field.type == string) {
                _ = try file.write(try std.fmt.allocPrint(allocator, "\t\"{s}\": \"{s}\",\n", .{ field.name, @field(self.*, field.name) }));
            }
        }

        _ = try file.write("\t\"dependencies\": {\n");

        var deps_iter = self.dependencies.iterator();
        var i: usize = 1;
        while (deps_iter.next()) |dep| : (i += 1) {
            if (i != self.dependencies.count()) {
                _ = try file.write(try std.fmt.allocPrint(allocator, "\t\t\"{s}\": \"{s}\",\n", .{ dep.key_ptr.*, dep.value_ptr.* }));
            } else {
                _ = try file.write(try std.fmt.allocPrint(allocator, "\t\t\"{s}\": \"{s}\"\n", .{ dep.key_ptr.*, dep.value_ptr.* }));
            }
        }

        _ = try file.write("\t}\n}");
    }

    pub fn fromJSON(allocator: Allocator) !Config {
        const config_file = try std.fs.cwd().openFile("zarn.json", .{});
        const source = try config_file.reader().readAllAlloc(allocator, std.math.maxInt(usize));

        var root = try JSON.parseFromSliceLeaky(JSON.Value, allocator, source, .{});

        // Get all the fields
        const name = root.object.get("name") orelse return error.ConfigMissingName;
        const version = root.object.get("version") orelse return error.ConfigMissingVersion;
        const license = root.object.get("license") orelse return error.ConfigMissingLicense;
        const description = root.object.get("description") orelse return error.ConfigMissingDescription;
        const author = root.object.get("author") orelse return error.ConfigMissingAuthor;
        const main = root.object.get("main") orelse return error.ConfigMissingMain;
        const dependencies_object = root.object.get("dependencies") orelse return error.ConfigMissingDependencies;
        var dependencies = std.StringHashMap(string).init(allocator);

        var deps_iter = dependencies_object.object.iterator();
        while (deps_iter.next()) |dep| {
            try dependencies.put(dep.key_ptr.*, dep.value_ptr.*.string);
        }

        return .{
            .name = name.string,
            .version = version.string,
            .license = license.string,
            .description = description.string,
            .author = author.string,
            .main = main.string,
            .dependencies = dependencies,
        };
    }

    pub fn addModule(self: *Config, module: ModuleInfo, allocator: Allocator) !void {
        if (self.dependencies.contains(module.name)) {
            std.log.debug("Module already exists: {s}", .{module.name});
            return;
        }

        try self.dependencies.put(module.name, module.tarball_url);
        try self.toJSON(allocator);

        // Add to modules.zig
        const modules_file = try std.fs.cwd().createFile("modules.zig", .{ .truncate = true });
        defer modules_file.close();
        try modules_file.seekTo(0);

        _ = try modules_file.write("const Module = struct { name: []const u8, path: []const u8 };\npub const modules: []const Module = &[_]Module{");

        var deps_iter = self.dependencies.iterator();
        while (deps_iter.next()) |dep| {
            _ = try modules_file.write(try std.fmt.allocPrint(allocator, ".{{ .name = \"{s}\", .path = \"{s}\" }},", .{
                dep.key_ptr.*,
                try std.fmt.allocPrint(allocator, "modules/{s}/src/main.zig", .{dep.key_ptr.*}),
            }));
        }
        _ = try modules_file.write("};");
    }
};
