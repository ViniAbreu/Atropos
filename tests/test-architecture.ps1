param(
    [string]$SourceRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src'),
    [ValidateRange(1, 5000)] [int]$MaximumFileLines = 600,
    [ValidateRange(1, 1000)] [int]$MaximumRoutineLines = 120
)

$ErrorActionPreference = 'Stop'
$sourceRootPath = [System.IO.Path]::GetFullPath($SourceRoot)
$violations = [System.Collections.Generic.List[string]]::new()

function Add-Violation([System.IO.FileInfo]$SourceFile, [int]$LineNumber,
    [string]$Message) {
    $relativePath = $SourceFile.FullName.Substring(
        $sourceRootPath.TrimEnd('\').Length + 1)
    $violations.Add("$relativePath`:$LineNumber $Message")
}

function Test-ForbiddenDependency([string]$Layer, [string]$UnitName,
    [string]$FileName) {
    if ($Layer -eq 'Core') {
        return $UnitName -match '^(Atropos\.(Adapters|Application|VCL)\.|Atropos\.App\.|Vcl\.|Xml\.|Winapi\.|System\.IOUtils$|System\.Win\.Registry$|SimpleParser\.|PasSyntaxTree\.)'
    }
    if ($Layer -eq 'Application') {
        if (($FileName -ne 'Atropos.Application.Factory.pas') -and
            ($UnitName -match '^Atropos\.Adapters\.')) { return $true }
        return $UnitName -match '^(Atropos\.App\.|Atropos\.VCL\.|Vcl\.|Xml\.|Winapi\.|System\.Win\.Registry$|SimpleParser\.|PasSyntaxTree\.)'
    }
    if ($Layer -eq 'Adapters') {
        return $UnitName -match '^(Atropos\.App\.|Atropos\.VCL\.|Vcl\.)'
    }
    return $false
}

Get-ChildItem -LiteralPath $sourceRootPath -Filter '*.pas' -File -Recurse |
    ForEach-Object {
    $sourceFile = $_
    $lines = @(Get-Content -LiteralPath $sourceFile.FullName)
    $relativePath = $sourceFile.FullName.Substring(
        $sourceRootPath.TrimEnd('\').Length + 1)
    $layer = ($relativePath -split '[\\/]')[0]
    if ($lines.Count -gt $MaximumFileLines) {
        Add-Violation $sourceFile $MaximumFileLines "exceeds $MaximumFileLines file lines ($($lines.Count))"
    }

    $insideUses = $false
    $implementationSeen = $false
    $implementationRoutineSeen = $false
    $routineStarts = [System.Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $lineNumber = $index + 1
        if ($line -match '^\s*implementation\s*$') { $implementationSeen = $true }
        if ($line -match '^\s*else\b|\belse\s+if\b') {
            Add-Violation $sourceFile $lineNumber 'contains else'
        }
        if ($implementationSeen -and
            ($line -match '^(class\s+)?(constructor|destructor|procedure|function)\s+[A-Za-z_]')) {
            $implementationRoutineSeen = $true
            $routineStarts.Add($index)
        }
        if ($implementationRoutineSeen -and
            ($line -match '^\s+(class\s+)?(constructor|destructor|procedure|function)\s+[A-Za-z_]')) {
            Add-Violation $sourceFile $lineNumber 'contains a nested named routine'
        }
        if ($line -match '^\s*uses\b') { $insideUses = $true }
        if ($insideUses) {
            foreach ($match in [regex]::Matches($line,
                '\b(?:Atropos\.[A-Za-z0-9_.]+|Vcl\.[A-Za-z0-9_.]+|Xml\.[A-Za-z0-9_.]+|Winapi\.[A-Za-z0-9_.]+|System\.IOUtils|System\.Win\.Registry|SimpleParser\.[A-Za-z0-9_.]+|PasSyntaxTree\.[A-Za-z0-9_.]+)\b')) {
                if (Test-ForbiddenDependency $layer $match.Value $sourceFile.Name) {
                    Add-Violation $sourceFile $lineNumber "has forbidden $Layer dependency $($match.Value)"
                }
            }
            if ($line.Contains(';')) { $insideUses = $false }
        }
    }

    for ($routineIndex = 0; $routineIndex -lt $routineStarts.Count; $routineIndex++) {
        $start = $routineStarts[$routineIndex]
        $finish = $lines.Count - 1
        if ($routineIndex + 1 -lt $routineStarts.Count) {
            $finish = $routineStarts[$routineIndex + 1] - 1
        }
        $routineLength = $finish - $start + 1
        if ($routineLength -gt $MaximumRoutineLines) {
            Add-Violation $sourceFile ($start + 1) "routine exceeds $MaximumRoutineLines lines ($routineLength)"
        }
    }
}

if ($violations.Count -gt 0) {
    throw ($violations -join [Environment]::NewLine)
}

Write-Host 'Architecture guard checks passed.'
