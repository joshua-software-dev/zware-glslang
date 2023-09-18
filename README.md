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
