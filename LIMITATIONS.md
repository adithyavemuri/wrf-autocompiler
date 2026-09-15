# Current limitations of the WRF autocompiler

## Supported configuration

The script has been proven end to end only on Linux x86-64 with a compatible
GNU `gcc`/`g++`/`gfortran` toolchain, `dmpar`, basic nesting, `em_real`, and
serial WPS. It can now detect Intel/oneAPI and NVIDIA HPC compiler families and
select matching configure entries, but those compiler paths remain unvalidated.

## Host prerequisites

The script does not install a compiler or basic build environment. These must
already be available on `PATH`:

- `make`, `perl`, `git`, `curl`, `tar`, `file`, `sed`, and `find`.
- A complete supported C/C++/Fortran family: GNU, Intel/oneAPI, or NVIDIA HPC.

It can build local M4 and tcsh/ncurses when those are missing, but it cannot
bootstrap every possible cluster prerequisite.

## Compiler and platform limitations

- Intel/oneAPI and NVHPC detection exists but lacks an end-to-end verified build.
- AOCC, Cray, and mixed compiler stacks are not supported.
- Automatic configure-menu matching can fail when upstream wording changes;
  explicit menu-number overrides are therefore available.
- No macOS, Windows, ARM, or non-Linux validation.
- Environment modules can be listed and one requested module can be loaded, but
  module naming and dependency combinations remain site-specific.
- System MPI/netCDF can be selected when wrappers and both configuration tools
  are visible; ABI compatibility is the user's responsibility.
- No Spack or scheduler integration.
- Products are built for the current host and are not guaranteed portable to
  another cluster or CPU architecture.

## WRF/WPS feature limitations

- Compile target, parallel mode, nesting, and WPS inclusion are selectable, but
  only the default `em_real`/`dmpar`/basic/WPS combination is proven.
- `WRF_CHEM` is explicitly disabled.
- WPS is configured serially.
- No DA, idealized cases, coupled models, chemistry, fire, or alternative core
  targets are built.
- netCDF is classic-only: netCDF-4/HDF5 and DAP are disabled.
- Optional PnetCDF, parallel HDF5, and other performance libraries are absent.
- The script does not download geographical data, meteorological input data, or
  runtime tables beyond files supplied by the WRF/WPS checkouts.

## Reproducibility and download limitations

- Network access is required unless every archive and checkout already exists.
- Downloads use HTTPS but are not verified against pinned SHA-256 checksums.
- WRF and WPS are shallow recursive Git clones.
- Existing Git checkouts are reused and submodules updated, but the script does
  not fully prove that every file still matches the requested tag.
- Version environment overrides are accepted without a compatibility matrix.
- Upstream URLs, tags, configure menus, or bundled-library layouts can change.

## Resume and stale-build limitations

- WRF/WPS configuration fingerprints prevent silent reuse across the exposed
  compiler, library, parallel, target, nesting, and menu choices.
- Older builds made before fingerprints were introduced require either a new
  `WRF_BUILD_ROOT` or an explicit `--reconfigure` cleanup.
- Unrecorded environment details and compiler flags can still change without
  invalidating the fingerprint; use a new build root for strict isolation.
- The script edits `/bin/csh` shebangs inside downloaded source trees when a
  local tcsh is needed, so those trees are not pristine upstream checkouts.

## Verification limitations

- Success checks confirm that expected executable paths exist.
- The script does not currently run `file`, `ldd`, or a full dependency audit on
  every final executable.
- It does not run `real.exe`, `wrf.exe`, or a meteorological validation case.
- It does not benchmark MPI scaling or numerical reproducibility.
- The build manifest records versions and paths but not complete compiler flags,
  source commits, checksums, or all configure files.

## Resource limitations

- `JOBS` defaults to every online CPU. On a memory-limited login node this may
  oversubscribe RAM or violate cluster policy; set `JOBS` explicitly.
- WRF, WPS, MPICH, netCDF, sources, archives, and intermediate objects require
  substantial disk space.
- The script has no scheduler submission mode and should not be run on a cluster
  login node unless local policy permits compilation there.

## Practical claim

The script is a successful rootless builder for one tested GNU WRF-ARW/WPS
configuration. It should not be advertised as a universal WRF autocompiler
until alternative compiler paths are validated and checksum verification,
final binary dependency checks, broader platform coverage, and runtime tests
are added.
