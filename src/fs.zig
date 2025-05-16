const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const console = @import("console"); // For printing the tree

// For now, we'll use a FixedBufferAllocator for simplicity.
// In a real OS, memory management would be much more complex.
// Define a static buffer for our filesystem's memory.
// This means our filesystem will have a fixed maximum size.
// Let's allocate 64KB for now.
var fs_memory_buffer: [1024 * 64]u8 = undefined;
var fixed_buffer_allocator_state = std.heap.FixedBufferAllocator.init(&fs_memory_buffer);
const allocator = fixed_buffer_allocator_state.allocator();

pub const FsError = error{
    NotFound,
    AlreadyExists,
    IsDirectory, // Expected file, found directory
    IsFile, // Expected directory, found file (e.g. in path traversal "foo/bar" where foo is a file)
    InvalidPath,
    OutOfMemory,
    NotADirectory, // Specific error for when an operation requires a directory (e.g. parent for creation) but finds a file.
};

pub const Inode = union(enum) {
    file: *File,
    directory: *Directory,
};

pub const File = struct {
    name: []const u8,
    data: ArrayList(u8),
    // TODO: Add permissions, timestamps, etc.

    pub fn init(name: []const u8) !*File {
        const self = try allocator.create(File);
        self.* = .{
            .name = try allocator.dupe(u8, name),
            .data = ArrayList(u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *File) void {
        allocator.free(self.name);
        self.data.deinit();
        allocator.destroy(self);
    }
};

pub const Directory = struct {
    name: []const u8,
    children: StringHashMap(Inode), // Map filename to Inode
    // TODO: Add permissions, timestamps, etc.

    pub fn init(name: []const u8) !*Directory {
        const self = try allocator.create(Directory);
        self.* = .{
            .name = try allocator.dupe(u8, name),
            .children = StringHashMap(Inode).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Directory) void {
        // Recursively deinit children
        var it = self.children.valueIterator();
        while (it.next()) |inode_ptr| {
            switch (inode_ptr.*) {
                .file => |f| f.deinit(),
                .directory => |d| d.deinit(),
            }
        }
        self.children.deinit();
        allocator.free(self.name);
        allocator.destroy(self);
    }
};

var root_directory: ?*Directory = null;

pub fn fs_init() !void {
    root_directory = try Directory.init("/");
    // TODO: Potentially populate with some initial files/directories like /dev, /tmp etc.
}

// Helper function to navigate to a node, not yet implemented
// fn navigate(path: []const u8) !Inode { ... }

// More functions to come:
// pub fn create_file(path: []const u8, name: []const u8) !*File { ... }
// pub fn read_file(path: []const u8) ![]const u8 { ... }
// pub fn write_file(path: []const u8, data: []const u8) !void { ... }
// pub fn list_directory(path: []const u8) ![]const []const u8 { ... }

fn print_node_recursive(node: Inode, indent_level: usize) void {
    // Print indentation
    for (0..indent_level) |_| {
        console.puts("  ");
    }

    switch (node) {
        .file => |f| {
            console.printf("- {s} (file)\n", .{f.name});
        },
        .directory => |d| {
            // Print directory name. Root directory name is "/", others are relative.
            if (d == root_directory) {
                console.puts("/ (directory)\n");
            } else {
                console.printf("+ {s} (directory)\n", .{d.name});
            }

            // Recursively print children
            // To ensure a consistent order for printing, we'd ideally sort keys.
            // For simplicity now, we iterate as the hash map provides.
            var it = d.children.iterator();
            while (it.next()) |entry| {
                // entry is a KeyValue struct with .key_ptr and .value_ptr
                print_node_recursive(entry.value_ptr.*, indent_level + 1);
            }
        },
    }
}

pub fn print_fs_tree() void {
    if (root_directory == null) {
        console.puts("[ ERROR ]   Filesystem not initialized.\n");
        return;
    }
    console.puts("[ RESULT ]   Filesystem Tree:\n");
    print_node_recursive(Inode{ .directory = root_directory.? }, 0);
}

pub fn get_root_dir() *Directory {
    return root_directory;
}

// find_node: Navigates the filesystem to find an Inode (file or directory) at the given absolute path.
pub fn find_node(full_path: []const u8) !Inode {
    if (full_path.len == 0 or full_path[0] != '/') {
        return FsError.InvalidPath; // Path must be absolute
    }
    if (std.mem.eql(u8, full_path, "/")) {
        return Inode{ .directory = root_directory.? };
    }

    var current_node: Inode = .{ .directory = root_directory.? };
    var it = std.mem.splitScalar(u8, full_path, '/');

    // The first part from splitScalar for an absolute path like "/foo/bar" is an empty slice.
    // We can skip it explicitly or let the loop's `part.len == 0` check handle it.
    // Let's ensure it's explicitly consumed if it's the token before first '/':
    _ = it.next(); // Consumes the part before the first '/', which is "" for absolute paths.

    while (it.next()) |part| {
        if (part.len == 0) { // Handles consecutive slashes like "/foo//bar" or a trailing slash "/foo/"
            continue;
        }

        const current_dir = switch (current_node) {
            .directory => |d| d,
            // If a component in the path (not the final one) is a file, it's an error.
            .file => return FsError.IsFile,
        };

        current_node = current_dir.children.get(part) orelse return FsError.NotFound;
    }
    return current_node;
}

// create_directory: Creates a new directory at the given absolute path.
// Example: create_directory("/usr/local")
pub fn create_directory(full_path_str: []const u8) !*Directory {
    if (full_path_str.len == 0 or full_path_str[0] != '/') {
        return FsError.InvalidPath; // Must be an absolute path
    }
    if (std.mem.eql(u8, full_path_str, "/")) {
        return FsError.AlreadyExists; // Root directory already exists
    }

    // Determine parent path and new directory name
    // e.g., for "/foo/bar", parent_path_slice is "/foo", new_dir_name_slice is "bar"
    // e.g., for "/baz", parent_path_slice is "/", new_dir_name_slice is "baz"
    const last_slash_idx = std.mem.lastIndexOfScalar(u8, full_path_str, '/') orelse {
        // This should not happen if path starts with '/' and is not just '/'
        return FsError.InvalidPath;
    };

    const new_dir_name_slice = full_path_str[last_slash_idx + 1 ..];
    if (new_dir_name_slice.len == 0) {
        return FsError.InvalidPath; // Path ends with a slash, e.g., "/foo/"
    }

    const parent_path_slice = if (last_slash_idx == 0)
        "/" // Parent is root directory
    else
        full_path_str[0..last_slash_idx];

    const parent_node = try find_node(parent_path_slice);

    const parent_dir = switch (parent_node) {
        .directory => |d| d,
        .file => return FsError.NotADirectory, // Parent path exists but is a file
    };

    if (parent_dir.children.contains(new_dir_name_slice)) {
        return FsError.AlreadyExists;
    }

    // Create the new directory. Directory.init makes an owned copy of the name.
    var new_dir = try Directory.init(new_dir_name_slice);
    errdefer new_dir.deinit(); // If the .put operation fails, ensure this new_dir is cleaned up.

    // Add the new directory to the parent's children map.
    // The StringHashMap will make its own owned copy of the key (new_dir.name).
    try parent_dir.children.put(new_dir.name, Inode{ .directory = new_dir });

    return new_dir;
}

// Basic test
test "initialize filesystem and create root" {
    try fs_init();
    defer if (root_directory != undefined) root_directory.deinit();

    try std.testing.expectEqualStrings("/", root_directory.name);
    try std.testing.expectEqual(@as(usize, 0), root_directory.children.count());
}

test "create and find directory" {
    try fs_init();
    defer if (root_directory != undefined) root_directory.deinit();

    const new_dir_path = "/test_dir";
    const new_dir = try create_directory(new_dir_path);
    try std.testing.expectEqualStrings("test_dir", new_dir.name);

    const found_node = try find_node(new_dir_path);
    const found_dir = switch (found_node) {
        .directory => |d| d,
        .file => unreachable, // Should be a directory
    };
    try std.testing.expect(new_dir == found_dir); // Check if it's the same object
    try std.testing.expectEqualStrings("test_dir", found_dir.name);

    // Check parent
    const parent_node = try find_node("/");
    const parent_dir = switch (parent_node) {
        .directory => |d| d,
        .file => unreachable,
    };
    try std.testing.expect(parent_dir.children.contains("test_dir"));
}

test "create nested directory" {
    try fs_init();
    defer if (root_directory != undefined) root_directory.deinit();

    _ = try create_directory("/parent");
    const nested_dir = try create_directory("/parent/nested");
    try std.testing.expectEqualStrings("nested", nested_dir.name);

    const found_node = try find_node("/parent/nested");
    const found_dir = switch (found_node) {
        .directory => |d| d,
        .file => unreachable,
    };
    try std.testing.expect(nested_dir == found_dir);

    // Check parent
    const parent_node = try find_node("/parent");
    const parent_dir = switch (parent_node) {
        .directory => |d| d,
        .file => unreachable,
    };
    try std.testing.expect(parent_dir.children.contains("nested"));
    const child_inode = parent_dir.children.get("nested").?;
    const child_dir = switch (child_inode) {
        .directory => |d| d,
        .file => unreachable,
    };
    try std.testing.expect(child_dir == nested_dir);
}

test "create directory error cases" {
    try fs_init();
    defer if (root_directory != undefined) root_directory.deinit();

    // Invalid path (not absolute)
    try std.testing.expectError(FsError.InvalidPath, create_directory("nodir"));
    // Invalid path (ends with /)
    try std.testing.expectError(FsError.InvalidPath, create_directory("/foo/"));
    // Root already exists
    try std.testing.expectError(FsError.AlreadyExists, create_directory("/"));

    // Parent does not exist
    try std.testing.expectError(FsError.NotFound, create_directory("/nonexistent_parent/foo"));

    // Directory already exists
    _ = try create_directory("/existing_dir");
    try std.testing.expectError(FsError.AlreadyExists, create_directory("/existing_dir"));

    // TODO: Test FsError.NotADirectory if we had file creation first.
    // e.g. create_file("/file.txt"), then try create_directory("/file.txt/oops")
}
