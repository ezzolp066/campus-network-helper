param([switch]$Check)

# Windows PowerShell 5.1. No extra runtime or downloaded dependency is needed.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $projectRoot 'src\CampusLogin.ps1'
$jsPath = Join-Path $projectRoot 'src\PortalAutomation.js'
$outputPath = Join-Path $projectRoot '校园网助手.cmd'

function Normalize-Lines([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

$source = Normalize-Lines ([IO.File]::ReadAllText($sourcePath))
$javascript = Normalize-Lines ([IO.File]::ReadAllText($jsPath))
$loader = '$automation = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot ''PortalAutomation.js''))'
if ([regex]::Matches($source, [regex]::Escape($loader)).Count -ne 1) {
    throw 'Expected exactly one portal script loader in src/CampusLogin.ps1.'
}
if ($javascript -match '(?m)^''@$') { throw 'JavaScript conflicts with the PowerShell here-string delimiter.' }
$inlineScript = '$automation = @''' + "`n" + $javascript.TrimEnd() + "`n'@"
$embeddedSource = $source.Replace($loader, $inlineScript)
if ($embeddedSource.Contains('$PSScriptRoot')) { throw 'Generated program still has an external source dependency.' }

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($embeddedSource, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# CheckOnly stops before credential access, browser launch, and network traffic.
& ([scriptblock]::Create($embeddedSource)) -CheckOnly

$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($embeddedSource))
$launcher = @'
@echo off
chcp 65001 >nul
title 校园网助手 1.1
echo 校园网助手 1.1 - 正在连接，请稍候……
set "CAMPUS_ASSISTANT_FILE=%~f0"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -Command "$r=[IO.File]::ReadAllText($env:CAMPUS_ASSISTANT_FILE);$p=$r.Substring($r.LastIndexOf(':CAMPUS_PAYLOAD')+15).Trim();try{& ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))))}catch{Write-Host 'Unable to start Campus Network Assistant.';exit 1}"
if errorlevel 1 pause
exit /b
:CAMPUS_PAYLOAD
'@
$content = ((Normalize-Lines $launcher).Replace("`n", "`r`n")) + "`r`n" + $encoded + "`r`n"
if ($Check) {
    if (-not (Test-Path -LiteralPath $outputPath)) { throw 'Missing output. Run this script without -Check first.' }
    if ([IO.File]::ReadAllText($outputPath) -cne $content) { throw 'Output differs from source. Rebuild the CMD file.' }
    Write-Output 'PASS: Embedded source parses, safe initialization succeeds, and the CMD matches source.'
} else {
    [IO.File]::WriteAllText($outputPath, $content, [Text.UTF8Encoding]::new($false))
    Write-Output ('Built: ' + $outputPath)
}
