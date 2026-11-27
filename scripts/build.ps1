[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Rid,

    [string]$UpstreamSha = "HEAD"
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }
}

$RootDir = Split-Path -Parent $PSScriptRoot
$SourceDir = Join-Path $RootDir "boringssl"
$BuildDir = Join-Path $RootDir "build"
$OutputDir = Join-Path $RootDir "dist"

foreach ($tool in @("git", "cmake", "ninja", "python")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found in PATH: $tool"
    }
}

Write-Host "========================================"
Write-Host " BoringSSL shared-library build"
Write-Host " RID: $Rid"
Write-Host " Upstream revision: $UpstreamSha"
Write-Host "========================================"

if (-not (Test-Path (Join-Path $SourceDir ".git"))) {
    Invoke-Checked git clone https://github.com/google/boringssl.git $SourceDir
}

Invoke-Checked git -C $SourceDir fetch origin
Invoke-Checked git -C $SourceDir checkout --detach $UpstreamSha

if (Test-Path $BuildDir) {
    Remove-Item $BuildDir -Recurse -Force
}

Invoke-Checked cmake `
    -S $SourceDir `
    -B $BuildDir `
    -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_SHARED_LIBS=ON

Invoke-Checked cmake --build $BuildDir --config Release --parallel

Invoke-Checked python "$PSScriptRoot/package.py" `
    --source $SourceDir `
    --build $BuildDir `
    --rid $Rid `
    --output $OutputDir `
    --upstream-sha $UpstreamSha

Write-Host "Build and packaging completed: $(Join-Path $OutputDir "boringssl-$Rid.zip")"
