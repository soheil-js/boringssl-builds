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
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FilePath,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) {
        $argText = if ($Arguments.Count -gt 0) { " " + ($Arguments -join " ") } else { "" }
        throw "Command failed with exit code ${exitCode}: $FilePath$argText"
    }
}

function Remove-DirectorySafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                $_.Attributes = $_.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
            }
        } catch {
            # Ignore attribute errors on locked/special items
        }
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

$RootDir = Split-Path -Parent $PSScriptRoot
$SourceDir = Join-Path $RootDir "boringssl"
$BuildDir = Join-Path $RootDir "build"
$OutputDir = Join-Path $RootDir "dist"

$requiredTools = @("git", "cmake", "ninja", "python", "go", "perl")
if ($Rid -eq "win-x64") {
    $requiredTools += "nasm"
}

foreach ($tool in $requiredTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found in PATH: $tool"
    }
}

Write-Host "========================================"
Write-Host " BoringSSL shared-library build"
Write-Host " RID: $Rid"
Write-Host " Upstream revision: $UpstreamSha"
Write-Host "========================================"

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir ".git"))) {
    Remove-DirectorySafe -Path $SourceDir
    Invoke-Checked git clone --filter=blob:none https://github.com/google/boringssl.git $SourceDir
}

Invoke-Checked git -C $SourceDir fetch --origin origin --prune
if ($UpstreamSha -ne "HEAD") {
    Invoke-Checked git -C $SourceDir fetch --depth=1 origin $UpstreamSha
}
Invoke-Checked git -C $SourceDir checkout --detach $UpstreamSha

Remove-DirectorySafe -Path $BuildDir

Invoke-Checked cmake `
    -S $SourceDir `
    -B $BuildDir `
    -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_SHARED_LIBS=ON

Invoke-Checked cmake --build $BuildDir --config Release --parallel

Invoke-Checked python (Join-Path $PSScriptRoot "package.py") `
    --source $SourceDir `
    --build $BuildDir `
    --rid $Rid `
    --output $OutputDir `
    --upstream-sha $UpstreamSha

$zipPath = Join-Path $OutputDir "boringssl-$Rid.zip"
if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Expected output package was not created: $zipPath"
}

Write-Host "Build and packaging completed: $zipPath"