#Requires -Version 5.1
<#
.SYNOPSIS
    Fetch and build the native still-image decoders for Windows x64.

.DESCRIPTION
    Builds libheif, libde265, dav1d, and LibRaw from pinned sources and stages
    the DLLs, import libraries, and headers under third_party/stills/win-x64.

    Run from an x64 Native Tools Command Prompt for VS 2022, or a VS 2022
    Developer PowerShell, so that cl.exe, cmake, ninja, meson, and nasm are
    available. Components whose output already exists are skipped.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Pinned upstream versions.
$LibheifVersion = '1.19.7'
$Libde265Version = '1.0.15'
$Dav1dVersion = '1.5.0'
$LibRawVersion = '0.21.3'
$LibRawCmakeCommit = 'eb98e4325aef2ce85d2eb031c2ff18640ca616d3'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$StillsRoot = Join-Path $RepoRoot 'third_party/stills'
$SrcDir = Join-Path $StillsRoot 'src'
$BuildDir = Join-Path $StillsRoot 'build'
$OutDir = Join-Path $StillsRoot 'win-x64'
$BinDir = Join-Path $OutDir 'bin'
$LibDir = Join-Path $OutDir 'lib'
$IncludeDir = Join-Path $OutDir 'include'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Command' failed with exit code $LASTEXITCODE."
    }
}

function Test-Component {
    param(
        [Parameter(Mandatory = $true)][string[]]$DllNames,
        [Parameter(Mandatory = $true)][string[]]$LibNames
    )
    $dll = $DllNames |
        ForEach-Object { Join-Path $BinDir $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    $lib = $LibNames |
        ForEach-Object { Join-Path $LibDir $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    return ([bool]$dll -and [bool]$lib)
}

function Assert-Component {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$DllNames,
        [Parameter(Mandatory = $true)][string[]]$LibNames
    )
    if (-not (Test-Component -DllNames $DllNames -LibNames $LibNames)) {
        throw "$Name build finished but its DLL/import library was not found under $OutDir."
    }
}

function Copy-Stage {
    param([Parameter(Mandatory = $true)][string]$StageDir)

    # Meson may install DLLs under lib/ on Windows; scan both staging dirs so
    # the layout of each build system does not matter.
    foreach ($sub in @('bin', 'lib')) {
        $subDir = Join-Path $StageDir $sub
        Get-ChildItem -LiteralPath $subDir -Filter '*.dll' -File -ErrorAction SilentlyContinue |
            Copy-Item -Destination $BinDir -Force
        Get-ChildItem -LiteralPath $subDir -Filter '*.lib' -File -ErrorAction SilentlyContinue |
            Copy-Item -Destination $LibDir -Force
    }

    $stageInclude = Join-Path $StageDir 'include'
    if (Test-Path -LiteralPath $stageInclude) {
        Copy-Item -Path (Join-Path $stageInclude '*') -Destination $IncludeDir -Recurse -Force
    }
}

function Get-Source {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Tag,
        [string]$Commit
    )
    $dest = Join-Path $SrcDir $Name
    if (Test-Path -LiteralPath (Join-Path $dest '.git')) {
        Write-Host "    using existing clone: $dest"
        return $dest
    }
    if (Test-Path -LiteralPath $dest) {
        throw "$dest exists but is not a git clone; remove it and rerun."
    }

    if ($Commit) {
        Invoke-Checked -Command 'git' -Arguments @('clone', $Url, $dest)
        Invoke-Checked -Command 'git' -Arguments @('-C', $dest, 'checkout', '--detach', $Commit)
    }
    else {
        Invoke-Checked -Command 'git' -Arguments @('clone', '--depth', '1', '--branch', $Tag, $Url, $dest)
    }
    return $dest
}

function Build-CMake {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [string[]]$Options = @()
    )
    $build = Join-Path $BuildDir $Name
    $stage = Join-Path $BuildDir "$Name-stage"
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }

    $configure = @(
        '-S', $SourceDir,
        '-B', $build,
        '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_INSTALL_PREFIX=$stage"
    ) + $Options
    Invoke-Checked -Command 'cmake' -Arguments $configure
    Invoke-Checked -Command 'cmake' -Arguments @('--build', $build, '--config', 'Release')
    Invoke-Checked -Command 'cmake' -Arguments @('--install', $build, '--config', 'Release')
    Copy-Stage -StageDir $stage
}

# Prerequisites.
$required = @('git', 'cmake', 'ninja', 'meson', 'nasm', 'cl')
$missing = @($required | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($missing.Count -gt 0) {
    throw @"
Missing prerequisites: $($missing -join ', ').

Run this script from an x64 Native Tools Command Prompt for VS 2022 (or a
VS 2022 Developer PowerShell) with CMake, Ninja, Meson, and NASM on PATH.
"@
}
if ($env:VSCMD_ARG_TGT_ARCH -and $env:VSCMD_ARG_TGT_ARCH -ne 'x64') {
    throw "This script builds win-x64, but the developer shell targets '$env:VSCMD_ARG_TGT_ARCH'."
}

foreach ($dir in @($SrcDir, $BuildDir, $BinDir, $LibDir, $IncludeDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Write-Host "Fetching and building still codecs into $OutDir"

# dav1d (Meson only; it has no CMake build).
Write-Host '==> dav1d'
if (Test-Component -DllNames @('dav1d.dll') -LibNames @('dav1d.lib', 'libdav1d.lib')) {
    Write-Host '    already present, skipping'
}
else {
    $src = Get-Source -Name 'dav1d' -Url 'https://github.com/videolan/dav1d.git' -Tag $Dav1dVersion
    $build = Join-Path $BuildDir 'dav1d'
    $stage = Join-Path $BuildDir 'dav1d-stage'
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }

    $setup = @('setup', $build, $src,
        '--buildtype=release',
        '--default-library=shared',
        "--prefix=$stage",
        '-Denable_tools=false',
        '-Denable_tests=false',
        '-Denable_docs=false',
        '-Denable_examples=false')
    if (Test-Path -LiteralPath (Join-Path $build 'build.ninja')) {
        $setup = @('setup', '--reconfigure', $build)
    }
    Invoke-Checked -Command 'meson' -Arguments $setup
    Invoke-Checked -Command 'meson' -Arguments @('compile', '-C', $build)
    Invoke-Checked -Command 'meson' -Arguments @('install', '-C', $build)
    Copy-Stage -StageDir $stage
    Assert-Component -Name 'dav1d' -DllNames @('dav1d.dll') -LibNames @('dav1d.lib', 'libdav1d.lib')
}

# libde265.
Write-Host '==> libde265'
$de265Dlls = @('libde265.dll', 'de265.dll')
$de265Libs = @('libde265.lib', 'de265.lib')
if (Test-Component -DllNames $de265Dlls -LibNames $de265Libs) {
    Write-Host '    already present, skipping'
}
else {
    $src = Get-Source -Name 'libde265' -Url 'https://github.com/strukturag/libde265.git' -Tag "v$Libde265Version"
    Build-CMake -Name 'libde265' -SourceDir $src -Options @(
        '-DBUILD_SHARED_LIBS=ON',
        '-DENABLE_SDL=OFF'
    )
    Assert-Component -Name 'libde265' -DllNames $de265Dlls -LibNames $de265Libs
}

# libheif, linked against the staged libde265 and dav1d.
Write-Host '==> libheif'
$heifDlls = @('heif.dll', 'libheif.dll')
$heifLibs = @('heif.lib', 'libheif.lib')
if (Test-Component -DllNames $heifDlls -LibNames $heifLibs) {
    Write-Host '    already present, skipping'
}
else {
    $de265Library = $de265Libs |
        ForEach-Object { Join-Path $LibDir $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    $dav1dLibrary = @('dav1d.lib', 'libdav1d.lib') |
        ForEach-Object { Join-Path $LibDir $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $de265Library -or -not $dav1dLibrary) {
        throw 'libheif needs the libde265 and dav1d import libraries; build those first.'
    }

    $src = Get-Source -Name 'libheif' -Url 'https://github.com/strukturag/libheif.git' -Tag "v$LibheifVersion"
    Build-CMake -Name 'libheif' -SourceDir $src -Options @(
        '-DBUILD_SHARED_LIBS=ON',
        '-DWITH_LIBDE265=ON',
        '-DWITH_DAV1D=ON',
        '-DWITH_X265=OFF',
        '-DWITH_AOM=OFF',
        '-DWITH_AOM_DECODER=OFF',
        '-DWITH_AOM_ENCODER=OFF',
        '-DWITH_EXAMPLES=OFF',
        '-DWITH_GDK_PIXBUF=OFF',
        '-DBUILD_TESTING=OFF',
        '-DENABLE_PLUGIN_LOADING=OFF',
        "-DLIBDE265_INCLUDE_DIR=$IncludeDir",
        "-DLIBDE265_LIBRARY=$de265Library",
        "-DDAV1D_INCLUDE_DIR=$IncludeDir",
        "-DDAV1D_LIBRARY=$dav1dLibrary"
    )
    Assert-Component -Name 'libheif' -DllNames $heifDlls -LibNames $heifLibs
}

# LibRaw via the LibRaw-cmake wrapper (the main repo has no CMakeLists.txt).
Write-Host '==> LibRaw'
$rawDlls = @('raw.dll', 'libraw.dll')
$rawLibs = @('raw.lib', 'libraw.lib')
if (Test-Component -DllNames $rawDlls -LibNames $rawLibs) {
    Write-Host '    already present, skipping'
}
else {
    $rawSource = Get-Source -Name 'libraw' -Url 'https://github.com/LibRaw/LibRaw.git' -Tag $LibRawVersion
    $wrapperSource = Get-Source -Name 'libraw-cmake' -Url 'https://github.com/LibRaw/LibRaw-cmake.git' -Commit $LibRawCmakeCommit
    Build-CMake -Name 'libraw' -SourceDir $wrapperSource -Options @(
        "-DLIBRAW_PATH=$rawSource",
        '-DENABLE_EXAMPLES=OFF',
        '-DBUILD_SHARED_LIBS=ON'
    )
    Assert-Component -Name 'LibRaw' -DllNames $rawDlls -LibNames $rawLibs
}

Write-Host ''
Write-Host "Done. Libraries are in $OutDir"
Get-ChildItem -LiteralPath $BinDir -Filter '*.dll' -File | ForEach-Object {
    Write-Host "    $($_.Name)"
}
