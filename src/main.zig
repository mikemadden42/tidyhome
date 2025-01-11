const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try clean(allocator);
}

fn clean(allocator: std.mem.Allocator) !void {
    var current_dir = try fs.cwd().openDir(".", .{ .iterate = true });
    defer current_dir.close();

    var iter = current_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        const file_name = entry.name;
        if (file_name[0] == '.') continue; // Skip dotfiles

        const ext = fs.path.extension(file_name);
        if (ext.len > 0 and !mem.eql(u8, ext, "9")) {
            // Remove the leading dot from the extension
            const ext_no_dot = if (ext[0] == '.') ext[1..] else ext;

            const dest_dir = try fs.path.join(allocator, &.{ "Documents", ext_no_dot });
            defer allocator.free(dest_dir);

            try fs.cwd().makePath(dest_dir);

            const dest_path = try fs.path.join(allocator, &.{ dest_dir, file_name });
            defer allocator.free(dest_path);

            if (fs.cwd().access(dest_path, .{})) {
                print("File {s} already exists in {s}\n", .{ file_name, dest_dir });
            } else |_| {
                try fs.cwd().rename(file_name, dest_path);
                print("Moved {s} to {s}\n", .{ file_name, dest_dir });
            }
        }
    }
}
