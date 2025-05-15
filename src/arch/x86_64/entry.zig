const main = @import("main");
const kmain = main.kmain;

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ lea %[stack_base_addr], %%rax
        \\ addq %[stack_size_val], %%rax
        \\ movq %%rax, %%rsp
        \\ xorq %%rbp, %%rbp
        \\ call %[kmain:P]
        :
        : [stack_base_addr] "m" (stack_bytes),
          [stack_size_val] "i" (@sizeOf(@TypeOf(stack_bytes))),
          [kmain] "X" (&kmain),
        : "rax", "rsp", "rbp", "memory", "cc"
    );
}
