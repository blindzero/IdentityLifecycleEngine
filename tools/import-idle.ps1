[CmdletBinding()]
param()

# Developer helper to validate module import behavior in a repo clone.

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'

Remove-Module -Name IdLE, IdLE.Core -Force -ErrorAction SilentlyContinue

Import-Module -Name $idleManifest -Force -ErrorAction Stop

Get-Module IdLE, IdLE.Core |
    Select-Object Name, Version, Path |
    Format-Table -AutoSize
