// build.zig
const std = @import("std");
const linker = @import("./linker.zig");

fn add_module(
    b: *std.Build,
    targ: *std.Build.Step.Compile,
    import_name: []const u8,
    module_name: []const u8,
    path: []const u8,
) void {
    targ.root_module.addImport(
        import_name,
        b.addModule(module_name, .{ .root_source_file = b.path(path) }),
    );
}

pub fn build(b: *std.Build) !void {
    const limine_zig = b.dependency("limine_zig", .{
        .api_revision = 3,
        .allow_deprecated = false,
        .no_pointers = false,
    });
    const limine_mod = limine_zig.module("limine");

    var disabled = std.Target.Cpu.Feature.Set.empty;
    var enabled = std.Target.Cpu.Feature.Set.empty;
    disabled.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    enabled.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const topts = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arch = topts.result.cpu.arch;
    const arch_enum = switch (arch) {
        .x86 => std.Target.Cpu.Arch.x86,
        .x86_64 => std.Target.Cpu.Arch.x86_64,
        else => unreachable,
    };
    const tq = std.Target.Query{
        .cpu_arch = arch_enum,
        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
        .cpu_features_sub = disabled,
        .cpu_features_add = enabled,
    };

    const hcf = b.addModule("hcf", .{
        .root_source_file = b.path(switch (arch) {
            .x86 => "src/arch/x86/hcf.zig",
            .x86_64 => "src/arch/x86_64/hcf.zig",
            else => unreachable,
        }),
    });

    const entry_path = b.path("src/boot/limine.zig");

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = entry_path,
            .target = b.resolveTargetQuery(tq),
            .optimize = optimize,
            .code_model = .kernel,
            .imports = &.{.{ .name = "hcf", .module = hcf }},
        }),
    });

    const gdt = b.addModule("gdt", .{
        .root_source_file = b.path(switch (arch) {
            .x86 => "src/arch/x86/gdt.zig",
            .x86_64 => "src/arch/x86_64/gdt.zig",
            else => unreachable,
        }),
    });

    const font = b.addModule("font", .{
        .root_source_file = b.path("PSF-Fonts/default8x16.psf"),
    });

    const console = b.addModule("console", .{
        .root_source_file = b.path("src/console.zig"),
        .imports = &.{
            .{ .name = "limine", .module = limine_mod },
            .{ .name = "font", .module = font },
        },
    });

    const fs = b.addModule("fs", .{
        .root_source_file = b.path("src/fs.zig"),
        .imports = &.{.{ .name = "console", .module = console }},
    });

    const main = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "limine", .module = limine_mod },
            .{ .name = "console", .module = console },
            .{ .name = "fs", .module = fs },
            .{ .name = "hcf", .module = hcf },
            .{ .name = "gdt", .module = gdt },
        },
    });

    kernel.root_module.addImport("main", main);
    kernel.root_module.addImport("limine", limine_mod);

    const LD = linker.ScriptDef{
        .output_format = "elf64-x86-64",
        .entry_symbol = "_start",
        .phdrs = &[_]linker.ProgramHeader{
            .{ .name = "limine_requests", .type = "PT_LOAD" },
            .{ .name = "text", .type = "PT_LOAD" },
            .{ .name = "rodata", .type = "PT_LOAD" },
            .{ .name = "data", .type = "PT_LOAD" },
        },
        .sections = &[_]linker.SectionDef{
            .{ .loc = "0xffffffff80000000" },
            .{
                .name = ".limine_requests",
                .phdrs = &[_][]const u8{"limine_requests"},
                .keep = &[_][]const u8{
                    "*(.limine_requests_start)",
                    "*(.limine_requests)",
                    "*(.limine_requests_end)",
                },
            },
            .{ .align_expr = "CONSTANT(MAXPAGESIZE)" },
            .{
                .name = ".text",
                .phdrs = &[_][]const u8{"text"},
                .patterns = &[_][]const u8{"*(.text .text.*)"},
            },
            .{ .align_expr = "CONSTANT(MAXPAGESIZE)" },
            .{
                .name = ".rodata",
                .phdrs = &[_][]const u8{"rodata"},
                .patterns = &[_][]const u8{"*(.rodata .rodata.*)"},
            },
            .{ .align_expr = "CONSTANT(MAXPAGESIZE)" },
            .{
                .name = ".data",
                .phdrs = &[_][]const u8{"data"},
                .patterns = &[_][]const u8{"*(.data .data.*)"},
            },
            .{
                .name = ".bss",
                .phdrs = &[_][]const u8{"data"},
                .patterns = &[_][]const u8{
                    "*(.bss .bss.*)",
                    "*(COMMON)",
                },
            },
            .{
                .name = null,
                .patterns = &[_][]const u8{
                    "*(.eh_frame*)",
                    "*(.note .note.*)",
                },
            },
        },
    };

    try linker.generateAndSetScript(b, kernel, "kernel-x86_64.ld", LD);

    b.installArtifact(kernel);
    const ks = b.step("kernel", "Build the kernel");
    ks.dependOn(&kernel.step);
}
