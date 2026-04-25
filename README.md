# tidyhome

A small CLI utility that organizes files in a directory by sorting them into subdirectories based on their file extension.

```
tidyhome [source_dir] [dest_base]
```

Defaults to the current directory as source and `Documents` as the destination base. For example, `report.pdf` would be moved to `dest_base/pdf/report.pdf`. Files that already exist at the destination are skipped.

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
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86_64-macos
```
