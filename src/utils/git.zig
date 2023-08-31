const std = @import("std");

const Allocator = std.mem.Allocator;
const JSON = std.json;
const URI = std.Uri;

const string = []const u8;

pub const RequestError = std.http.Client.RequestError;
pub const GitError = RequestError || error{
    InvalidUrl,
    RequestError,
    ResponseError,
    ModuleNotFound,

    JSONParseError,

    DefaultBranchNotFound,
    ShaNotFound,

    AuthorNotFound,
    NameNotFound,
};

pub const ModuleInfo = struct {
    sha: string,
    name: string,
    author: string,
    branch: string,
    tarball_url: string,

    pub fn toString(self: ModuleInfo) string {
        return std.fmt.allocPrint(std.heap.page_allocator, "ModuleInfo {{ sha: \"{s}\", name: \"{s}\", branch: \"{s}\", tarball_url: \"{s}\" }}", .{
            self.sha,
            self.name,
            self.branch,
            self.tarball_url,
        }) catch "";
    }
};

pub fn findModule(allocator: Allocator, module: string) GitError!ModuleInfo {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Prepare find URL
    var url = std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}", .{module}) catch "";
    var uri = URI.parse(url) catch return GitError.InvalidUrl;

    // Create Request
    var request = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
    defer request.deinit();
    request.start() catch return GitError.RequestError;
    request.wait() catch return GitError.RequestError;

    if (request.response.status != .ok) {
        std.log.err("Failed to find module \"{s}\". Response: \"{s}\"", .{ module, request.response.status.phrase() orelse "unknown" });
        return GitError.ModuleNotFound;
    }

    // Get Default Branch
    var response = request.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch return GitError.ResponseError;
    var root = JSON.parseFromSliceLeaky(JSON.Value, allocator, response, .{}) catch return GitError.JSONParseError;
    const branch = root.object.get("default_branch") orelse return GitError.DefaultBranchNotFound;

    // Prepare repo url
    url = std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/commits/{s}", .{ module, branch.string }) catch "";
    uri = URI.parse(url) catch return GitError.InvalidUrl;

    // Create Request
    request = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
    request.start() catch return GitError.RequestError;
    request.wait() catch return GitError.RequestError;

    if (request.response.status != .ok) {
        std.log.err("Failed to fetch details for \"{s}\". Response: \"{s}\"", .{ module, request.response.status.phrase() orelse "unknown" });
        return GitError.ModuleNotFound;
    }

    // Handle Response
    response = request.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch return GitError.ResponseError;
    root = JSON.parseFromSliceLeaky(JSON.Value, allocator, response, .{}) catch return GitError.JSONParseError;
    const sha = root.object.get("sha") orelse return GitError.ShaNotFound;

    var splits = std.mem.splitSequence(u8, module, "/");

    const author = splits.next() orelse return GitError.AuthorNotFound;
    const name = splits.next() orelse return GitError.NameNotFound;
    const tarball_url = std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/tarball/{s}", .{ module, branch.string }) catch "";

    return .{
        .sha = sha.string,
        .name = name,
        .author = author,
        .branch = branch.string,
        .tarball_url = tarball_url,
    };
}
