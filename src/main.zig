const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const print = std.debug.print;

const MoveConfig = struct {
    source_dir: []const u8 = ".",
    dest_base_dir: []const u8 = "Documents",
    ignore_extensions: []const []const u8 = &.{"9"},
    verbose: bool = true,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = MoveConfig{};
    try clean(allocator, config);
}

fn clean(allocator: std.mem.Allocator, config: MoveConfig) !void {
    var current_dir = try fs.cwd().openDir(config.source_dir, .{ .iterate = true });
    defer current_dir.close();

    var iter = current_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!shouldMoveFile(entry.name, config)) continue;

        try moveFile(allocator, entry.name, config);
    }
}

fn shouldMoveFile(file_name: []const u8, config: MoveConfig) bool {
    if (file_name[0] == '.') return false;
    const ext = fs.path.extension(file_name);
    if (ext.len == 0) return false;

    for (config.ignore_extensions) |ignore_ext| {
        if (mem.eql(u8, ext[1..], ignore_ext)) return false;
    }
    return true;
}

fn moveFile(allocator: std.mem.Allocator, file_name: []const u8, config: MoveConfig) !void {
    const ext = fs.path.extension(file_name);
    const ext_no_dot = if (ext[0] == '.') ext[1..] else ext;

    const dest_dir = try fs.path.join(allocator, &.{ config.dest_base_dir, ext_no_dot });
    defer allocator.free(dest_dir);

    try fs.cwd().makePath(dest_dir);

    const dest_path = try fs.path.join(allocator, &.{ dest_dir, file_name });
    defer allocator.free(dest_path);

    if (fs.cwd().access(dest_path, .{})) {
        if (config.verbose) {
            print("File {s} already exists in {s}\n", .{ file_name, dest_dir });
        }
    } else |_| {
        try fs.cwd().rename(file_name, dest_path);
        if (config.verbose) {
            print("Moved {s} to {s}\n", .{ file_name, dest_dir });
        }
    }
}
