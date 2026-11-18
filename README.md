# tidyhome

A small CLI utility that organizes files in a directory by sorting them into subdirectories based on their file extension.

```
tidyhome [options] <source_dir> [dest_base]
```

The source directory is required; the destination base defaults to `Documents` (relative to the current directory). For example, `report.pdf` would be moved to `dest_base/pdf/report.pdf`. Extension directories are lowercase, so `SCAN.PDF` also goes to `pdf/` (the file name itself is unchanged). Only the last extension counts, so `archive.tar.gz` goes to `gz/`. Files that already exist at the destination are skipped.

| Option | Description |
| --- | --- |
| `-n`, `--dry-run` | Show what would be moved without changing anything |
| `-h`, `--help` | Show usage and exit |

Use `--` to pass a source directory whose name starts with `-`.

## Exit Codes

| Code | Meaning |
| --- | --- |
| 0 | Success (files that already exist at the destination are skipped, not failures) |
| 1 | The source directory could not be opened, or at least one file could not be moved |
| 2 | Invalid arguments |

## Limitations

- **No copying:** files are only renamed, never copied. If `dest_base` is on a different filesystem from `source_dir`, each file fails with `CrossDevice`.
- **exFAT and FAT32:** these don't support renames that refuse to overwrite, so tidyhome first creates an empty placeholder at the destination, then renames over it. If tidyhome is killed between those two steps, the empty placeholder is left behind, and later runs report that file as already existing. Delete the empty file to move it.
- **Linux and FreeBSD:** where the filesystem doesn't support renames that refuse to overwrite (always on FreeBSD), files are moved by hard-linking them to the destination and then removing the original. If the removal fails, the file is left in both places.
- **Extension case:** only ASCII letters are lowercased, so `photo.ÉPS` and `photo.éps` go to different directories.
- **Windows reserved names:** an extension that is a reserved device name (`con`, `aux`, `nul`, `prn`, `com1`–`com9`, `lpt1`–`lpt9`) can't be a directory name on Windows, so files like `x.con` fail with an error and are left in place.

## CI

`.github/workflows/ci.yml` runs the tests on Linux, macOS, and Windows and cross-compiles every target below. To run the same checks locally:

```sh
zig fmt --check src/main.zig   # formatting
zig fmt --check .              # formatting (entire project)
zig build                      # debug build
zig build test                 # tests
zig build test --release=safe  # tests with safety checks
zig build --release=safe       # release build with safety checks
zig build --release=fast       # release build
zig build --release=small      # size-optimized build
```

## Cross Compilation

```sh
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-windows
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86_64-macos
zig build -Dtarget=x86_64-freebsd
```
