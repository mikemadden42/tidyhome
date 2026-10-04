const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

const usage =
    \\Usage: tidyhome [options] <source_dir> [dest_base]
    \\
    \\Move files in <source_dir> into <dest_base>/<extension>/.
    \\<dest_base> defaults to "Documents" (relative to the current directory).
    \\
    \\Options:
    \\  -n, --dry-run  Show what would be moved without changing anything
    \\  -h, --help     Show this help and exit
    \\
;

const Options = struct {
    source_dir: []const u8,
    dest_base: []const u8 = "Documents",
    dry_run: bool = false,
};

const ParseResult = union(enum) {
    run: Options,
    help,
    err: []const u8,
};

fn parseArgs(args: []const []const u8) ParseResult {
    var positional: [2][]const u8 = undefined;
    var n_positional: usize = 0;
    var dry_run = false;
    var options_done = false;

    for (args) |arg| {
        if (!options_done and arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--")) {
                options_done = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                return .help;
            } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--dry-run")) {
                dry_run = true;
            } else {
                return .{ .err = "unknown option" };
            }
            continue;
        }
        if (n_positional == positional.len) return .{ .err = "too many arguments" };
        positional[n_positional] = arg;
        n_positional += 1;
    }

    if (n_positional == 0) return .{ .err = "missing source directory" };

    var opts: Options = .{ .source_dir = positional[0], .dry_run = dry_run };
    if (n_positional > 1) opts.dest_base = positional[1];
    return .{ .run = opts };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var stdout_buf: [0x200]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    const args = try init.minimal.args.toSlice(allocator);

    const opts = switch (parseArgs(args[1..])) {
        .run => |opts| opts,
        .help => {
            try stdout.writeAll(usage);
            try stdout.flush();
            return;
        },
        .err => |msg| {
            var stderr_buf: [0x200]u8 = undefined;
            var stderr_writer = Io.File.stderr().writer(io, &stderr_buf);
            const stderr = &stderr_writer.interface;
            try stderr.print("error: {s}\n\n{s}", .{ msg, usage });
            try stderr.flush();
            std.process.exit(2);
        },
    };

    var dir = try Dir.cwd().openDir(io, opts.source_dir, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file or entry.name[0] == '.') continue;

        const ext = std.fs.path.extension(entry.name);
        if (ext.len <= 1) continue;

        const ext_name = ext[1..];

        const dest_dir = try std.fs.path.join(allocator, &.{ opts.dest_base, ext_name });
        const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, entry.name });
        const src_path = try std.fs.path.join(allocator, &.{ opts.source_dir, entry.name });

        if (Dir.cwd().access(io, dest_path, .{})) {
            try stdout.print("File {s} already exists in {s}\n", .{ entry.name, dest_dir });
            continue;
        } else |err| {
            if (err != error.FileNotFound) return err;
            if (opts.dry_run) {
                try stdout.print("Would move {s} to {s}\n", .{ entry.name, dest_dir });
                continue;
            }
            try Dir.cwd().createDirPath(io, dest_dir);
            try Dir.rename(Dir.cwd(), src_path, Dir.cwd(), dest_path, io);
            try stdout.print("Moved {s} to {s}\n", .{ entry.name, dest_dir });
        }
    }
    try stdout.flush();
}

test "parseArgs requires a source directory" {
    try std.testing.expectEqualStrings("missing source directory", parseArgs(&.{}).err);
    try std.testing.expectEqualStrings("missing source directory", parseArgs(&.{"-n"}).err);
}

test "parseArgs positional arguments" {
    const one = parseArgs(&.{"src"}).run;
    try std.testing.expectEqualStrings("src", one.source_dir);
    try std.testing.expectEqualStrings("Documents", one.dest_base);
    try std.testing.expect(!one.dry_run);

    const two = parseArgs(&.{ "src", "dst" }).run;
    try std.testing.expectEqualStrings("dst", two.dest_base);

    try std.testing.expectEqualStrings("too many arguments", parseArgs(&.{ "a", "b", "c" }).err);
}

test "parseArgs options" {
    try std.testing.expect(parseArgs(&.{"--help"}) == .help);
    try std.testing.expect(parseArgs(&.{ "src", "-h" }) == .help);
    try std.testing.expect(parseArgs(&.{ "--dry-run", "src" }).run.dry_run);
    try std.testing.expect(parseArgs(&.{ "src", "-n" }).run.dry_run);
    try std.testing.expectEqualStrings("unknown option", parseArgs(&.{ "--bogus", "src" }).err);
    try std.testing.expectEqualStrings("-n", parseArgs(&.{ "--", "-n" }).run.source_dir);
    try std.testing.expectEqualStrings("-", parseArgs(&.{"-"}).run.source_dir);
}
