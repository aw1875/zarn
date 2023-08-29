const std = @import("std");

const json = std.json;
const Allocator = std.mem.Allocator;

const string = []const u8;

const RepoDetails = struct {
    author: string,
    repo: string,
    branch: string,
    repo_url: string,
    tarball_url: string,
};

pub const Git = struct {
    sha: string,
    node_id: string,
    commit: Commit,
    url: string,
    html_url: string,
    comments_url: string,
    author: GitAuthor,
    committer: GitAuthor,
    parents: []Parent,
    stats: Stats,
    files: []File,

    repo_details: ?RepoDetails = null,

    fn parseUrl(allocator: Allocator, url: string) !RepoDetails {
        var splits = std.mem.splitSequence(u8, url, "/");

        var author: string = undefined;
        var repo: string = undefined;

        while (splits.next()) |split| {
            if (std.mem.eql(u8, split, "github.com")) {
                author = splits.next().?;
                repo = splits.next().?;
            }
        }

        // TODO: Make branch dynamic
        const formatted_url = try std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/{s}/commits/{s}", .{ author, repo, "master" });
        const tarball_url = try std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/{s}/tarball/{s}", .{ author, repo, "master" });

        return .{ .author = author, .repo = repo, .branch = "master", .repo_url = formatted_url, .tarball_url = tarball_url };
    }

    // TODO allow just author/repo (ex: aw1875/zarn) rather than entire url
    pub fn getGitDetails(allocator: Allocator, url: string) !Git {
        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        const repo_details = try Git.parseUrl(allocator, url);

        const uri = std.Uri.parse(repo_details.repo_url) catch unreachable;
        var request = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
        defer request.deinit();

        try request.start();
        try request.wait();

        if (request.response.status != .ok) {
            std.log.err("Failed to get repo details", .{});
            return error.RequestNotOk;
        }

        const response = try request.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        var git = try json.parseFromSliceLeaky(Git, allocator, response, .{ .ignore_unknown_fields = true });
        git.repo_details = repo_details;

        return git;
    }
};

const GitAuthor = struct {
    login: string,
    id: u64,
    node_id: string,
    avatar_url: string,
    gravatar_id: string,
    url: string,
    html_url: string,
    followers_url: string,
    following_url: string,
    gists_url: string,
    starred_url: string,
    subscriptions_url: string,
    organizations_url: string,
    repos_url: string,
    events_url: string,
    received_events_url: string,
    type: string,
    site_admin: bool,
};

const Commit = struct {
    author: CommitAuthor,
    committer: CommitAuthor,
    message: string,
    tree: Tree,
    comment_count: u64,
    verification: Verification,
};

const CommitAuthor = struct {
    name: string,
    email: string,
    date: string,
};

const Tree = struct {
    sha: string,
    url: string,
};

const Verification = struct {
    verified: bool,
    reason: string,
    signature: ?string = null,
    payload: ?string = null,
};

const File = struct {
    sha: string,
    filename: string,
    status: string,
    additions: u64,
    deletions: u64,
    changes: u64,
    blob_url: string,
    raw_url: string,
    contents_url: string,
    patch: string,
};

const Parent = struct {
    sha: string,
    url: string,
    html_url: string,
};

const Stats = struct {
    total: u64,
    additions: u64,
    deletions: u64,
};
