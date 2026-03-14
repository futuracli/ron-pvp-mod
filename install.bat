@echo off
chcp 65001 >nul
title PVP Mod Installer - Ready or Not
color 0A

echo ============================================
echo   PVP MOD INSTALLER fuer Ready or Not
echo   Version 3.0
echo ============================================
echo.

:: Steam-Pfad automatisch finden
set "GAME_PATH="

:: Standard Steam Pfade pruefen
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
if exist "E:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64" (
    set "GAME_PATH=E:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
)
if exist "F:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64" (
    set "GAME_PATH=F:\SteamLibrary\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64"
)

if "%GAME_PATH%"=="" (
    echo [!] Ready or Not konnte nicht automatisch gefunden werden!
    echo.
    echo Bitte gib den Pfad zu deinem Ready or Not Ordner ein.
    echo Beispiel: D:\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64
    echo.
    set /p "GAME_PATH=Pfad: "
)

:: Pruefen ob der Pfad existiert
if not exist "%GAME_PATH%" (
    echo [FEHLER] Der Pfad existiert nicht: %GAME_PATH%
    echo Bitte starte das Script erneut und gib den korrekten Pfad ein.
    pause
    exit /b 1
)

echo [OK] Spiel gefunden: %GAME_PATH%
echo.

:: Pruefen ob UE4SS installiert ist
echo [1/4] Pruefe UE4SS...
if exist "%GAME_PATH%\UE4SS.dll" (
    echo [OK] UE4SS ist bereits installiert!
) else (
    echo [!] UE4SS ist NICHT installiert!
    echo.
    echo Du musst UE4SS v3.0.1 zuerst installieren:
    echo 1. Lade herunter: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1
    echo 2. Entpacke den Inhalt nach: %GAME_PATH%
    echo 3. Starte dieses Script erneut
    echo.
    echo Oeffne den Download-Link? (J/N)
    set /p "OPEN_DL=Eingabe: "
    if /i "%OPEN_DL%"=="J" (
        start https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1
    )
    pause
    exit /b 1
)

:: PVPMod kopieren
echo.
echo [2/4] Installiere PVP Mod...
if not exist "%GAME_PATH%\Mods" mkdir "%GAME_PATH%\Mods"
if not exist "%GAME_PATH%\Mods\PVPMod" mkdir "%GAME_PATH%\Mods\PVPMod"
if not exist "%GAME_PATH%\Mods\PVPMod\Scripts" mkdir "%GAME_PATH%\Mods\PVPMod\Scripts"

:: Mod-Dateien kopieren
copy /Y "%~dp0PVPMod\Scripts\main.lua" "%GAME_PATH%\Mods\PVPMod\Scripts\main.lua" >nul
copy /Y "%~dp0PVPMod\enabled.txt" "%GAME_PATH%\Mods\PVPMod\enabled.txt" >nul
echo [OK] PVP Mod Dateien kopiert!

:: mods.txt aktualisieren
echo.
echo [3/4] Aktualisiere mods.txt...
if exist "%GAME_PATH%\Mods\mods.txt" (
    findstr /C:"PVPMod" "%GAME_PATH%\Mods\mods.txt" >nul 2>&1
    if errorlevel 1 (
        echo PVPMod : 1>> "%GAME_PATH%\Mods\mods.txt"
        echo [OK] PVPMod zu mods.txt hinzugefuegt!
    ) else (
        echo [OK] PVPMod ist bereits in mods.txt!
    )
) else (
    echo PVPMod : 1> "%GAME_PATH%\Mods\mods.txt"
    echo [OK] mods.txt erstellt!
)

:: UE4SS-settings anpassen (Konsole aktivieren)
echo.
echo [4/4] Konfiguriere UE4SS Konsole...
if exist "%GAME_PATH%\UE4SS-settings.ini" (
    powershell -Command "(Get-Content '%GAME_PATH%\UE4SS-settings.ini') -replace 'ConsoleEnabled = 0','ConsoleEnabled = 1' -replace 'GuiConsoleVisible = 0','GuiConsoleVisible = 1' | Set-Content '%GAME_PATH%\UE4SS-settings.ini'"
    echo [OK] UE4SS Konsole aktiviert!
) else (
    echo [!] UE4SS-settings.ini nicht gefunden, uebersprungen
)

:: Fertig
echo.
echo ============================================
echo   INSTALLATION ABGESCHLOSSEN!
echo ============================================
echo.
echo   So benutzt du den PVP Mod:
echo   1. Starte Ready or Not
echo   2. Lade eine Map (Multiplayer/Coop)
echo   3. Druecke F5 fuer das PVP Menu
echo   4. Numpad 1-9 fuer Menu-Auswahl
echo.
echo   F5 = PVP Menu
echo   F6 = Scoreboard
echo   F7 = Debug Info
echo.
echo   Alle Spieler im Coop brauchen diesen Mod!
echo ============================================
echo.
pause
