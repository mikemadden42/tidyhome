//! End-to-end tests that run the built tidyhome binary, covering what the
//! in-process tests in main.zig can't: exit codes and real stdout/stderr.

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const build_options = @import("build_options");

const io = std.testing.io;
const gpa = std.testing.allocator;

/// Runs tidyhome in `cwd` with stdout and stderr both written to `log`, as
/// `tidyhome args... >> log 2>&1` would, and returns its exit code.
fn runTidyhome(cwd: Dir, log: Io.File, args: []const []const u8) !u8 {
    // The build system's path is relative to our cwd, not the child's.
    const test_cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(test_cwd);
    const exe_path = try std.fs.path.resolve(gpa, &.{ test_cwd, build_options.exe_path });
    defer gpa.free(exe_path);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, exe_path);
    try argv.appendSlice(gpa, args);

    var child = try std.process.spawn(io, .{
        .argv = argv.items,
        .cwd = .{ .dir = cwd },
        .stdin = .ignore,
        .stdout = .{ .file = log },
        .stderr = .{ .file = log },
    });
    return switch (try child.wait(io)) {
        .exited => |code| code,
        else => error.TestUnexpectedResult,
    };
}

/// Creates `log.txt` in `dir` holding `prefix`, with the file offset left at
/// the end so the child continues after it, like a shell's `>>`.
fn createLog(dir: Dir, prefix: []const u8) !Io.File {
    const log = try dir.createFile(io, "log.txt", .{});
    errdefer log.close(io);
    try log.writeStreamingAll(io, prefix);
    return log;
}

fn readLog(dir: Dir) ![]u8 {
    return dir.readFileAlloc(io, "log.txt", gpa, .limited(4096));
}

test "exit code 0 and output appends to an existing log" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/a.pdf", .data = "a" });

    const log = try createLog(tmp.dir, "previous run\n");
    const code = try runTidyhome(tmp.dir, log, &.{ "src", "out" });
    log.close(io);
    try std.testing.expectEqual(0, code);

    const output = try readLog(tmp.dir);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("previous run\nMoved a.pdf to out" ++ std.fs.path.sep_str ++ "pdf\n", output);
}

test "exit code 1 keeps stdout and stderr intact in a merged log" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/a.pdf", .data = "a" });
    try tmp.dir.writeFile(io, .{ .sub_path = "src/b.txt", .data = "b" });
    // A regular file where the txt destination directory should go.
    try tmp.dir.createDirPath(io, "out");
    try tmp.dir.writeFile(io, .{ .sub_path = "out/txt", .data = "blocker" });

    const log = try createLog(tmp.dir, "");
    const code = try runTidyhome(tmp.dir, log, &.{ "src", "out" });
    log.close(io);
    try std.testing.expectEqual(1, code);

    // Directory iteration order varies, so check for each line rather than
    // the exact log.
    const output = try readLog(tmp.dir);
    defer gpa.free(output);
    const expected_lines = [_][]const u8{
        "Moved a.pdf to out" ++ std.fs.path.sep_str ++ "pdf\n",
        "error: could not move b.txt: ",
        "error: 1 file(s) could not be moved\n",
    };
    for (expected_lines) |line| {
        if (std.mem.indexOf(u8, output, line) == null) {
            std.debug.print("missing {f} in log:\n{s}\n", .{ std.zig.fmtString(line), output });
            return error.TestExpectedEqual;
        }
    }
}

test "exit code 1 when the source directory can't be opened" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const log = try createLog(tmp.dir, "");
    const code = try runTidyhome(tmp.dir, log, &.{"nope"});
    log.close(io);
    try std.testing.expectEqual(1, code);

    const output = try readLog(tmp.dir);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("error: cannot open source directory 'nope': FileNotFound\n", output);
}

test "exit code 2 for invalid arguments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const log = try createLog(tmp.dir, "");
    const code = try runTidyhome(tmp.dir, log, &.{"--bogus"});
    log.close(io);
    try std.testing.expectEqual(2, code);

    const output = try readLog(tmp.dir);
    defer gpa.free(output);
    try std.testing.expect(std.mem.startsWith(u8, output, "error: unknown option\n\nUsage: tidyhome "));
}
