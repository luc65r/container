const std = @import("std");
const sys = @import("sys.zig");

const CLONE = std.os.linux.CLONE;
const MS = std.os.linux.MS;
const MNT = std.os.linux.MNT;
const EPOLL = std.os.linux.EPOLL;

pub fn IOStreams(comptime Stdin: type, comptime Stdout: type, comptime Stderr: type) type {
    return struct {
        stdin: Stdin,
        stdout: Stdout,
        stderr: Stderr,
        pipes: [3][2]std.os.fd_t = undefined,

        const Self = @This();

        pub fn initPipes(self: *Self) !void {
            for (self.pipes) |*pipe| {
                pipe.* = try std.os.pipe();
            }
        }

        pub fn setPipesAsStdio(self: Self) !void {
            for (self.pipes) |p, i| {
                std.os.close(p[side(.parent, i)]);
                try std.os.dup2(p[side(.child, i)], @intCast(i32, i));
                std.os.close(p[side(.child, i)]);
            }
        }

        pub fn readPipes(self: Self) !void {
            for (self.pipes) |p, i| {
                std.os.close(p[side(.child, i)]);
            }

            const epollfd = try std.os.epoll_create1(0);
            const epoll_event = std.os.linux.epoll_event;
            for (self.pipes) |p, i| {
                try std.os.epoll_ctl(epollfd, EPOLL.CTL_ADD, p[side(.parent, i)], &epoll_event{
                    .events = if (i == 0) EPOLL.OUT else EPOLL.IN,
                    .data = .{
                        .fd = p[side(.parent, i)],
                    },
                });
            }

            var open_fds: u32 = 3;
            while (open_fds > 0) {
                var events: [3]std.os.linux.epoll_event = undefined;
                std.log.debug("waiting for events", .{});
                const nfds = std.os.epoll_wait(epollfd, &events, -1);
                std.log.debug("got {} events", .{nfds});
                for (events[0..nfds]) |event| {
                    if (event.events & (EPOLL.IN | EPOLL.OUT) != 0) {
                        if (event.events & EPOLL.IN != 0)
                            std.log.debug("got pollin", .{});
                        if (event.events & EPOLL.OUT != 0)
                            std.log.debug("got pollout", .{});
                        var buf: [1024]u8 = undefined;
                        if (event.data.fd == self.pipes[0][1]) {
                            std.log.debug("reading for stdin", .{});
                            const r = try self.stdin.read(&buf);
                            if (r == 0) {
                                std.log.debug("finished reading for stdin", .{});
                                try std.os.epoll_ctl(epollfd, EPOLL.CTL_DEL, event.data.fd, null);
                                std.os.close(event.data.fd);
                                open_fds -= 1;
                            } else {
                                std.log.debug("writing {} bytes to stdin", .{r});
                                const w = try std.os.write(event.data.fd, buf[0..r]);
                                std.debug.assert(w == r);
                            }
                        } else if (event.data.fd == self.pipes[1][0]) {
                            std.log.debug("reading from stdout", .{});
                            const r = try std.os.read(event.data.fd, &buf);
                            std.log.debug("writing {} bytes for stdout", .{r});
                            const w = try self.stdout.write(buf[0..r]);
                            std.debug.assert(w == r);
                        } else if (event.data.fd == self.pipes[2][0]) {
                            std.log.debug("reading from stderr", .{});
                            const r = try std.os.read(event.data.fd, &buf);
                            std.log.debug("writing {} bytes for stderr", .{r});
                            const w = try self.stderr.write(buf[0..r]);
                            std.debug.assert(w == r);
                        } else {
                            unreachable;
                        }
                    }
                    if (event.events & (EPOLL.ERR | EPOLL.HUP) != 0) {
                        if (event.events & EPOLL.ERR != 0)
                            std.log.debug("got pollerr", .{});
                        if (event.events & EPOLL.HUP != 0)
                            std.log.debug("got pollhup", .{});
                        try std.os.epoll_ctl(epollfd, EPOLL.CTL_DEL, event.data.fd, null);
                        std.os.close(event.data.fd);
                        open_fds -= 1;
                    }
                }
            }
            std.os.close(epollfd);
        }

        const Side = enum {
            parent,
            child,
        };

        fn side(s: Side, i: usize) u1 {
            switch (s) {
                .parent => return if (i == 0) 1 else 0,
                .child => return if (i == 0) 0 else 1,
            }
        }
    };
}

pub fn ioStreams(stdin: anytype, stdout: anytype, stderr: anytype) IOStreams(@TypeOf(stdin), @TypeOf(stdout), @TypeOf(stderr)) {
    return .{ .stdin = stdin, .stdout = stdout, .stderr = stderr };
}

pub fn Container(comptime IOStreamsType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        argp: []const []const u8,
        bind_mounts: []const struct {
            target: []const u8, // relative path from `dir`
            source: ?[]const u8, // absolute path
        },
        dir: std.fs.Dir,
        cwd: []const u8,
        streams: IOStreamsType,

        const Self = @This();

        pub const Result = struct {
            exit_status: u32,
            user_time: f64,
            system_time: f64,
        };

        pub fn run(_self: Self) !Result {
            var self = _self;

            std.log.info("creating pipes", .{});
            try self.streams.initPipes();

            {
                std.log.info("making mount paths", .{});
                for (self.bind_mounts) |mount| {
                    try self.dir.makePath(mount.target);
                }
            }

            std.log.info("cloning", .{});
            const child_pid = try sys.clone3(.{
                .flags = CLONE.NEWUSER | CLONE.NEWNS | CLONE.NEWNET | CLONE.NEWPID | CLONE.NEWIPC,
            });
            if (child_pid == 0) {
                {
                    std.log.info("bind mounting dirs", .{});
                    for (self.bind_mounts) |mount| {
                        if (mount.source) |source| {
                            var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                            const target = try self.dir.realpath(mount.target, &buf);
                            const source_c = try std.os.toPosixPath(source);
                            const target_c = try std.os.toPosixPath(target);
                            try sys.mount(&source_c, &target_c, null, MS.BIND | MS.REC, null);
                        }
                    }
                }
                {
                    std.log.info("mounting /proc", .{});
                    try self.dir.makeDir("proc");
                    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                    const path = try self.dir.realpath("proc", &buf);
                    const path_c = try std.os.toPosixPath(path);
                    try sys.mount(null, &path_c, "proc", 0, null);
                }
                {
                    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                    const path = try self.dir.realpath(".", &buf);
                    const path_c = try std.os.toPosixPath(path);
                    std.os.close(self.dir.fd);

                    std.log.info("making sure target directory is a mount point", .{});
                    try sys.mount(&path_c, &path_c, null, MS.BIND | MS.REC, null);
                    std.log.info("pivoting root", .{});
                    try sys.pivot_root(&path_c, &path_c);
                    std.log.info("unmounting old root", .{});
                    try sys.umount2("/", MNT.DETACH);
                    try std.os.chdir(self.cwd);
                }
                {
                    std.log.info("duplicating pipes", .{});
                    try self.streams.setPipesAsStdio();
                }
                {
                    const argv = try toCStringArray(self.allocator, self.argv);
                    const argp = try toCStringArray(self.allocator, self.argp);
                    return std.os.execvpeZ(argv[0].?, argv, argp);
                }
            }

            try self.streams.readPipes();

            const rc = try sys.wait4(child_pid, 0);
            std.debug.assert(rc.pid == child_pid);
            std.debug.assert(std.os.linux.W.IFEXITED(rc.status));

            return Result{
                .exit_status = std.os.linux.W.EXITSTATUS(rc.status),
                .user_time = timevalToSec(rc.rusage.utime),
                .system_time = timevalToSec(rc.rusage.stime),
            };
        }
    };
}

fn timevalToSec(tv: std.os.timeval) f64 {
    return @intToFloat(f64, tv.tv_sec) + @intToFloat(f64, tv.tv_usec) / 1_000_000;
}

fn toCStringArray(allocator: std.mem.Allocator, slice: []const []const u8) ![*:null]?[*:0]u8 {
    const csa = try allocator.allocSentinel(?[*:0]u8, slice.len, null);
    for (slice) |s, i| {
        csa[i] = try allocator.allocSentinel(u8, s.len, 0);
        std.mem.copy(u8, csa[i].?[0..s.len], s);
    }
    return csa;
}
