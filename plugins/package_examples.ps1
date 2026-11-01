$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$source = Join-Path $root 'examples'
$dest = Join-Path $root 'zips'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Get-ChildItem $source -Directory | ForEach-Object {
  $zip = Join-Path $dest ($_.Name + '.zip')
  if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
  [System.IO.Compression.ZipFile]::CreateFromDirectory($_.FullName, $zip)
  Write-Output "Packaged $($_.Name) -> $zip"
}

Get-ChildItem $dest -Filter *.zip | Select-Object Name, Length
