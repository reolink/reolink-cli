# reolink-cli one-line installer (Windows).
#
# From PowerShell or the Command Prompt:
#
#   powershell -NoProfile -Command "iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 | iex"
#
# From PowerShell only (iwr/iex are PowerShell aliases; in cmd.exe this fails
# with "'iwr' is not recognized", which does not hint at the cause):
#
#   iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 | iex
#
# Runs on Windows PowerShell 5.1 and PowerShell 7.
#
# Downloads the latest release for Windows x64, installs it to
# %USERPROFILE%\.local\bin, adds it to your user PATH, and initializes config.
# For AI agents use `npx skills add reolink/reolink-cli` instead.
$ErrorActionPreference = 'Stop'

$Repo   = if ($env:REOLINK_REPO)   { $env:REOLINK_REPO }   else { 'reolink/reolink-cli' }
# NOT overridable, deliberately. Both the archive and the checksum used to come
# from $Repo, so REOLINK_REPO moved the anchor along with the download and an
# attacker-supplied repository validated its own archive (GHSA-65x2-w384-qp7j,
# finding 2). A genuine mirror serves identical bytes and still passes; a fork
# serving its own build no longer does.
$ChecksumRepo = 'reolink/reolink-cli'
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
  # not install. This is an integrity check, not a signature: it proves the
  # archive is the one whose hash was committed to $ChecksumRepo, not who
  # built it.
  Write-Host "==> verifying checksum against $ChecksumRepo"
  $sumsPath = Join-Path $tmp "CHECKSUMS"
  try {
    Invoke-WebRequest -Headers $headers -Uri "https://raw.githubusercontent.com/$ChecksumRepo/main/checksums/$tag.sha256" -OutFile $sumsPath
  } catch {
    throw "no committed checksum file for $tag (checksums/$tag.sha256 on the default branch of $ChecksumRepo). Either this release has not been synced yet, or the tag did not come from the release process. Refusing to install."
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
    throw @"
checksum mismatch for $asset
  expected $expected
  actual   $actual
The download does not match the checksum committed to $ChecksumRepo. Nothing was installed.

A truncated or proxy-mangled download is the ordinary cause, so retrying is worth one attempt.
If it fails again, stop and report it at https://github.com/$ChecksumRepo/security/advisories/new
- do not work around it by pointing REOLINK_REPO elsewhere or downloading the archive by hand,
which skips the only check that would have caught the problem.
"@
  }
  Write-Host "    ok ($expected)"

  # Refuse a hostile archive layout before unpacking (GHSA-65x2-w384-qp7j,
  # finding 3). Expand-Archive's own traversal behaviour has varied across
  # PowerShell versions, so the guarantee is made here instead of assumed.
  # Windows PowerShell 5.1 — `powershell.exe`, the default on Windows — does not
  # load this assembly until something asks for it, while PowerShell 7 has it
  # already. Without this line the type lookup below fails and the installer
  # aborts before touching anything, on the exact shell most users are running.
  # Harmless where it is already loaded.
  Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
  $entries = [System.IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $bad = $entries.Entries |
      Where-Object { $_.FullName -match '^([A-Za-z]:)?[\\/]' -or $_.FullName -match '(^|[\\/])\.\.([\\/]|$)' } |
      Select-Object -First 5 -ExpandProperty FullName
  } finally { $entries.Dispose() }
  if ($bad) { throw "archive contains absolute or parent-directory members - refusing to extract:`n$($bad -join "`n")" }

  $unpack = Join-Path $tmp 'unpack'
  New-Item -ItemType Directory -Force -Path $unpack | Out-Null
  Expand-Archive -Path $zip -DestinationPath $unpack -Force
  New-Item -ItemType Directory -Force -Path $Bin | Out-Null

  # Derived, not discovered. The archive always unpacks to one directory named
  # after itself; searching the tree for a filename lets an archive that
  # carries a second reolink-cli.exe decide which one gets installed and run.
  $root = Join-Path $unpack ([System.IO.Path]::GetFileNameWithoutExtension($asset))
  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "archive does not unpack to $([System.IO.Path]::GetFileNameWithoutExtension($asset))\ - layout is not what this installer expects"
  }
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
    $src = Join-Path $root (Join-Path 'bin' $exe)
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
      throw "$exe is not at bin\$exe in the archive - refusing to guess"
    }
    # A reparse point here would copy whatever it targets, under a name we then
    # place on PATH. The archive ships regular files; anything else is not it.
    $item = Get-Item -LiteralPath $src -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      throw "bin\$exe in the archive is a reparse point - refusing to install"
    }
    Copy-Item -LiteralPath $src (Join-Path $Bin $exe) -Force
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
