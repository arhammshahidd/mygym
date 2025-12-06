# Script to fix orphaned quotes at end of lines
$files = @(
    "lib\features\trainings\presentation\pages\edit_plan_page.dart",
    "lib\features\profile\presentation\pages\edit_profile_page.dart"
)

foreach ($filePath in $files) {
    $fullPath = Join-Path "mygym" $filePath
    if (Test-Path $fullPath) {
        $lines = Get-Content $fullPath
        $newLines = @()
        
        foreach ($line in $lines) {
            # Remove orphaned quote at end of line (pattern: ,' or ;' or }' or )' at end)
            $line = $line -replace ",\'\s*$", ","
            $line = $line -replace ";\'\s*$", ";"
            $line = $line -replace "\}\'\s*$", "}"
            $line = $line -replace "\)\'\s*$", ")"
            $line = $line -replace "\'\s*$", ""  # Remove standalone ' at end
            
            $newLines += $line
        }
        
        $newLines | Set-Content -Path $fullPath
        Write-Host "Fixed: $filePath"
    }
}

Write-Host "Done"

