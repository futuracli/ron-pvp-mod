============================================
PVP MOD v3.0 fuer Ready or Not
============================================

VORAUSSETZUNG:
- Ready or Not (Steam)
- UE4SS v3.0.1 (wird beim Setup erklaert)

============================================
INSTALLATION (2 Schritte)
============================================

SCHRITT 1: UE4SS installieren (einmalig)
-----------------------------------------
1. Lade UE4SS v3.0.1 herunter:
   https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1

2. Entpacke den GESAMTEN Inhalt der ZIP nach:
   ...\Steam\steamapps\common\Ready Or Not\ReadyOrNot\Binaries\Win64\

   Dort sollte jetzt dwmapi.dll und UE4SS.dll liegen.

SCHRITT 2: PVP Mod installieren
-----------------------------------------
Doppelklick auf: install.bat

Das Script macht alles automatisch:
- Findet dein Ready or Not
- Kopiert den Mod
- Aktiviert die Konsole
- Fertig!

============================================
STEUERUNG
============================================

F5           = PVP Menu oeffnen/schliessen
F6           = Scoreboard anzeigen
F7           = Debug Info
Numpad 1-9   = Menu-Auswahl

Im Menu:
  [1] Neues PVP Match starten
  [2] PVP stoppen
  [3] Naechste Runde
  [4] Team-Management (Teams festlegen)
  [5] Spielmodus (TDM / FFA)
  [6] Einstellungen
  [7] Alle teleportieren
  [8] Scoreboard
  [9] Debug

============================================
FEATURES
============================================

- 2 Spielmodi: Team Deathmatch & Free For All
- Team-Spawns: Jedes Team spawnt zusammen an einem Punkt
- Teams manuell festlegen oder zufaellig zuweisen
- Teams tauschen, einzelne Spieler wechseln
- Scoreboard mit Kills/Deaths
- Kill-Feed
- Einstellbare Runden (3/5/7)
- Schaden-Multiplikator (1x/2x/10x)
- Friendly Fire toggle

============================================
MULTIPLAYER / MIT FREUNDEN SPIELEN
============================================

WICHTIG: Alle Spieler brauchen:
1. UE4SS installiert
2. Den PVP Mod installiert

Einfach diese ZIP an deine Freunde schicken!
Jeder fuehrt install.bat aus und fertig.

Der Host startet ein Coop-Match, alle joinen,
dann drueckt der Host F5 um PVP zu starten.

============================================
DEINSTALLATION
============================================

Doppelklick auf: uninstall.bat

============================================
FEHLERBEHEBUNG
============================================

Problem: "Nichts passiert wenn ich F5 druecke"
-> Pruefe ob UE4SS.dll im Win64 Ordner liegt
-> Pruefe ob in Mods/mods.txt "PVPMod : 1" steht
-> Starte das Spiel neu (nicht nur die Map)

Problem: "UE4SS Fenster ist weiss/leer"
-> In UE4SS-settings.ini: GraphicsAPI = dx11

Problem: "Spiel crasht beim Start"
-> In UE4SS-settings.ini: bUseUObjectArrayCache = false

Problem: "Alte xinput1_3.dll im Ordner"
-> Loesche xinput1_3.dll, die crasht das Spiel!
