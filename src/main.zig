const std = @import("std");
const Container = @import("container.zig").Container;

pub fn main() !void {
    const dir = try std.fs.cwd().makeOpenPath("/tmp/container", .{});
    const stdin = std.io.fixedBufferStream("this is a test\n").reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const c = Container(@TypeOf(stdin), @TypeOf(stdout), @TypeOf(stderr)){
        .exe = "cat",
        .argv = &[_:null]?[*:0]u8{"cat"},
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
        .dir = dir,
        .cwd = "/",
        .stdin = stdin,
        .stdout = stdout,
        .stderr = stderr,
    };
    const res = try c.run();
    try stdout.print("{s}\n", .{res});
}

test {
    std.testing.refAllDecls(@This());
}
