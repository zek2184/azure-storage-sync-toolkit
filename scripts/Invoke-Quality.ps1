[CmdletBinding()]
param(
    [switch]$RequireAnalyzer,
    [switch]$RequirePester
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($path in @('src', 'scripts', 'tests')) {
    foreach ($file in @(Get-ChildItem -Path (Join-Path $repositoryRoot $path) -Recurse -File)) {
        if ($file.Extension -in @('.ps1', '.psm1', '.psd1')) {
            $sourceFiles.Add($file)
        }
    }
}
$sourceFiles.Add((Get-Item -LiteralPath (Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1')))

$syntaxErrors = New-Object System.Collections.Generic.List[object]
foreach ($file in $sourceFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    foreach ($parseError in @($parseErrors)) {
        $syntaxErrors.Add($parseError)
    }
}

if ($syntaxErrors.Count -gt 0) {
    $syntaxErrors | Format-Table -AutoSize
    throw "PowerShell syntax validation found $($syntaxErrors.Count) error(s)."
}
Write-Output "PASS: parsed $($sourceFiles.Count) PowerShell files without syntax errors."

& (Join-Path $PSScriptRoot 'Test-Foundation.ps1')
& (Join-Path $PSScriptRoot 'Test-Inventory.ps1')
& (Join-Path $PSScriptRoot 'Test-Preview.ps1')
& (Join-Path $PSScriptRoot 'Test-Apply.ps1')

$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $analyzer) {
    if ($RequireAnalyzer) {
        throw 'PSScriptAnalyzer is required but is not installed.'
    }
    Write-Warning 'PSScriptAnalyzer is not installed; analyzer checks were skipped.'
}
else {
    Import-Module $analyzer.Path -Force
    $settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'
    $findings = @()
    foreach ($path in @('src', 'scripts', 'tests')) {
        $findings += @(Invoke-ScriptAnalyzer -Path (Join-Path $repositoryRoot $path) -Recurse -Settings $settingsPath)
    }
    if ($findings.Count -gt 0) {
        $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }
    Write-Output 'PASS: PSScriptAnalyzer reported no errors or warnings.'
}

$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $pester) {
    if ($RequirePester) {
        throw 'Pester 5 or later is required but is not installed.'
    }
    Write-Warning 'Pester 5 or later is not installed; Pester tests were skipped.'
}
else {
    Import-Module $pester.Path -Force
    $pesterParameters = @{
        Path = Join-Path $repositoryRoot 'tests'
        PassThru = $true
    }
    if ($env:GITHUB_ACTIONS -eq 'true') {
        $pesterParameters.CI = $true
    }
    $result = Invoke-Pester @pesterParameters
    if ($result.FailedCount -gt 0) {
        throw "Pester reported $($result.FailedCount) failing test(s)."
    }
    Write-Output "PASS: Pester completed $($result.TotalCount) test(s)."
}

