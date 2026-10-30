#!/bin/sh
# Build libheif + libde265 + dav1d + LibRaw for Android and stage them into
# android/app/src/main/jniLibs/<abi>/.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NDK=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
[ -n "$NDK" ] || { echo "error: set ANDROID_NDK_HOME or ANDROID_NDK_ROOT" >&2; exit 1; }
[ -d "$NDK" ] || { echo "error: NDK not found at $NDK" >&2; exit 1; }

# Git Bash hands us a Windows-style path; the NDK tools need POSIX form.
if command -v cygpath >/dev/null 2>&1; then
  NDK=$(cygpath -u "$NDK")
fi
NDK=$(CDPATH= cd -- "$NDK" && pwd)

API=26
SRC="$ROOT/third_party/stills/src"
BUILD="$ROOT/third_party/stills/build"
STAGE="$ROOT/third_party/stills/stage"
JNI="$ROOT/android/app/src/main/jniLibs"

PREBUILT="$NDK/toolchains/llvm/prebuilt"
[ -d "$PREBUILT" ] || { echo "error: no LLVM prebuilt dir in $NDK" >&2; exit 1; }

case $(uname -s) in
  Linux)                        host_glob='linux-*' ;;
  Darwin)                       host_glob='darwin-*' ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) host_glob='windows-*' ;;
  *) echo "error: unsupported host $(uname -s)" >&2; exit 1 ;;
esac

HOST_TAG=
for d in "$PREBUILT"/$host_glob; do
  [ -d "$d" ] && HOST_TAG=$(basename "$d") && break
done
[ -n "$HOST_TAG" ] || { echo "error: no $host_glob toolchain in $PREBUILT" >&2; exit 1; }

TOOLCHAIN="$PREBUILT/$HOST_TAG/bin"
AR="$TOOLCHAIN/llvm-ar"
RANLIB="$TOOLCHAIN/llvm-ranlib"
STRIP="$TOOLCHAIN/llvm-strip"

# --- sources ---------------------------------------------------------------
mkdir -p "$SRC"

clone_tag() { # url tag dir
  [ -d "$3/.git" ] && return 0
  git clone --depth 1 --branch "$2" "$1" "$3"
}

clone_tag https://github.com/strukturag/libheif.git          v1.19.7 "$SRC/libheif"
clone_tag https://github.com/strukturag/libde265.git         v1.0.15 "$SRC/libde265"
clone_tag https://code.videolan.org/videolan/dav1d.git       1.5.0   "$SRC/dav1d"
clone_tag https://github.com/LibRaw/LibRaw.git               0.21.3  "$SRC/libraw"

if [ ! -d "$SRC/libraw-cmake/.git" ]; then
  git clone https://github.com/LibRaw/LibRaw-cmake.git "$SRC/libraw-cmake"
  git -C "$SRC/libraw-cmake" checkout eb98e4325aef2ce85d2eb031c2ff18640ca616d3
fi

# --- helpers ---------------------------------------------------------------
find_lib() { # dir name-pattern
  find "$1" \( -type f -o -type l \) -name "$2" 2>/dev/null | head -n 1
}

mkdir -p "$BUILD" "$STAGE" "$JNI"

for abi in arm64-v8a armeabi-v7a; do
  case $abi in
    arm64-v8a)   triple=aarch64-linux-android$API;  cpu_family=aarch64; cpu=aarch64 ;;
    armeabi-v7a) triple=armv7a-linux-androideabi$API; cpu_family=arm;   cpu=armv7 ;;
  esac

  prefix="$STAGE/$abi"
  jnidir="$JNI/$abi"

  if [ -f "$jnidir/libheif.so" ] && [ -f "$jnidir/libde265.so" ] && [ -f "$jnidir/libraw.so" ]; then
    echo "== $abi: already staged, skipping"
    continue
  fi

  echo "== $abi"
  mkdir -p "$jnidir"

  # --- dav1d (static, header + lib go into the stage prefix) ---------------
  dav1d_build="$SRC/dav1d/build-android-$abi"
  mkdir -p "$dav1d_build"
  cross="$dav1d_build/cross.ini"
  {
    printf "[binaries]\n"
    printf "c = '%s'\n"       "$TOOLCHAIN/$triple-clang"
    printf "cpp = '%s'\n"     "$TOOLCHAIN/$triple-clang++"
    printf "ar = '%s'\n"      "$AR"
    printf "ranlib = '%s'\n"  "$RANLIB"
    printf "strip = '%s'\n"   "$STRIP"
    printf "\n[built-in options]\n"
    printf "c_link_args = []\n"
    printf "cpp_link_args = []\n"
    printf "b_staticpic = true\n"
    printf "\n[host_machine]\n"
    printf "system = 'android'\n"
    printf "cpu_family = '%s'\n" "$cpu_family"
    printf "cpu = '%s'\n"        "$cpu"
    printf "endian = 'little'\n"
  } > "$cross"

  rm -rf "$dav1d_build/build"
  meson setup "$dav1d_build/build" \
    --cross-file "$cross" \
    --buildtype=release \
    --default-library=static \
    --prefix="$prefix" \
    -Denable_tools=false \
    -Denable_tests=false \
    -Denable_docs=false \
    -Denable_examples=false
  meson compile -C "$dav1d_build/build"
  meson install -C "$dav1d_build/build"

  # --- libde265 (shared, and it must carry its own SONAME) ----------------
  de265_build="$BUILD/libde265-$abi"
  cmake -S "$SRC/libde265" -B "$de265_build" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="android-$API" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_SDL=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS=-Wl,-soname,libde265.so
  cmake --build "$de265_build" -j
  cmake --build "$de265_build" --target install

  # --- libheif (shared) ---------------------------------------------------
  heif_build="$BUILD/libheif-$abi"
  cmake -S "$SRC/libheif" -B "$heif_build" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="android-$API" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DWITH_LIBDE265=ON \
    -DWITH_DAV1D=ON \
    -DWITH_X265=OFF \
    -DWITH_AOM_DECODER=OFF \
    -DWITH_AOM_ENCODER=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_GDK_PIXBUF=OFF \
    -DENABLE_PLUGIN_LOADING=OFF \
    -DBUILD_TESTING=OFF \
    -DLIBDE265_INCLUDE_DIR="$prefix/include" \
    -DLIBDE265_LIBRARY="$prefix/lib/libde265.so" \
    -DDAV1D_INCLUDE_DIR="$prefix/include" \
    -DDAV1D_LIBRARY="$prefix/lib/libdav1d.a"
  cmake --build "$heif_build" -j

  # --- LibRaw (shared, via LibRaw-cmake) ----------------------------------
  raw_build="$BUILD/libraw-$abi"
  cmake -S "$SRC/libraw-cmake" -B "$raw_build" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="android-$API" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DLIBRAW_PATH="$SRC/libraw" \
    -DENABLE_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=ON
  cmake --build "$raw_build" -j

  # --- stage into jniLibs (follow symlinks, never ship libdav1d.so) ------
  for spec in "libheif:$heif_build:libheif.so*" "libde265:$de265_build:libde265.so*" "libraw:$raw_build:libraw.so*"; do
    name=${spec%%:*}
    rest=${spec#*:}
    dir=${rest%%:*}
    pattern=${rest#*:}
    src=$(find_lib "$dir" "$pattern")
    [ -n "$src" ] || { echo "error: $name library not found under $dir" >&2; exit 1; }
    cp -L "$src" "$jnidir/$name.so"
    "$STRIP" --strip-unneeded "$jnidir/$name.so" 2>/dev/null || true
  done
done

echo "done: $JNI"
