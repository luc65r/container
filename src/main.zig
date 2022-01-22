const std = @import("std");
const log = std.log;
const os = std.os;
const CLONE = os.linux.CLONE;
const sys = @import("sys.zig");

pub fn main() !void {
    const inpipe = try os.pipe();
    const outpipe = try os.pipe();

    log.info("calling {s}", .{os.argv[1..os.argv.len]});
    const child_pid = try sys.clone3(.{
        .flags = CLONE.NEWUSER | CLONE.NEWNS | CLONE.NEWNET,
    });
    if (child_pid == 0) {
        os.close(inpipe[1]);
        os.close(outpipe[0]);
        try os.dup2(inpipe[0], 0);
        try os.dup2(outpipe[1], 1);
        os.close(inpipe[0]);
        os.close(outpipe[1]);

        return os.execvpeZ(os.argv[1], @ptrCast([*:null]?[*:0]u8, &os.argv[1]), @ptrCast([*:null]?[*:0]u8, os.environ.ptr));
    }

    os.close(inpipe[0]);
    os.close(outpipe[1]);

    os.close(inpipe[1]);

    while ((try sys.splice(outpipe[0], null, 1, null, std.math.maxInt(u32), 0)) != 0) {}
    os.close(outpipe[0]);
}

test {
    std.testing.refAllDecls(@This());
}
