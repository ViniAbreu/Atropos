$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $repositoryRoot 'src'
$violations = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $sourceRoot -Filter '*.pas' -File -Recurse | ForEach-Object {
    $sourceFile = $_
    $lineNumber = 0
    Get-Content -LiteralPath $sourceFile.FullName | ForEach-Object {
        $lineNumber++
        if ($_ -match '^\s*else\b|\belse\s+if\b') {
            $relativePath = [System.IO.Path]::GetRelativePath($repositoryRoot, $sourceFile.FullName)
            $violations.Add("$relativePath`:$lineNumber contains else")
        }
    }
}

if ($violations.Count -gt 0) {
    throw ($violations -join [Environment]::NewLine)
}

Write-Host 'Architecture guard checks passed.'
