# zware-glslang
A zig library to run a wasm32-wasi binary build of glslang in a build step

```zig
const zglslang_dep = b.dependency("zware_glslang", .{ .target = target, .optimize = optimize });
const zware_glslang = zglslang_dep.artifact("zware_glslang");

const lib = b.addSharedLibrary(.{
    .name = "vulkan_layer_lurk",
    .root_source_file = .{ .path = "src/main.zig" },
    .target = target,
    .optimize = optimize,
});

const frag_shader_compile = b.addRunArtifact(zware_glslang);
// Due to wasi limitations, paths must be relative to the $CWD used to
// execute the program. If you want to compile a file anywhere in your zig
// project folder, it should be fine, but be aware of the limitation.
frag_shader_compile.addArgs(&[_][]const u8{
    "--quiet",
    "-V",
    "-o",
    "zig-cache/frag.spv",
    "src/frag.glsl",
});

lib.step.dependOn(&frag_shader_compile.step);
```

Note: The above snippet does not implement caching by the build system. You'll either need to configure your `build.zig` to do so, or check manually if you can skip generating when not needed should you not want the compile to run on every build.

```zig
// an example of providing a shader input from an absolute path
const absolute_input = "example/absolute/path/to/shader.vert.glsl";
const build_rel_output = "build/path/to/shader.vert.spv";
const absolute_output = b.pathFromRoot(build_rel_output);

var found_vert_output = true;
std.fs.accessAbsolute(absolute_output, .{}) catch {
    found_vert_output = false;
};

if (!found_vert_output) {
    const file =
        std.fs.openFileAbsolute(absolute_input, .{}) catch @panic("Failed to read fragment shader");
    const file_bytes = file.readToEndAlloc(b.allocator, 4096) catch @panic("oom");
    defer b.allocator.free(file_bytes);

    const vert_shader_compile = b.addRunArtifact(zware_glslang);
    var new_stdio = std.ArrayList(std.Build.Step.Run.StdIo.Check)
        .initCapacity(b.allocator, 1) catch @panic("oom");
    new_stdio.appendAssumeCapacity(.{ .expect_term = .{ .Exited = 0 } });

    vert_shader_compile.setStdIn(.{ .bytes = b.allocator.dupe(u8, file_bytes) catch @panic("oom") });
    vert_shader_compile.stdio = .{ .check = new_stdio };
    vert_shader_compile.addArgs(&[_][]const u8{
        "--quiet",
        "--stdin",
        "-V",
        "-S", // glslang requires manually specifying shader type when provided
        "vert", // from stdin, in this case its a vertex shader, so "vert" it is
        "-o",
        build_rel_output, // this path must still be build $CWD relative
    });

    lib.step.dependOn(&vert_shader_compile.step);
}
```
