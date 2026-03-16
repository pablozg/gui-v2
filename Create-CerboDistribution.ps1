param(
    [string]$GxZip = "venus-gx-arm.zip",
    [string]$WasmZip = "venus-webassembly.zip",
    [string]$OutputFile = "gui-v2-cerbo-distribution.zip",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-UserPath {
    param(
        [string]$BaseDir,
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $Path))
}

function Get-CandidateDirectories {
    param([string]$SearchRoot)

    $directories = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    $directories.Add((Get-Item -LiteralPath $SearchRoot))

    foreach ($directory in Get-ChildItem -LiteralPath $SearchRoot -Directory -Recurse) {
        $directories.Add($directory)
    }

    return $directories
}

function Find-GxPayloadRoot {
    param([string]$SearchRoot)

    $candidates = foreach ($directory in Get-CandidateDirectories -SearchRoot $SearchRoot) {
        $hasVictronTree = Test-Path (Join-Path $directory.FullName "Victron/VenusOS")
        $hasBinary = Test-Path (Join-Path $directory.FullName "venus-gui-v2")
        $hasGlobalQml = Test-Path (Join-Path $directory.FullName "Global.qml")

        if (($hasVictronTree -and $hasBinary) -or ($hasVictronTree -and $hasGlobalQml)) {
            [PSCustomObject]@{
                Score = $directory.FullName.Length
                Path = $directory.FullName
            }
        }
    }

    if (-not $candidates) {
        throw "No se ha podido localizar el contenido GX dentro de '$SearchRoot'."
    }

    return ($candidates | Sort-Object Score | Select-Object -First 1).Path
}

function Find-WasmPayloadRoot {
    param([string]$SearchRoot)

    $candidates = foreach ($directory in Get-CandidateDirectories -SearchRoot $SearchRoot) {
        $hasIndex = Test-Path (Join-Path $directory.FullName "index.html")
        $hasLoader = Test-Path (Join-Path $directory.FullName "qtloader.js")
        $hasRuntime = Test-Path (Join-Path $directory.FullName "venus-gui-v2.js")

        if ($hasIndex -and $hasLoader -and $hasRuntime) {
            [PSCustomObject]@{
                Score = $directory.FullName.Length
                Path = $directory.FullName
            }
        }
    }

    if (-not $candidates) {
        throw "No se ha podido localizar el contenido WASM dentro de '$SearchRoot'."
    }

    return ($candidates | Sort-Object Score | Select-Object -First 1).Path
}

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$DestinationDir
    )

    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

    foreach ($item in Get-ChildItem -LiteralPath $SourceDir -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $DestinationDir -Recurse -Force
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$gxZipPath = Resolve-UserPath -BaseDir $scriptDir -Path $GxZip
$wasmZipPath = Resolve-UserPath -BaseDir $scriptDir -Path $WasmZip
$outputPath = Resolve-UserPath -BaseDir $scriptDir -Path $OutputFile
$deployScriptPath = Join-Path $scriptDir "Deploy-CerboDistribution.ps1"
$launcherScriptPath = Join-Path $scriptDir "Install-CerboDistribution.cmd"
$windowsToolsSourceDir = Join-Path $scriptDir "tools\windows"

if (-not (Test-Path -LiteralPath $gxZipPath)) {
    throw "No existe el zip GX: $gxZipPath"
}

if (-not (Test-Path -LiteralPath $wasmZipPath)) {
    throw "No existe el zip WASM: $wasmZipPath"
}

if (-not (Test-Path -LiteralPath $deployScriptPath)) {
    throw "No existe el script de despliegue esperado: $deployScriptPath"
}

if (-not (Test-Path -LiteralPath $launcherScriptPath)) {
    throw "No existe el lanzador esperado: $launcherScriptPath"
}

if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
    throw "El archivo de salida ya existe: $outputPath. Usa -Force para sobrescribirlo."
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gui-v2-distribution-" + [System.Guid]::NewGuid().ToString("N"))
$gxExtractDir = Join-Path $workDir "gx-extract"
$wasmExtractDir = Join-Path $workDir "wasm-extract"
$stageDir = Join-Path $workDir "package"
$gxPayloadDir = Join-Path $stageDir "gx_payload"
$wasmPayloadDir = Join-Path $stageDir "wasm_payload"
$windowsToolsStageDir = Join-Path $stageDir "tools\windows"

try {
    New-Item -ItemType Directory -Path $gxExtractDir, $wasmExtractDir, $stageDir | Out-Null

    Write-Host "Extrayendo artefacto GX..." -ForegroundColor Yellow
    Expand-Archive -LiteralPath $gxZipPath -DestinationPath $gxExtractDir -Force

    Write-Host "Extrayendo artefacto WASM..." -ForegroundColor Yellow
    Expand-Archive -LiteralPath $wasmZipPath -DestinationPath $wasmExtractDir -Force

    $gxRoot = Find-GxPayloadRoot -SearchRoot $gxExtractDir
    $wasmRoot = Find-WasmPayloadRoot -SearchRoot $wasmExtractDir

    Write-Host "Raiz GX detectada: $gxRoot" -ForegroundColor DarkGray
    Write-Host "Raiz WASM detectada: $wasmRoot" -ForegroundColor DarkGray

    Copy-DirectoryContents -SourceDir $gxRoot -DestinationDir $gxPayloadDir
    Copy-DirectoryContents -SourceDir $wasmRoot -DestinationDir $wasmPayloadDir

    $gxFileCount = @(Get-ChildItem -LiteralPath $gxPayloadDir -File -Recurse).Count
    $wasmFileCount = @(Get-ChildItem -LiteralPath $wasmPayloadDir -File -Recurse).Count

    if ($gxFileCount -eq 0) {
        throw "El payload GX ha quedado vacio."
    }

    if ($wasmFileCount -eq 0) {
        throw "El payload WASM ha quedado vacio."
    }

    Copy-Item -LiteralPath $deployScriptPath -Destination (Join-Path $stageDir "Deploy-CerboDistribution.ps1") -Force
    Copy-Item -LiteralPath $launcherScriptPath -Destination (Join-Path $stageDir "Install-CerboDistribution.cmd") -Force

    $bundledWindowsTools = @()
    if (Test-Path -LiteralPath $windowsToolsSourceDir) {
        $supportedTools = @("ssh.exe", "scp.exe", "tar.exe")
        foreach ($toolName in $supportedTools) {
            $toolPath = Join-Path $windowsToolsSourceDir $toolName
            if (Test-Path -LiteralPath $toolPath) {
                New-Item -ItemType Directory -Path $windowsToolsStageDir -Force | Out-Null
                Copy-Item -LiteralPath $toolPath -Destination (Join-Path $windowsToolsStageDir $toolName) -Force
                $bundledWindowsTools += $toolName
            }
        }
    }

    $readme = @"
Uso rapido:

Opcion A: sin extraer el zip
1. Copia este zip, Deploy-CerboDistribution.ps1 e Install-CerboDistribution.cmd al mismo directorio.
2. Ejecuta:
   powershell -ExecutionPolicy Bypass -File .\Deploy-CerboDistribution.ps1 -GxHost <IP_DEL_CERBO> -Password <PASSWORD>

Opcion B: extrayendo el zip
1. Extrae el zip en una carpeta.
2. Haz doble clic en Install-CerboDistribution.cmd.
3. El instalador te pedira la IP/hostname y la password root del Cerbo.

Este paquete despliega:
- Binario GX y archivos locales en /opt/victronenergy/gui-v2/
- Build WASM en /var/www/venus/gui-v2/
- Antes de sobrescribir nada, crea un zip de backup restaurable en esta misma carpeta.

Compatibilidad Windows 10/11:
- No necesita instalar PowerShell ni utilidades externas.
- Usa ssh/scp/tar nativos de Windows si estan disponibles.
- Si el paquete incluye tools\windows\ssh.exe, scp.exe y tar.exe, se usaran automaticamente.
"@
    Set-Content -LiteralPath (Join-Path $stageDir "README.txt") -Value $readme -Encoding Ascii

    $manifest = [ordered]@{
        createdAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source = @{
            gxZip = [System.IO.Path]::GetFileName($gxZipPath)
            wasmZip = [System.IO.Path]::GetFileName($wasmZipPath)
        }
        payload = @{
            gxFiles = $gxFileCount
            wasmFiles = $wasmFileCount
        }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stageDir "manifest.json") -Encoding Ascii

    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }

    Write-Host "Creando paquete unificado..." -ForegroundColor Yellow
    Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $outputPath -CompressionLevel Optimal

    Write-Host ""
    Write-Host "Paquete generado correctamente:" -ForegroundColor Green
    Write-Host "  $outputPath"
    Write-Host ""
    Write-Host "Incluye:" -ForegroundColor Cyan
    Write-Host "  - gx_payload ($gxFileCount archivos)"
    Write-Host "  - wasm_payload ($wasmFileCount archivos)"
    Write-Host "  - Deploy-CerboDistribution.ps1"
    Write-Host "  - Install-CerboDistribution.cmd"
    if ($bundledWindowsTools.Count -gt 0) {
        Write-Host "  - tools/windows ($($bundledWindowsTools -join ', '))"
    }
    Write-Host "  - manifest.json"
}
finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}
