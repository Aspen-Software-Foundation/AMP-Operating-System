// linker.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;

/// One entry in PHDRS { … } block.
pub const ProgramHeader = struct {
    name: []const u8,
    type: []const u8, // e.g. "PT_LOAD"
    flags: ?[]const u8 = null, // e.g. "FLAGS (READ|EXECUTE)"
    filehdr: bool = false,
    phdrs_attr: bool = false, // if we want "PHDRS" on this entry

    pub fn format(self: ProgramHeader, w: anytype) !void {
        try w.print("    {s} {s}", .{ self.name, self.type });
        if (self.filehdr) try w.print(" FILEHDR", .{});
        if (self.phdrs_attr) try w.print(" PHDRS", .{});
        if (self.flags) |f| try w.print(" {s}", .{f});
        try w.print(";\n", .{});
    }
};

/// One “definition” in SECTIONS { … }.
pub const SectionDef = struct {
    /// If null + patterns/keep ⇒ /DISCARD/
    name: ?[]const u8 = null,
    /// “. = expr;”
    loc: ?[]const u8 = null,
    /// “. = ALIGN(expr);” (only if loc == null)
    align_expr: ?[]const u8 = null,
    /// &[_][]const u8{"text","data"}
    phdrs: ?[]const []const u8 = null,
    /// &[_][]const u8{"*(.text .text.*)"}
    patterns: ?[]const []const u8 = null,
    /// &[_][]const u8{"*(.limine_requests)"}
    keep: ?[]const []const u8 = null,
    /// Optional region (>FLASH, etc.)
    region: ?[]const u8 = null,
    /// Optional fill (=0xFF, etc.)
    fill: ?[]const u8 = null,

    pub fn render(self: SectionDef, w: anytype, indent: []const u8) !void {
        // 1) location counter or ALIGN
        if (self.loc) |e| {
            try w.print("{s}. = {s};\n", .{ indent, e });
        } else if (self.align_expr) |e| {
            try w.print("{s}. = ALIGN({s});\n", .{ indent, e });
        }

        // 2) the section itself
        if (self.name != null or self.patterns != null or self.keep != null) {
            const sec_name = self.name orelse "/DISCARD/";

            // Header line: “.sec_name :”
            try w.print("{s}{s} :\n", .{ indent, sec_name });

            // Open brace
            try w.print("{s}{{\n", .{indent});

            // Inner indent = indent + 4 spaces
            const inner = try std.fmt.allocPrint(
                std.heap.page_allocator,
                "{s}    ",
                .{indent},
            );
            defer std.heap.page_allocator.free(inner);

            // Patterns
            if (self.patterns) |ps| {
                for (ps) |p| {
                    try w.print("{s}{s}\n", .{ inner, p });
                }
            }
            // KEEP(…)
            if (self.keep) |ks| {
                for (ks) |k| {
                    try w.print("{s}KEEP({s})\n", .{ inner, k });
                }
            }

            // Close brace
            try w.print("{s}}}", .{indent});

            // PHDRS after the block
            if (self.phdrs) |list| {
                if (list.len > 0) {
                    try w.print(" :", .{});
                    for (list, 0..) |h, i| {
                        try w.print("{s}{s}", .{ if (i == 0) " " else " ", h });
                    }
                }
            }
            try w.print("\n\n", .{});
        }
    }
};

/// Top‐level linker‐script description.
pub const ScriptDef = struct {
    output_format: ?[]const u8 = null,
    entry_symbol: ?[]const u8 = null,
    phdrs: []const ProgramHeader = &.{},
    sections: []const SectionDef = &.{},
    raw_prepend: ?[]const u8 = null,
    raw_append: ?[]const u8 = null,
};

/// Render `def` into a .ld in the build‐cache and call
/// `artifact.setLinkerScriptPath(...)`.
pub fn generateAndSetScript(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    script_name: []const u8,
    comptime def: ScriptDef,
) !void {
    var buf = std.ArrayList(u8).init(b.allocator);
    defer buf.deinit();
    const w = buf.writer();

    if (def.raw_prepend) |r| {
        try w.print("{s}\n", .{r});
    }
    if (def.output_format) |fmt| {
        try w.print("OUTPUT_FORMAT({s})\n\n", .{fmt});
    }
    if (def.entry_symbol) |e| {
        try w.print("ENTRY({s})\n\n", .{e});
    }

    if (def.phdrs.len > 0) {
        try w.print("PHDRS\n{{\n", .{});
        for (def.phdrs) |ph| try ph.format(w);
        try w.print("}}\n\n", .{});
    }

    if (def.sections.len > 0) {
        try w.print("SECTIONS\n{{\n", .{});
        const indent = "    ";
        for (def.sections) |sd| try sd.render(w, indent);
        try w.print("}}\n", .{});
    }

    if (def.raw_append) |r| {
        try w.print("\n{s}\n", .{r});
    }

    const script_path = try fs.path.join(b.allocator, &[_][]const u8{ b.cache_root.path.?, script_name });
    defer b.allocator.free(script_path);

    const file = try fs.cwd().createFile(script_path, .{});
    defer file.close();
    try file.writer().writeAll(buf.items);

    artifact.setLinkerScript(.{ .cwd_relative = script_path });
}
