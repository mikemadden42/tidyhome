# TODO

## Correctness & Safety

- [x] **Safe Defaults:** Require an explicit source directory (or default to a dry run). Today `zig build run` with no arguments moves `build.zig`, `build.zig.zon`, and `*.md` from the repo into `./Documents/`.
- [x] **Argument Parsing:** Handle `--help`/usage and add `--dry-run`. Currently `tidyhome --help` treats `--help` as the source path and fails with `error: FileNotFound`; extra arguments are silently ignored.
- [x] **Per-File Error Handling:** Report and continue when a single file fails (`RenameAcrossMountPoints`, `AccessDenied`, `NotDir` when a file blocks a destination directory) instead of aborting the whole run with `try`.
- [x] **Robust Logging:** Flush `stdout` after each message or via `defer`. On an aborted run, "Moved ..." lines still in the 512-byte buffer are lost, so files can be moved without any record.
- [x] **Atomic No-Replace Rename:** Replace the `access()` + `rename()` check with an atomic no-overwrite move (`renameat2(RENAME_NOREPLACE)` on Linux, `renamex_np(RENAME_EXCL)` on macOS, or link + unlink). POSIX `rename` silently replaces a destination created between the check and the move.
- [x] **Normalize Extension Case:** Lowercase extensions so `B.PDF` and `a.pdf` land in the same directory on case-sensitive filesystems.
- [x] **Avoid Empty Directories:** Only create the destination directory when a file will actually be moved there (skipped files currently still trigger `createDirPath`).
- [x] **Clear Source Directory Errors:** Name the path when the source directory can't be opened. Today `tidyhome nope` prints only `error: FileNotFound`; it should say something like `error: cannot open source directory 'nope': FileNotFound`.
- [x] **Streaming Output:** Use `writerStreaming` instead of `writer` for stdout and stderr. The positional writers each start at offset 0, so `tidyhome src >> run.log` overwrites the existing log and `tidyhome src out > log 2>&1` interleaves stderr on top of stdout (e.g. `.txt: NotDir` clobbering the end of a "Moved ..." line).
- [x] **macOS No-Replace Fallback:** Catch `error.OperationUnsupported` from `renamePreserve` and fall back to an exclusive-create placeholder + `rename`. On macOS, Zig calls `renameatx_np(RENAME_EXCL)` with no fallback, so on exFAT and FAT32 (confirmed with `hdiutil` disk images) every file failed. Link + unlink isn't an option there: neither filesystem supports hard links.
- [x] **No-Op Moves:** Detect when a file is already at its destination. `tidyhome Documents/pdf Documents` prints `Moved a.pdf to Documents/pdf` and exits 0, because renaming a file to its own path succeeds.
- [ ] **Unknown Entry Kinds:** Stat entries whose kind is `.unknown` instead of skipping them. Filesystems that don't report types from `readdir` (some network filesystems, older XFS) currently move nothing, with no warning.
- [ ] **Windows Reserved Names:** Handle extensions that map to reserved device names (`x.con`, `x.aux`, `x.nul`, `x.com1`). Windows can't create those directories, so the file fails with an error.
- [x] **Destination in Errors:** Name the destination in per-file errors. `error: could not move a.pdf: NotDir` doesn't say which path was blocked.

## Build & Project

- [x] **Conditional Strip:** Use `.strip = optimize != .debug` (or a `b.option`) so Debug builds keep symbols and stack traces.
- [x] **Remove Template Leftovers:** Drop the empty `src/root.zig`, the exported `tidyhome` module and its test step, and the `zig init` boilerplate comments in `build.zig`.
- [x] **Testing:** Extract the organize logic into a function taking a `Dir` and add test blocks using `std.testing.tmpDir` to verify file organization logic. `zig build test` currently passes vacuously.
- [x] **CI Workflow:** Add a GitHub Actions workflow running the commands listed in the README's CI section (no workflow exists yet).
- [x] **Document Compound Extensions:** Note in the README that `archive.tar.gz` is sorted by its last extension (`gz/`).
- [x] **Document Exit Codes:** Add the exit codes to the README: 0 on success, 1 if any file could not be moved (or the source directory can't be opened), 2 for invalid arguments.
- [x] **Portable Test Paths:** Build expected paths in tests with `std.fs.path.join` (or `sep_str`) instead of hard-coded `/` so `zig build test` passes on Windows and Windows can join the CI test matrix.
- [ ] **Document Cross-Filesystem Moves:** Note in the README that moves across filesystems fail with `CrossDevice` (no copy fallback), or add a copy + delete fallback.
- [ ] **Document Link + Unlink Fallback:** Note in the README that on Linux filesystems without `RENAME_NOREPLACE` (and always on FreeBSD), Zig moves by link + unlink and ignores a failed unlink, so a file can be left in both the source and the destination.
- [ ] **Document ASCII-Only Lowercasing:** Note in the README that only ASCII letters in extensions are lowercased (`allocLowerString`), so `.ÄBC` and `.äbc` land in different directories.
- [x] **Exit Code Tests:** Test `main`'s exit codes (0, 1, 2) end to end by running the built binary from `build.zig`, including output sent to a file with stdout and stderr merged, to cover the Streaming Output item.

## Performance

- [x] **Optimize Path Handling:** Use the existing directory handle for renames (`dir` vs `Dir.cwd()`) to eliminate redundant path joining for source files.
- [x] **Memory Management:** Refactor the main loop to use a fixed-size buffer or a resetable arena for path allocations to prevent linear memory growth in large directories.
