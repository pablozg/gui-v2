param(
    [Alias("Host", "H")]
    [string]$GxHost,

    [string]$Password,

    [string]$PackagePath = "gui-v2-cerbo-distribution.zip"
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

function Test-IsDeployToGxSourceRoot {
    param([string]$DirectoryPath)

    $knownTopLevelDirs = @("components", "pages", "data", "themes")
    foreach ($dirName in $knownTopLevelDirs) {
        if (Test-Path (Join-Path $DirectoryPath $dirName)) {
            return $true
        }
    }

    return $false
}

function Require-Command {
    param(
        [string]$CommandName,
        [string[]]$CandidatePaths = @(),
        [string]$HelpMessage
    )

    foreach ($candidate in $CandidatePaths) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if ($HelpMessage) {
        throw $HelpMessage
    }

    throw "No se encontro el comando requerido '$CommandName'."
}

function ConvertTo-PlainText {
    param([Security.SecureString]$SecureString)

    if (-not $SecureString) {
        return ""
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedPackagePath = Resolve-UserPath -BaseDir $scriptDir -Path $PackagePath

if ([string]::IsNullOrWhiteSpace($GxHost)) {
    $GxHost = Read-Host "IP o hostname del Cerbo"
}

if ([string]::IsNullOrWhiteSpace($GxHost)) {
    throw "Debes indicar la IP o hostname del Cerbo."
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $securePassword = Read-Host "Password root del Cerbo" -AsSecureString
    $Password = ConvertTo-PlainText -SecureString $securePassword
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw "Debes indicar la password del Cerbo."
}

$sshExe = Require-Command -CommandName "ssh" -CandidatePaths @(
    (Join-Path $scriptDir "tools\windows\ssh.exe"),
    (Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe")
    ) -HelpMessage "No se ha encontrado 'ssh.exe'. Este instalador funciona sin instalar software adicional si el equipo dispone del cliente OpenSSH nativo de Windows 10/11, o si el paquete incluye tools\windows\ssh.exe."
$scpExe = Require-Command -CommandName "scp" -CandidatePaths @(
    (Join-Path $scriptDir "tools\windows\scp.exe"),
    (Join-Path $env:WINDIR "System32\OpenSSH\scp.exe")
    ) -HelpMessage "No se ha encontrado 'scp.exe'. Este instalador funciona sin instalar software adicional si el equipo dispone del cliente OpenSSH nativo de Windows 10/11, o si el paquete incluye tools\windows\scp.exe."
$tarExe = Require-Command -CommandName "tar" -CandidatePaths @(
    (Join-Path $scriptDir "tools\windows\tar.exe"),
    (Join-Path $env:WINDIR "System32\tar.exe")
    ) -HelpMessage "No se ha encontrado 'tar.exe'. En Windows 10/11 suele venir incluido de serie, y el paquete tambien puede llevarlo en tools\windows\tar.exe."

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gui-v2-deploy-" + [System.Guid]::NewGuid().ToString("N"))
$extractDir = Join-Path $workDir "package"
$backupExtractDir = Join-Path $workDir "backup-extract"
$backupStageDir = Join-Path $workDir "backup-package"
$tarPath = Join-Path $workDir "gui-v2-complete-deploy.tar.gz"
$backupTarPath = Join-Path $workDir "gui-v2-existing-installation-backup.tar.gz"
$askpassPath = Join-Path $workDir "gx-askpass.bat"
$remoteTarPath = "/tmp/gui-v2-complete-deploy.tar.gz"
$remoteBackupTarPath = "/tmp/gui-v2-existing-installation-backup.tar.gz"
$remoteStageDir = "/tmp/gui-v2-complete-deploy"
$gxTargetDir = "/opt/victronenergy/gui-v2"
$gxGuiTargetDir = "$gxTargetDir/Victron/VenusOS"
$wasmTargetDir = "/var/www/venus/gui-v2"
$gxUser = "root"

New-Item -ItemType Directory -Path $extractDir, $backupExtractDir, $backupStageDir -Force | Out-Null

try {
    $payloadRootDir = $null
    $extractedModeGxPayloadDir = Join-Path $scriptDir "gx_payload"
    $extractedModeWasmPayloadDir = Join-Path $scriptDir "wasm_payload"

    if ((Test-Path -LiteralPath $extractedModeGxPayloadDir) -and (Test-Path -LiteralPath $extractedModeWasmPayloadDir)) {
        $payloadRootDir = $scriptDir
        Write-Host "Usando payload ya extraido junto al script." -ForegroundColor Yellow
    } elseif (Test-Path -LiteralPath $resolvedPackagePath) {
        Write-Host "Extrayendo paquete..." -ForegroundColor Yellow
        Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $extractDir -Force
        $payloadRootDir = $extractDir
    } else {
        throw "No existe el paquete a desplegar: $resolvedPackagePath y tampoco se han encontrado gx_payload/wasm_payload junto al script."
    }

	    $gxPayloadDir = Join-Path $payloadRootDir "gx_payload"
	    $wasmPayloadDir = Join-Path $payloadRootDir "wasm_payload"
        $windowsToolsPayloadDir = Join-Path $payloadRootDir "tools\windows"
        $payloadRootDirForTar = $payloadRootDir

    if (-not (Test-Path -LiteralPath $gxPayloadDir)) {
        throw "El paquete no contiene gx_payload."
    }

    if (-not (Test-Path -LiteralPath $wasmPayloadDir)) {
        throw "El paquete no contiene wasm_payload."
    }

        $gxPayloadLooksLikeFullRoot = (Test-Path (Join-Path $gxPayloadDir "Victron\VenusOS")) -or (Test-Path (Join-Path $gxPayloadDir "venus-gui-v2"))
        $gxPayloadIsDeployToGxSource = Test-IsDeployToGxSourceRoot -DirectoryPath $gxPayloadDir
        if (-not $gxPayloadLooksLikeFullRoot -and $gxPayloadIsDeployToGxSource) {
            $payloadRootDirForTar = Join-Path $workDir "normalized-package"
            $normalizedGxPayloadDir = Join-Path $payloadRootDirForTar "gx_payload\Victron\VenusOS"
            $normalizedWasmPayloadDir = Join-Path $payloadRootDirForTar "wasm_payload"

            Write-Host "Normalizando payload GX al destino $gxGuiTargetDir..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $payloadRootDirForTar, $normalizedGxPayloadDir, $normalizedWasmPayloadDir -Force | Out-Null
            Copy-DirectoryContents -SourceDir $gxPayloadDir -DestinationDir $normalizedGxPayloadDir
            Copy-DirectoryContents -SourceDir $wasmPayloadDir -DestinationDir $normalizedWasmPayloadDir

            foreach ($optionalFile in @("manifest.json", "README.txt")) {
                $optionalSourcePath = Join-Path $payloadRootDir $optionalFile
                if (Test-Path -LiteralPath $optionalSourcePath) {
                    Copy-Item -LiteralPath $optionalSourcePath -Destination (Join-Path $payloadRootDirForTar $optionalFile) -Force
                }
            }
        }

	    Set-Content -LiteralPath $askpassPath -Value "@echo $Password" -Encoding Ascii -NoNewline
	    $env:SSH_ASKPASS = $askpassPath
	    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY = "required"

	    $sshCommonArgs = @(
	        "-o", "StrictHostKeyChecking=no",
	        "-o", "UserKnownHostsFile=/dev/null",
	        "-o", "PreferredAuthentications=password",
        "-o", "PubkeyAuthentication=no",
        "-o", "NumberOfPasswordPrompts=1",
	        "-o", "ConnectTimeout=15"
	    )

        $backupStamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $safeHost = ($GxHost -replace "[^A-Za-z0-9._-]", "_")
        $backupZipPath = Join-Path $scriptDir ("gui-v2-cerbo-backup-{0}-{1}.zip" -f $safeHost, $backupStamp)
        $backupGxSourceDir = Join-Path $backupExtractDir "opt\victronenergy\gui-v2"
        $backupWasmSourceDir = Join-Path $backupExtractDir "var\www\venus\gui-v2"
        $backupGxPayloadDir = Join-Path $backupStageDir "gx_payload"
        $backupWasmPayloadDir = Join-Path $backupStageDir "wasm_payload"
        $backupWindowsToolsDir = Join-Path $backupStageDir "tools\windows"

        Write-Host "Creando copia de seguridad del Cerbo..." -ForegroundColor Yellow
        $remoteBackupCommands = @(
            "set -e",
            "rm -f '$remoteBackupTarPath'",
            "tar czf '$remoteBackupTarPath' -C / opt/victronenergy/gui-v2 var/www/venus/gui-v2"
        )
        & $sshExe @sshCommonArgs ("{0}@{1}" -f $gxUser, $GxHost) ($remoteBackupCommands -join "; ")
        if ($LASTEXITCODE -ne 0) {
            throw "Fallo al crear la copia de seguridad remota del Cerbo."
        }

        Write-Host "Descargando copia de seguridad..." -ForegroundColor Yellow
        & $scpExe @sshCommonArgs ("{0}@{1}:{2}" -f $gxUser, $GxHost, $remoteBackupTarPath) $backupTarPath
        if ($LASTEXITCODE -ne 0) {
            throw "Fallo al descargar la copia de seguridad del Cerbo."
        }

        & $sshExe @sshCommonArgs ("{0}@{1}" -f $gxUser, $GxHost) ("rm -f '{0}'" -f $remoteBackupTarPath)

        Write-Host "Preparando zip de restauracion..." -ForegroundColor Yellow
        & $tarExe -xzf $backupTarPath -C $backupExtractDir
        if ($LASTEXITCODE -ne 0) {
            throw "Fallo al extraer localmente la copia de seguridad descargada."
        }

        if (-not (Test-Path -LiteralPath $backupGxSourceDir)) {
            throw "La copia de seguridad descargada no contiene $gxTargetDir."
        }

        if (-not (Test-Path -LiteralPath $backupWasmSourceDir)) {
            throw "La copia de seguridad descargada no contiene $wasmTargetDir."
        }

        Copy-DirectoryContents -SourceDir $backupGxSourceDir -DestinationDir $backupGxPayloadDir
        Copy-DirectoryContents -SourceDir $backupWasmSourceDir -DestinationDir $backupWasmPayloadDir
        Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination (Join-Path $backupStageDir "Deploy-CerboDistribution.ps1") -Force

        $launcherPath = Join-Path $scriptDir "Install-CerboDistribution.cmd"
        if (Test-Path -LiteralPath $launcherPath) {
            Copy-Item -LiteralPath $launcherPath -Destination (Join-Path $backupStageDir "Install-CerboDistribution.cmd") -Force
        }

        if (Test-Path -LiteralPath $windowsToolsPayloadDir) {
            Copy-DirectoryContents -SourceDir $windowsToolsPayloadDir -DestinationDir $backupWindowsToolsDir
        }

        $backupReadme = @"
Este archivo es una copia de seguridad creada automaticamente antes del despliegue en $GxHost.

Para restaurarla:
1. Extrae este zip en una carpeta.
2. Ejecuta Install-CerboDistribution.cmd
   o
   powershell -ExecutionPolicy Bypass -File .\Deploy-CerboDistribution.ps1 -GxHost <IP_DEL_CERBO> -Password <PASSWORD>

Contenido respaldado:
- $gxTargetDir
- $gxGuiTargetDir
- $wasmTargetDir
"@
        Set-Content -LiteralPath (Join-Path $backupStageDir "README.txt") -Value $backupReadme -Encoding Ascii

        $backupManifest = [ordered]@{
            createdAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            backupOf = @{
                host = $GxHost
                gxTargetDir = $gxTargetDir
                gxGuiTargetDir = $gxGuiTargetDir
                wasmTargetDir = $wasmTargetDir
            }
        }
        $backupManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupStageDir "manifest.json") -Encoding Ascii

	        if (Test-Path -LiteralPath $backupZipPath) {
	            Remove-Item -LiteralPath $backupZipPath -Force
	        }
	        Compress-Archive -Path (Join-Path $backupStageDir "*") -DestinationPath $backupZipPath -CompressionLevel Optimal
	        Write-Host "Copia de seguridad guardada en: $backupZipPath" -ForegroundColor Green

        $tarItems = @("gx_payload", "wasm_payload")
        if (Test-Path -LiteralPath (Join-Path $payloadRootDirForTar "manifest.json")) {
            $tarItems += "manifest.json"
        }
        if (Test-Path -LiteralPath (Join-Path $payloadRootDirForTar "README.txt")) {
            $tarItems += "README.txt"
        }

        Write-Host "Empaquetando payload para el Cerbo..." -ForegroundColor Yellow
        Push-Location $payloadRootDirForTar
        try {
            & $tarExe -czf $tarPath @tarItems
            if ($LASTEXITCODE -ne 0) {
                throw "Fallo al crear el tar temporal de despliegue."
            }
        }
        finally {
            Pop-Location
        }

		    Write-Host "Subiendo paquete al Cerbo $GxHost..." -ForegroundColor Yellow
		    & $scpExe @sshCommonArgs $tarPath ("{0}@{1}:{2}" -f $gxUser, $GxHost, $remoteTarPath)
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo al subir el paquete al Cerbo."
    }

    $remoteCommands = @(
        "set -e",
        "restart_gui() { svc -u /service/start-gui >/dev/null 2>&1 || true; }",
        "trap restart_gui EXIT",
        "/opt/victronenergy/swupdate-scripts/remount-rw.sh",
        "rm -rf '$remoteStageDir'",
        "mkdir -p '$remoteStageDir'",
        "tar xzf '$remoteTarPath' -C '$remoteStageDir'",
        "svc -d /service/start-gui",
        "mkdir -p '$gxTargetDir'",
        "cp -r '$remoteStageDir/gx_payload/.' '$gxTargetDir/'",
        "mkdir -p '$wasmTargetDir'",
        "cp -r '$remoteStageDir/wasm_payload/.' '$wasmTargetDir/'",
        "if [ -f '$gxTargetDir/venus-gui-v2' ]; then chmod 755 '$gxTargetDir/venus-gui-v2'; fi",
        "sync",
        "trap - EXIT",
        "svc -u /service/start-gui",
        "rm -rf '$remoteStageDir' '$remoteTarPath'"
    )
    $remoteCommand = $remoteCommands -join "; "

    Write-Host "Aplicando despliegue completo en el Cerbo..." -ForegroundColor Yellow
    & $sshExe @sshCommonArgs ("{0}@{1}" -f $gxUser, $GxHost) $remoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "El despliegue remoto devolvio un error."
    }

	    Write-Host ""
	    Write-Host "Despliegue completado correctamente." -ForegroundColor Green
        Write-Host "  Backup:    $backupZipPath"
	    Write-Host "  GX local:  $gxTargetDir"
	    Write-Host "  GX GUI:    $gxGuiTargetDir"
	    Write-Host "  WASM web:  $wasmTargetDir"
}
finally {
    $Password = $null
    Remove-Item Env:\SSH_ASKPASS -ErrorAction SilentlyContinue
    Remove-Item Env:\SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
    Remove-Item Env:\DISPLAY -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}
