const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 1. Set up the Arena Allocator
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit(); // This one line handles ALL cleanup at the end
    const allocator = arena.allocator();

    // Because the Arena catches everything, we don't even need
    // to manually free the arguments array anymore!
    const args = try std.process.argsAlloc(allocator);

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

        // 2. Build paths without manual defer frees!
        // The Arena will hold onto these strings until the program exits.
        const dest_dir = try std.fs.path.join(allocator, &.{ dest_base, ext_name });
        try std.fs.cwd().makePath(dest_dir);

        const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, entry.name });

        // 3. The Bug Fix: Build the full path to the source file
        const src_path = try std.fs.path.join(allocator, &.{ source_dir, entry.name });

        if (std.fs.cwd().access(dest_path, .{})) {
            print("File {s} already exists in {s}\n", .{ entry.name, dest_dir });
            continue;
        } else |_| {
            // Move the file using the full source path we just built
            try std.fs.cwd().rename(src_path, dest_path);
            print("Moved {s} to {s}\n", .{ entry.name, dest_dir });
        }
    }
}
