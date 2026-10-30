#!/bin/sh
# Build the native still-image decoders for Linux x64 into third_party/stills.
set -eu

# Pinned upstream versions and URLs.
LIBHEIF_VERSION="1.19.7"
LIBHEIF_URL="https://github.com/strukturag/libheif.git"
LIBHEIF_TAG="v${LIBHEIF_VERSION}"

LIBDE265_VERSION="1.0.15"
LIBDE265_URL="https://github.com/strukturag/libde265.git"
LIBDE265_TAG="v${LIBDE265_VERSION}"

DAV1D_VERSION="1.5.0"
DAV1D_URL="https://code.videolan.org/videolan/dav1d.git"
DAV1D_TAG="${DAV1D_VERSION}"

LIBRAW_VERSION="0.21.3"
LIBRAW_URL="https://github.com/LibRaw/LibRaw.git"
LIBRAW_TAG="${LIBRAW_VERSION}"

LIBRAW_CMAKE_COMMIT="eb98e4325aef2ce85d2eb031c2ff18640ca616d3"
LIBRAW_CMAKE_URL="https://github.com/LibRaw/LibRaw-cmake.git"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(dirname -- "${SCRIPT_DIR}")
STILLS_ROOT="${REPO_ROOT}/third_party/stills"
SRC_DIR="${STILLS_ROOT}/src"
BUILD_DIR="${STILLS_ROOT}/build"
OUT_DIR="${STILLS_ROOT}/linux-x64"
LIB_DIR="${OUT_DIR}/lib"
INCLUDE_DIR="${OUT_DIR}/include"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

run() {
    printf '+' >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    "$@"
}

component_present() {
    [ -e "${LIB_DIR}/$1" ]
}

ensure_source() {
    name=$1
    url=$2
    ref=$3
    mode=$4
    dest="${SRC_DIR}/${name}"

    if [ -d "${dest}/.git" ]; then
        printf '    using existing clone: %s\n' "${dest}" >&2
        return 0
    fi
    if [ -e "${dest}" ]; then
        die "${dest} exists but is not a git clone; remove it and rerun."
    fi

    if [ "${mode}" = "commit" ]; then
        run git clone "${url}" "${dest}"
        run git -C "${dest}" checkout --detach "${ref}"
    else
        run git clone --depth 1 --branch "${ref}" "${url}" "${dest}"
    fi
}

copy_stage() {
    stage_dir=$1

    if [ -d "${stage_dir}/lib" ]; then
        for file in "${stage_dir}"/lib/*.so*; do
            [ -e "${file}" ] || continue
            cp -L "${file}" "${LIB_DIR}/"
        done
    fi

    if [ -d "${stage_dir}/include" ]; then
        cp -R "${stage_dir}/include/." "${INCLUDE_DIR}/"
    fi
}

ensure_canonical() {
    name=$1

    if [ -e "${LIB_DIR}/${name}" ]; then
        return 0
    fi

    set -- "${LIB_DIR}/${name}".*
    if [ -e "$1" ]; then
        cp -L "$1" "${LIB_DIR}/${name}"
        return 0
    fi

    die "${name} was not produced under ${LIB_DIR}"
}

build_cmake() {
    name=$1
    source_dir=$2
    shift 2

    build_dir="${BUILD_DIR}/${name}"
    stage_dir="${BUILD_DIR}/${name}-stage"
    rm -rf "${stage_dir}"

    run cmake -S "${source_dir}" -B "${build_dir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${stage_dir}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        "$@"
    run cmake --build "${build_dir}" --config Release
    run cmake --install "${build_dir}" --config Release
    copy_stage "${stage_dir}"
}

build_dav1d() {
    source_dir=$(ensure_source "dav1d" "${DAV1D_URL}" "${DAV1D_TAG}" "tag")
    build_dir="${BUILD_DIR}/dav1d"
    stage_dir="${BUILD_DIR}/dav1d-stage"
    rm -rf "${stage_dir}"

    if [ -f "${build_dir}/build.ninja" ]; then
        run meson setup --reconfigure "${build_dir}" --prefix="${stage_dir}"
    else
        run meson setup "${build_dir}" "${source_dir}" \
            --buildtype=release \
            --default-library=shared \
            --prefix="${stage_dir}" \
            -Denable_tools=false \
            -Denable_tests=false \
            -Denable_docs=false \
            -Denable_examples=false
    fi
    run meson compile -C "${build_dir}"
    run meson install -C "${build_dir}"
    copy_stage "${stage_dir}"
}

missing=""
for tool in git cmake ninja meson; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        missing="${missing} ${tool}"
    fi
done
if [ -n "${missing}" ]; then
    die "missing required commands:${missing}. Install them and rerun."
fi

for dir in "${SRC_DIR}" "${BUILD_DIR}" "${LIB_DIR}" "${INCLUDE_DIR}"; do
    mkdir -p "${dir}"
done

printf 'Fetching and building still codecs into %s\n' "${OUT_DIR}"

printf '==> dav1d\n'
if component_present "libdav1d.so"; then
    printf '    already present, skipping\n'
else
    build_dav1d
    ensure_canonical "libdav1d.so"
fi

printf '==> libde265\n'
if component_present "libde265.so"; then
    printf '    already present, skipping\n'
else
    libde265_source=$(ensure_source "libde265" "${LIBDE265_URL}" "${LIBDE265_TAG}" "tag")
    build_cmake "libde265" "${libde265_source}" \
        -DBUILD_SHARED_LIBS=ON \
        -DENABLE_SDL=OFF
    ensure_canonical "libde265.so"
fi

printf '==> libheif\n'
if component_present "libheif.so"; then
    printf '    already present, skipping\n'
else
    libheif_source=$(ensure_source "libheif" "${LIBHEIF_URL}" "${LIBHEIF_TAG}" "tag")
    build_cmake "libheif" "${libheif_source}" \
        -DWITH_LIBDE265=ON \
        -DWITH_DAV1D=ON \
        -DWITH_X265=OFF \
        -DWITH_AOM=OFF \
        -DWITH_EXAMPLES=OFF \
        -DBUILD_SHARED_LIBS=ON \
        -DENABLE_PLUGIN_LOADING=OFF \
        -DLIBDE265_INCLUDE_DIR="${INCLUDE_DIR}" \
        -DLIBDE265_LIBRARY="${LIB_DIR}/libde265.so" \
        -DDAV1D_INCLUDE_DIR="${INCLUDE_DIR}" \
        -DDAV1D_LIBRARY="${LIB_DIR}/libdav1d.so"
    ensure_canonical "libheif.so"
fi

printf '==> LibRaw\n'
if component_present "libraw.so"; then
    printf '    already present, skipping\n'
else
    libraw_source=$(ensure_source "libraw" "${LIBRAW_URL}" "${LIBRAW_TAG}" "tag")
    libraw_cmake_source=$(ensure_source "libraw-cmake" "${LIBRAW_CMAKE_URL}" "${LIBRAW_CMAKE_COMMIT}" "commit")
    build_cmake "libraw" "${libraw_cmake_source}" \
        -DLIBRAW_PATH="${libraw_source}" \
        -DENABLE_EXAMPLES=OFF \
        -DBUILD_SHARED_LIBS=ON
    ensure_canonical "libraw.so"
fi

printf '\nDone. Libraries are in %s\n' "${LIB_DIR}"
for file in "${LIB_DIR}"/*.so*; do
    [ -e "${file}" ] || continue
    printf '    %s\n' "$(basename "${file}")"
done
