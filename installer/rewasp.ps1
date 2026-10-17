# ReWasp installer logic (run by ReWasp-Setup.exe as administrator; also usable by hand).
#
#   install    put ReWasp into every 64-bit FL Studio that has Image-Line's "no 64 bit
#              version" placeholder Wasp_x64.dll, using the original 32-bit Wasp.dll
#              found in an older FL Studio on this PC (or the one given with -WaspDll)
#   uninstall  put the placeholders back and remove ReWasp's files from FL
#   detect     only find the original Wasp.dll and write its path to -Out (the installer
#              skips its "where is Wasp" page when this succeeds)
#
# Exit codes: 0 ok, 2 FL Studio is running, 3 no 32-bit Wasp.dll found, 4 no 64-bit FL
# Studio with the Wasp placeholder found, 1 anything else. Details go to rewasp.log.
param(
    [ValidateSet('install', 'uninstall', 'detect')] [string] $Action = 'install',
    [string] $Bin = (Join-Path $PSScriptRoot 'bin'),         # Wasp_x64.dll + WaspHost32.exe
    [string] $Backup = (Join-Path $PSScriptRoot 'backup'),   # Image-Line's placeholders
    [string] $WaspDll = '',
    [string] $Out = '',                                      # detect: file that receives the path
    [string[]] $TestFLFolders = @()   # testing only: use these FL folders instead of searching (FL may stay open)
)
$ErrorActionPreference = 'Stop'
$Log = Join-Path $PSScriptRoot 'rewasp.log'
function Say($msg) { Write-Host $msg; Add-Content -Path $Log -Value $msg -Encoding utf8 }
Set-Content -Path $Log -Value "ReWasp $Action - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -Encoding utf8

$Placeholder = "doesn't have a 64 bit version"   # text inside Image-Line's placeholder
$OurMarker = 'WaspHost32.exe'                    # text inside ReWasp's Wasp_x64.dll

function Test-FileHas($path, $text) {
    $bytes = [IO.File]::ReadAllBytes($path)
    foreach ($enc in [Text.Encoding]::ASCII, [Text.Encoding]::Unicode) {
        if ($enc.GetString($bytes).Contains($text)) { return $true }
    }
    return $false
}

function Test-Is32BitPE($path) {
    try {
        $b = [IO.File]::ReadAllBytes($path)
        $pe = [BitConverter]::ToInt32($b, 0x3C)
        return [BitConverter]::ToUInt16($b, $pe + 4) -eq 0x14C   # IMAGE_FILE_MACHINE_I386
    } catch { return $false }
}

# Every FL Studio install folder: from Windows' list of installed programs (covers custom
# install locations) plus the default Image-Line folders.
function Get-FLFolders {
    if ($TestFLFolders) { return $TestFLFolders }
    $dirs = @()
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'FL Studio*' } | ForEach-Object {
            $loc = $_.InstallLocation
            if (-not $loc -and $_.UninstallString) { $loc = Split-Path ($_.UninstallString -replace '"', '') -Parent }
            if ($loc) { $dirs += $loc.TrimEnd('\') }
        }
    }
    foreach ($pf in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
        if ($pf -and (Test-Path "$pf\Image-Line")) {
            $dirs += Get-ChildItem "$pf\Image-Line" -Directory | Where-Object Name -like 'FL Studio*' | ForEach-Object FullName
        }
    }
    $dirs | Where-Object { Test-Path $_ } | Sort-Object -Unique
}

# Wasp builds from FL Studio 12 and older (file version 1.3.52 or lower) work, and need their Artwork
# folder. FL Studio 20's build (1.3.53+) crashes in the helper (it expects newer host features), so it
# isn't used, even if someone has copied an Artwork folder next to it.
function Test-UsableWasp($file) {
    if (-not (Test-Path (Join-Path $file.DirectoryName 'Artwork'))) { return $false }
    try { $v = [version]$file.VersionInfo.FileVersion } catch { return $false }
    return $v -lt [version]'1.3.53'
}

function Find-WaspSource {
    if ($WaspDll) {
        if (-not (Test-Path $WaspDll)) { Say "Not found: $WaspDll"; return $null }
        if (-not (Test-Is32BitPE $WaspDll)) { Say "Not a 32-bit plugin: $WaspDll"; return $null }
        if (-not (Test-UsableWasp (Get-Item $WaspDll))) {
            Say "$WaspDll can't be used. Use the Wasp from FL Studio 12 or older, with its Artwork folder next to it (FL Studio 20's isn't supported yet)."
            return $null
        }
        return (Resolve-Path $WaspDll).Path
    }
    $found = foreach ($fl in Get-FLFolders) {
        $p = "$fl\Plugins\Fruity\Generators\Wasp\Wasp.dll"
        if ((Test-Path $p) -and (Test-Is32BitPE $p) -and -not (Test-FileHas $p $Placeholder)) { Get-Item $p }
    }
    $usable = $found | Where-Object { Test-UsableWasp $_ }
    $best = $usable | Sort-Object LastWriteTime -Descending | Select-Object -First 1   # newest usable build
    if ($best) { return $best.FullName }
    if ($found) { Say "Found only FL Studio 20's Wasp ($($found[0].FullName)), which ReWasp doesn't support yet." }
    return $null
}

if ($Action -eq 'detect') {
    $source = Find-WaspSource
    if (-not $source) { exit 3 }
    if ($Out) { Set-Content -Path $Out -Value $source -Encoding utf8 } else { $source }
    exit 0
}

$records = Join-Path $Backup 'installed.txt'   # FL Wasp folders ReWasp was installed into

if (-not $TestFLFolders -and (Get-Process FL64, FL, 'FL Studio' -ErrorAction SilentlyContinue)) {
    Say 'FL Studio is running. Close it and try again.'
    exit 2
}

try {
    if ($Action -eq 'uninstall') {
        $dirs = if (Test-Path $records) { Get-Content $records } else { @() }
        foreach ($dir in $dirs | Sort-Object -Unique) {
            if (-not (Test-Path $dir)) { continue }
            $target = "$dir\Wasp_x64.dll"
            $fl = Split-Path (Split-Path (Split-Path (Split-Path $dir)))   # <FL>\Plugins\Fruity\Generators\Wasp
            $saved = Join-Path $Backup ((Split-Path $fl -Leaf) + '\Wasp_x64.dll')
            if ((Test-Path $target) -and (Test-FileHas $target $OurMarker)) {
                if (Test-Path $saved) { Copy-Item $saved $target -Force; Say "Restored Image-Line's placeholder: $target" }
                else { Remove-Item $target -Force; Say "Removed: $target" }
            }
            if (Test-Path "$dir\x86\WaspHost32.exe") { Remove-Item "$dir\x86" -Recurse -Force; Say "Removed: $dir\x86" }
        }
        $artRecords = Join-Path $Backup 'artwork.txt'
        if (Test-Path $artRecords) {
            foreach ($art in Get-Content $artRecords) { if (Test-Path $art) { Remove-Item $art -Recurse -Force; Say "Removed: $art" } }
        }
        Say 'ReWasp removed.'
        exit 0
    }

    $source = Find-WaspSource
    if (-not $source) {
        Say 'No original 32-bit Wasp.dll found.'
        Say 'ReWasp needs the one from FL Studio 12 or older (Plugins\Fruity\Generators\Wasp\Wasp.dll, next to its Artwork folder).'
        Say 'Install an older FL Studio alongside your current one, or point the installer at a copy of Wasp.dll.'
        exit 3
    }
    Say "Original 32-bit Wasp: $source"
    $srcDir = Split-Path $source

    New-Item -ItemType Directory -Force $Backup | Out-Null
    $done = @()
    foreach ($fl in Get-FLFolders) {
        $dir = "$fl\Plugins\Fruity\Generators\Wasp"
        $target = "$dir\Wasp_x64.dll"
        if (-not (Test-Path $target)) { continue }                       # 32-bit-only or very old FL
        $ours = Test-FileHas $target $OurMarker
        if (-not $ours -and -not (Test-FileHas $target $Placeholder)) {   # a real 64-bit Wasp? leave it alone
            Say "Skipped (not the placeholder): $target"
            continue
        }
        $saved = Join-Path $Backup ((Split-Path $fl -Leaf) + '\Wasp_x64.dll')
        if (-not $ours -and -not (Test-Path $saved)) {
            New-Item -ItemType Directory -Force (Split-Path $saved) | Out-Null
            Copy-Item $target $saved
        }
        # the original 32-bit Wasp (plus its language DLL and artwork) goes into x86\ next to our plugin
        New-Item -ItemType Directory -Force "$dir\x86" | Out-Null
        Copy-Item "$Bin\WaspHost32.exe" "$dir\x86\" -Force
        Get-ChildItem $srcDir -Filter *.dll | Where-Object { $_.Name -notlike '*_x64.dll' -and $_.Name -notlike 'Wasp XT*' } |
            ForEach-Object { Copy-Item $_.FullName "$dir\x86\" -Force }
        if (Test-Path "$srcDir\Artwork") { Copy-Item "$srcDir\Artwork" "$dir\x86\" -Recurse -Force }
        Copy-Item "$Bin\Wasp_x64.dll" $target -Force
        Say "Installed into $(Split-Path $fl -Leaf)"
        $done += $dir
    }
    # Wasp folders without Wasp's images (e.g. some FL Studio 20 installs) make Wasp show
    # "Cannot open file ...\Wasp\Artwork\Back.bmp" and a blank purple window: add them.
    $artRecords = Join-Path $Backup 'artwork.txt'
    $artAdded = @()
    if (Test-Path "$srcDir\Artwork") {
        foreach ($fl in Get-FLFolders) {
            $dir = "$fl\Plugins\Fruity\Generators\Wasp"
            if (-not (Test-Path $dir) -or (Test-Path "$dir\Artwork")) { continue }
            Copy-Item "$srcDir\Artwork" "$dir\" -Recurse -Force
            Say "Added Wasp's images to $(Split-Path $fl -Leaf)"
            $artAdded += "$dir\Artwork"
        }
    }
    if ($artAdded) { $artAdded + $(if (Test-Path $artRecords) { Get-Content $artRecords } else { @() }) | Sort-Object -Unique | Set-Content $artRecords }

    if (-not $done) {
        Say 'No 64-bit FL Studio with the Wasp placeholder was found (FL Studio 12 or newer).'
        exit 4
    }
    $done + $(if (Test-Path $records) { Get-Content $records } else { @() }) | Sort-Object -Unique | Set-Content $records
    Say 'Done. Open FL Studio: Wasp works in 64-bit, and old projects load with their Wasp sounds.'
    exit 0
} catch {
    Say "Failed: $($_.Exception.Message)"
    exit 1
}
