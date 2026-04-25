# TODO

- [ ] **Optimize Path Handling:** Use the existing directory handle for renames (`dir` vs `Dir.cwd()`) to eliminate redundant path joining for source files.
- [ ] **Memory Management:** Refactor the main loop to use a fixed-size buffer or a resetable arena for path allocations to prevent linear memory growth in large directories.
- [ ] **Performance Optimization:** Implement a cache (e.g., a hash map) for destination directories to avoid redundant `createDirPath` syscalls for every file.
- [ ] **Robust Logging:** Use `defer` to ensure `stdout` is flushed even if the program encounters an error during execution.
- [ ] **Testing:** Add test blocks in `src/main.zig` using `std.testing.tmpDir` to verify file organization logic.
