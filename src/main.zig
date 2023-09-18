const std = @import("std");

const zware = @import("zware");


fn environ_get(vm: *zware.VirtualMachine) zware.WasmError!void
{
    _ = vm.popOperand(u32);
    _ = vm.popOperand(u32);
    try vm.pushOperand(u64, 0);
}

fn environ_sizes_get(vm: *zware.VirtualMachine) zware.WasmError!void
{
    _ = vm.popOperand(u32);
    _ = vm.popOperand(u32);
    try vm.pushOperand(u64, 0);
}

fn toWasiError(err: anyerror) std.os.wasi.errno_t
{
    return switch (err) {
        error.AccessDenied => .ACCES,
        error.DiskQuota => .DQUOT,
        error.InputOutput => .IO,
        error.FileTooBig => .FBIG,
        error.NoSpaceLeft => .NOSPC,
        error.BrokenPipe => .PIPE,
        error.NotOpenForWriting => .BADF,
        error.SystemResources => .NOMEM,
        error.FileNotFound => .NOENT,
        error.PathAlreadyExists => .EXIST,
        error.IsDir => .ISDIR,
        else => std.debug.panic("WASI: Unhandled zig stdlib error: {s}", .{@errorName(err)}),
    };
}

fn toWasiFileType(kind: std.fs.File.Kind) std.os.wasi.filetype_t
{
    return switch (kind) {
        .block_device => .BLOCK_DEVICE,
        .character_device => .CHARACTER_DEVICE,
        .directory => .DIRECTORY,
        .sym_link => .SYMBOLIC_LINK,
        .file => .REGULAR_FILE,
        .unknown => .UNKNOWN,

        .named_pipe,
        .unix_domain_socket,
        .whiteout,
        .door,
        .event_port,
        => .UNKNOWN,
    };
}

fn fd_filestat_get(vm: *zware.VirtualMachine) zware.WasmError!void
{
    const stat_ptr = vm.popOperand(u32);
    const fd = vm.popOperand(i32);

    const memory = try vm.inst.getMemory(0);

    const host_fd = vm.getHostFd(fd);
    const file = std.fs.File{ .handle = host_fd };
    const stat = file.stat() catch |err|
    {
        try vm.pushOperand(u64, @intFromEnum(toWasiError(err)));
        return;
    };

    try memory.write(u64, stat_ptr, 0, 0); // device id
    try memory.write(u64, stat_ptr, 8, stat.inode); // inode
    try memory.write(u64, stat_ptr, 16, @intFromEnum(toWasiFileType(stat.kind))); // filetype
    try memory.write(u64, stat_ptr, 24, 1); // nlink - hard links refering to this file count
    try memory.write(u64, stat_ptr, 32, stat.size); // size in bytes
    try memory.write(u64, stat_ptr, 40, @as(u64, @intCast(stat.atime))); // atime - last access time
    try memory.write(u64, stat_ptr, 48, @as(u64, @intCast(stat.mtime))); // mtime - last modified time
    try memory.write(u64, stat_ptr, 56, @as(u64, @intCast(stat.ctime))); // ctime - last status change time

    try vm.pushOperand(u64, @intFromEnum(std.os.wasi.errno_t.SUCCESS));
}

fn fd_fdstat_set_flags(vm: *zware.VirtualMachine) zware.WasmError!void
{
    _ = vm.popOperand(i32);
    _ = vm.popOperand(i32);
    try vm.pushOperand(u64, 0);
}

fn proc_exit(vm: *zware.VirtualMachine) zware.WasmError!void
{
    const param0 = vm.popOperand(i32);
    const code: u32 = std.math.absCast(param0);
    std.os.exit(@truncate(code));
}

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const glslang = try std.compress.zstd.decompress.decodeAlloc
    (
        gpa.allocator(),
        @embedFile("glslang.wasm.zst"),
        true,
        std.math.maxInt(usize),
    );
    defer alloc.free(glslang);

    var store = zware.Store.init(alloc);
    defer store.deinit();

    var module = zware.Module.init(alloc, glslang);
    defer module.deinit();
    try module.decode();

    try store.exposeHostFunction("wasi_snapshot_preview1", "args_get", zware.wasi.args_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "args_sizes_get", zware.wasi.args_sizes_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "clock_time_get", zware.wasi.clock_time_get, &[_]zware.ValType{ .I32, .I64, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "environ_get", environ_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "environ_sizes_get", environ_sizes_get, &[_]zware.ValType{ .I32, .I32, }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_close", zware.wasi.fd_close, &[_]zware.ValType{.I32}, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_fdstat_get", zware.wasi.fd_fdstat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_fdstat_set_flags", fd_fdstat_set_flags, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_filestat_get", fd_filestat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_prestat_dir_name", zware.wasi.fd_prestat_dir_name, &[_]zware.ValType{ .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_prestat_get", zware.wasi.fd_prestat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_read", zware.wasi.fd_read, &[_]zware.ValType{ .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_seek", zware.wasi.fd_seek, &[_]zware.ValType{ .I32, .I64, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_write", zware.wasi.fd_write, &[_]zware.ValType{ .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "path_open", zware.wasi.path_open, &[_]zware.ValType{ .I32, .I32, .I32, .I32, .I32, .I64, .I64, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "proc_exit", proc_exit, &[_]zware.ValType{.I32}, &[_]zware.ValType{});
    try store.exposeHostFunction("wasi_snapshot_preview1", "random_get", zware.wasi.random_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});

    var instance = zware.Instance.init(alloc, &store, module);
    try instance.instantiate();
    defer instance.deinit();

    const cwd = try std.fs.cwd().openDir("./", .{});

    try instance.addWasiPreopen(0, "stdin", std.os.STDIN_FILENO);
    try instance.addWasiPreopen(1, "stdout", std.os.STDOUT_FILENO);
    try instance.addWasiPreopen(2, "stderr", std.os.STDERR_FILENO);
    try instance.addWasiPreopen(3, "./", cwd.fd);

    const args = try instance.forwardArgs(alloc);
    defer std.process.argsFree(alloc, args);

    var in = [_]u64{};
    var out = [_]u64{};
    try instance.invoke("_start", in[0..], out[0..], .{});
}
