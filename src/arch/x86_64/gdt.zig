// GDT entry structure for x86_64
const GDTEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

// GDT pointer structure for x86_64
const GDTPointer = packed struct {
    limit: u16,
    base: u64, // Base address is 64-bit in x86_64
};

// Number of entries in our GDT (usually fewer needed in 64-bit flat model)
const GDT_ENTRIES: usize = 3; // Null, Kernel Code, Kernel Data

// Our GDT array
var gdt: [GDT_ENTRIES]GDTEntry = undefined;
var gdt_ptr: GDTPointer = undefined;

// Function to set a GDT entry
pub fn gdt_set_gate(idx: usize, base: u64, limit: u32, access: u8, gran: u8) void {
    // In 64-bit flat model, base and limit are usually 0 and 0xFFFFFFFF.
    // The base and limit fields of the descriptor are largely ignored by the CPU
    // for code and data segments in 64-bit mode.
    // We set them here for completeness, but they don't control memory access
    // in the same way as in 32-bit mode.

    gdt[idx].base_low = @truncate(base & 0xFFFF);
    gdt[idx].base_middle = @truncate((base >> 16) & 0xFF);
    gdt[idx].base_high = @truncate((base >> 24) & 0xFF); // Still 8 bits here for the legacy part

    gdt[idx].limit_low = @truncate(limit & 0xFFFF);
    gdt[idx].granularity = @truncate(((limit >> 16) & 0x0F) | (gran & 0xF0));

    gdt[idx].access = access;

    // For 64-bit mode, a long mode code segment descriptor (Type field 0b10xx)
    // has the `Long Mode` bit (L-bit) set in the granularity byte.
    // This is typically done by setting the granularity byte to 0xAF (4KB granularity, Long Mode).
    // For data segments in 64-bit mode, the D/B bit (bit 14 of the granularity byte)
    // should be 0 for a 32-bit operand size and 1 for a 16-bit operand size.
    // However, in 64-bit mode, data segments are typically treated as 32-bit operand size
    // by default when the Long Mode bit is set in the code segment.
    // We'll use 0xAF for code and 0xCF for data (4KB granularity, 32-bit operand size assumed).
}

// Initialize the GDT
pub fn gdt_init() void {
    // Set up GDT pointer
    gdt_ptr.limit = @sizeOf(@TypeOf(gdt)) - 1;
    // Use @intFromPtr to get the 64-bit address of the GDT
    gdt_ptr.base = @intFromPtr(&gdt);

    // Null descriptor (always required at index 0)
    gdt_set_gate(0, 0, 0, 0, 0);

    // Kernel Code segment: base=0, limit=4GB (ignored), ring 0, executable, readable, Long Mode
    // Access: 0x9A (Present, DPL 0, Executable, Readable)
    // Granularity: 0xAF (4KB granularity, Long Mode)
    gdt_set_gate(1, 0, 0xFFFFFFFF, 0x9A, 0xAF);

    // Kernel Data segment: base=0, limit=4GB (ignored), ring 0, writable
    // Access: 0x92 (Present, DPL 0, Writable)
    // Granularity: 0xCF (4KB granularity, 32-bit operand size)
    gdt_set_gate(2, 0, 0xFFFFFFFF, 0x92, 0xCF);

    // In a typical 64-bit kernel, you might not need separate user mode segments in the GDT
    // if you are using a flat memory model and relying on paging for user/kernel separation
    // and protection. However, you might still define them if you plan to use segment
    // registers for specific purposes (e.g., FS/GS for thread-local storage).
    // If you do define them, the access flags and granularity would change for Ring 3.
    // For a basic flat model kernel, these two segments (Kernel Code and Kernel Data) are often sufficient.

    // Load the GDT
    load_gdt();
}

pub fn load_gdt() void {
    asm volatile (
        \\lgdt (%[ptr])
        \\mov $0x10, %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\mov %%ax, %%ss
        \\pushq $0x08
        \\leaq .reload_cs(%%rip), %%rax
        \\pushq %%rax
        \\lretq
        \\.reload_cs:
        :
        : [ptr] "r" (&gdt_ptr),
        : "memory", "rax"
    );
}
