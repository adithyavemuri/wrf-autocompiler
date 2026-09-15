# How the WRF builder works

## Purpose

`build_wrf.sh` creates a WRF installation in a user-owned directory. It does
not install operating-system packages. The default build root is
`../wrf-arw-local`; set `WRF_BUILD_ROOT` to keep multiple configurations.

## Build stages

1. Validate command-line choices.
2. Detect an environment-module command and optionally load one module.
3. Detect complete GNU, Intel/oneAPI, or NVIDIA HPC compiler families.
4. Compile and link a tiny mixed C/Fortran program as a toolchain check.
5. Select local or existing MPI/netCDF dependencies.
6. Obtain recursive WRF and, when requested, WPS source checkouts.
7. Match the requested compiler and parallel mode against WRF's actual
   configure menu, unless an exact menu number was supplied.
8. Compile the requested WRF target and check expected executables.
9. Optionally compile WPS and independently check its three executables.
10. Write `activate.sh`, a build manifest, logs, and configuration fingerprints.

## Local dependencies versus system dependencies

### Local

```bash
./build_wrf.sh --dependencies local
```

The script builds MPICH and classic netCDF locally. This is isolated and
reproducible but slower and may not use a cluster's optimized interconnect.

### System or module environment

```bash
./build_wrf.sh --module gcc/12 --dependencies system
```

The script requires `nc-config`, `nf-config`, and, for distributed-memory
builds, `mpicc` and `mpif90`. It validates their presence but cannot guarantee
that an arbitrary site combination is ABI-compatible.

### Automatic

```bash
./build_wrf.sh --dependencies auto
```

The system stack is selected only when the required configuration tools and
MPI wrappers are visible; otherwise the local path is selected.

## Configuration examples

Default distributed-memory real-data build:

```bash
./build_wrf.sh
```

Shared-memory build without WPS:

```bash
./build_wrf.sh --parallel smpar --target em_real --wps no
```

Separate build roots for two configurations:

```bash
WRF_BUILD_ROOT="$PWD/builds/dmpar" ./build_wrf.sh --parallel dmpar
WRF_BUILD_ROOT="$PWD/builds/smpar" ./build_wrf.sh --parallel smpar
```

Exact configure-menu selection:

```bash
./build_wrf.sh --wrf-option 34 --wps-option 1
```

Use exact numbers only after reviewing:

```bash
./build_wrf.sh --configure-help
```

## Safe rebuild behavior

A configuration fingerprint is written after a successful build. If a later
run requests a different compiler, dependency source, parallel mode, target,
nesting mode, or configure entry, the script stops instead of reusing stale
binaries. Prefer a new `WRF_BUILD_ROOT`. Use `--reconfigure` only when deleting
the old generated objects is intentional.

## What it does not provide

The builder does not download WRF geographical datasets or meteorological
inputs, submit scheduler jobs, tune site MPI, run a forecast case, benchmark
scaling, or verify scientific results.

