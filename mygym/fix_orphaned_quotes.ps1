# Script to remove orphaned quotes left after removing print statements
$files = @(
    "lib\features\trainings\presentation\pages\edit_plan_page.dart",
    "lib\features\profile\presentation\pages\edit_profile_page.dart"
)

foreach ($filePath in $files) {
    $fullPath = Join-Path "mygym" $filePath
    if (Test-Path $fullPath) {
        $content = Get-Content $fullPath -Raw
        
        # Remove orphaned quotes at end of lines (pattern: ';' at end of line)
        $content = $content -replace "';'\r?\n", "`r`n"
        $content = $content -replace "';'$", ""
        
        # Also fix cases where there's a space before the orphaned quote
        $content = $content -replace " ';'\r?\n", "`r`n"
        $content = $content -replace " ';'$", ""
        
        Set-Content -Path $fullPath -Value $content -NoNewline
        Write-Host "Fixed: $filePath"
    }
}

Write-Host "Done fixing orphaned quotes"

