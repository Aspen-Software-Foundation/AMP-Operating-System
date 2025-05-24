const gdt = @import("./arch/x86_64/gdt.zig");
const idt = @import("./arch/x86_64/idt.zig");
const fs = @import("fs");
const console = @import("console");
const builtin = @import("builtin");
const limine = @import("limine");
const hcf = @import("hcf").hcf;

export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};

// Foreground:
const BLACK = "30m";
const RED = "31m";
const GREEN = "32m";
const YELLOW = "33m";
const BLUE = "34m";
const MAGENTA = "35m";
const CYAN = "36m";
const WHITE = "37m";
const BRIGHT_WHITE = "97m";

// Background:
const BLACK_BG = "40m";
const RED_BG = "41m";
const GREEN_BG = "42m";
const YELLOW_BG = "43m";
const BLUE_BG = "44m";
const MAGENTA_BG = "45m";
const CYAN_BG = "46m";
const WHITE_BG = "47m";
const BRIGHT_BLACK_BG = "100m";
const BRIGHT_RED_BG = "101m";
const BRIGHT_GREEN_BG = "102m";
const BRIGHT_YELLOW_BG = "103m";
const BRIGHT_BLUE_BG = "104m";
const BRIGHT_MAGENTA_BG = "105m";
const BRIGHT_CYAN_BG = "106m";
const BRIGHT_WHITE_BG = "107m";

// Reset:
const CSI = "\x1b[";
const RESET = "\x1b[0m";

pub fn kmain() callconv(.C) void {
    console.initialize(framebuffer_request.response.?.getFramebuffers()[0]);
    console.puts("Welcome to the Aspen Multi-Platform Operating System!\n");
    console.printf("Made with love, from {s}{s}Aspen{s}.\n\n", .{ CSI, RED, RESET });

    // Initialize GDT
    gdt.gdt_init();
    console.printf("{s}{s}[ INFO ]{s} GDT initialized.\n", .{ CSI, CYAN, RESET });

    // Initialize IDT
    idt.initIDT();
    console.printf("{s}{s}[ INFO ]{s} IDT initialized.\n", .{ CSI, CYAN, RESET });

    // Initialize PIC (CRITICAL: Must be done before enabling interrupts!)
    idt.initPIC();
    console.printf("{s}{s}[ INFO ]{s} PIC initialized and remapped.\n", .{ CSI, CYAN, RESET });

    // Enable interrupts (do this after GDT, IDT, and PIC are set up)
    idt.enableInterrupts();
    console.printf("{s}{s}[ INFO ]{s} Interrupts enabled.\n", .{ CSI, CYAN, RESET });

    // Test if interrupts are working
    if (idt.interruptsEnabled()) {
        console.printf("{s}{s}[ SUCCESS ]{s} Interrupt system is active.\n", .{ CSI, GREEN, RESET });
    } else {
        console.printf("{s}{s}[ WARNING ]{s} Interrupts may not be working.\n", .{ CSI, YELLOW, RESET });
    }

    // Initialize filesystem
    fs.fs_init() catch |err| {
        console.printf("{s}{s}[ ERROR ]{s} Filesystem initialization failed: {s}\n", .{ CSI, RED, RESET, @errorName(err) });
        hcf();
    };
    console.printf("{s}{s}[ INFO ]{s} Filesystem initialized.\n", .{ CSI, CYAN, RESET });

    // Create some test directories
    console.printf("{s}{s}[ INFO ]{s} Creating test directories...\n", .{ CSI, CYAN, RESET });
    const paths_to_create = [_][]const u8{
        "/user",
        "/home",
        "/home/Documents",
        "/home/Downloads",
        "/home/Pictures",
        "/home/Videos",
        "/home/Music",
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
            console.printf("{s}{s}[ ERROR ]{s} Failed to create directory '{s}': {s}\n", .{ CSI, RED, RESET, path_to_create, @errorName(err) });
            // We could halt here, or just print the error and continue
        }
    }

    console.printf("{s}{s}[ INFO ]{s} Test directory creation complete.\n", .{ CSI, CYAN, RESET });

    // Print the filesystem tree
    fs.print_fs_tree();

    console.printf("\n{s}{s}[ INFO ]{s} System initialization complete. Entering idle loop...\n", .{ CSI, CYAN, RESET });

    // Instead of immediately halting, let's loop for a bit to see if interrupts work
    var counter: u32 = 0;
    while (counter < 1000000000) {
        counter += 1;
        // Small delay to prevent overwhelming the system
        if (counter % 100000000 == 0) {
            console.printf("{s}{s}[ DEBUG ]{s} Heartbeat: {d}\n", .{ CSI, MAGENTA, RESET, counter / 100000000});
        }
    }
    console.printf("{s}{s}[ WARNING ]{s} Shutting down system... \n", .{ CSI, YELLOW, RESET});
    hcf(); // Halt the system after the loop completes

}
