// GDT entry structure
const GDTEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

// GDT pointer structure
const GDTPointer = packed struct {
    limit: u16,
    base: u32,
};

// Number of entries in our GDT
const GDT_ENTRIES: usize = 5;

// Our GDT array
var gdt: [GDT_ENTRIES]GDTEntry = undefined;
var gdt_ptr: GDTPointer = undefined;

// Function to set a GDT entry
pub fn gdt_set_gate(idx: usize, base: u32, limit: u32, access: u8, gran: u8) void {
    gdt[idx].base_low = @truncate(base & 0xFFFF);
    gdt[idx].base_middle = @truncate((base >> 16) & 0xFF);
    gdt[idx].base_high = @truncate((base >> 24) & 0xFF);

    gdt[idx].limit_low = @truncate(limit & 0xFFFF);
    gdt[idx].granularity = @truncate(((limit >> 16) & 0x0F) | (gran & 0xF0));

    gdt[idx].access = access;
}

// Initialize the GDT
pub fn gdt_init() void {
    // Set up GDT pointer
    gdt_ptr.limit = @sizeOf(@TypeOf(gdt)) - 1;
    gdt_ptr.base = @intFromPtr(&gdt);

    // Null descriptor
    gdt_set_gate(0, 0, 0, 0, 0);

    // Code segment: base=0, limit=4GB, ring 0 (kernel), code segment, executable, readable
    gdt_set_gate(1, 0, 0xFFFFFFFF, 0x9A, 0xCF);

    // Data segment: base=0, limit=4GB, ring 0 (kernel), data segment, writable
    gdt_set_gate(2, 0, 0xFFFFFFFF, 0x92, 0xCF);

    // User mode code segment: base=0, limit=4GB, ring 3 (user), code segment, executable, readable
    gdt_set_gate(3, 0, 0xFFFFFFFF, 0xFA, 0xCF);

    // User mode data segment: base=0, limit=4GB, ring 3 (user), data segment, writable
    gdt_set_gate(4, 0, 0xFFFFFFFF, 0xF2, 0xCF);

    // Load the GDT
    load_gdt();
}

pub fn load_gdt() void {
    asm volatile (
        \\lgdt (%[ptr])
        \\movw $0x10, %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        \\movw %%ax, %%ss
        \\ljmp $0x08, $.reload_cs
        \\.reload_cs:
        :
        : [ptr] "r" (&gdt_ptr),
        : "memory", "eax"
    );
}
