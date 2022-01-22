const std = @import("std");
const os = std.os;
const linux = os.linux;

const errno = linux.getErrno;
const pid_t = linux.pid_t;
const fd_t = linux.fd_t;
const off_t = linux.off_t;
const UnexpectedError = os.UnexpectedError;
const unexpectedErrno = os.unexpectedErrno;

pub const CloneArgs = extern struct {
    flags: u64 = 0,
    pidfd: u64 = 0,
    child_tid: u64 = 0,
    parent_tid: u64 = 0,
    exit_signal: u64 = 0,
    stack: u64 = 0,
    stack_size: u64 = 0,
    tls: u64 = 0,
    set_tid: u64 = 0,
    set_tid_size: u64 = 0,
    cgroup: u64 = 0,
};

pub const Clone3Error = error{
    SystemResources,
    DomainControllerEnabled,
    DomainInvalid,
    PidAlreadyExists,
    PermissionDenied,
} || UnexpectedError;

pub fn clone3(args: CloneArgs) Clone3Error!pid_t {
    const rc = linux.syscall2(.clone3, @ptrToInt(&args), @sizeOf(CloneArgs));
    switch (errno(rc)) {
        .SUCCESS => return @intCast(pid_t, rc),
        .AGAIN => return error.SystemResources,
        .BUSY => return error.DomainControllerEnabled,
        .EXIST => return error.PidAlreadyExists,
        .INVAL => unreachable,
        .NOMEM => return error.SystemResources,
        .NOSPC => return error.SystemResources,
        .OPNOTSUPP => return error.DomainInvalid,
        .PERM => return error.PermissionDenied,
        .USERS => return error.SystemResources,
        else => |err| return unexpectedErrno(err),
    }
}

pub const SPLICE = struct {
    pub const MOVE = 1;
    pub const NONBLOCK = 2;
    pub const MORE = 4;
    pub const GIFT = 8;
};

pub const SpliceError = error{
    WouldBlock,
    SystemResources,
} || UnexpectedError;

pub fn splice(
    fd_in: fd_t,
    off_in: ?*off_t,
    fd_out: fd_t,
    off_out: ?*off_t,
    len: usize,
    flags: u32,
) SpliceError!usize {
    const rc = linux.syscall6(.splice, @bitCast(usize, @as(isize, fd_in)), @ptrToInt(off_in), @bitCast(usize, @as(isize, fd_out)), @ptrToInt(off_out), len, flags);
    switch (errno(rc)) {
        .SUCCESS => return rc,
        .AGAIN => return error.WouldBlock,
        .BADF => unreachable,
        .INVAL => unreachable,
        .NOMEM => return error.SystemResources,
        .SPIPE => unreachable,
        else => |err| return unexpectedErrno(err),
    }
}
