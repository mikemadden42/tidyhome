const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var stdout_buf: [0x200]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    const args = try init.minimal.args.toSlice(allocator);

    const source_dir = if (args.len > 1) args[1] else ".";
    const dest_base = if (args.len > 2) args[2] else "Documents";

    var dir = try Dir.cwd().openDir(io, source_dir, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file or entry.name[0] == '.') continue;

        const ext = std.fs.path.extension(entry.name);
        if (ext.len <= 1) continue;

        const ext_name = ext[1..];

        const dest_dir = try std.fs.path.join(allocator, &.{ dest_base, ext_name });
        try Dir.cwd().createDirPath(io, dest_dir);

        const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, entry.name });
        const src_path = try std.fs.path.join(allocator, &.{ source_dir, entry.name });

        if (Dir.cwd().access(io, dest_path, .{})) {
            try stdout.print("File {s} already exists in {s}\n", .{ entry.name, dest_dir });
            continue;
        } else |err| {
            if (err != error.FileNotFound) return err;
            try Dir.rename(Dir.cwd(), src_path, Dir.cwd(), dest_path, io);
            try stdout.print("Moved {s} to {s}\n", .{ entry.name, dest_dir });
        }
    }
    try stdout.flush();
}
