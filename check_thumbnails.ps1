# PowerShell script to check for thumbnail issues in project subfolders.

# --- CONFIGURATION ---
$videoExtensions = @("*.mp4", "*.avi", "*.mov", "*.mkv")
$thumbWidth = 256
$thumbHeight = 256

# --- SCRIPT ---

function Get-ProjectFolders {
    Get-ChildItem -Path . -Directory | Where-Object {
        $_.Name.ToLower() -notin @("sc", "landscape", "landscape rotate", "edit", "thumbnails", "edit thumbnails")
    }
}

function Get-VideoFiles {
    param($projectFolder)
    $videoFiles = @()
    # Videos in the root of the project folder
    $videoFiles += Get-ChildItem -Path $projectFolder.FullName -Include $videoExtensions -Recurse -Depth 1 -File
    # Videos in Landscape, Landscape Rotate, Edit subfolders
    foreach ($subfolder in @("Landscape", "Landscape Rotate", "Edit")) {
        $subfolderPath = Join-Path $projectFolder.FullName $subfolder
        if (Test-Path $subfolderPath) {
            $videoFiles += Get-ChildItem -Path $subfolderPath -Include $videoExtensions -File
        }
    }
    return $videoFiles
}

# Add the System.Drawing assembly to check image dimensions
Add-Type -AssemblyName System.Drawing

$allProjectFolders = Get-ProjectFolders
$overallIssues = @{
    MissingRegular = 0
    MissingEdit = 0
    WrongDimensions = 0
    Obsolete = 0
}
$fixCommands = @()

Write-Host "Starting thumbnail check for all project folders..." -ForegroundColor Yellow

foreach ($folder in $allProjectFolders) {
    Write-Host "`n--------------------------------------------------"
    Write-Host "Checking Project: $($folder.Name)" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------"

    $videos = Get-VideoFiles -projectFolder $folder
    $videoBasenames = $videos | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }

    $regularThumbsDir = Join-Path $folder.FullName "Thumbnails"
    $editThumbsDir = Join-Path $folder.FullName "Edit Thumbnails"

    $projectIssues = @{
        MissingRegular = New-Object System.Collections.Generic.List[string]
        MissingEdit = New-Object System.Collections.Generic.List[string]
        WrongDimensions = New-Object System.Collections.Generic.List[string]
        ObsoleteRegular = New-Object System.Collections.Generic.List[string]
        ObsoleteEdit = New-Object System.Collections.Generic.List[string]
    }

    # 1. Check for missing regular thumbnails
    if (Test-Path $regularThumbsDir) {
        foreach ($video in $videos) {
            $thumbName = "$([System.IO.Path]::GetFileNameWithoutExtension($video.Name)).jpg"
            $thumbPath = Join-Path $regularThumbsDir $thumbName
            if (-not (Test-Path $thumbPath)) {
                $projectIssues.MissingRegular.Add($video.FullName)
            }
        }
    } else {
        # If the whole Thumbnails dir is missing, all are missing
        $videos.ForEach({ $projectIssues.MissingRegular.Add($_.FullName) })
    }


    # 2. Check for missing edit thumbnails
    if (Test-Path $editThumbsDir) {
        foreach ($video in $videos) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($video.Name)
            $isMissingAll = $true
            for ($i = 1; $i -le 10; $i++) {
                $thumbName = "${baseName}_${i}.jpg"
                $thumbPath = Join-Path $editThumbsDir $thumbName
                if (Test-Path $thumbPath) {
                    $isMissingAll = $false
                    break
                }
            }
            if ($isMissingAll) {
                $projectIssues.MissingEdit.Add($video.FullName)
            }
        }
    } else {
         # If the whole Edit Thumbnails dir is missing, all are missing
        $videos.ForEach({ $projectIssues.MissingEdit.Add($_.FullName) })
    }


    # 3. Check existing thumbnails for wrong dimensions and obsolescence
    if (Test-Path $regularThumbsDir) {
        $regularThumbs = Get-ChildItem -Path $regularThumbsDir -Filter *.jpg -File
        foreach ($thumb in $regularThumbs) {
            $thumbBasename = [System.IO.Path]::GetFileNameWithoutExtension($thumb.Name)
            if ($thumbBasename -in $videoBasenames) {
                try {
                    $img = [System.Drawing.Image]::FromFile($thumb.FullName)
                    if ($img.Width -gt $thumbWidth -or $img.Height -gt $thumbHeight -or ($img.Width -ne $thumbWidth -and $img.Height -ne $thumbHeight)) {
                        $projectIssues.WrongDimensions.Add($thumb.FullName)
                    }
                } catch {
                    Write-Warning "Could not read image file: $($thumb.FullName)"
                } finally {
                    if ($img) { $img.Dispose() }
                }
            } else {
                $projectIssues.ObsoleteRegular.Add($thumb.FullName)
            }
        }
    }
     if (Test-Path $editThumbsDir) {
        $editThumbs = Get-ChildItem -Path $editThumbsDir -Filter *.jpg -File
        foreach ($thumb in $editThumbs) {
            $videoBasename = $thumb.Name.Substring(0, $thumb.Name.LastIndexOf('_'))
             if ($videoBasename -in $videoBasenames) {
                try {
                    $img = [System.Drawing.Image]::FromFile($thumb.FullName)
                    if ($img.Width -gt $thumbWidth -or $img.Height -gt $thumbHeight -or ($img.Width -ne $thumbWidth -and $img.Height -ne $thumbHeight)) {
                        $projectIssues.WrongDimensions.Add($thumb.FullName)
                    }
                } catch {
                     Write-Warning "Could not read image file: $($thumb.FullName)"
                } finally {
                    if ($img) { $img.Dispose() }
                }
            } else {
                 $projectIssues.ObsoleteEdit.Add($thumb.FullName)
            }
        }
    }

    # --- Report for the current project ---
    $totalProjectIssues = $projectIssues.MissingRegular.Count + $projectIssues.MissingEdit.Count + $projectIssues.WrongDimensions.Count + $projectIssues.ObsoleteRegular.Count + $projectIssues.ObsoleteEdit.Count
    if ($totalProjectIssues -eq 0) {
        Write-Host "OK - No thumbnail issues found." -ForegroundColor Green
    } else {
        if ($projectIssues.MissingRegular.Count -gt 0) {
            Write-Host " - Missing Regular Thumbnails: $($projectIssues.MissingRegular.Count)" -ForegroundColor Red
            $overallIssues.MissingRegular += $projectIssues.MissingRegular.Count
            $fixCommands += 'if not exist "' + $regularThumbsDir + '" mkdir "' + $regularThumbsDir + '"'
            $projectIssues.MissingRegular | ForEach-Object {
                $videoPath = $_
                $thumbName = "$([System.IO.Path]::GetFileNameWithoutExtension($videoPath)).jpg"
                $thumbPath = Join-Path $regularThumbsDir $thumbName
                $fixCommands += "ffmpeg -y -i ""$videoPath"" -ss 00:00:02.000 -frames:v 1 -vf ""scale=${thumbWidth}:${thumbHeight}:force_original_aspect_ratio=decrease"" ""$thumbPath"""
            }
        }
        if ($projectIssues.MissingEdit.Count -gt 0) {
            Write-Host " - Missing Edit Mode Thumbnails: $($projectIssues.MissingEdit.Count)" -ForegroundColor Red
            $overallIssues.MissingEdit += $projectIssues.MissingEdit.Count
            $fixCommands += 'if not exist "' + $editThumbsDir + '" mkdir "' + $editThumbsDir + '"'
            $projectIssues.MissingEdit | ForEach-Object {
                $videoPath = $_
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($videoPath)
                try {
                    $durationStr = ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i $videoPath
                    $durationInt = [math]::Floor([double]::Parse($durationStr))
                    if ($durationInt -eq 0) { $durationInt = 10 }
                    $interval = [math]::Floor($durationInt / 10)
                    if ($interval -eq 0) { $interval = 1 }

                    for ($i = 1; $i -le 10; $i++) {
                        $timestamp = ($i - 1) * $interval
                        $thumbName = "${baseName}_${i}.jpg"
                        $thumbPath = Join-Path $editThumbsDir $thumbName
                        $fixCommands += "ffmpeg -ss $timestamp -i ""$videoPath"" -vframes 1 -vf ""scale=${thumbWidth}:${thumbHeight}:force_original_aspect_ratio=decrease"" -y ""$thumbPath"" >nul 2>&1"
                    }
                } catch {
                    Write-Warning "Failed to get duration for $($videoPath). Skipping edit thumbnail generation for this file."
                }
            }
        }
        if ($projectIssues.WrongDimensions.Count -gt 0) {
            Write-Host " - Thumbnails with Wrong Dimensions: $($projectIssues.WrongDimensions.Count)" -ForegroundColor Red
            $overallIssues.WrongDimensions += $projectIssues.WrongDimensions.Count
             $projectIssues.WrongDimensions | ForEach-Object {
                $thumbPath = $_
                # This is a bit tricky, we need to find the original video.
                # For now, we just delete it and the user can re-run to generate the missing one.
                $fixCommands += "del ""$thumbPath"""
            }
        }
        if ($projectIssues.ObsoleteRegular.Count -gt 0) {
            Write-Host " - Obsolete Regular Thumbnails: $($projectIssues.ObsoleteRegular.Count)" -ForegroundColor Red
            $overallIssues.Obsolete += $projectIssues.ObsoleteRegular.Count
            $projectIssues.ObsoleteRegular | ForEach-Object { $fixCommands += "del ""$_""" }
        }
         if ($projectIssues.ObsoleteEdit.Count -gt 0) {
            Write-Host " - Obsolete Edit Thumbnails: $($projectIssues.ObsoleteEdit.Count)" -ForegroundColor Red
            $overallIssues.Obsolete += $projectIssues.ObsoleteEdit.Count
            $projectIssues.ObsoleteEdit | ForEach-Object { $fixCommands += "del ""$_""" }
        }
    }
}

# --- Overall Summary and Fix Prompt ---
Write-Host "`n=================================================="
Write-Host "Overall Summary" -ForegroundColor Yellow
Write-Host "=================================================="
$totalOverallIssues = $overallIssues.MissingRegular + $overallIssues.MissingEdit + $overallIssues.WrongDimensions + $overallIssues.Obsolete
if ($totalOverallIssues -gt 0) {
    Write-Host "Missing Regular Thumbnails: $($overallIssues.MissingRegular)"
    Write-Host "Missing Edit Sets:          $($overallIssues.MissingEdit)"
    Write-Host "Wrong Dimensions:           $($overallIssues.WrongDimensions)"
    Write-Host "Obsolete Thumbnails:        $($overallIssues.Obsolete)"

    $choice = Read-Host "`nIssues found. Would you like to generate a 'fix_thumbnails.bat' script to resolve them? (y/n)"
    if ($choice -eq 'y') {
        $fixScriptContent = @"
@echo off
setlocal enabledelayedexpansion
echo Starting thumbnail fix process...
$($fixCommands -join "`r`n")
echo.
echo Thumbnail fix process complete.
pause
"@
        Set-Content -Path "fix_thumbnails.bat" -Value $fixScriptContent
        Write-Host "`nfix_thumbnails.bat has been generated. Run it to fix the issues." -ForegroundColor Green
    }
} else {
    Write-Host "All project thumbnails are in good shape!" -ForegroundColor Green
}
