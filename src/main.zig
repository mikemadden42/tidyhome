const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const source_dir = if (args.len > 1) args[1] else ".";
    const dest_base = if (args.len > 2) args[2] else "Documents";

    var dir = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file or entry.name[0] == '.') continue;

        const ext = std.fs.path.extension(entry.name);
        if (ext.len <= 1) continue;

        const ext_name = ext[1..];

        // Create destination directory
        const dest_dir = try std.fs.path.join(allocator, &.{ dest_base, ext_name });
        defer allocator.free(dest_dir);

        try std.fs.cwd().makePath(dest_dir);

        // Create full destination path
        const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, entry.name });
        defer allocator.free(dest_path);

        // Check if file already exists at destination
        if (std.fs.cwd().access(dest_path, .{})) {
            print("File {s} already exists in {s}\n", .{ entry.name, dest_dir });
            continue; // Skip this file
        } else |_| {
            // File doesn't exist, safe to move
            try std.fs.cwd().rename(entry.name, dest_path);
            print("Moved {s} to {s}\n", .{ entry.name, dest_dir });
        }
    }
}
