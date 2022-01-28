const std = @import("std");
const Container = @import("container.zig").Container;

pub fn main() !void {
    var tmpdir = try TmpDir("container").create();
    defer tmpdir.cleanup();

    const stdin = std.io.fixedBufferStream("this is a test\n").reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const c = Container(@TypeOf(stdin), @TypeOf(stdout), @TypeOf(stderr)){
        .exe = std.os.argv[1],
        .argv = @ptrCast([*:null]?[*:0]u8, &std.os.argv[1]),
        .argp = &[_:null]?[*:0]u8{},
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
        .stdin = stdin,
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
