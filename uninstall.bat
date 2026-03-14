@echo off
chcp 65001 >nul
title PVP Mod Deinstallation - Ready or Not
color 0C

echo ============================================
echo   PVP MOD DEINSTALLATION
echo ============================================
echo.

set "GAME_PATH="
if exist "C:\Program Files (x86)\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64" (
    set "GAME_PATH=C:\Program Files (x86)\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
)
if exist "C:\Program Files\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64" (
    set "GAME_PATH=C:\Program Files\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
)
if exist "D:\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64" (
    set "GAME_PATH=D:\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
)
if exist "D:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64" (
    set "GAME_PATH=D:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
)

if "%GAME_PATH%"=="" (
    echo [!] Spiel nicht gefunden. Bitte Pfad eingeben:
    set /p "GAME_PATH=Pfad: "
)

if exist "%GAME_PATH%\Mods\PVPMod" (
    rmdir /s /q "%GAME_PATH%\Mods\PVPMod"
    echo [OK] PVPMod Ordner entfernt
) else (
    echo [!] PVPMod nicht gefunden
)

echo.
echo Hinweis: UE4SS wurde NICHT entfernt.
echo PVPMod Eintrag in mods.txt muss manuell entfernt werden.
echo.
echo Deinstallation abgeschlossen!
pause
