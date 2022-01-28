const std = @import("std");
const clap = @import("clap");
const Container = @import("container.zig").Container;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help  Display this help and exit") catch unreachable,
        clap.parseParam("<COMMAND>...") catch unreachable,
    };

    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    var diag = clap.Diagnostic{};
    var args = clap.parseEx(clap.Help, &params, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.flag("--help"))
        return clap.help(stdout, &params);

    var tmpdir = try TmpDir("container").create();
    defer tmpdir.cleanup();

    const in = std.io.fixedBufferStream("this is a test\n").reader();

    const c = Container(@TypeOf(in), @TypeOf(stdout), @TypeOf(stderr)){
        .allocator = allocator,
        .argv = args.positionals(),
        .argp = &.{},
        .bind_mounts = &.{
            .{
                .target = "nix/store",
                .source = "/nix/store",
            },
            .{
                .target = "bin",
                .source = "/bin",
            },
            .{
                .target = "usr",
                .source = "/usr",
            },
        },
        .dir = tmpdir.dir,
        .cwd = "/",
        .stdin = in,
        .stdout = stdout,
        .stderr = stderr,
    };

    const res = try c.run();
    try stdout.print("{s}\n", .{res});
}

fn TmpDir(comptime prefix: []const u8) type {
    return struct {
        dir: std.fs.Dir,
        parent_dir: std.fs.Dir,
        sub_path: [sub_path_len]u8,

        const Self = @This();

        const random_bytes_count = 12;
        const sub_path_len = prefix.len + std.fs.base64_encoder.calcSize(random_bytes_count);

        pub fn create() !Self {
            var random_bytes: [random_bytes_count]u8 = undefined;
            std.crypto.random.bytes(&random_bytes);
            var sub_path: [sub_path_len]u8 = undefined;
            std.mem.copy(u8, &sub_path, prefix);
            _ = std.fs.base64_encoder.encode(sub_path[prefix.len..sub_path.len], &random_bytes);

            const tmp = try std.fs.openDirAbsolute("/tmp", .{});
            try tmp.makeDir(&sub_path);
            const dir = try tmp.openDir(&sub_path, .{});

            return Self{
                .dir = dir,
                .parent_dir = tmp,
                .sub_path = sub_path,
            };
        }

        pub fn cleanup(self: *Self) void {
            self.dir.close();
            self.parent_dir.deleteTree(&self.sub_path) catch {};
            self.parent_dir.close();
            self.* = undefined;
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}
