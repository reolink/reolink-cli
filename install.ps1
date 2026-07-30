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

  # Verify against the checksums COMMITTED TO THE REPOSITORY, not the
  # SHA256SUMS attached to the release. A checksum from the same release can
  # only detect accidental corruption: whoever can replace the asset can
  # regenerate a matching SHA256SUMS in the same API call. A file on the
  # default branch is behind a reviewed pull request and permanent history;
  # checksums/<tag>.sha256 is committed there as part of each release, from
  # the machine that built it.
  #
  # Fail closed: no fallback to the release-attached SHA256SUMS, and a tag
  # with no committed checksum file aborts — so a fabricated release does
  # not install. This is an integrity check, not a signature.
  Write-Host "==> verifying checksum against the repository"
  $sumsPath = Join-Path $tmp "CHECKSUMS"
  try {
    Invoke-WebRequest -Headers $headers -Uri "https://raw.githubusercontent.com/$Repo/main/checksums/$tag.sha256" -OutFile $sumsPath
  } catch {
    throw "no committed checksum file for $tag (checksums/$tag.sha256 on the default branch). Either this release has not been synced yet, or the tag did not come from the release process. Refusing to install."
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
  if (-not $expected) { throw "checksums/$tag.sha256 has no entry for $asset - refusing to install" }
  $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $expected) {
    throw "checksum mismatch for $asset`n  expected $expected`n  actual   $actual`nThe download does not match the checksum committed to the repository. Nothing was installed."
  }
  Write-Host "    ok ($expected)"

  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  New-Item -ItemType Directory -Force -Path $Bin | Out-Null
  # Windows locks running .exe files, so Copy-Item -Force would fail with
  # "file in use". Stop any reolink process running from $Bin first.
  Get-Process -Name reolink-gateway,reolink-cli -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like (Join-Path $Bin '*') } |
    ForEach-Object { Write-Host "stopping $($_.Name) (pid $($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  # Resolve each binary first and fail by name when it is absent. Piping
  # Get-ChildItem straight into Copy-Item silently does nothing on an empty
  # pipeline, so a malformed archive used to install nothing, exit 0, and only
  # surface later as `config init` failing to find a file it never mentions.
  # install.sh has always failed loudly here; this is the missing half.
  foreach ($exe in 'reolink-cli.exe', 'reolink-gateway.exe') {
    $src = Get-ChildItem -Path $tmp -Recurse -Filter $exe -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if (-not $src) { throw "$exe not found in the archive" }
    Copy-Item $src.FullName (Join-Path $Bin $exe) -Force
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
