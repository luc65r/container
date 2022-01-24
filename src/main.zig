const std = @import("std");
const log = std.log;
const fs = std.fs;
const os = std.os;
const linux = os.linux;
const assert = std.debug.assert;
const CLONE = linux.CLONE;
const sys = @import("sys.zig");

pub fn main() !void {
    const inpipe = try os.pipe();
    const outpipe = try os.pipe();

    const tmpdir_path = "/tmp/container";
    try os.mkdir(tmpdir_path, 0o700);
    var tmpdir = try fs.openDirAbsolute(tmpdir_path, .{});

    log.info("calling {s}", .{os.argv[1..os.argv.len]});
    const child_pid = try sys.clone3(.{
        .flags = CLONE.NEWUSER | CLONE.NEWNS | CLONE.NEWNET | CLONE.NEWPID,
    });
    if (child_pid == 0) {
        os.close(inpipe[1]);
        os.close(outpipe[0]);
        try os.dup2(inpipe[0], 0);
        try os.dup2(outpipe[1], 1);
        os.close(inpipe[0]);
        os.close(outpipe[1]);

        try tmpdir.setAsCwd();
        tmpdir.close();
        try sys.chroot(".");

        return os.execvpeZ(os.argv[1], @ptrCast([*:null]?[*:0]u8, &os.argv[1]), @ptrCast([*:null]?[*:0]u8, os.environ.ptr));
    }

    os.close(inpipe[0]);
    os.close(outpipe[1]);

    os.close(inpipe[1]);

    while ((try sys.splice(outpipe[0], null, 1, null, std.math.maxInt(u32), os.STDOUT_FILENO)) != 0) {}
    os.close(outpipe[0]);

    const rc = try sys.wait4(child_pid, 0);
    assert(rc.pid == child_pid);
    assert(linux.W.IFEXITED(rc.status) and linux.W.EXITSTATUS(rc.status) == 0);
    log.info("{}", .{rc});

    try tmpdir.deleteTree(".");
    tmpdir.close();
}

test {
    std.testing.refAllDecls(@This());
}
