#!/usr/bin/env bash
# Build WRF-ARW and optionally WPS with user-selected compilers and libraries.
#
# This script never uses sudo or a system package manager. It uses an existing
# C/C++/Fortran toolchain. MPI and netCDF can be built below ROOT_DIR or taken
# from an already configured host/module environment.
# By default ROOT_DIR is a sibling of this script directory, keeping generated
# build products out of the autocompiler source tree.
#
# Review first. Typical invocation later:
#   ./build_wrf.sh --preflight
#   ./build_wrf.sh
#
# To inspect the available WRF/WPS configure choices without building:
#   ./build_wrf.sh --configure-help

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ROOT_DIR="${WRF_BUILD_ROOT:-$(dirname -- "$SCRIPT_DIR")/wrf-arw-local}"
readonly DOWNLOAD_DIR="$ROOT_DIR/downloads"
readonly SOURCE_DIR="$ROOT_DIR/sources"
readonly BUILD_DIR="$ROOT_DIR/build"
readonly INSTALL_DIR="$ROOT_DIR/install"
readonly LOG_DIR="$ROOT_DIR/logs"
readonly AUX_DIR="$INSTALL_DIR/build-tools"

# Pinned versions: override from the environment if a different tested set is
# desired. WPS 4.6 is the current matching WPS series for WRF 4.6/4.7 builds.
readonly WRF_VERSION="${WRF_VERSION:-4.7.1}"
readonly WPS_VERSION="${WPS_VERSION:-4.6.0}"
readonly MPICH_VERSION="${MPICH_VERSION:-4.2.3}"
readonly NETCDF_C_VERSION="${NETCDF_C_VERSION:-4.7.2}"
readonly NETCDF_FORTRAN_VERSION="${NETCDF_FORTRAN_VERSION:-4.5.2}"
readonly M4_VERSION="${M4_VERSION:-1.4.21}"
readonly NCURSES_VERSION="${NCURSES_VERSION:-6.5}"
readonly TCSH_VERSION="${TCSH_VERSION:-6.24.16}"
readonly JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"
readonly WRF_SOURCE_DIR="$SOURCE_DIR/WRF-${WRF_VERSION}-recursive"
readonly WPS_SOURCE_DIR="$SOURCE_DIR/WPS-${WPS_VERSION}-recursive"

# The menu numbers are specific to Linux x86_64 + GNU compilers. If an upstream
# release changes its menus, the script validates the generated configuration
# and prints the menus instead of silently building the wrong target.
WRF_CONFIGURE_OPTION="${WRF_CONFIGURE_OPTION:-auto}"
WRF_NESTING_OPTION="${WRF_NESTING_OPTION:-1}"
WPS_CONFIGURE_OPTION="${WPS_CONFIGURE_OPTION:-auto}"
COMPILER_FAMILY="${COMPILER_FAMILY:-auto}"
DEPENDENCY_MODE="${DEPENDENCY_MODE:-local}"
PARALLELISM="${PARALLELISM:-dmpar}"
WRF_TARGET="${WRF_TARGET:-em_real}"
BUILD_WPS="${BUILD_WPS:-auto}"
MODULE_NAME="${MODULE_NAME:-}"
SELECTED_COMPILER=""
NETCDF_PREFIX=""

CONFIGURE_HELP=0
PREFLIGHT_ONLY=0
LIST_MODULES=0
RECONFIGURE=0

usage() {
  cat <<'EOF'
Usage: build_wrf.sh [OPTIONS]

Options:
  --preflight               Check the host toolchain without downloading/building.
  --configure-help          Download/unpack sources and print configure menus.
  --compiler FAMILY         auto, gnu, intel, or nvhpc (default: auto).
  --dependencies MODE       local, system, or auto (default: local).
  --parallel MODE           serial, smpar, dmpar, or dm+sm (default: dmpar).
  --target NAME             WRF compile target (default: em_real).
  --nesting MODE            none, basic, preset, vortex, or menu number.
  --wrf-option VALUE        auto or an exact WRF configure menu number.
  --wps-option VALUE        auto or an exact WPS configure menu number.
  --wps MODE                auto, yes, or no. Auto builds WPS for em_real.
  --module NAME             Load this environment module before detection.
  --list-modules            Print visible modules during preflight.
  --reconfigure             Explicitly clean generated WRF/WPS objects first.
  -h, --help                Show this help.

Environment overrides:
  WRF_BUILD_ROOT, WRF_VERSION, WPS_VERSION, MPICH_VERSION,
  NETCDF_C_VERSION, NETCDF_FORTRAN_VERSION, M4_VERSION, NCURSES_VERSION,
  TCSH_VERSION, JOBS,
  WRF_CONFIGURE_OPTION, WRF_NESTING_OPTION, WPS_CONFIGURE_OPTION,
  COMPILER_FAMILY, DEPENDENCY_MODE, PARALLELISM, WRF_TARGET, BUILD_WPS,
  MODULE_NAME, CC, CXX, FC, F77
EOF
}

while (($#)); do
  case "$1" in
    --preflight) PREFLIGHT_ONLY=1 ;;
    --configure-help) CONFIGURE_HELP=1 ;;
    --compiler) COMPILER_FAMILY="${2:?--compiler requires a value}"; shift ;;
    --dependencies) DEPENDENCY_MODE="${2:?--dependencies requires a value}"; shift ;;
    --parallel) PARALLELISM="${2:?--parallel requires a value}"; shift ;;
    --target) WRF_TARGET="${2:?--target requires a value}"; shift ;;
    --nesting) WRF_NESTING_OPTION="${2:?--nesting requires a value}"; shift ;;
    --wrf-option) WRF_CONFIGURE_OPTION="${2:?--wrf-option requires a value}"; shift ;;
    --wps-option) WPS_CONFIGURE_OPTION="${2:?--wps-option requires a value}"; shift ;;
    --wps) BUILD_WPS="${2:?--wps requires a value}"; shift ;;
    --module) MODULE_NAME="${2:?--module requires a value}"; shift ;;
    --list-modules) LIST_MODULES=1 ;;
    --reconfigure) RECONFIGURE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$COMPILER_FAMILY" in auto|gnu|intel|nvhpc) ;; *) printf 'Invalid compiler family: %s\n' "$COMPILER_FAMILY" >&2; exit 2 ;; esac
case "$DEPENDENCY_MODE" in local|system|auto) ;; *) printf 'Invalid dependency mode: %s\n' "$DEPENDENCY_MODE" >&2; exit 2 ;; esac
case "$PARALLELISM" in serial|smpar|dmpar|dm+sm) ;; *) printf 'Invalid parallel mode: %s\n' "$PARALLELISM" >&2; exit 2 ;; esac
case "$BUILD_WPS" in auto|yes|no) ;; *) printf 'Invalid WPS mode: %s\n' "$BUILD_WPS" >&2; exit 2 ;; esac
case "$WRF_TARGET" in *[!A-Za-z0-9_-]*|'') printf 'Invalid WRF target: %s\n' "$WRF_TARGET" >&2; exit 2 ;; esac
case "$WRF_NESTING_OPTION" in none) WRF_NESTING_OPTION=0 ;; basic) WRF_NESTING_OPTION=1 ;; preset) WRF_NESTING_OPTION=2 ;; vortex) WRF_NESTING_OPTION=3 ;; *[!0-9]*|'') printf 'Invalid nesting mode: %s\n' "$WRF_NESTING_OPTION" >&2; exit 2 ;; esac
if [[ "$BUILD_WPS" == auto ]]; then [[ "$WRF_TARGET" == em_real ]] && BUILD_WPS=yes || BUILD_WPS=no; fi

mkdir -p "$DOWNLOAD_DIR" "$SOURCE_DIR" "$BUILD_DIR" "$INSTALL_DIR" "$LOG_DIR"
readonly RUN_LOG="$LOG_DIR/build-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$RUN_LOG") 2>&1
trap 'printf "ERROR: line %d failed. See %s\n" "$LINENO" "$RUN_LOG" >&2' ERR

log() { printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

require_commands() {
  local missing=() command_name
  for command_name in make perl git curl tar file sed find; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
  done
  if ((${#missing[@]})); then
    printf 'Missing bootstrap commands: %s\n' "${missing[*]}" >&2
    printf 'This script never installs host tools. Make these commands available on PATH.\n' >&2
    exit 1
  fi
}

initialize_modules() {
  if ! type module >/dev/null 2>&1; then
    for init_script in /etc/profile.d/modules.sh /usr/share/Modules/init/bash /usr/share/lmod/lmod/init/bash; do
      if [[ -r "$init_script" ]]; then
        # The module command is normally a shell function, so it must be sourced.
        source "$init_script"
        break
      fi
    done
  fi
  if ((LIST_MODULES)); then
    if type module >/dev/null 2>&1; then
      log "Visible environment modules"
      module avail 2>&1 || true
    else
      log "No environment-module command was detected"
    fi
  fi
  if [[ -n "$MODULE_NAME" ]]; then
    type module >/dev/null 2>&1 || {
      printf 'Requested module %s, but no module command is available.\n' "$MODULE_NAME" >&2
      exit 1
    }
    log "Loading environment module: $MODULE_NAME"
    module load "$MODULE_NAME"
  fi
}

compiler_available() {
  case "$1" in
    gnu) command -v gcc >/dev/null && command -v g++ >/dev/null && command -v gfortran >/dev/null ;;
    intel) { command -v icx >/dev/null && command -v icpx >/dev/null && command -v ifx >/dev/null; } || \
           { command -v icc >/dev/null && command -v icpc >/dev/null && command -v ifort >/dev/null; } ;;
    nvhpc) command -v nvc >/dev/null && command -v nvc++ >/dev/null && command -v nvfortran >/dev/null ;;
  esac
}

report_compilers() {
  local family
  for family in gnu intel nvhpc; do
    if compiler_available "$family"; then
      printf '  %-7s available\n' "$family"
    else
      printf '  %-7s not found\n' "$family"
    fi
  done
}

select_compiler() {
  if [[ "$COMPILER_FAMILY" == auto ]]; then
    local candidate
    for candidate in gnu intel nvhpc; do
      if compiler_available "$candidate"; then
        COMPILER_FAMILY="$candidate"
        break
      fi
    done
  fi
  compiler_available "$COMPILER_FAMILY" || {
    printf 'Requested compiler family is unavailable: %s\nDetected candidates:\n' "$COMPILER_FAMILY" >&2
    report_compilers >&2
    exit 1
  }
  case "$COMPILER_FAMILY" in
    gnu) CC="${CC:-gcc}"; CXX="${CXX:-g++}"; FC="${FC:-gfortran}"; F77="${F77:-$FC}" ;;
    intel)
      if command -v ifx >/dev/null 2>&1; then
        CC="${CC:-icx}"; CXX="${CXX:-icpx}"; FC="${FC:-ifx}"; F77="${F77:-$FC}"
      else
        CC="${CC:-icc}"; CXX="${CXX:-icpc}"; FC="${FC:-ifort}"; F77="${F77:-$FC}"
      fi ;;
    nvhpc) CC="${CC:-nvc}"; CXX="${CXX:-nvc++}"; FC="${FC:-nvfortran}"; F77="${F77:-$FC}" ;;
  esac
  export CC CXX FC F77
  SELECTED_COMPILER="$COMPILER_FAMILY"
}

bootstrap_build_tools() {
  export PATH="$AUX_DIR/bin:$PATH"

  if ! command -v m4 >/dev/null 2>&1; then
    local m4_archive="$DOWNLOAD_DIR/m4-${M4_VERSION}.tar.xz"
    local m4_source="$SOURCE_DIR/m4-${M4_VERSION}"
    local m4_build="$BUILD_DIR/m4-${M4_VERSION}"
    download "https://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.xz" "$m4_archive"
    extract_fresh "$m4_archive" "$m4_source"
    mkdir -p "$m4_build"
    log "Building GNU M4 $M4_VERSION locally"
    (cd "$m4_build" && "$m4_source/configure" --prefix="$AUX_DIR")
    make -C "$m4_build" -j "$JOBS"
    make -C "$m4_build" install
  fi

  if ! command -v tcsh >/dev/null 2>&1 && ! command -v csh >/dev/null 2>&1; then
    if [[ ! -f "$AUX_DIR/lib/libtinfow.a" ]]; then
      local ncurses_archive="$DOWNLOAD_DIR/ncurses-${NCURSES_VERSION}.tar.gz"
      local ncurses_source="$SOURCE_DIR/ncurses-${NCURSES_VERSION}"
      local ncurses_build="$BUILD_DIR/ncurses-${NCURSES_VERSION}"
      download "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" "$ncurses_archive"
      extract_fresh "$ncurses_archive" "$ncurses_source"
      mkdir -p "$ncurses_build"
      log "Building ncurses $NCURSES_VERSION locally for tcsh"
      (cd "$ncurses_build" && "$ncurses_source/configure" \
        --prefix="$AUX_DIR" --without-shared --without-debug \
        --enable-widec --with-termlib --without-cxx-binding)
      make -C "$ncurses_build" -j "$JOBS"
      make -C "$ncurses_build" install
    fi

    local tcsh_archive="$DOWNLOAD_DIR/tcsh-${TCSH_VERSION}.tar.gz"
    local tcsh_source="$SOURCE_DIR/tcsh-${TCSH_VERSION}"
    local tcsh_build="$BUILD_DIR/tcsh-${TCSH_VERSION}"
    download "https://astron.com/pub/tcsh/tcsh-${TCSH_VERSION}.tar.gz" "$tcsh_archive"
    extract_fresh "$tcsh_archive" "$tcsh_source"
    mkdir -p "$tcsh_build"
    log "Building tcsh $TCSH_VERSION locally"
    (cd "$tcsh_build" && \
      CPPFLAGS="-I$AUX_DIR/include -I$AUX_DIR/include/ncursesw" \
      LDFLAGS="-L$AUX_DIR/lib" LIBS='-ltinfow' \
      "$tcsh_source/configure" --prefix="$AUX_DIR")
    make -C "$tcsh_build" -j "$JOBS"
    make -C "$tcsh_build" install
    ln -sfn tcsh "$AUX_DIR/bin/csh"
  fi

  command -v m4 >/dev/null 2>&1 || { printf 'Local M4 bootstrap failed.\n' >&2; exit 1; }
  command -v csh >/dev/null 2>&1 || command -v tcsh >/dev/null 2>&1 || {
    printf 'Local C shell bootstrap failed.\n' >&2; exit 1;
  }
}

check_toolchain() {
  local test_dir
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/wrf-toolchain-check.XXXXXX")"
  printf '%s\n' \
    'subroutine wrf_answer(n) bind(C)' \
    '  use iso_c_binding' \
    '  integer(c_int), intent(out) :: n' \
    '  n = 42' \
    'end subroutine wrf_answer' > "$test_dir/check.f90"
  printf '%s\n' \
    'void wrf_answer(int *);' \
    'int main(void) { int n = 0; wrf_answer(&n); return n == 42 ? 0 : 1; }' \
    > "$test_dir/check.c"
  "$FC" -c "$test_dir/check.f90" -o "$test_dir/check-f.o"
  "$CC" -c "$test_dir/check.c" -o "$test_dir/check-c.o"
  "$FC" "$test_dir/check-c.o" "$test_dir/check-f.o" -o "$test_dir/check"
  "$test_dir/check"
  rm -rf -- "$test_dir"

  log "Compiler verified: family=$COMPILER_FAMILY CC=$(command -v "$CC") FC=$(command -v "$FC")"
}

select_dependencies() {
  if [[ "$DEPENDENCY_MODE" == auto ]]; then
    if command -v nc-config >/dev/null 2>&1 && command -v nf-config >/dev/null 2>&1 && \
       { [[ "$PARALLELISM" != dmpar && "$PARALLELISM" != dm+sm ]] || command -v mpif90 >/dev/null 2>&1; }; then
      DEPENDENCY_MODE=system
    else
      DEPENDENCY_MODE=local
    fi
  fi
  if [[ "$DEPENDENCY_MODE" == system ]]; then
    command -v nc-config >/dev/null 2>&1 && command -v nf-config >/dev/null 2>&1 || {
      printf 'System mode requires both nc-config and nf-config on PATH.\n' >&2
      exit 1
    }
    if [[ "$PARALLELISM" == dmpar || "$PARALLELISM" == dm+sm ]]; then
      command -v mpicc >/dev/null 2>&1 && command -v mpif90 >/dev/null 2>&1 || {
        printf 'Parallel system mode requires mpicc and mpif90 on PATH.\n' >&2
        exit 1
      }
    fi
    NETCDF_PREFIX="$(nc-config --prefix)"
    [[ -d "$NETCDF_PREFIX/include" && -d "$NETCDF_PREFIX/lib" ]] || {
      printf 'nc-config returned an unusable prefix: %s\n' "$NETCDF_PREFIX" >&2
      exit 1
    }
  else
    NETCDF_PREFIX="$INSTALL_DIR/netcdf"
  fi
  log "Dependency mode: $DEPENDENCY_MODE; netCDF prefix: $NETCDF_PREFIX"
}

write_build_manifest() {
  {
    printf 'build_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'host=%s\n' "$(uname -n)"
    printf 'architecture=%s\n' "$(uname -m)"
    printf 'compiler_family=%s\n' "$COMPILER_FAMILY"
    printf 'cc_path=%s\n' "$(command -v "$CC")"
    printf 'cxx_path=%s\n' "$(command -v "$CXX")"
    printf 'fc_path=%s\n' "$(command -v "$FC")"
    printf 'dependency_mode=%s\n' "$DEPENDENCY_MODE"
    printf 'netcdf_prefix=%s\n' "$NETCDF_PREFIX"
    printf 'mpich_version=%s\n' "$([[ "$DEPENDENCY_MODE" == local ]] && printf '%s' "$MPICH_VERSION" || printf 'system')"
    printf 'netcdf_c_version=%s\n' "$NETCDF_C_VERSION"
    printf 'netcdf_fortran_version=%s\n' "$NETCDF_FORTRAN_VERSION"
    printf 'wrf_version=%s\n' "$WRF_VERSION"
    printf 'wps_version=%s\n' "$WPS_VERSION"
    printf 'wrf_target=%s\n' "$WRF_TARGET"
    printf 'parallelism=%s\n' "$PARALLELISM"
    printf 'wrf_configure_option=%s\n' "$WRF_CONFIGURE_OPTION"
    printf 'wrf_nesting_option=%s\n' "$WRF_NESTING_OPTION"
    printf 'wps_built=%s\n' "$BUILD_WPS"
  } > "$ROOT_DIR/build-manifest.txt"
}

download() {
  local url="$1" destination="$2"
  if [[ -s "$destination" ]]; then
    log "Using cached $(basename "$destination")"
    return
  fi
  log "Downloading $url"
  curl --fail --location --proto '=https' --tlsv1.2 \
    --retry 4 --retry-delay 3 --output "$destination.part" "$url"
  mv -- "$destination.part" "$destination"
}

extract_fresh() {
  local archive="$1" destination="$2"
  if [[ -d "$destination" ]]; then
    log "Using existing source tree $destination"
    return
  fi
  local temporary="$destination.extracting"
  rm -rf -- "$temporary"
  mkdir -p "$temporary"
  tar -xf "$archive" --strip-components=1 -C "$temporary"
  mv -- "$temporary" "$destination"
}

clone_recursive() {
  local repository="$1" tag="$2" destination="$3"
  if [[ -d "$destination/.git" ]]; then
    log "Using existing recursive checkout $destination"
    git -C "$destination" submodule update --init --recursive
    return
  fi
  [[ ! -e "$destination" ]] || {
    printf 'Checkout destination exists but is not a Git checkout: %s\n' "$destination" >&2
    exit 1
  }
  log "Cloning $repository at $tag with all submodules"
  git clone --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules \
    "$repository" "$destination"
}

download_sources() {
  if [[ "$DEPENDENCY_MODE" == local ]]; then
    download "https://www.mpich.org/static/downloads/${MPICH_VERSION}/mpich-${MPICH_VERSION}.tar.gz" \
      "$DOWNLOAD_DIR/mpich-${MPICH_VERSION}.tar.gz"
    download "https://github.com/Unidata/netcdf-c/archive/refs/tags/v${NETCDF_C_VERSION}.tar.gz" \
      "$DOWNLOAD_DIR/netcdf-c-${NETCDF_C_VERSION}.tar.gz"
    download "https://downloads.unidata.ucar.edu/netcdf-fortran/${NETCDF_FORTRAN_VERSION}/netcdf-fortran-${NETCDF_FORTRAN_VERSION}.tar.gz" \
      "$DOWNLOAD_DIR/netcdf-fortran-${NETCDF_FORTRAN_VERSION}-release.tar.gz"
    extract_fresh "$DOWNLOAD_DIR/mpich-${MPICH_VERSION}.tar.gz" "$SOURCE_DIR/mpich-${MPICH_VERSION}"
    extract_fresh "$DOWNLOAD_DIR/netcdf-c-${NETCDF_C_VERSION}.tar.gz" "$SOURCE_DIR/netcdf-c-${NETCDF_C_VERSION}"
    extract_fresh "$DOWNLOAD_DIR/netcdf-fortran-${NETCDF_FORTRAN_VERSION}-release.tar.gz" "$SOURCE_DIR/netcdf-fortran-${NETCDF_FORTRAN_VERSION}-release"
  fi
  clone_recursive "https://github.com/wrf-model/WRF.git" "v${WRF_VERSION}" "$WRF_SOURCE_DIR"
  if [[ "$BUILD_WPS" == yes || "$CONFIGURE_HELP" == 1 ]]; then
    clone_recursive "https://github.com/wrf-model/WPS.git" "v${WPS_VERSION}" "$WPS_SOURCE_DIR"
  fi

  # Release scripts use an absolute /bin/csh shebang. Point them at the local
  # tcsh when the host has no /bin/csh; tcsh is compatible with these scripts.
  if [[ ! -x /bin/csh && -x "$AUX_DIR/bin/tcsh" ]]; then
    find "$WRF_SOURCE_DIR" "$WPS_SOURCE_DIR" \
      -type f -exec sed -i "1s|^#!/bin/csh|#!$AUX_DIR/bin/tcsh|" {} +
  fi
}

write_environment_file() {
  local path_prefix="$AUX_DIR/bin"
  local library_prefix=""
  if [[ "$DEPENDENCY_MODE" == local ]]; then
    path_prefix="$path_prefix:$INSTALL_DIR/mpich/bin:$INSTALL_DIR/netcdf/bin"
    library_prefix="$INSTALL_DIR/mpich/lib:$INSTALL_DIR/netcdf/lib:"
  fi
  cat > "$ROOT_DIR/activate.sh" <<EOF
# Source this file to use this local WRF toolchain.
export WRF_LOCAL_ROOT="$ROOT_DIR"
export PATH="$path_prefix:\${PATH}"
export NETCDF="$NETCDF_PREFIX"
export WRF_DIR="$WRF_SOURCE_DIR"
export LD_LIBRARY_PATH="$library_prefix\${LD_LIBRARY_PATH:-}"
EOF
}

compiler_menu_pattern() {
  case "$COMPILER_FAMILY" in
    gnu) printf 'gnu|gfortran' ;;
    intel) printf 'intel|ifort|ifx' ;;
    nvhpc) printf 'nvidia|nvhpc|pgi|nvfortran|pgf90' ;;
  esac
}

menu_option_from_file() {
  local menu_file="$1" family_pattern="$2" parallel_pattern="$3"
  awk -v family="$family_pattern" -v parallel="$parallel_pattern" '
    tolower($0) ~ family && tolower($0) ~ parallel && match($0, /^[[:space:]]*[0-9]+\./) {
      value=substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", value); print value; exit
    }
  ' "$menu_file"
}

resolve_wrf_option() {
  [[ "$WRF_CONFIGURE_OPTION" == auto ]] || return
  local menu_file="$LOG_DIR/wrf-configure-menu.txt" pattern parallel_pattern option
  pattern="$(compiler_menu_pattern)"
  parallel_pattern="\\($PARALLELISM\\)"
  [[ "$PARALLELISM" == 'dm+sm' ]] && parallel_pattern='\(dm\+sm\)'
  (cd "$WRF_SOURCE_DIR" && ./configure </dev/null || true) > "$menu_file" 2>&1
  option="$(menu_option_from_file "$menu_file" "$pattern" "$parallel_pattern")"
  [[ -n "$option" ]] || {
    printf 'Could not resolve a WRF menu entry for compiler=%s parallel=%s.\n' "$COMPILER_FAMILY" "$PARALLELISM" >&2
    printf 'Review %s and rerun with --wrf-option NUMBER.\n' "$menu_file" >&2
    exit 1
  }
  WRF_CONFIGURE_OPTION="$option"
}

resolve_wps_option() {
  [[ "$WPS_CONFIGURE_OPTION" == auto ]] || return
  local menu_file="$LOG_DIR/wps-configure-menu.txt" pattern option
  pattern="$(compiler_menu_pattern)"
  (cd "$WPS_SOURCE_DIR" && WRF_DIR="$WRF_SOURCE_DIR" ./configure --build-grib2-libs </dev/null || true) > "$menu_file" 2>&1
  option="$(menu_option_from_file "$menu_file" "$pattern" '\\(serial\\)')"
  [[ -n "$option" ]] || {
    printf 'Could not resolve a serial WPS menu entry for compiler=%s.\n' "$COMPILER_FAMILY" >&2
    printf 'Review %s and rerun with --wps-option NUMBER.\n' "$menu_file" >&2
    exit 1
  }
  WPS_CONFIGURE_OPTION="$option"
}

build_mpich() {
  local prefix="$INSTALL_DIR/mpich" build="$BUILD_DIR/mpich-${MPICH_VERSION}"
  [[ -x "$prefix/bin/mpif90" ]] && { log "MPICH already installed"; return; }
  mkdir -p "$build"
  log "Configuring MPICH $MPICH_VERSION"
  (cd "$build" && "$SOURCE_DIR/mpich-${MPICH_VERSION}/configure" \
    --prefix="$prefix" CC="$CC" CXX="$CXX" FC="$FC" F77="$F77")
  make -C "$build" -j "$JOBS"
  make -C "$build" install
}

build_netcdf() {
  local prefix="$INSTALL_DIR/netcdf"
  export PATH="$INSTALL_DIR/mpich/bin:$prefix/bin:$PATH"
  if [[ "$PARALLELISM" == dmpar || "$PARALLELISM" == dm+sm ]]; then
    export CC=mpicc CXX=mpicxx FC=mpif90 F77=mpif77
  fi
  export CPPFLAGS="-I$prefix/include"
  export LDFLAGS="-L$prefix/lib"

  if [[ ! -f "$prefix/.wrf-classic-netcdf-c-${NETCDF_C_VERSION}" ]]; then
    local c_build="$BUILD_DIR/netcdf-c-${NETCDF_C_VERSION}"
    mkdir -p "$c_build"
    if [[ -f "$c_build/Makefile" ]]; then make -C "$c_build" distclean; fi
    log "Building classic netCDF-C $NETCDF_C_VERSION locally"
    (cd "$c_build" && "$SOURCE_DIR/netcdf-c-${NETCDF_C_VERSION}/configure" \
      --prefix="$prefix" --disable-dap --disable-netcdf-4 --disable-shared)
    make -C "$c_build" -j "$JOBS"
    make -C "$c_build" check
    make -C "$c_build" install
    touch "$prefix/.wrf-classic-netcdf-c-${NETCDF_C_VERSION}"
  fi

  if [[ ! -x "$prefix/bin/nf-config" ]]; then
    local f_build="$BUILD_DIR/netcdf-fortran-${NETCDF_FORTRAN_VERSION}"
    mkdir -p "$f_build"
    log "Building netCDF-Fortran $NETCDF_FORTRAN_VERSION locally"
    if [[ -f "$f_build/Makefile" ]]; then make -C "$f_build" clean; fi
    (cd "$f_build" && LIBS='-lnetcdf' \
      "$SOURCE_DIR/netcdf-fortran-${NETCDF_FORTRAN_VERSION}-release/configure" \
      --prefix="$prefix" --disable-shared)
    # Generated Fortran include files are not fully parallel-safe in this release.
    make -C "$f_build"
    make -C "$f_build" check
    make -C "$f_build" install
  fi
}

configure_wrf() {
  local wrf="$WRF_SOURCE_DIR"
  [[ "$DEPENDENCY_MODE" == local ]] && export PATH="$INSTALL_DIR/mpich/bin:$INSTALL_DIR/netcdf/bin:$PATH"
  export NETCDF="$NETCDF_PREFIX"
  export WRFIO_NCD_LARGE_FILE_SUPPORT=1
  export WRF_CHEM=0
  resolve_wrf_option
  log "Configuring WRF: compiler=$COMPILER_FAMILY, parallel=$PARALLELISM, option=$WRF_CONFIGURE_OPTION, nesting=$WRF_NESTING_OPTION"
  (cd "$wrf" && printf '%s\n%s\n' "$WRF_CONFIGURE_OPTION" "$WRF_NESTING_OPTION" | ./configure)
  [[ -f "$wrf/configure.wrf" ]] || { printf 'WRF configuration failed.\n' >&2; exit 1; }
  if [[ "$PARALLELISM" == dmpar || "$PARALLELISM" == dm+sm ]]; then
    grep -Eq 'DM[_ ]PARALLEL|dmpar|mpif90|mpiifort|mpiifx|nvfortran' "$wrf/configure.wrf" || {
      printf 'Generated configure.wrf does not appear to enable MPI.\n' >&2
      exit 1
    }
  fi
}

build_wrf() {
  local wrf="$WRF_SOURCE_DIR"
  local marker="$wrf/.wrf-autocompiler-config"
  local signature="compiler=$COMPILER_FAMILY;cc=$(command -v "$CC");fc=$(command -v "$FC");dependencies=$DEPENDENCY_MODE;netcdf=$NETCDF_PREFIX;parallel=$PARALLELISM;target=$WRF_TARGET;nesting=$WRF_NESTING_OPTION;wrf_option=$WRF_CONFIGURE_OPTION"
  if ((RECONFIGURE)) && [[ -x "$wrf/clean" ]]; then
    log "Explicit reconfiguration requested; cleaning generated WRF objects"
    (cd "$wrf" && ./clean -a)
    rm -f -- "$marker"
  fi
  if [[ -x "$wrf/main/wrf.exe" || -f "$marker" ]]; then
    if [[ -f "$marker" && "$(<"$marker")" == "$signature" ]]; then
      log "WRF already built with the requested configuration"
      return
    fi
    printf 'Existing WRF products do not have the requested configuration fingerprint.\n' >&2
    printf 'Use a different WRF_BUILD_ROOT or explicitly pass --reconfigure.\n' >&2
    exit 1
  fi
  configure_wrf
  log "Compiling WRF target $WRF_TARGET (this can take a long time)"
  (cd "$wrf" && ./compile -j "$JOBS" "$WRF_TARGET" 2>&1 | tee "$LOG_DIR/wrf-compile.log")
  if [[ "$WRF_TARGET" == em_real ]]; then
    local executable
    for executable in wrf.exe real.exe ndown.exe tc.exe; do
      [[ -x "$wrf/main/$executable" ]] || { printf 'Missing WRF executable: %s\n' "$executable" >&2; exit 1; }
    done
  else
    find "$wrf/main" -maxdepth 1 -type f -perm -u+x -name '*.exe' -print | grep -q . || {
      printf 'No executable was found for WRF target %s.\n' "$WRF_TARGET" >&2
      exit 1
    }
  fi
  printf '%s\n' "$signature" > "$marker"
}

configure_wps() {
  local wps="$WPS_SOURCE_DIR"
  [[ "$DEPENDENCY_MODE" == local ]] && export PATH="$INSTALL_DIR/mpich/bin:$INSTALL_DIR/netcdf/bin:$PATH"
  export NETCDF="$NETCDF_PREFIX"
  export WRF_DIR="$WRF_SOURCE_DIR"
  # WPS' bundled libpng configure check does not reliably translate its
  # --with-zlib-prefix argument into compiler/linker search paths. Supply
  # those paths explicitly so no system zlib/libpng development files are
  # required.
  export CPPFLAGS="-I$wps/grib2/include"
  export LDFLAGS="-L$wps/grib2/lib"
  resolve_wps_option
  log "Configuring WPS: compiler=$COMPILER_FAMILY, option=$WPS_CONFIGURE_OPTION with bundled GRIB2 libraries"
  (cd "$wps" && printf '%s\n' "$WPS_CONFIGURE_OPTION" | ./configure --build-grib2-libs)
  [[ -f "$wps/configure.wps" ]] || { printf 'WPS configuration failed.\n' >&2; exit 1; }
  grep -Eqi "$FC|gfortran|ifort|ifx|nvfortran|PGI|Intel|GNU|NVIDIA" "$wps/configure.wps" || {
    printf 'Generated configure.wps does not appear to use the selected compiler family.\n' >&2
    exit 1
  }
}

build_wps() {
  local wps="$WPS_SOURCE_DIR"
  local marker="$wps/.wrf-autocompiler-config"
  local signature="compiler=$COMPILER_FAMILY;fc=$(command -v "$FC");dependencies=$DEPENDENCY_MODE;netcdf=$NETCDF_PREFIX;wps_option=$WPS_CONFIGURE_OPTION;wrf_target=$WRF_TARGET"
  if ((RECONFIGURE)) && [[ -x "$wps/clean" ]]; then
    log "Explicit reconfiguration requested; cleaning generated WPS objects"
    (cd "$wps" && ./clean -a)
    rm -f -- "$marker"
  fi
  if [[ -x "$wps/geogrid.exe" || -x "$wps/ungrib.exe" || -x "$wps/metgrid.exe" || -f "$marker" ]]; then
    if [[ -f "$marker" && "$(<"$marker")" == "$signature" && -x "$wps/geogrid.exe" && -x "$wps/ungrib.exe" && -x "$wps/metgrid.exe" ]]; then
      log "WPS already built with the requested configuration"
      return
    fi
    printf 'Existing WPS products do not have the requested configuration fingerprint.\n' >&2
    printf 'Use a different WRF_BUILD_ROOT or explicitly pass --reconfigure.\n' >&2
    exit 1
  fi
  configure_wps

  # Prebuild the two compression libraries in dependency order. WPS' external
  # Makefile suppresses dependency failures, which can otherwise hide a failed
  # libpng zlib probe until ungrib.exe is missing at the end of the build.
  if [[ ! -f "$wps/grib2/lib/libz.a" ]]; then
    log "Building WPS bundled zlib locally"
    (cd "$wps/external/zlib-1.2.11" && \
      ./configure --prefix="$wps/grib2" --static && make -j "$JOBS" && make install)
  fi
  if [[ ! -f "$wps/grib2/lib/libpng.a" ]]; then
    log "Building WPS bundled libpng locally"
    (cd "$wps/external/libpng-1.6.37" && \
      { [[ ! -f Makefile ]] || make distclean; } && \
      CPPFLAGS="-I$wps/grib2/include" LDFLAGS="-L$wps/grib2/lib" \
      ./configure --prefix="$wps/grib2" --disable-shared && \
      make -j "$JOBS" && make install)
  fi
  log "Compiling WPS"
  (cd "$wps" && ./compile 2>&1 | tee "$LOG_DIR/wps-compile.log")
  local executable
  for executable in geogrid.exe ungrib.exe metgrid.exe; do
    [[ -x "$wps/$executable" ]] || { printf 'Missing WPS executable: %s\n' "$executable" >&2; exit 1; }
  done
  printf '%s\n' "$signature" > "$marker"
}

show_configure_help() {
  log "WRF configure menu"
  (cd "$WRF_SOURCE_DIR" && ./configure </dev/null || true)
  log "WPS configure menu"
  (cd "$WPS_SOURCE_DIR" && WRF_DIR="$WRF_SOURCE_DIR" \
    ./configure --build-grib2-libs </dev/null || true)
}

main() {
  require_commands
  initialize_modules
  log "Detected compiler families"
  report_compilers
  select_compiler
  check_toolchain
  select_dependencies
  if ((PREFLIGHT_ONLY)); then
    log "Preflight passed: compiler=$COMPILER_FAMILY dependencies=$DEPENDENCY_MODE parallel=$PARALLELISM target=$WRF_TARGET WPS=$BUILD_WPS"
    log "No sources were downloaded and nothing was compiled"
    exit 0
  fi
  bootstrap_build_tools
  download_sources
  if ((CONFIGURE_HELP)); then show_configure_help; exit 0; fi
  if [[ "$DEPENDENCY_MODE" == local ]]; then
    build_mpich
    build_netcdf
  fi
  write_environment_file
  build_wrf
  [[ "$BUILD_WPS" == yes ]] && build_wps
  write_build_manifest
  log "Build complete"
  printf 'WRF: %s\nWPS: %s\nEnvironment: source %s\nLog: %s\n' \
    "$WRF_SOURCE_DIR" "$WPS_SOURCE_DIR" \
    "$ROOT_DIR/activate.sh" "$RUN_LOG"
}

main "$@"
