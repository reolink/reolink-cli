# reolink-cli one-line installer (Windows).
#
#   iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 | iex
#
# Downloads the latest release for Windows x64, installs it to
# %USERPROFILE%\.local\bin, adds it to your user PATH, and initializes config.
# For AI agents use `npx skills add reolink/reolink-cli` instead.
$ErrorActionPreference = 'Stop'

$Repo   = if ($env:REOLINK_REPO)   { $env:REOLINK_REPO }   else { 'reolink/reolink-cli' }
$Prefix = if ($env:REOLINK_PREFIX) { $env:REOLINK_PREFIX } else { Join-Path $env:USERPROFILE '.local' }
$Bin    = Join-Path $Prefix 'bin'

$headers = @{ 'User-Agent' = 'reolink-cli-install' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }

Write-Host "==> resolving latest release of $Repo"
$rel = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/latest"
$tag = $rel.tag_name
if (-not $tag) { throw "could not resolve the latest release (public repo? set GITHUB_TOKEN if private)" }
$ver   = $tag.TrimStart('v')
# Release archives carry the build flavour in the name so internal (Song P2P)
# and customer (LAN-only) builds can never be mistaken for one another. Only
# the external flavour is published here.
$asset = "reolink-cli-$ver-external-windows-x86_64.zip"

$tmp = Join-Path $env:TEMP ("reolink-install-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $zip = Join-Path $tmp $asset
  Write-Host "==> downloading $asset ($tag)"
  Invoke-WebRequest -Headers $headers -Uri "https://github.com/$Repo/releases/download/$tag/$asset" -OutFile $zip

  # Verify against the release's published SHA256SUMS before unpacking. This
  # script installs executables fetched over the network, so an unverified
  # archive is the weakest link; every release ships SHA256SUMS for this.
  Write-Host "==> verifying checksum"
  $sumsPath = Join-Path $tmp "SHA256SUMS"
  try {
    Invoke-WebRequest -Headers $headers -Uri "https://github.com/$Repo/releases/download/$tag/SHA256SUMS" -OutFile $sumsPath
  } catch {
    throw "could not fetch SHA256SUMS for $tag - refusing to install an unverified binary"
  }
  # Split on whitespace rather than regex-matching the line: the asset name
  # would otherwise be interpolated into a pattern, where one mis-escaped
  # character silently matches nothing and blocks every install.
  $expected = $null
  foreach ($line in Get-Content $sumsPath) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -eq 2) {
      $name = $parts[1].Trim().TrimStart('*')
      if ($name -eq $asset) { $expected = $parts[0].Trim().ToLower(); break }
    }
  }
  if (-not $expected) { throw "SHA256SUMS has no entry for $asset - refusing to install" }
  $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $expected) {
    throw "checksum mismatch for $asset`n  expected $expected`n  actual   $actual`nThe download is corrupt or tampered with. Nothing was installed."
  }
  Write-Host "    ok ($expected)"

  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  New-Item -ItemType Directory -Force -Path $Bin | Out-Null
  # Windows locks running .exe files, so Copy-Item -Force would fail with
  # "file in use". Stop any reolink process running from $Bin first.
  Get-Process -Name reolink-gateway,reolink-cli -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like (Join-Path $Bin '*') } |
    ForEach-Object { Write-Host "stopping $($_.Name) (pid $($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  foreach ($b in 'reolink-cli.exe', 'reolink-gateway.exe') {
    $src = Get-ChildItem -Path $tmp -Recurse -Filter $b | Select-Object -First 1
    if (-not $src) { throw "$b not found in the archive" }
    Copy-Item $src.FullName (Join-Path $Bin $b) -Force
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# Add to user PATH if missing.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$Bin*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$Bin", 'User')
  $env:Path = "$env:Path;$Bin"
  Write-Host "added $Bin to your user PATH (restart the shell to pick it up everywhere)"
}

& (Join-Path $Bin 'reolink-cli.exe') config init 2>$null | Out-Null

Write-Host ""
Write-Host "installed reolink-cli + reolink-gateway to $Bin"
& (Join-Path $Bin 'reolink-cli.exe') --version
Write-Host ""
Write-Host "next steps:"
Write-Host "  reolink-cli gateway start --addr 127.0.0.1:9000"
Write-Host "  reolink-cli device add front-door --host <camera-ip> --user admin"
Write-Host "  reolink-cli --camera front-door info"
