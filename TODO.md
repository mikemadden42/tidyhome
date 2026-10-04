# TODO

## Correctness & Safety

- [x] **Safe Defaults:** Require an explicit source directory (or default to a dry run). Today `zig build run` with no arguments moves `build.zig`, `build.zig.zon`, and `*.md` from the repo into `./Documents/`.
- [x] **Argument Parsing:** Handle `--help`/usage and add `--dry-run`. Currently `tidyhome --help` treats `--help` as the source path and fails with `error: FileNotFound`; extra arguments are silently ignored.
- [x] **Per-File Error Handling:** Report and continue when a single file fails (`RenameAcrossMountPoints`, `AccessDenied`, `NotDir` when a file blocks a destination directory) instead of aborting the whole run with `try`.
- [x] **Robust Logging:** Flush `stdout` after each message or via `defer`. On an aborted run, "Moved ..." lines still in the 512-byte buffer are lost, so files can be moved without any record.
- [x] **Atomic No-Replace Rename:** Replace the `access()` + `rename()` check with an atomic no-overwrite move (`renameat2(RENAME_NOREPLACE)` on Linux, `renamex_np(RENAME_EXCL)` on macOS, or link + unlink). POSIX `rename` silently replaces a destination created between the check and the move.
- [x] **Normalize Extension Case:** Lowercase extensions so `B.PDF` and `a.pdf` land in the same directory on case-sensitive filesystems.
- [x] **Avoid Empty Directories:** Only create the destination directory when a file will actually be moved there (skipped files currently still trigger `createDirPath`).

## Build & Project

- [x] **Conditional Strip:** Use `.strip = optimize != .debug` (or a `b.option`) so Debug builds keep symbols and stack traces.
- [x] **Remove Template Leftovers:** Drop the empty `src/root.zig`, the exported `tidyhome` module and its test step, and the `zig init` boilerplate comments in `build.zig`.
- [x] **Testing:** Extract the organize logic into a function taking a `Dir` and add test blocks using `std.testing.tmpDir` to verify file organization logic. `zig build test` currently passes vacuously.
- [ ] **CI Workflow:** Add a GitHub Actions workflow running the commands listed in the README's CI section (no workflow exists yet).
- [x] **Document Compound Extensions:** Note in the README that `archive.tar.gz` is sorted by its last extension (`gz/`).

## Performance

- [x] **Optimize Path Handling:** Use the existing directory handle for renames (`dir` vs `Dir.cwd()`) to eliminate redundant path joining for source files.
- [ ] **Performance Optimization:** Implement a cache (e.g., a hash map) for destination directories to avoid redundant `createDirPath` syscalls for every file.
- [x] **Memory Management:** Refactor the main loop to use a fixed-size buffer or a resetable arena for path allocations to prevent linear memory growth in large directories.
