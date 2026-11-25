param([switch]$Test, [switch]$Editor, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$candidates = @(
    (Join-Path $root 'runtime\Godot.exe'),
    'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
)
$engine = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $engine) {
    $command = Get-Command godot,godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $engine = $command.Source }
}
if (-not $engine) { throw 'Godot 4.3+ not found. Place Godot.exe inside runtime/ or add Godot to PATH.' }
# Keep all application data with this project; no installation is required.
$env:APPDATA = Join-Path $root '.runtime\Roaming'
$env:LOCALAPPDATA = Join-Path $root '.runtime\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$arguments = @('--path', $root, '--log-file', (Join-Path $root 'runtime.log'))
if ($Editor) { $arguments += '--editor' }
if ($Test) { $arguments += @('--headless', '--fixed-fps', '60', '--', '--self-test') }
elseif ($Capture) { $arguments += @('--', '--capture') }
$quotedArguments = $arguments | ForEach-Object { '"{0}"' -f $_ }
$process = Start-Process -FilePath $engine -ArgumentList $quotedArguments -WorkingDirectory $root -Wait -PassThru
exit $process.ExitCode
