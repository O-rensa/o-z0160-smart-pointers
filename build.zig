const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const smart_ptr_module = b.addModule("o_z0160_smart_pointers", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "unique-ptr",
        .root_module = smart_ptr_module,
    });

    b.installArtifact(lib);

    const smart_ptr_test = b.addTest(.{
        .root_module = smart_ptr_module,
    });

    const run_smart_ptr_test = b.addRunArtifact(smart_ptr_test);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_smart_ptr_test.step);
}
