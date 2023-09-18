const std = @import("std");

// Parts of the following are adapted from software with the following license

// MIT License

// Copyright (c) 2023 Cascade Operating System

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

fn downloadWithHttpClient(allocator: std.mem.Allocator, url: []const u8, writer: anytype) !void
{
    const uri = try std.Uri.parse(url);

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var headers = std.http.Headers{ .allocator = allocator };
    defer headers.deinit();

    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    try req.start();
    try req.wait();

    if (req.response.status != .ok) return error.ResponseNotOk;

    var buffer: [4096]u8 = undefined;

    while (true)
    {
        const number_read = try req.reader().read(&buffer);
        if (number_read == 0) break;
        try writer.writeAll(buffer[0..number_read]);
    }
}

fn fetch(step: *std.Build.Step, url: []const u8, destination_path: []const u8) !void
{
    const file = try std.fs.cwd().createFile(destination_path, .{});
    defer file.close();

    var buffered_writer = std.io.bufferedWriter(file.writer());

    downloadWithHttpClient(step.owner.allocator, url, buffered_writer.writer()) catch |err|
    {
        return step.fail("failed to fetch '{s}': {s}", .{ url, @errorName(err) });
    };

    try buffered_writer.flush();
}

pub fn download_file(self: *std.build.Step, progress: *std.Progress.Node) !void
{
    _ = progress;
    const file_path = @as([]const u8, self.owner.pathFromRoot("src/glslang.wasm.zst"));

    var file_exists = true;
    std.fs.accessAbsolute(file_path, .{}) catch { file_exists = false; };
    if (!file_exists)
    {
        try fetch
        (
            self,
            "https://github.com/joshua-software-dev/glslang/releases/download/13.0.0/glslang_opt_wasisdk.wasm.zst",
            file_path
        );
    }
}
