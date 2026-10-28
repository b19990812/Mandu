param(
    [ValidateSet('Info', 'Devices', 'Install', 'Build', 'Tasks')][string]$Action = 'Build',
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [string]$DevEcoHome = 'D:\Software\DevEco Studio'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$taskTemp = Join-Path $projectRoot 'temp'
foreach ($relative in @('logs', 'tmp', 'hvigor-home', 'build')) {
    New-Item -ItemType Directory -Path (Join-Path $taskTemp $relative) -Force | Out-Null
}
$node = Join-Path $DevEcoHome 'tools\node\node.exe'
$java = Join-Path $DevEcoHome 'jbr'
$hdc = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\hdc.exe'
if (-not (Test-Path -LiteralPath $node)) { throw "未找到 DevEco Node：$node" }
$env:NODE_HOME = Split-Path -Parent $node
$env:JAVA_HOME = $java
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
$env:HVIGOR_USER_HOME = Join-Path $taskTemp 'hvigor-home'
$env:TEMP = Join-Path $taskTemp 'tmp'
$env:TMP = $env:TEMP
$env:Path = "$env:NODE_HOME;$java\bin;$DevEcoHome\tools\ohpm\bin;$env:Path"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $taskTemp "logs\$Action-$Mode-$stamp.log"
Push-Location $projectRoot
try {
    if ($Action -eq 'Info') {
        $info = Get-Content -LiteralPath (Join-Path $DevEcoHome 'product-info.json') -Raw | ConvertFrom-Json
        "DevEco Studio $($info.version) / build $($info.buildNumber)" | Tee-Object -FilePath $log
        & $node --version 2>&1 | Tee-Object -FilePath $log -Append
        & (Join-Path $java 'bin\java.exe') -version 2>&1 | Tee-Object -FilePath $log -Append
        Get-Content -LiteralPath (Join-Path $DevEcoHome 'sdk\default\sdk-pkg.json') | Tee-Object -FilePath $log -Append
        exit 0
    }
    if ($Action -eq 'Devices') {
        & $hdc list targets 2>&1 | Tee-Object -FilePath $log
    } elseif ($Action -eq 'Install') {
        & $node (Join-Path $DevEcoHome 'tools\ohpm\bin\pm-cli.js') install --cache (Join-Path $taskTemp 'ohpm-cache') 2>&1 |
            Tee-Object -FilePath $log
    } else {
        $arguments = @('--mode', 'module', '-p', 'product=default', '-p', "buildMode=$Mode",
            '-p', "build-cache-dir=$(Join-Path $taskTemp 'build')")
        if ($Action -eq 'Tasks') { $arguments += 'tasks' }
        else {
            $target = if ($Mode -eq 'debug') { 'lab' } else { 'default' }
            $arguments += @('-p', "module=entry@$target", 'assembleHap')
        }
        & $node (Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js') @arguments --no-daemon 2>&1 |
            Tee-Object -FilePath $log
    }
    $resultCode = $LASTEXITCODE
    if ($resultCode -ne 0) { throw "工具退出码 $resultCode；日志：$log" }
    if ($Action -eq 'Build') {
        $appConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'AppScope\app.json5') -Raw | ConvertFrom-Json
        $artifactDir = Join-Path $projectRoot "artifacts\$($appConfig.app.versionName)"
        New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
        $projectConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'build-profile.json5') -Raw | ConvertFrom-Json
        $product = $projectConfig.app.products | Where-Object { $_.name -eq 'default' } | Select-Object -First 1
        $signature = if ([string]::IsNullOrWhiteSpace($product.signingConfig)) { 'unsigned' } else { 'signed' }
        $hap = Join-Path $projectRoot "entry\build\default\outputs\$target\entry-$target-$signature.hap"
        if (-not (Test-Path -LiteralPath $hap)) { throw "未找到预期的 $signature HAP：$hap" }
        $delivered = Join-Path $artifactDir "hs-mihon-$Mode-$target-$signature.hap"
        Copy-Item -LiteralPath $hap -Destination $delivered -Force
        $hashes = Get-ChildItem -LiteralPath $artifactDir -Filter '*.hap' | Sort-Object Name | ForEach-Object {
            "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
        }
        Set-Content -LiteralPath (Join-Path $artifactDir 'SHA256SUMS') -Value $hashes
        Write-Output "HAP：$delivered"
    }
} finally {
    Pop-Location
    $updated = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'China Standard Time').ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath (Join-Path $taskTemp 'list') -Value "`n- 路径：temp/logs/、temp/tmp/、temp/hvigor-home/、temp/build/；用途：$Action ($Mode)；关联任务：P0；创建/更新时间：$updated（Asia/Hong_Kong）；是否可删除：可，核查交付后清理。"
}
