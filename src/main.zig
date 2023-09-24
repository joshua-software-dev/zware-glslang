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

fn fd_fdstat_set_flags(vm: *zware.VirtualMachine) zware.WasmError!void
{
    _ = vm.popOperand(i32);
    _ = vm.popOperand(i32);
    try vm.pushOperand(u64, 0);
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
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_filestat_get", zware.wasi.fd_filestat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_prestat_dir_name", zware.wasi.fd_prestat_dir_name, &[_]zware.ValType{ .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_prestat_get", zware.wasi.fd_prestat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_read", zware.wasi.fd_read, &[_]zware.ValType{ .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_seek", zware.wasi.fd_seek, &[_]zware.ValType{ .I32, .I64, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "fd_write", zware.wasi.fd_write, &[_]zware.ValType{ .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "path_open", zware.wasi.path_open, &[_]zware.ValType{ .I32, .I32, .I32, .I32, .I32, .I64, .I64, .I32, .I32 }, &[_]zware.ValType{.I32});
    try store.exposeHostFunction("wasi_snapshot_preview1", "proc_exit", zware.wasi.proc_exit, &[_]zware.ValType{.I32}, &[_]zware.ValType{});
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
    try instance.invoke("_start", in[0..], out[0..], .{ .operand_stack_size = 1024 * 4 });
}
