const gdt = @import("./arch/x86_64/gdt.zig");
const fs = @import("./fs.zig");
const console = @import("./console.zig");
const builtin = @import("builtin");
const limine = @import("limine");

export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};

pub fn kmain() callconv(.C) void {
    console.initialize(framebuffer_request.response.?.getFramebuffers()[0]);

    console.puts("Welcome to the Aspen Multi-Platform Operating System!\n");
    console.puts("Made with love, from Aspen.\n\n");

    gdt.gdt_init();
    console.puts("[ INFO ]   GDT initialized.\n");

    // Initialize filesystem
    fs.fs_init() catch |err| {
        console.printf("[ ERROR ]   Filesystem initialization failed: {s}\n", .{@errorName(err)});
        halt();
    };
    console.puts("[ INFO ]   Filesystem initialized.\n");

    // Create some test directories
    console.puts("[ INFO ]   Creating test directories...\n");
    const paths_to_create = [_][]const u8{
        "/home",
        "/home/user",
        "/etc",
        "/var",
        "/var/log",
    };

    for (paths_to_create) |path_to_create| {
        if (fs.create_directory(path_to_create)) |created_dir_node| {
            // Successfully created the directory.
            // We can ignore the 'created_dir_node' if we don't need to use it immediately.
            _ = created_dir_node; // Suppress unused variable warning
            // console.printf("Successfully created directory: {s}\n", .{path_to_create}); // Optional success message
        } else |err| {
            console.printf("[ ERROR ]   Failed to create directory '{s}': {s}\n", .{ path_to_create, @errorName(err) });
            // We could halt here, or just print the error and continue
        }
    }
    console.puts("[ INFO ]   Test directory creation complete.\n");

    // Print the filesystem tree
    fs.print_fs_tree();

    halt();
}

fn halt() void {
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}
