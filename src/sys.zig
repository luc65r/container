const std = @import("std");
const os = std.os;
const linux = os.linux;

const errno = linux.getErrno;
const pid_t = linux.pid_t;
const fd_t = linux.fd_t;
const off_t = linux.off_t;
const rusage = linux.rusage;
const itimerspec = linux.itimerspec;
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

pub fn splice(fd_in: fd_t, off_in: ?*off_t, fd_out: fd_t, off_out: ?*off_t, len: usize, flags: u32) SpliceError!usize {
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

pub const Wait4Error = error{
    WouldBlock,
    NoChild,
} || UnexpectedError;

pub const Wait4Result = struct {
    pid: pid_t,
    status: u32,
    rusage: rusage,
};

pub fn wait4(pid: pid_t, flags: u32) Wait4Error!Wait4Result {
    var status: u32 = undefined;
    var usage: rusage = undefined;
    while (true) {
        const rc = linux.syscall4(.wait4, @bitCast(usize, @as(isize, pid)), @ptrToInt(&status), flags, @ptrToInt(&usage));
        switch (errno(rc)) {
            .SUCCESS => return Wait4Result{
                .pid = @intCast(pid_t, rc),
                .status = status,
                .rusage = usage,
            },
            .INTR => continue,
            .AGAIN => return error.WouldBlock,
            .CHILD => return error.NoChild,
            .FAULT => unreachable,
            .INVAL => unreachable,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const MountError = error{
    AccessDenied,
    FileBusy,
    MountLoop,
    SystemResources,
    NameTooLong,
    NoDevice,
    FileNotFound,
    NotBlock,
    NotDir,
    PermissionDenied,
    ReadOnly,
} || UnexpectedError;

pub fn mount(source: ?[*:0]const u8, target: ?[*:0]const u8, fstype: ?[*:0]const u8, flags: u32, data: ?*anyopaque) MountError!void {
    const rc = linux.syscall5(.mount, @ptrToInt(source), @ptrToInt(target), @ptrToInt(fstype), flags, @ptrToInt(data));
    switch (errno(rc)) {
        .SUCCESS => return,
        .ACCES => return error.AccessDenied,
        .BUSY => return error.FileBusy,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .LOOP => return error.MountLoop,
        .MFILE => return error.SystemResources,
        .NAMETOOLONG => return error.NameTooLong,
        .NODEV => return error.NoDevice,
        .NOENT => return error.FileNotFound,
        .NOMEM => return error.SystemResources,
        .NOTBLK => return error.NotBlock,
        .NOTDIR => return error.NotDir,
        .NXIO => unreachable,
        .PERM => return error.PermissionDenied,
        .ROFS => return error.ReadOnly,
        else => |err| return unexpectedErrno(err),
    }
}

const UmountError = error{
    Marked,
    FileBusy,
    NameTooLong,
    FileNotFound,
    SystemResources,
    PermissionDenied,
} || UnexpectedError;

pub fn umount2(target: ?[*:0]const u8, flags: u32) UmountError!void {
    const rc = linux.syscall2(.umount2, @ptrToInt(target), flags);
    switch (errno(rc)) {
        .SUCCESS => return,
        .AGAIN => return error.Marked,
        .BUSY => return error.FileBusy,
        .INVAL => unreachable,
        .NAMETOOLONG => return error.NameTooLong,
        .NOENT => return error.FileNotFound,
        .NOMEM => return error.SystemResources,
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

pub const PivotRootError = error{
    DeviceBusy,
    NotDir,
    PermissionDenied,
} || UnexpectedError;

pub fn pivot_root(new_root: [*:0]const u8, put_old: [*:0]const u8) PivotRootError!void {
    const rc = linux.syscall2(.pivot_root, @ptrToInt(new_root), @ptrToInt(put_old));
    switch (errno(rc)) {
        .SUCCESS => return,
        .BUSY => return error.DeviceBusy,
        .INVAL => unreachable,
        .NOTDIR => return error.NotDir,
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

pub const TimerfdCreateError = error{
    SystemResources,
    PermissionDenied,
} || UnexpectedError;

pub fn timerfd_create(clockid: i32, flags: u32) TimerfdCreateError!fd_t {
    const rc = linux.timerfd_create(clockid, flags);
    switch (errno(rc)) {
        .SUCCESS => return @intCast(fd_t, rc),
        .INVAL => unreachable,
        .MFILE => return error.SystemResources,
        .NODEV => return error.SystemResources,
        .NOMEM => return error.SystemResources,
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

pub const TimerfdSetError = error{
    Canceled,
} || UnexpectedError;

pub fn timerfd_settime(fd: fd_t, flags: u32, new_value: *const itimerspec, old_value: ?*itimerspec) TimerfdSetError!void {
    const rc = linux.timerfd_settime(fd, flags, new_value, old_value);
    switch (errno(rc)) {
        .SUCCESS => return,
        .BADF => unreachable,
        .CANCELED => return error.Canceled,
        .FAULT => unreachable,
        .INVAL => unreachable,
        else => |err| return unexpectedErrno(err),
    }
}
