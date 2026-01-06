@echo off
setlocal EnableExtensions EnableDelayedExpansion

:MENU
cls
echo ======================================
echo   SC Utilities
echo ======================================
echo.
echo 1. Update scdate.txt (newest shortcut date)
echo 2. Update scdata.txt (shortcut listing)
echo 3. Update BOTH
echo 4. Generate scnew.txt (for Load SC New)
echo 5. Update selections.txt (all folders)
echo 6. Exit
echo.
set /p choice=Choose an option [1-6]:

if "%choice%"=="1" goto SCDATE
if "%choice%"=="2" goto SCDATA
if "%choice%"=="3" goto BOTH
if "%choice%"=="4" goto SCNEW
if "%choice%"=="5" goto SELECTIONS
if "%choice%"=="6" goto END

echo.
echo Invalid choice.
pause
goto MENU


:BOTH
call :DO_SCDATE
call :DO_SCDATA
goto DONE

:SCDATE
call :DO_SCDATE
goto DONE

:SCDATA
call :DO_SCDATA
goto DONE

:SCNEW
call :DO_SCNEW
goto DONE

:SELECTIONS
call :DO_SELECTIONS
goto DONE


:: --------------------------------------------------
:: Update scdate.txt (newest .lnk timestamp)
:: --------------------------------------------------
:DO_SCDATE
echo.
echo Updating scdate.txt files...

for /d /r %%D in (sc) do (
    powershell -NoProfile -Command ^
        "$sc = '%%D';" ^
        "$lnk = Get-ChildItem $sc -Filter *.lnk -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1;" ^
        "if ($lnk) {" ^
        "  $iso = $lnk.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss');" ^
        "  $out = Join-Path (Split-Path $sc -Parent) 'scdate.txt';" ^
        "  Set-Content -Path $out -Value $iso -Encoding ASCII" ^
        "}"
)

exit /b


:: --------------------------------------------------
:: Update scdata.txt
:: --------------------------------------------------
:DO_SCDATA
echo.
echo Updating scdata.txt files...

:: Recursive sc folders (UNCHANGED behavior)
for /d /r %%D in (sc) do (
    if exist "%%D\*.lnk" (
        dir "%%D\*.lnk" /b > "%%D\..\scdata.txt"
    )
)

:: Top-level ".\sc" (grouped target output — FIXED)
if exist "%CD%\sc\*.lnk" (
    powershell -NoProfile -Command ^
        "$out = Join-Path (Get-Location) 'scdata.txt';" ^
        "Remove-Item $out -ErrorAction SilentlyContinue;" ^
        "$ws = New-Object -ComObject WScript.Shell;" ^
        "$groups = @{};" ^
        "Get-ChildItem '.\sc' -Filter *.lnk | ForEach-Object {" ^
        "  $t = $ws.CreateShortcut($_.FullName).TargetPath;" ^
        "  if ($t) {" ^
        "    $folder = Split-Path (Split-Path $t -Parent) -Leaf;" ^
        "    $file = Split-Path $t -Leaf;" ^
        "    if (-not $groups.ContainsKey($folder)) { $groups[$folder] = @() };" ^
        "    $groups[$folder] += $file;" ^
        "  }" ^
        "};" ^
        "$groups.Keys | Sort-Object | ForEach-Object {" ^
        "  Add-Content $out ('\"' + $_ + '\"');" ^
        "  $groups[$_] | Sort-Object | ForEach-Object { Add-Content $out $_ };" ^
        "  Add-Content $out '';" ^
        "}"
)

exit /b


:: --------------------------------------------------
:: Generate scnew.txt (for Load SC New)
:: --------------------------------------------------
:DO_SCNEW
echo.
echo Generating scnew.txt...

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\generate_scnew.ps1"

exit /b


:: --------------------------------------------------
:: Update selections.txt in all folders
:: --------------------------------------------------
:DO_SELECTIONS
echo.
echo Updating selections.txt files...

for /d /r %%D in (.) do (
    set "OUT=%%D\selections.txt"
    > "!OUT!" echo.

    for %%F in ("sc" "Landscape" "Landscape Rotate" "Edit") do (
        echo # %%~F>> "!OUT!"
        if exist "%%D\%%~F\" (
            for /f "delims=" %%A in ('dir /b /a:-d "%%D\%%~F" 2^>nul') do (
                echo %%A>> "!OUT!"
            )
        )
        echo.>> "!OUT!"
    )
)

exit /b



:DONE
echo.
echo Done.
pause
goto MENU


:END
endlocal
exit /b
