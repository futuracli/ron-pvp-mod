@echo off
chcp 65001 >nul
title PVP Mod Auto-Updater
color 0B

echo ============================================
echo   PVP MOD AUTO-UPDATER
echo ============================================
echo.

:: Steam-Pfad finden
set "GAME_PATH="
for %%P in (
    "C:\Program Files (x86)\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
    "C:\Program Files\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
    "D:\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
    "D:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
    "E:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
    "F:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
) do (
    if exist %%P set "GAME_PATH=%%~P"
)

if "%GAME_PATH%"=="" (
    echo [!] Ready or Not nicht gefunden!
    set /p "GAME_PATH=Pfad eingeben: "
)

echo [OK] Spiel: %GAME_PATH%
echo.

:: Neueste Version von GitHub herunterladen
echo [1/3] Lade neueste Version herunter...
set "DL_URL=https://raw.githubusercontent.com/futuracli/ron-pvp-mod/main/PVPMod/Scripts/main.lua"
set "DL_DEST=%GAME_PATH%\Mods\PVPMod\Scripts\main.lua"

:: Ordner erstellen falls noetig
if not exist "%GAME_PATH%\Mods\PVPMod\Scripts" (
    mkdir "%GAME_PATH%\Mods\PVPMod\Scripts"
)
if not exist "%GAME_PATH%\Mods\PVPMod\enabled.txt" (
    echo.> "%GAME_PATH%\Mods\PVPMod\enabled.txt"
)

:: Download mit PowerShell
powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_DEST%' -ErrorAction Stop; Write-Host '[OK] main.lua heruntergeladen!' } catch { Write-Host '[FEHLER] Download fehlgeschlagen:' $_.Exception.Message }"

:: mods.txt pruefen
echo.
echo [2/3] Pruefe mods.txt...
if exist "%GAME_PATH%\Mods\mods.txt" (
    findstr /C:"PVPMod" "%GAME_PATH%\Mods\mods.txt" >nul 2>&1
    if errorlevel 1 (
        echo PVPMod : 1>> "%GAME_PATH%\Mods\mods.txt"
        echo [OK] PVPMod hinzugefuegt
    ) else (
        echo [OK] PVPMod bereits aktiv
    )
)

:: UE4SS Konsole aktivieren
echo.
echo [3/3] UE4SS Konsole...
if exist "%GAME_PATH%\UE4SS-settings.ini" (
    powershell -Command "(Get-Content '%GAME_PATH%\UE4SS-settings.ini') -replace 'ConsoleEnabled = 0','ConsoleEnabled = 1' -replace 'GuiConsoleVisible = 0','GuiConsoleVisible = 1' | Set-Content '%GAME_PATH%\UE4SS-settings.ini'"
    echo [OK] Konsole aktiviert
)

echo.
echo ============================================
echo   UPDATE ABGESCHLOSSEN!
echo   Starte Ready or Not und druecke F5
echo ============================================
echo.
pause
