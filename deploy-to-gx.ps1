#
# Deploy modified GUI v2 QML files to Cerbo GX via SSH
# Automatically detects all changed files (committed + uncommitted) vs origin/main
# Reads SSH password from .deploy-password file (not tracked by git)
#
# Usage: .\deploy-to-gx.ps1 -Host <IP_or_hostname> [-Restart]
#
# Examples:
#   .\deploy-to-gx.ps1 -Host 192.168.1.100
#   .\deploy-to-gx.ps1 -Host 192.168.1.100 -Restart
#   .\deploy-to-gx.ps1 -Host venus.local -Restart

param(
    [Parameter(Mandatory=$true)]
    [Alias("H","Host")]
    [string]$GxHost,

    [switch]$Restart
)

$GxUser = "root"
$GxBase = "/opt/victronenergy/gui-v2/Victron/VenusOS"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $ScriptDir

# --- Password setup via SSH_ASKPASS ---
$pwFile = Join-Path $ScriptDir ".deploy-password"
if (-not (Test-Path $pwFile)) {
    Write-Host "Password file not found: .deploy-password" -ForegroundColor Red
    Write-Host "Create it with your GX root password:" -ForegroundColor Yellow
    Write-Host "  echo 'YOUR_PASSWORD' > .deploy-password" -ForegroundColor Yellow
    Pop-Location
    exit 1
}

$password = (Get-Content $pwFile -Raw).Trim()
$askpassBat = "$env:TEMP\gx-askpass.bat"
Set-Content -Path $askpassBat -Value "@echo $password" -NoNewline

$env:SSH_ASKPASS = $askpassBat
$env:SSH_ASKPASS_REQUIRE = "force"
$env:DISPLAY = "required"

# --- Detect modified files ---

# Auto-detect modified QML/JS files vs origin/main (committed + uncommitted)
# Use @() to force array even if single result
$committed = @(git diff --name-only origin/main HEAD 2>$null)
$uncommitted = @(git diff --name-only HEAD 2>$null)
$allChanged = @($committed) + @($uncommitted)

# Deduplicate and filter: QML/JS files under components/, pages/, data/ or root,
# plus JSON theme files under themes/
[string[]]$Files = @($allChanged | Sort-Object -Unique | Where-Object {
    $_ -and (
        (($_ -match '\.(qml|js)$') -and ($_ -match '^(components|pages|data)/|^[^/]+$')) -or
        (($_ -match '\.json$') -and ($_ -match '^themes/'))
    )
})

if ($Files.Count -eq 0) {
    Write-Host "No modified QML/JS files found vs origin/main." -ForegroundColor Yellow
    Pop-Location
    exit 0
}

Write-Host "=== Deploy GUI v2 to Cerbo GX ===" -ForegroundColor Cyan
Write-Host "Host: $GxHost"
Write-Host "Target: $GxBase"
Write-Host "Files to deploy: $($Files.Count)"
Write-Host ""

foreach ($f in $Files) {
    Write-Host "  - $f"
}
Write-Host ""

# Create backup on GX device
Write-Host ">> Creating backup on GX device..." -ForegroundColor Yellow
$backupCmd = "mkdir -p /tmp/gui-v2-backup"
foreach ($f in $Files) {
    $dir = ($f -replace '/[^/]+$', '')
    $backupCmd += " && mkdir -p '/tmp/gui-v2-backup/$dir'"
    $backupCmd += " && if [ -f '$GxBase/$f' ]; then cp '$GxBase/$f' '/tmp/gui-v2-backup/$f'; fi"
}
ssh "${GxUser}@${GxHost}" "$backupCmd"
Write-Host "   Backup saved to /tmp/gui-v2-backup/" -ForegroundColor Green
Write-Host ""

# Pack all files into a tar, upload once, extract on device (single password prompt)
Write-Host ">> Packing $($Files.Count) files into tar..." -ForegroundColor Yellow
$tarFile = "$env:TEMP\gui-v2-deploy.tar.gz"
# tar needs forward-slash paths
$tarArgs = @("-czf", $tarFile) + $Files
tar @tarArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "   FAILED: tar creation failed" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "   Created $tarFile" -ForegroundColor Green
Write-Host ""

Write-Host ">> Uploading tar to GX device..." -ForegroundColor White
scp "$tarFile" "${GxUser}@${GxHost}:/tmp/gui-v2-deploy.tar.gz"
if ($LASTEXITCODE -ne 0) {
    Write-Host "   FAILED: scp upload failed" -ForegroundColor Red
    Remove-Item $tarFile -ErrorAction SilentlyContinue
    Pop-Location
    exit 1
}
Write-Host "   Uploaded successfully" -ForegroundColor Green
Write-Host ""

Write-Host ">> Extracting on GX device..." -ForegroundColor Yellow
$extractCmd = "cd '$GxBase' && tar xzf /tmp/gui-v2-deploy.tar.gz && rm /tmp/gui-v2-deploy.tar.gz"
if ($Restart) {
    $extractCmd += " && svc -t /service/start-gui && echo 'GUI service restarted'"
}
ssh "${GxUser}@${GxHost}" "$extractCmd"
if ($LASTEXITCODE -ne 0) {
    Write-Host "   FAILED: extract failed on device" -ForegroundColor Red
} else {
    Write-Host "   Extracted $($Files.Count) files" -ForegroundColor Green
    if ($Restart) {
        Write-Host "   GUI service restarted" -ForegroundColor Green
    }
}

# Clean up local tar
Remove-Item $tarFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Done: $($Files.Count) files deployed ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "To restore backup:" -ForegroundColor DarkYellow
Write-Host "  ssh ${GxUser}@${GxHost} 'cp -r /tmp/gui-v2-backup/* ${GxBase}/'"

# Cleanup
Remove-Item $askpassBat -ErrorAction SilentlyContinue
Remove-Item Env:\SSH_ASKPASS -ErrorAction SilentlyContinue
Remove-Item Env:\SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
Remove-Item Env:\DISPLAY -ErrorAction SilentlyContinue

Pop-Location
