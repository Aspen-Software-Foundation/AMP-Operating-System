const std = @import("std");
const fmt = @import("std").fmt;
const limine = @import("limine");

// --- Font Data and Structures ---
const default_font_bytes = @embedFile("font.psf"); // ADJUST PATH AS NEEDED

const Psf1Magic = enum(u16) {
    MAGIC0 = 0x36,
    MAGIC1 = 0x04,
};

const Psf1Header = extern struct {
    magic: [2]u8,
    mode: u8,
    char_size: u8, // Height of the character in scanlines
};

// --- Framebuffer and Font Globals ---
var fb_addr: usize = 0;
var fb_width: usize = 0; // pixels
var fb_height: usize = 0; // pixels
var fb_pitch: usize = 0; // bytes per row
var fb_bpp: u16 = 0; // bytes per pixel

var font_header: *const Psf1Header = undefined;
var font_glyph_data: []const u8 = undefined;
var char_width: u8 = 8; // PSF1 characters are always 8 pixels wide
var char_height: u8 = 0; // Will be read from font

var text_cols: usize = 0; // Number of character columns on screen
var text_rows: usize = 0; // Number of character rows on screen

// --- Console State ---
var cursor_row: usize = 0;
var cursor_col: usize = 0;
var fg_color: u32 = 0xFF_FF_FF_FF; // White (ARGB)
var bg_color: u32 = 0xFF_00_00_00; // Black (ARGB, alpha FF for opaque)

// --- Helper: Draw a single pixel ---
fn drawPixel(x: usize, y: usize, color: u32) void {
    if (x >= fb_width or y >= fb_height) {
        return; // Out of bounds
    }

    // We'll assume 32bpp (4 bytes per pixel) for simplicity.
    // A robust implementation would handle different BPP values from fb_bpp.
    if (fb_bpp == 4) {
        const fb_ptr_u32: [*]volatile u32 = @ptrCast(@as(*align(4) u8, @ptrFromInt(fb_addr)));
        fb_ptr_u32[(y * (fb_pitch / @sizeOf(u32))) + x] = color;
    } else {
        // Fallback or error for other BPPs. For now, we do nothing.
        // You could print an error once to a serial port if available, or panic.
    }
}

// --- Initialization ---
pub fn initialize(framebuffer: *limine.Framebuffer) void {
    fb_addr = @intFromPtr(framebuffer.address);
    fb_width = framebuffer.width;
    fb_height = framebuffer.height;
    fb_pitch = framebuffer.pitch;
    fb_bpp = framebuffer.bpp / 8; // Convert bits to bytes

    // Basic check for 32bpp, which our drawPixel currently assumes
    if (fb_bpp != 4) {
        // Handle this case: either support other BPPs or indicate an issue.
        // For now, we'll proceed, but drawing might be incorrect.
        // A panic("Unsupported BPP") might be appropriate in a real kernel.
    }

    // Parse Font
    if (default_font_bytes.len < @sizeOf(Psf1Header)) {
        panic("Font file too small for header");
    }
    font_header = @ptrCast(default_font_bytes.ptr);

    if (font_header.magic[0] != @intFromEnum(Psf1Magic.MAGIC0) or
        font_header.magic[1] != @intFromEnum(Psf1Magic.MAGIC1))
    {
        panic("Invalid PSF1 magic number");
    }

    char_height = font_header.char_size;
    if (char_height == 0) panic("Font char_size is zero");

    const header_size = @sizeOf(Psf1Header);
    font_glyph_data = default_font_bytes[header_size..];

    // Calculate text grid dimensions
    text_cols = fb_width / char_width;
    text_rows = fb_height / char_height;

    clear();
}

// --- Clear Screen ---
pub fn clear() void {
    for (0..fb_height) |y| {
        for (0..fb_width) |x| {
            drawPixel(x, y, bg_color);
        }
    }
    cursor_row = 0;
    cursor_col = 0;
}

// --- Scroll Screen ---
fn scrollOneLine() void {
    if (text_rows == 0) return;

    const line_height_pixels = char_height;
    const bytes_per_pixel_row = fb_pitch;
    const scroll_amount_bytes = line_height_pixels * bytes_per_pixel_row;

    // Number of pixel rows to keep
    const rows_to_keep = fb_height - line_height_pixels;
    if (rows_to_keep == 0) { // Cannot scroll if screen is too small
        clear();
        return;
    }

    const src_ptr: [*]u8 = @ptrFromInt(fb_addr + scroll_amount_bytes);
    const dst_ptr: [*]u8 = @ptrFromInt(fb_addr);
    const len_bytes = rows_to_keep * bytes_per_pixel_row;

    @memcpy(dst_ptr[0..len_bytes], src_ptr[0..len_bytes]);

    // Clear the last text line
    const last_line_start_y = (text_rows - 1) * line_height_pixels;
    for (0..line_height_pixels) |y_offset| {
        for (0..fb_width) |x_pixel| {
            drawPixel(x_pixel, last_line_start_y + y_offset, bg_color);
        }
    }

    if (cursor_row > 0) {
        cursor_row -= 1;
    }
}

// --- Put Character ---
pub fn putChar(c: u8) void {
    if (char_height == 0) return; // Font not initialized

    if (c == '\n') {
        cursor_col = 0;
        cursor_row += 1;
    } else if (c == '\r') {
        cursor_col = 0;
    } else if (c == '\t') {
        // Advance to next tab stop (e.g., every 8 columns)
        const tab_size = 8;
        cursor_col = (cursor_col + tab_size) & ~(@as(usize, tab_size - 1));
    } else if (c == 8) { // Backspace
        if (cursor_col > 0) {
            cursor_col -= 1;
        } else if (cursor_row > 0) {
            cursor_row -= 1;
            cursor_col = text_cols - 1; // Move to end of previous line
        } else {
            return; // At 0,0, nothing to backspace
        }

        // Erase the character at the new cursor position
        const screen_x_base = cursor_col * char_width;
        const screen_y_base = cursor_row * char_height;
        var y_offset: usize = 0;
        while (y_offset < char_height) : (y_offset += 1) {
            var x_offset: usize = 0; // CORRECTED: Reset x_offset for each row
            while (x_offset < char_width) : (x_offset += 1) {
                drawPixel(screen_x_base + x_offset, screen_y_base + y_offset, bg_color);
            }
        }
    } else if (c >= 32 and c <= 126) { // Printable ASCII
        if (cursor_col >= text_cols) { // Line wrap
            cursor_col = 0;
            cursor_row += 1;
        }
        // Scroll if needed *before* drawing, so we draw on a valid line
        if (cursor_row >= text_rows) {
            scrollOneLine();
            // cursor_row is now text_rows - 1 after scrollOneLine adjusts it
        }

        const screen_x_base = cursor_col * char_width;
        const screen_y_base = cursor_row * char_height;

        const glyph_index = c; // c is u8
        const glyph_offset_in_font = @as(usize, glyph_index) * @as(usize, char_height);

        if (glyph_offset_in_font + @as(usize, char_height) > font_glyph_data.len) {
            // Character not in font or font data too small, draw a placeholder (e.g., '?') or skip
            // For now, let's try to draw a space or a default char if we had one
            // Or simply advance cursor
            // To prevent infinite loop if '?' also causes issues, just advance
            // This part could be improved by drawing a specific "unknown char" glyph
            // For now, draw background for the cell
            var y_fill: usize = 0;
            while (y_fill < char_height) : (y_fill += 1) {
                var x_fill: usize = 0;
                while (x_fill < char_width) : (x_fill += 1) {
                    drawPixel(screen_x_base + x_fill, screen_y_base + y_fill, bg_color);
                }
            }
            cursor_col += 1;
            return;
        }

        const glyph = font_glyph_data[glyph_offset_in_font .. glyph_offset_in_font + @as(usize, char_height)];

        var y_char: usize = 0;
        while (y_char < @as(usize, char_height)) : (y_char += 1) {
            const row_byte: u8 = glyph[y_char];

            var x_char: usize = 0;
            while (x_char < @as(usize, char_width)) : (x_char += 1) {
                // 1) Bring x_char into u8 so we can do 7 - x8:
                const x8: u8 = @intCast(x_char);

                // 2) Compute shift amount (0..7) as a 3‐bit integer:
                const shift_amount: u3 = @intCast(@as(u8, 7) - x8);

                // 3) Shift row_byte right by that 3‐bit amount, mask LSB:
                const bit_set: bool = ((row_byte >> shift_amount) & 1) != 0;

                // 4) Choose color:
                const col: u32 = if (bit_set) fg_color else bg_color;

                // 5) Plot the pixel:
                drawPixel(screen_x_base + x_char, screen_y_base + y_char, col);
            }
        }
        cursor_col += 1;
    }
    // Else: character is non-printable and not handled, ignore.

    // Final check for scrolling if a newline or character wrap pushed us over
    // This check might be redundant if handled before drawing, but good for safety.
    if (cursor_row >= text_rows) {
        scrollOneLine();
    }
}

// --- Puts and Printf (no changes needed) ---
pub fn puts(data: []const u8) void {
    for (data) |c|
        putChar(c);
}

pub const writer = std.io.Writer(void, error{}, callback){ .context = {} };
fn callback(_: void, string: []const u8) error{}!usize {
    puts(string);
    return string.len;
}
pub fn printf(comptime format: []const u8, args: anytype) void {
    fmt.format(writer, format, args) catch unreachable;
}

fn panic(msg: []const u8) noreturn {
    // A very simple panic: try to print to console, then halt.
    // This assumes putChar/puts is somewhat functional.
    puts("\nKERNEL PANIC: ");
    puts(msg);
    puts("\n");
    while (true) {
        asm volatile ("cli; hlt");
    }
}
