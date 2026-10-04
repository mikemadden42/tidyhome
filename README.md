# tidyhome

A small CLI utility that organizes files in a directory by sorting them into subdirectories based on their file extension.

```
tidyhome [options] <source_dir> [dest_base]
```

The source directory is required; the destination base defaults to `Documents` (relative to the current directory). For example, `report.pdf` would be moved to `dest_base/pdf/report.pdf`. Extension directories are lowercase, so `SCAN.PDF` also goes to `pdf/` (the file name itself is unchanged). Files that already exist at the destination are skipped.

| Option | Description |
| --- | --- |
| `-n`, `--dry-run` | Show what would be moved without changing anything |
| `-h`, `--help` | Show usage and exit |

Use `--` to pass a source directory whose name starts with `-`.

## CI

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
