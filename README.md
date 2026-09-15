# Rootless WRF-ARW and WPS builder

`build_wrf.sh` builds WRF-ARW below a user-owned directory. It never calls
`sudo` or a system package manager. The known-good default remains GNU,
locally built MPICH/netCDF, `dmpar`, `em_real`, basic nesting, and WPS.

```bash
./build_wrf.sh --preflight
./build_wrf.sh
```

For the shortest known-good path:

```bash
./quick_build.sh
```

See [QUICK_START.md](QUICK_START.md) for workstation and cluster setup.

Inspect detected compilers and cluster modules:

```bash
./build_wrf.sh --preflight --list-modules
```

Use an already installed compiler/MPI/netCDF environment:

```bash
./build_wrf.sh --module gcc/12 --compiler gnu --dependencies system
```

Choose another WRF configuration:

```bash
./build_wrf.sh \
  --compiler gnu \
  --dependencies local \
  --parallel smpar \
  --target em_real \
  --nesting basic \
  --wps yes
```

Intel/oneAPI and NVIDIA HPC compiler discovery is supported at preflight and
configure-menu selection. Since those paths have not been compiled end to end
on this machine, first run `--preflight --compiler intel` or
`--preflight --compiler nvhpc`, then review `--configure-help`.

Important controls:

- `--compiler auto|gnu|intel|nvhpc`
- `--dependencies local|system|auto`
- `--parallel serial|smpar|dmpar|dm+sm`
- `--target em_real` or another WRF compile target
- `--nesting none|basic|preset|vortex|NUMBER`
- `--wps auto|yes|no`
- `--module NAME`
- `--wrf-option NUMBER` and `--wps-option NUMBER` to override menu discovery
- `--reconfigure` to explicitly clean and rebuild generated objects

Each successful build records a configuration fingerprint. If existing
binaries do not match the requested compiler, dependency source, parallel mode,
target, nesting, or configure entry, the script stops. Use a separate
`WRF_BUILD_ROOT` to retain both configurations, or pass `--reconfigure` when
discarding the old generated objects is intentional.

The default output is the sibling directory `../wrf-arw-local`. After a
successful build:

```bash
. ../wrf-arw-local/activate.sh
```

The proven configuration is WRF 4.7.1 `em_real`, GNU `dmpar`, basic nesting,
MPICH 4.2.3, classic netCDF-C 4.7.2, netCDF-Fortran 4.5.2, and WPS 4.6.0.

The alternative paths increase user control but are not all proven
configurations. Read [LIMITATIONS.md](LIMITATIONS.md) before using it on a
different workstation or cluster.

For a plain-language explanation of every stage, dependency choice, rebuild
rule, and configuration example, see [HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).

Ready-to-edit examples are under `examples/`:

- `preflight.sh`: detect modules and compilers without downloading;
- `build_local_gnu.sh`: reproduce the known-good local GNU configuration;
- `build_with_cluster_module.sh MODULE_NAME`: use a cluster-provided stack.

Before publishing, complete [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
