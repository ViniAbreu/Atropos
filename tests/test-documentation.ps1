$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$markdownFiles = @(
    Get-Item -LiteralPath (Join-Path $repositoryRoot 'README.md')
    Get-Item -LiteralPath (Join-Path $repositoryRoot 'CONTRIBUTING.md')
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'docs') -Filter '*.md' -File -Recurse
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Fixtures') -Filter '*.md' -File -Recurse
)
$failures = [System.Collections.Generic.List[string]]::new()
$portugueseProsePattern = '(?i)\b(não|para|projeto|projetos|compilação|configuração|plataforma|antes|depois|alterações|arquivos|fontes|relatório|relatórios|segurança|limitações|documentação|instalação|contribuir|usuário|unidade|unidades|nenhuma|quando|somente|diretório|execução|cobertura|testes)\b|[áàâãéêíóôõúç]'

foreach ($markdownFile in $markdownFiles) {
    $content = Get-Content -Raw -LiteralPath $markdownFile.FullName
    foreach ($match in [regex]::Matches($content, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Split('#')[0]
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match '^(https?|mailto):') {
            continue
        }
        $resolvedTarget = Join-Path $markdownFile.DirectoryName $target
        if (-not (Test-Path -LiteralPath $resolvedTarget)) {
            $failures.Add("Broken link in $($markdownFile.FullName): $target")
        }
    }
    if ($content -match '\b\d+ automated tests\b' -or $content -match '\b\d+ tests and smoke\b') {
        $failures.Add("Brittle test count in $($markdownFile.FullName)")
    }
    if ($content -match $portugueseProsePattern) {
        $failures.Add("Portuguese prose in English documentation: $($markdownFile.FullName)")
    }
}

$cliDocumentation = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'docs\cli.md')
foreach ($requiredOption in @('-dproj', '--remove', '--move', '--dry-run', '--target', '--output', '--debug', '--help')) {
    if ($cliDocumentation -notmatch [regex]::Escape($requiredOption)) {
        $failures.Add("CLI option is not documented: $requiredOption")
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Documentation consistency checks passed.'
