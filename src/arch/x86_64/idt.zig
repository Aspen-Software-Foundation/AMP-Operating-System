const std = @import("std");

// IDT Entry structure for x86-64
const IDTEntry = packed struct {
    offset_low: u16,
    selector: u16,
    ist: u8,
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    reserved: u32,
};

// IDT Descriptor structure
const IDTDescriptor = packed struct {
    limit: u16,
    base: u64,
};

// IDT with 256 entries
var idt: [256]IDTEntry = [_]IDTEntry{std.mem.zeroes(IDTEntry)} ** 256;

// Set an IDT entry
fn set_idt_gate(vector: u8, handler_addr: u64, selector: u16, flags: u8) void {
    idt[vector].offset_low = @truncate(handler_addr & 0xFFFF);
    idt[vector].selector = selector;
    idt[vector].ist = 0;
    idt[vector].type_attr = flags;
    idt[vector].offset_mid = @truncate((handler_addr >> 16) & 0xFFFF);
    idt[vector].offset_high = @truncate((handler_addr >> 32) & 0xFFFFFFFF);
    idt[vector].reserved = 0;
}

// Simple interrupt handlers
fn default_interrupt_handler() align(16) callconv(.Naked) void {
    asm volatile (
        \\push %rax
        \\mov $0x20, %al
        \\out %al, $0x20
        \\pop %rax
        \\iretq
        ::: "memory");
}

fn timer_interrupt_handler() align(16) callconv(.Naked) void {
    asm volatile (
        \\push %rax
        \\push %rcx
        \\push %rdx
        \\
        \\# Send EOI to master PIC
        \\mov $0x20, %al
        \\out %al, $0x20
        \\
        \\pop %rdx
        \\pop %rcx
        \\pop %rax
        \\iretq
        ::: "memory");
}

fn keyboard_interrupt_handler() align(16) callconv(.Naked) void {
    asm volatile (
        \\push %rax
        \\
        \\# Read from keyboard port
        \\in $0x60, %al
        \\
        \\# Send EOI to master PIC
        \\mov $0x20, %al
        \\out %al, $0x20
        \\
        \\pop %rax
        \\iretq
        ::: "memory");
}

// Exception handlers
fn divide_error_handler() align(16) callconv(.Naked) void {
    asm volatile (
        \\cli
        \\hlt
        ::: "memory");
}

fn page_fault_handler() align(16) callconv(.Naked) void {
    asm volatile (
        \\cli
        \\hlt
        ::: "memory");
}

fn general_protection_fault_handler() align(16) callconv(.Naked) void {
    asm volatile (
        \\cli
        \\hlt
        ::: "memory");
}

// Initialize IDT
pub fn initIDT() void {
    const CODE_SEGMENT: u16 = 0x08;
    const INTERRUPT_GATE: u8 = 0x8E; // Present, Ring 0, 32-bit Interrupt Gate
    const TRAP_GATE: u8 = 0x8F; // Present, Ring 0, 32-bit Trap Gate

    // Clear IDT
    for (&idt) |*entry| {
        entry.* = std.mem.zeroes(IDTEntry);
    }

    // Set up exception handlers
    set_idt_gate(0, @intFromPtr(&divide_error_handler), CODE_SEGMENT, TRAP_GATE);
    set_idt_gate(13, @intFromPtr(&general_protection_fault_handler), CODE_SEGMENT, TRAP_GATE);
    set_idt_gate(14, @intFromPtr(&page_fault_handler), CODE_SEGMENT, TRAP_GATE);

    // Set up IRQ handlers (assuming PIC remapped to 32-47)
    set_idt_gate(32, @intFromPtr(&timer_interrupt_handler), CODE_SEGMENT, INTERRUPT_GATE); // Timer
    set_idt_gate(33, @intFromPtr(&keyboard_interrupt_handler), CODE_SEGMENT, INTERRUPT_GATE); // Keyboard

    // Set default handler for all other interrupts
    var i: u16 = 0;
    while (i < 256) : (i += 1) {
        if (idt[i].type_attr == 0) { // If not already set
            set_idt_gate(@truncate(i), @intFromPtr(&default_interrupt_handler), CODE_SEGMENT, INTERRUPT_GATE);
        }
    }

    // Load IDT
    const idt_descriptor = IDTDescriptor{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };

    asm volatile ("lidt (%[idt_ptr])"
        :
        : [idt_ptr] "r" (&idt_descriptor),
        : "memory"
    );
}

// Enable interrupts
pub fn enableInterrupts() void {
    asm volatile ("sti");
}

// Disable interrupts
pub fn disableInterrupts() void {
    asm volatile ("cli");
}

// Check if interrupts are enabled
pub fn interruptsEnabled() bool {
    var flags: u64 = undefined;
    asm volatile ("pushfq; popq %[flags]"
        : [flags] "=r" (flags),
        :
        : "memory"
    );
    return (flags & 0x200) != 0;
}

// PIC initialization (you'll need this before enabling interrupts)
pub fn initPIC() void {
    // Remap PIC to use interrupts 32-47 instead of 0-15

    // Save masks
    const mask1 = inb(0x21);
    const mask2 = inb(0xA1);

    // Start initialization sequence
    outb(0x20, 0x11); // ICW1: Initialize master PIC
    outb(0xA0, 0x11); // ICW1: Initialize slave PIC

    // ICW2: Vector offsets
    outb(0x21, 0x20); // Master PIC: IRQ 0-7 -> INT 32-39
    outb(0xA1, 0x28); // Slave PIC: IRQ 8-15 -> INT 40-47

    // ICW3: Tell master about slave
    outb(0x21, 0x04); // Master: slave on IRQ2
    outb(0xA1, 0x02); // Slave: cascade identity

    // ICW4: 8086 mode
    outb(0x21, 0x01);
    outb(0xA1, 0x01);

    // Restore masks
    outb(0x21, mask1);
    outb(0xA1, mask2);
}

// I/O port functions
inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}
