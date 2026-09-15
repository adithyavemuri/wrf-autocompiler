# Quick start

## Fastest workstation path

The computer must already provide compatible `gcc`, `g++`, `gfortran`, `make`,
Perl, Git, curl, tar, `file`, sed, and find. Then run:

```bash
./quick_build.sh
```

This first performs the compiler preflight and then builds the known-good
configuration using local MPICH and netCDF:

- GNU compiler family
- distributed-memory `dmpar`
- `em_real`
- basic nesting
- WPS enabled

All downloaded sources, libraries, executables, and logs are placed under the
sibling `wrf-arw-local` directory unless `WRF_BUILD_ROOT` is set.

After completion:

```bash
. ../wrf-arw-local/activate.sh
```

## Fastest cluster path

First see what this login environment exposes:

```bash
./examples/preflight.sh
```

If the required compiler, MPI, and netCDF tools come from one module:

```bash
./examples/build_with_cluster_module.sh MODULE_NAME
```

For example, only if that exact module exists at your site:

```bash
./examples/build_with_cluster_module.sh WRF/4.7.1
```

The system path requires `nc-config`, `nf-config`, `mpicc`, and `mpif90` after
the module is loaded. Cluster module names are site-specific and cannot be
chosen universally by the script.

## Before a long build

- Set `JOBS` lower than the CPU count when memory is limited.
- Check cluster policy before compiling on a login node.
- Allow substantial disk space and build time.
- Use a different `WRF_BUILD_ROOT` for each configuration.
- Read `LIMITATIONS.md`; successful compilation is not a forecast validation.

