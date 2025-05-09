const gdt = @import("./arch/x86_64/gdt.zig");
const console = @import("./console.zig");
const fs = @import("./fs.zig");

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const MultibootHeader = packed struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,
    padding: u32 = 0,
};

export var multiboot: MultibootHeader align(4) linksection(".multiboot") = .{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

// We specify that this function is "naked" to let the compiler know
// not to generate a standard function prologue and epilogue, since
// we don't have a stack yet.
export fn _start() callconv(.Naked) noreturn {
    // We use inline assembly to set up the stack before jumping to
    // our kernel main.
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ call %[kmain:P]
        :
        // The stack grows downwards on x86, so we need to point ESP
        // to one element past the end of `stack_bytes`.
        //
        // Unfortunately, we can't just compute `&stack_bytes[stack_bytes.len]`,
        // as the Zig compiler will notice the out-of-bounds access
        // at compile-time and throw an error.
        //
        // We can instead take the start address of `stack_bytes` and
        // add the size of the array to get the one-past-the-end
        // pointer. However, Zig disallows pointer arithmetic on all
        // pointer types except "multi-pointers" `[*]`, so we must cast
        // to that type first.
        //
        // Finally, we pass the whole expression as an input operand
        // with the "immediate" constraint to force the compiler to
        // encode this as an absolute address. This prevents the
        // compiler from doing unnecessary extra steps to compute
        // the address at runtime (especially in Debug mode), which
        // could possibly clobber registers that are specified by
        // multiboot to hold special values (e.g. EAX).
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          // We let the compiler handle the reference to kmain by passing it as an input operand as well.
          [kmain] "X" (&kmain),
    );
}

fn kmain() callconv(.C) void {
    console.initialize();

    console.puts("Welcome to the Aspen Multi-Platform Operating System!\n");

    gdt.gdt_init();
    console.puts("[ INFO ]   GDT initialized.\n");

    // Initialize filesystem
    fs.fs_init() catch |err| {
        console.printf("[ ERR ]   Filesystem initialization failed: {s}\n", .{@errorName(err)});
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
            console.printf("[ ERR ]   Failed to create directory '{s}': {s}\n", .{ path_to_create, @errorName(err) });
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
