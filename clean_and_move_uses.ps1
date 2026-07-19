$ErrorActionPreference = "Continue"

Write-Host "Removing all .bak files..."
$bakFiles = Get-ChildItem -Path . -Filter *.bak -Recurse
if ($bakFiles) {
    $bakFiles | Remove-Item -Force
    Write-Host "$($bakFiles.Count) .bak files removed."
} else {
    Write-Host "No .bak files found."
}

Write-Host "Moving implementation uses to interface uses in .pas files..."
$files = Get-ChildItem -Path . -Filter *.pas -Recurse
$updatedCount = 0

foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    
    # Find implementation uses
    if ($content -match '(?ism)^[ \t]*implementation\s+uses\s+(.*?);') {
        $implUses = $matches[1]
        
        # Remove the implementation uses block, keep 'implementation'
        $newContent = $content -replace '(?ism)^[ \t]*implementation\s+uses\s+.*?;', 'implementation'
        
        # Add to interface uses
        if ($newContent -match '(?ism)^[ \t]*interface\s+uses\s+(.*?);') {
            $interfaceUses = $matches[1]
            $newInterfaceUses = "interface`r`nuses`r`n  $interfaceUses, $implUses;"
            $newContent = $newContent -replace '(?ism)^[ \t]*interface\s+uses\s+.*?;', $newInterfaceUses
        } else {
            $newInterfaceUses = "interface`r`nuses`r`n  $implUses;"
            $newContent = $newContent -replace '(?im)^[ \t]*interface\b', $newInterfaceUses
        }
        
        [System.IO.File]::WriteAllText($file.FullName, $newContent, [System.Text.Encoding]::UTF8)
        Write-Host "Updated $($file.Name)"
        $updatedCount++
    }
}

Write-Host "Done. Updated $updatedCount files."
