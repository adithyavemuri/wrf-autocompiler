# GitHub release checklist

- [x] No `sudo` or system package-manager calls.
- [x] Preflight performs a mixed C/Fortran compiler test.
- [x] Local and existing MPI/netCDF modes are selectable.
- [x] Compiler, module, parallel, target, nesting, and WPS controls are documented.
- [x] Configuration fingerprints protect against stale binary reuse.
- [x] Example scripts and limitations are included.
- [x] A one-command known-good quick-build wrapper is included.
- [ ] Choose and add a license.
- [ ] Add pinned SHA-256 checksums for downloaded archives.
- [ ] Test Intel/oneAPI and NVIDIA HPC configurations end to end.
- [ ] Test the system-dependency path on at least one managed cluster.
- [ ] Run a minimal `real.exe` and `wrf.exe` case before a stable release.
