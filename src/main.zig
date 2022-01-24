const std = @import("std");
const sys = @import("sys.zig");

pub fn main() !void {
    const inpipe = try std.os.pipe();
    const outpipe = try std.os.pipe();

    const tmpdir_path = "/tmp/container";
    try std.os.mkdir(tmpdir_path, 0o700);
    var tmpdir = try std.fs.openDirAbsolute(tmpdir_path, .{});

    std.log.info("calling {s}", .{std.os.argv[1..std.os.argv.len]});
    const child_pid = try sys.clone3(.{
        .flags = std.os.linux.CLONE.NEWUSER | std.os.linux.CLONE.NEWNS | std.os.linux.CLONE.NEWNET | std.os.linux.CLONE.NEWPID,
    });
    if (child_pid == 0) {
        std.os.close(inpipe[1]);
        std.os.close(outpipe[0]);
        try std.os.dup2(inpipe[0], 0);
        try std.os.dup2(outpipe[1], 1);
        std.os.close(inpipe[0]);
        std.os.close(outpipe[1]);

        try tmpdir.setAsCwd();
        tmpdir.close();
        try sys.chroot(".");

        return std.os.execvpeZ(std.os.argv[1], @ptrCast([*:null]?[*:0]u8, &std.os.argv[1]), @ptrCast([*:null]?[*:0]u8, std.os.environ.ptr));
    }

    std.os.close(inpipe[0]);
    std.os.close(outpipe[1]);

    std.os.close(inpipe[1]);

    while ((try sys.splice(outpipe[0], null, 1, null, std.math.maxInt(u32), std.os.STDOUT_FILENO)) != 0) {}
    std.os.close(outpipe[0]);

    const rc = try sys.wait4(child_pid, 0);
    std.debug.assert(rc.pid == child_pid);
    std.debug.assert(std.os.linux.W.IFEXITED(rc.status) and std.os.linux.W.EXITSTATUS(rc.status) == 0);
    std.log.info("{}", .{rc});

    try tmpdir.deleteTree(".");
    tmpdir.close();
}

test {
    std.testing.refAllDecls(@This());
}
