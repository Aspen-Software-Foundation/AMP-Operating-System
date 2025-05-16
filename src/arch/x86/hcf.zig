pub fn hcf() void {
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}
