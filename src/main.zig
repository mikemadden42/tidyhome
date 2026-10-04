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

    var stderr_buf: [0x200]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(allocator);

    const opts = switch (parseArgs(args[1..])) {
        .run => |opts| opts,
        .help => {
            try stdout.writeAll(usage);
            try stdout.flush();
            return;
        },
        .err => |msg| {
            try stderr.print("error: {s}\n\n{s}", .{ msg, usage });
            try stderr.flush();
            std.process.exit(2);
        },
    };

    const failed = try organize(io, allocator, Dir.cwd(), opts, stdout, stderr);
    if (failed > 0) {
        try stderr.print("error: {d} file(s) could not be moved\n", .{failed});
        try stderr.flush();
        std.process.exit(1);
    }
}

/// Moves each regular, non-hidden file with an extension in `opts.source_dir`
/// to `opts.dest_base/<extension>/`. Both paths are resolved relative to `base`.
/// A file that cannot be moved is reported to `err_out` and skipped; returns
/// the number of such files.
fn organize(io: Io, allocator: std.mem.Allocator, base: Dir, opts: Options, out: *Io.Writer, err_out: *Io.Writer) !usize {
    var dir = try base.openDir(io, opts.source_dir, .{ .iterate = true });
    defer dir.close(io);

    var failed: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file or entry.name[0] == '.') continue;

        const ext = std.fs.path.extension(entry.name);
        if (ext.len <= 1) continue;

        organizeFile(io, allocator, base, opts, entry.name, ext[1..], out) catch |err| switch (err) {
            error.OutOfMemory, error.WriteFailed, error.Canceled => |e| return e,
            else => |e| {
                try err_out.print("error: could not move {s}: {t}\n", .{ entry.name, e });
                try err_out.flush();
                failed += 1;
            },
        };
    }
    return failed;
}

fn organizeFile(
    io: Io,
    allocator: std.mem.Allocator,
    base: Dir,
    opts: Options,
    name: []const u8,
    ext_name: []const u8,
    out: *Io.Writer,
) !void {
    const dest_dir = try std.fs.path.join(allocator, &.{ opts.dest_base, ext_name });
    const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, name });
    const src_path = try std.fs.path.join(allocator, &.{ opts.source_dir, name });

    // Flush after every message so the log stays accurate if a later file
    // aborts the run.
    defer out.flush() catch {};

    if (base.access(io, dest_path, .{})) {
        try out.print("File {s} already exists in {s}\n", .{ name, dest_dir });
        return;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }
    if (opts.dry_run) {
        try out.print("Would move {s} to {s}\n", .{ name, dest_dir });
        return;
    }
    try base.createDirPath(io, dest_dir);
    try Dir.rename(base, src_path, base, dest_path, io);
    try out.print("Moved {s} to {s}\n", .{ name, dest_dir });
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

fn expectFileContents(dir: Dir, path: []const u8, expected: []const u8) !void {
    var buf: [64]u8 = undefined;
    const actual = try dir.readFile(std.testing.io, path, &buf);
    try std.testing.expectEqualStrings(expected, actual);
}

fn expectMissing(dir: Dir, path: []const u8) !void {
    try std.testing.expectError(error.FileNotFound, dir.access(std.testing.io, path, .{}));
}

/// Creates `src/` in `dir` populated with a mix of files that should and
/// should not be moved.
fn makeSourceTree(dir: Dir) !void {
    const io = std.testing.io;
    try dir.createDirPath(io, "src/subdir.d");
    try dir.writeFile(io, .{ .sub_path = "src/a.pdf", .data = "a" });
    try dir.writeFile(io, .{ .sub_path = "src/b.pdf", .data = "b" });
    try dir.writeFile(io, .{ .sub_path = "src/notes.txt", .data = "notes" });
    try dir.writeFile(io, .{ .sub_path = "src/archive.tar.gz", .data = "gz" });
    try dir.writeFile(io, .{ .sub_path = "src/.hidden.txt", .data = "hidden" });
    try dir.writeFile(io, .{ .sub_path = "src/noext", .data = "noext" });
    try dir.writeFile(io, .{ .sub_path = "src/trailingdot.", .data = "dot" });
}

test "organize moves files into extension directories" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try makeSourceTree(tmp.dir);

    var out_buf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err_out: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(0, try organize(std.testing.io, arena.allocator(), tmp.dir, .{ .source_dir = "src", .dest_base = "out" }, &out, &err_out));

    try expectFileContents(tmp.dir, "out/pdf/a.pdf", "a");
    try expectFileContents(tmp.dir, "out/pdf/b.pdf", "b");
    try expectFileContents(tmp.dir, "out/txt/notes.txt", "notes");
    try expectFileContents(tmp.dir, "out/gz/archive.tar.gz", "gz");
    try expectMissing(tmp.dir, "src/a.pdf");
    try expectMissing(tmp.dir, "src/notes.txt");

    // Hidden files, files without an extension, and directories stay put.
    try expectFileContents(tmp.dir, "src/.hidden.txt", "hidden");
    try expectFileContents(tmp.dir, "src/noext", "noext");
    try expectFileContents(tmp.dir, "src/trailingdot.", "dot");
    try tmp.dir.access(std.testing.io, "src/subdir.d", .{});
    try expectMissing(tmp.dir, "out/d");

    const output = out.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Moved notes.txt to out/txt\n") != null);
    try std.testing.expectEqual(4, std.mem.count(u8, output, "Moved "));
}

test "organize skips files that already exist at the destination" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.createDirPath(io, "out/txt");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/notes.txt", .data = "new" });
    try tmp.dir.writeFile(io, .{ .sub_path = "out/txt/notes.txt", .data = "old" });

    var out_buf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err_out: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(0, try organize(io, arena.allocator(), tmp.dir, .{ .source_dir = "src", .dest_base = "out" }, &out, &err_out));

    try expectFileContents(tmp.dir, "src/notes.txt", "new");
    try expectFileContents(tmp.dir, "out/txt/notes.txt", "old");
    try std.testing.expectEqualStrings("File notes.txt already exists in out/txt\n", out.buffered());
}

test "organize dry run leaves the filesystem untouched" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try makeSourceTree(tmp.dir);

    var out_buf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err_out: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(0, try organize(std.testing.io, arena.allocator(), tmp.dir, .{
        .source_dir = "src",
        .dest_base = "out",
        .dry_run = true,
    }, &out, &err_out));

    try expectMissing(tmp.dir, "out");
    try expectFileContents(tmp.dir, "src/a.pdf", "a");
    try expectFileContents(tmp.dir, "src/notes.txt", "notes");

    const output = out.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Would move a.pdf to out/pdf\n") != null);
    try std.testing.expectEqual(4, std.mem.count(u8, output, "Would move "));
}

test "organize creates a nested destination base" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/a.pdf", .data = "a" });

    var out_buf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err_out: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(0, try organize(io, arena.allocator(), tmp.dir, .{ .source_dir = "src", .dest_base = "x/y" }, &out, &err_out));

    try expectFileContents(tmp.dir, "x/y/pdf/a.pdf", "a");
}

test "organize reports a missing source directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var out_buf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err_out: Io.Writer = .fixed(&err_buf);
    try std.testing.expectError(
        error.FileNotFound,
        organize(std.testing.io, std.testing.allocator, tmp.dir, .{ .source_dir = "nope" }, &out, &err_out),
    );
}

test "organize reports a failing file and continues with the rest" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/a.pdf", .data = "a" });
    try tmp.dir.writeFile(io, .{ .sub_path = "src/notes.txt", .data = "notes" });
    // A regular file where the pdf destination directory should go.
    try tmp.dir.createDirPath(io, "out");
    try tmp.dir.writeFile(io, .{ .sub_path = "out/pdf", .data = "blocker" });

    var out_buf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err_out: Io.Writer = .fixed(&err_buf);
    const failed = try organize(io, arena.allocator(), tmp.dir, .{ .source_dir = "src", .dest_base = "out" }, &out, &err_out);

    try std.testing.expectEqual(1, failed);
    try expectFileContents(tmp.dir, "src/a.pdf", "a");
    try expectFileContents(tmp.dir, "out/pdf", "blocker");
    try expectFileContents(tmp.dir, "out/txt/notes.txt", "notes");
    try std.testing.expectEqualStrings("Moved notes.txt to out/txt\n", out.buffered());
    try std.testing.expect(std.mem.startsWith(u8, err_out.buffered(), "error: could not move a.pdf: "));
}
