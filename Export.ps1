param(
    [ValidateSet('Web', 'Windows', 'All')][string]$Target = 'Web',
    [switch]$DebugBuild
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$engine = Join-Path $root 'runtime\Godot.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Missing runtime/Godot.exe.' }
function Invoke-Godot([string[]]$EngineArguments) {
    # The bundled engine is a Windows GUI executable: explicitly wait for it.
    $quoted = $EngineArguments | ForEach-Object { '"{0}"' -f $_ }
    $process = Start-Process -FilePath $engine -ArgumentList $quoted -WorkingDirectory $root -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Godot exited with code $($process.ExitCode). Check the export log in build/." }
}
# Keep import caches and editor data inside this workspace, just like Start.ps1.
$env:APPDATA = Join-Path $root '.runtime\Roaming'
$env:LOCALAPPDATA = Join-Path $root '.runtime\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$build = Join-Path $root 'build'
$web = Join-Path $root 'web-dist'
foreach ($directory in @($build, $web)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    [IO.File]::WriteAllText((Join-Path $directory '.gdignore'), '')
}
Invoke-Godot @('--headless', '--path', $root, '--editor', '--import', '--log-file', (Join-Path $build 'export-import.log'))
$mode = if ($DebugBuild) { '--export-debug' } else { '--export-release' }
if ($Target -in @('Web', 'All')) {
    Invoke-Godot @('--headless', '--path', $root, $mode, 'Web', (Join-Path $web 'index.html'), '--log-file', (Join-Path $build 'export-web.log'))
    foreach ($file in @('scene-files.js', 'scene-files.css')) {
        Copy-Item -LiteralPath (Join-Path $root "web\$file") -Destination $web -Force
    }
    $licenses = Join-Path $web 'licenses'
    New-Item -ItemType Directory -Force -Path $licenses | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'runtime\GODOT_LICENSE.txt'),(Join-Path $root 'runtime\THIRD_PARTY_NOTICES.json'),(Join-Path $root 'assets\fonts\OFL.txt') -Destination $licenses -Force
    Write-Output "Web exported: $web\index.html"
}
if ($Target -in @('Windows', 'All')) {
    $windows = Join-Path $build 'windows'
    New-Item -ItemType Directory -Force -Path $windows | Out-Null
    Invoke-Godot @('--headless', '--path', $root, $mode, 'Windows Desktop', (Join-Path $windows 'TrackPlayground.exe'), '--log-file', (Join-Path $build 'export-windows.log'))
    Copy-Item -LiteralPath (Join-Path $root 'runtime\GODOT_LICENSE.txt'),(Join-Path $root 'runtime\THIRD_PARTY_NOTICES.json'),(Join-Path $root 'assets\fonts\OFL.txt') -Destination $windows -Force
    Write-Output "Windows exported: $windows\TrackPlayground.exe"
}
