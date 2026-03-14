--[[
    PVP MOD v3.1 for Ready or Not (UE4SS)

    F5       = PVP Menu
    F6       = Scoreboard
    F7       = Debug
    Numpad 1-9 = Menu-Auswahl
--]]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local CONFIG = {
    ROUNDS_TO_WIN = 5,
    FRIENDLY_FIRE = true,
    TEAM_SPAWN_RADIUS = 250,
    SPAWN_SCATTER_RANGE = 4000,
    DEBUG = true,
    GAMEMODE_TDM = 1,
    GAMEMODE_FFA = 2,
    GAMEMODE = 1,
    DAMAGE_MULTIPLIER = 1.0,
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local PVP = {
    enabled = false,
    currentRound = 0,
    roundActive = false,
    scores = { Blue = 0, Red = 0 },
    spawnPoints = {},
    teams = {},
    teamSpawns = { Blue = nil, Red = nil },
    menuOpen = false,
    menuPage = "main",
}

------------------------------------------------------------
-- AUSGABE - Nur print(), kein ClientMessage (das laggt)
------------------------------------------------------------

local function Log(msg)
    print(string.format("[PVP] %s\n", tostring(msg)))
end

local function Debug(msg)
    if CONFIG.DEBUG then
        print(string.format("[PVP-DBG] %s\n", tostring(msg)))
    end
end

local function Msg(msg)
    local text = tostring(msg)
    print(string.format("[PVP] %s\n", text))
end

-- Toast-Nachricht im Spiel-HUD anzeigen
local function Toast(msg)
    local text = tostring(msg)
    print(string.format("[PVP] %s\n", text))
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local hud = FindFirstOf("HumanCharacterHUD_V2")
                if hud and hud:IsValid() then
                    hud:AddToast(text)
                end
            end)
        end)
    end)
end

-- Score-Popup im Spiel-HUD anzeigen
local function ScorePopup(msg)
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local hud = FindFirstOf("HumanCharacterHUD_V2")
                if hud and hud:IsValid() then
                    hud:AddScorePopup(FText(tostring(msg)))
                end
            end)
        end)
    end)
end

local function MsgBlock(lines)
    for _, line in ipairs(lines) do
        print(string.format("[PVP] %s\n", tostring(line)))
    end
end

------------------------------------------------------------
-- HILFSFUNKTIONEN
------------------------------------------------------------

local function Safe(fn)
    local ok, err = pcall(fn)
    if not ok and CONFIG.DEBUG then
        print(string.format("[PVP-ERR] %s\n", tostring(err)))
    end
    return ok
end

local function RandomElement(tbl)
    if not tbl or #tbl == 0 then return nil end
    return tbl[math.random(1, #tbl)]
end

local function ShuffleTable(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(1, i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

local function CountTable(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

local function GetDistance(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    return math.sqrt(dx*dx + dy*dy)
end

-- Kurzer Spielername aus dem vollen UE-Pfad
local function ShortName(obj)
    local name = "Player"
    Safe(function()
        local full = obj:GetFullName()
        -- Nimm den letzten Teil nach dem letzten Punkt
        local last = string.match(full, "%.([^%.]+)$")
        if last then
            name = last
        else
            name = full
        end
        -- Kuerze Blueprint-Suffix
        name = string.gsub(name, "_C_(%d+)$", "#%1")
        name = string.gsub(name, "BasePlayer", "Player")
    end)
    return name
end

-- Alle PlayerCharacter-Instanzen sammeln
local function GetAllPlayers()
    local players = {}
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function()
                    table.insert(players, { name = ShortName(char), char = char })
                end)
            end
        end
    end)
    return players
end

------------------------------------------------------------
-- SPAWN SYSTEM
-- Generiert Spawn-Punkte um die Spielerposition herum,
-- weil FindAllOf("PlayerStart") auf vielen Maps nichts findet
------------------------------------------------------------

local function CollectSpawnPoints()
    PVP.spawnPoints = {}

    -- Finde die aktuelle Spielerposition als Basis
    local basePos = nil
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function()
                    local loc = char:K2_GetActorLocation()
                    if loc then
                        basePos = { X = loc.X, Y = loc.Y, Z = loc.Z }
                    end
                end)
            end
        end
    end)

    if not basePos then
        Msg("FEHLER: Keine Spielerposition gefunden!")
        return
    end

    Debug(string.format("Basis-Position: X=%.0f Y=%.0f Z=%.0f", basePos.X, basePos.Y, basePos.Z))

    -- Versuche zuerst echte Spawn-Punkte zu finden
    local classesToTry = { "PlayerStart", "ActorSpawnPoint", "PlayerStart_VIP_Spawn", "SpawnGenerator" }
    for _, className in ipairs(classesToTry) do
        Safe(function()
            local found = FindAllOf(className)
            if found then
                for _, obj in pairs(found) do
                    Safe(function()
                        local loc = obj:K2_GetActorLocation()
                        if loc then
                            table.insert(PVP.spawnPoints, { X = loc.X, Y = loc.Y, Z = loc.Z })
                        end
                    end)
                end
            end
        end)
    end

    if #PVP.spawnPoints > 0 then
        Msg(string.format("Map-Spawns gefunden: %d", #PVP.spawnPoints))
        return
    end

    -- Fallback: Generiere Spawn-Punkte um die Spielerposition
    Msg("Keine Map-Spawns, generiere zufaellige Positionen...")
    local range = CONFIG.SPAWN_SCATTER_RANGE
    for i = 1, 12 do
        local angle = (i / 12) * 2 * math.pi + (math.random() * 0.5)
        local dist = range * 0.4 + math.random() * range * 0.6
        table.insert(PVP.spawnPoints, {
            X = basePos.X + math.cos(angle) * dist,
            Y = basePos.Y + math.sin(angle) * dist,
            Z = basePos.Z
        })
    end

    Msg(string.format("Generierte Spawn-Punkte: %d", #PVP.spawnPoints))
end

-- 2 weit entfernte Punkte als Team-Spawns waehlen
local function PickTeamSpawnPoints()
    if #PVP.spawnPoints < 2 then
        Msg("Zu wenige Spawn-Punkte!")
        return
    end

    local bestDist = 0
    local bestA, bestB = 1, 2

    for i = 1, #PVP.spawnPoints do
        for j = i + 1, #PVP.spawnPoints do
            local dist = GetDistance(PVP.spawnPoints[i], PVP.spawnPoints[j])
            if dist > bestDist then
                bestDist = dist
                bestA, bestB = i, j
            end
        end
    end

    PVP.teamSpawns.Blue = PVP.spawnPoints[bestA]
    PVP.teamSpawns.Red = PVP.spawnPoints[bestB]

    Debug(string.format("Team-Spawns: Abstand=%.0f", bestDist))
end

-- Spieler zum Team-Spawn teleportieren
local function TeleportPlayer(char, team)
    local baseSpawn = nil

    if CONFIG.GAMEMODE == CONFIG.GAMEMODE_FFA then
        baseSpawn = RandomElement(PVP.spawnPoints)
    else
        baseSpawn = (team == "Blue") and PVP.teamSpawns.Blue or PVP.teamSpawns.Red
    end

    if not baseSpawn then
        baseSpawn = RandomElement(PVP.spawnPoints)
    end
    if not baseSpawn then
        Debug("Kein Spawn verfuegbar")
        return false
    end

    local ok = false
    Safe(function()
        local radius = CONFIG.TEAM_SPAWN_RADIUS
        local angle = math.random() * 2 * math.pi
        local dist = math.random() * radius
        local newX = baseSpawn.X + math.cos(angle) * dist
        local newY = baseSpawn.Y + math.sin(angle) * dist

        char:K2_SetActorLocation({ X = newX, Y = newY, Z = baseSpawn.Z }, false, {}, true)
        char:K2_SetActorRotation({ Pitch = 0, Yaw = math.random(0, 360), Roll = 0 }, true)
        Debug(string.format("Teleport [%s] -> X=%.0f Y=%.0f", team, newX, newY))
        ok = true
    end)
    return ok
end

------------------------------------------------------------
-- NPCs ENTFERNEN
-- CyberneticCharacter = Suspects/Gegner
-- CivilianCharacter = Zivilisten
------------------------------------------------------------

local function ClearNPCs()
    local removed = 0

    local npcClasses = { "CyberneticCharacter", "CivilianCharacter" }
    for _, className in ipairs(npcClasses) do
        Safe(function()
            local npcs = FindAllOf(className)
            if npcs then
                for _, npc in pairs(npcs) do
                    Safe(function()
                        -- Erst Kill versuchen, dann zerstoeren
                        pcall(function() npc:Kill() end)
                        pcall(function() npc:K2_DestroyActor() end)
                        removed = removed + 1
                    end)
                end
            end
        end)
    end

    Msg(string.format("NPCs entfernt: %d", removed))
end

------------------------------------------------------------
-- FRIENDLY FIRE
------------------------------------------------------------

local function SetFriendlyFire(enabled)
    Safe(function()
        local chars = FindAllOf("ReadyOrNotCharacter")
        if chars then
            local count = 0
            for _, char in pairs(chars) do
                Safe(function()
                    char.bNoTeamDamage = not enabled
                    count = count + 1
                end)
            end
            Msg(string.format("Friendly Fire %s (%d chars)", enabled and "AN" or "AUS", count))
        end
    end)
end

------------------------------------------------------------
-- TEAMS
-- ETeamType enum aus dem Header Dump:
--   0 = TT_NONE
--   1 = TT_SERT_RED    (Red Team)
--   2 = TT_SERT_BLUE   (Blue Team)
--   3 = TT_SUSPECT
--   4 = TT_CIVILIAN
--   5 = TT_SQUAD
------------------------------------------------------------

local TEAM_ENUM = {
    NONE = 0,
    RED = 1,        -- TT_SERT_RED
    BLUE = 2,       -- TT_SERT_BLUE
    SUSPECT = 3,
    CIVILIAN = 4,
    SQUAD = 5,
}

-- Setzt das Team eines Spielers im Spiel-Engine (leichtgewichtig)
local function ApplyTeamToPlayer(playerChar, team)
    local enumVal = (team == "Blue") and TEAM_ENUM.BLUE or TEAM_ENUM.RED

    -- Nur DefaultTeam Property setzen - das reicht und laggt nicht
    Safe(function() playerChar.DefaultTeam = enumVal end)

    Debug(string.format("Team gesetzt: %s -> Enum %d", team, enumVal))
end

-- Teams im Spiel-Engine anwenden
local function ApplyAllTeams()
    local players = GetAllPlayers()
    for _, p in ipairs(players) do
        local team = PVP.teams[p.name] or "Blue"
        ApplyTeamToPlayer(p.char, team)
    end
    Msg("Teams angewendet!")
end

local function AutoAssignTeams()
    PVP.teams = {}
    local players = GetAllPlayers()
    players = ShuffleTable(players)

    if CONFIG.GAMEMODE == CONFIG.GAMEMODE_FFA then
        for _, p in ipairs(players) do
            PVP.teams[p.name] = "FFA"
        end
        Msg(string.format("FFA: %d Spieler", #players))
    else
        for i, p in ipairs(players) do
            PVP.teams[p.name] = (i % 2 == 1) and "Blue" or "Red"
        end
        local b, r = 0, 0
        for _, t in pairs(PVP.teams) do
            if t == "Blue" then b = b + 1 elseif t == "Red" then r = r + 1 end
        end
        Msg(string.format("Teams: BLUE %d vs RED %d", b, r))

        -- Teams sofort im Spiel anwenden
        ApplyAllTeams()
    end
end

local function SwapTeams()
    for name, team in pairs(PVP.teams) do
        if team == "Blue" then PVP.teams[name] = "Red"
        elseif team == "Red" then PVP.teams[name] = "Blue" end
    end
    ApplyAllTeams()
    Msg("Teams getauscht!")
end

local function TogglePlayerTeam(idx)
    local players = GetAllPlayers()
    if idx > #players then
        Msg(string.format("Spieler %d existiert nicht (nur %d da)", idx, #players))
        return
    end
    local p = players[idx]
    local cur = PVP.teams[p.name] or "None"
    PVP.teams[p.name] = (cur == "Blue") and "Red" or "Blue"
    ApplyTeamToPlayer(p.char, PVP.teams[p.name])
    Msg(string.format("%s -> %s", p.name, PVP.teams[p.name]))
end

local function GetTeam(name)
    return PVP.teams[name] or "Blue"
end

------------------------------------------------------------
-- SCOREBOARD
------------------------------------------------------------

local function ShowScoreboard()
    MsgBlock({
        "========== SCOREBOARD ==========",
        string.format("Runde %d/%d | BLUE %d - %d RED",
            PVP.currentRound, CONFIG.ROUNDS_TO_WIN, PVP.scores.Blue, PVP.scores.Red),
        "--------------------------------",
    })

    local players = GetAllPlayers()
    for _, p in ipairs(players) do
        local team = GetTeam(p.name)
        local dead = false
        Safe(function() dead = p.char:IsDeadOrUnconscious() end)
        Msg(string.format("  [%s] %s %s", team, p.name, dead and "- TOT" or "- LEBT"))
    end

    -- Stats aus PlayerState
    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then
            Msg("--- Stats ---")
            for _, ps in pairs(states) do
                Safe(function()
                    local name = ShortName(ps)
                    local k, d = 0, 0
                    Safe(function() k = ps.Kills end)
                    Safe(function() d = ps.Deaths end)
                    Msg(string.format("  %s: K:%d D:%d", name, k, d))
                end)
            end
        end
    end)

    Msg("================================")
end

------------------------------------------------------------
-- RUNDEN
------------------------------------------------------------

local function CheckRoundEnd()
    if not PVP.roundActive then return end

    local players = GetAllPlayers()
    if #players == 0 then return end

    if CONFIG.GAMEMODE == CONFIG.GAMEMODE_TDM then
        local aliveBlue, aliveRed = 0, 0
        for _, p in ipairs(players) do
            local dead = false
            Safe(function() dead = p.char:IsDeadOrUnconscious() end)
            if not dead then
                local t = GetTeam(p.name)
                if t == "Blue" then aliveBlue = aliveBlue + 1
                elseif t == "Red" then aliveRed = aliveRed + 1 end
            end
        end
        Debug(string.format("Alive: B=%d R=%d", aliveBlue, aliveRed))
        if aliveBlue == 0 and aliveRed > 0 then EndRound("Red")
        elseif aliveRed == 0 and aliveBlue > 0 then EndRound("Blue") end
    else
        local alive = 0
        local lastAlive = nil
        for _, p in ipairs(players) do
            local dead = false
            Safe(function() dead = p.char:IsDeadOrUnconscious() end)
            if not dead then alive = alive + 1; lastAlive = p.name end
        end
        if alive <= 1 and #players > 1 then
            PVP.roundActive = false
            Msg(string.format("RUNDE %d - %s GEWINNT!", PVP.currentRound, lastAlive or "Niemand"))
        end
    end
end

function EndRound(winner)
    PVP.roundActive = false
    PVP.scores[winner] = (PVP.scores[winner] or 0) + 1
    local roundMsg = string.format("RUNDE %d - TEAM %s GEWINNT!", PVP.currentRound, winner)
    local scoreMsg = string.format("BLUE %d - %d RED", PVP.scores.Blue, PVP.scores.Red)
    Msg(roundMsg)
    Msg(scoreMsg)
    Toast(roundMsg)
    ScorePopup(scoreMsg)
    if PVP.scores[winner] >= CONFIG.ROUNDS_TO_WIN then
        local matchMsg = string.format("TEAM %s GEWINNT DAS MATCH!", winner)
        Msg(matchMsg)
        Toast(matchMsg)
    end
end

-- Tote Spieler respawnen ueber GameMode
local function RespawnPlayers()
    Safe(function()
        local gm = FindFirstOf("ReadyOrNotGameMode")
        if gm and gm:IsValid() then
            -- Versuche verschiedene Respawn-Methoden
            Safe(function() gm:RespawnDeadPlayers() end)
            Safe(function() gm:RespawnAllPlayers() end)
            Debug("Respawn ausgefuehrt")
        else
            Debug("GameMode nicht gefunden fuer Respawn")
        end
    end)

    -- Zusaetzlich: Health resetten fuer alle lebenden Spieler
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function() char:ResetHealth() end)
            end
        end
    end)
end

local function StartRound()
    if CountTable(PVP.teams) == 0 then AutoAssignTeams() end
    if #PVP.spawnPoints == 0 then CollectSpawnPoints() end

    PVP.currentRound = PVP.currentRound + 1
    PVP.roundActive = true

    PickTeamSpawnPoints()

    -- 1) Tote Spieler respawnen
    RespawnPlayers()

    -- 2) NPCs killen
    ClearNPCs()

    local roundMsg = string.format("RUNDE %d STARTET!", PVP.currentRound)
    Msg(roundMsg)
    Toast(roundMsg)

    -- 3) Teams im Spiel setzen (kein "Eigenbeschuss" mehr)
    ApplyAllTeams()

    -- 4) Friendly Fire
    if CONFIG.FRIENDLY_FIRE then SetFriendlyFire(true) end

    -- 5) Teleport
    local players = GetAllPlayers()
    local count = 0
    for _, p in ipairs(players) do
        local team = GetTeam(p.name)
        if TeleportPlayer(p.char, team) then count = count + 1 end
    end
    Msg(string.format("%d Spieler teleportiert!", count))
end

local function StartNewMatch()
    PVP.currentRound = 0
    PVP.roundActive = false
    PVP.scores = { Blue = 0, Red = 0 }
    PVP.enabled = true

    CollectSpawnPoints()
    AutoAssignTeams()

    MsgBlock({
        "=============================",
        "PVP MATCH GESTARTET!",
        string.format("Modus: %s | Best of %d",
            CONFIG.GAMEMODE == CONFIG.GAMEMODE_TDM and "TDM" or "FFA", CONFIG.ROUNDS_TO_WIN),
        "Menu [3] = erste Runde starten",
        "=============================",
    })
end

------------------------------------------------------------
-- MENU
------------------------------------------------------------

local function ShowMenu()
    if PVP.menuPage == "main" then
        MsgBlock({
            "======== PVP MENU ========",
            string.format("Status: %s | %s | R%d/%d | B%d-R%d",
                PVP.enabled and "AN" or "AUS",
                CONFIG.GAMEMODE == CONFIG.GAMEMODE_TDM and "TDM" or "FFA",
                PVP.currentRound, CONFIG.ROUNDS_TO_WIN,
                PVP.scores.Blue, PVP.scores.Red),
            "--------------------------",
            "[1] Neues Match starten",
            "[2] PVP stoppen",
            "[3] Naechste Runde",
            "[4] Team-Management >>",
            "[5] Spielmodus >>",
            "[6] Einstellungen >>",
            "[7] Alle teleportieren",
            "[8] NPCs entfernen",
            "[9] Scoreboard",
            "==========================",
        })
    elseif PVP.menuPage == "teams" then
        Msg("===== TEAM MANAGEMENT =====")
        local players = GetAllPlayers()
        for i, p in ipairs(players) do
            Msg(string.format("  %d. %s -> %s", i, p.name, GetTeam(p.name)))
        end
        MsgBlock({
            "---------------------------",
            "[1] Auto-Teams (zufaellig)",
            "[2] Alle -> BLUE",
            "[3] Alle -> RED",
            "[4] Teams tauschen",
            "[5-8] Spieler 1-4 wechseln",
            "[9] Zurueck",
            "===========================",
        })
    elseif PVP.menuPage == "gamemode" then
        MsgBlock({
            "===== SPIELMODUS =====",
            string.format("Aktuell: %s", CONFIG.GAMEMODE == CONFIG.GAMEMODE_TDM and "TDM" or "FFA"),
            "[1] Team Deathmatch",
            "[2] Free For All",
            "[9] Zurueck",
            "======================",
        })
    elseif PVP.menuPage == "settings" then
        MsgBlock({
            "===== EINSTELLUNGEN =====",
            string.format("Runden: %d | FF: %s | DMG: %.0fx",
                CONFIG.ROUNDS_TO_WIN,
                CONFIG.FRIENDLY_FIRE and "AN" or "AUS",
                CONFIG.DAMAGE_MULTIPLIER),
            "-------------------------",
            "[1] Runden: 3",
            "[2] Runden: 5",
            "[3] Runden: 7",
            "[4] Friendly Fire toggle",
            "[5] DMG: 1x  [6] DMG: 2x  [7] DMG: 10x",
            "[8] Debug toggle",
            "[9] Zurueck",
            "=========================",
        })
    end
end

local function HandleMenu(key)
    if not PVP.menuOpen then return end

    if PVP.menuPage == "main" then
        if key == 1 then StartNewMatch(); PVP.menuOpen = false
        elseif key == 2 then
            PVP.enabled = false; PVP.roundActive = false
            SetFriendlyFire(false); Msg("PVP GESTOPPT"); PVP.menuOpen = false
        elseif key == 3 then
            if not PVP.enabled then Msg("Erst [1] druecken!"); return end
            if PVP.roundActive then Msg("Runde laeuft!"); return end
            StartRound(); PVP.menuOpen = false
        elseif key == 4 then PVP.menuPage = "teams"; ShowMenu()
        elseif key == 5 then PVP.menuPage = "gamemode"; ShowMenu()
        elseif key == 6 then PVP.menuPage = "settings"; ShowMenu()
        elseif key == 7 then
            if #PVP.spawnPoints == 0 then CollectSpawnPoints() end
            if CountTable(PVP.teams) == 0 then AutoAssignTeams() end
            PickTeamSpawnPoints()
            local players = GetAllPlayers()
            for _, p in ipairs(players) do TeleportPlayer(p.char, GetTeam(p.name)) end
            Msg("Alle teleportiert!")
        elseif key == 8 then ClearNPCs()
        elseif key == 9 then ShowScoreboard() end

    elseif PVP.menuPage == "teams" then
        if key == 1 then AutoAssignTeams(); ShowMenu()
        elseif key == 2 then
            for _, p in ipairs(GetAllPlayers()) do PVP.teams[p.name] = "Blue" end
            Msg("Alle -> BLUE"); ShowMenu()
        elseif key == 3 then
            for _, p in ipairs(GetAllPlayers()) do PVP.teams[p.name] = "Red" end
            Msg("Alle -> RED"); ShowMenu()
        elseif key == 4 then SwapTeams(); ShowMenu()
        elseif key >= 5 and key <= 8 then TogglePlayerTeam(key - 4); ShowMenu()
        elseif key == 9 then PVP.menuPage = "main"; ShowMenu() end

    elseif PVP.menuPage == "gamemode" then
        if key == 1 then CONFIG.GAMEMODE = 1; Msg("Modus: TDM"); ShowMenu()
        elseif key == 2 then CONFIG.GAMEMODE = 2; Msg("Modus: FFA"); ShowMenu()
        elseif key == 9 then PVP.menuPage = "main"; ShowMenu() end

    elseif PVP.menuPage == "settings" then
        if key == 1 then CONFIG.ROUNDS_TO_WIN = 3; Msg("Runden: 3")
        elseif key == 2 then CONFIG.ROUNDS_TO_WIN = 5; Msg("Runden: 5")
        elseif key == 3 then CONFIG.ROUNDS_TO_WIN = 7; Msg("Runden: 7")
        elseif key == 4 then CONFIG.FRIENDLY_FIRE = not CONFIG.FRIENDLY_FIRE
            Msg("FF: " .. (CONFIG.FRIENDLY_FIRE and "AN" or "AUS"))
            SetFriendlyFire(CONFIG.FRIENDLY_FIRE)
        elseif key == 5 then CONFIG.DAMAGE_MULTIPLIER = 1.0; Msg("DMG: 1x")
        elseif key == 6 then CONFIG.DAMAGE_MULTIPLIER = 2.0; Msg("DMG: 2x")
        elseif key == 7 then CONFIG.DAMAGE_MULTIPLIER = 10.0; Msg("DMG: 10x")
        elseif key == 8 then CONFIG.DEBUG = not CONFIG.DEBUG; Msg("Debug: " .. (CONFIG.DEBUG and "AN" or "AUS"))
        elseif key == 9 then PVP.menuPage = "main"; ShowMenu() end
        if key ~= 9 then ShowMenu() end
    end
end

------------------------------------------------------------
-- DEBUG
------------------------------------------------------------

function ShowDebugInfo()
    Msg("=== DEBUG ===")
    local players = GetAllPlayers()
    Msg(string.format("Spieler: %d | Spawns: %d | Teams: %d",
        #players, #PVP.spawnPoints, CountTable(PVP.teams)))

    Safe(function()
        local gm = FindFirstOf("ReadyOrNotGameMode")
        Msg(string.format("GameMode: %s", gm and "OK" or "NICHT GEFUNDEN"))
    end)

    for _, p in ipairs(players) do
        local team = GetTeam(p.name)
        local dead = false
        Safe(function() dead = p.char:IsDeadOrUnconscious() end)
        local loc = nil
        Safe(function() loc = p.char:K2_GetActorLocation() end)
        Msg(string.format("  %s [%s] %s %s", p.name, team,
            dead and "TOT" or "LEBT",
            loc and string.format("@ %.0f,%.0f,%.0f", loc.X, loc.Y, loc.Z) or ""))
    end

    if PVP.teamSpawns.Blue then
        Msg(string.format("  Blue Spawn: %.0f,%.0f", PVP.teamSpawns.Blue.X, PVP.teamSpawns.Blue.Y))
    end
    if PVP.teamSpawns.Red then
        Msg(string.format("  Red Spawn: %.0f,%.0f", PVP.teamSpawns.Red.X, PVP.teamSpawns.Red.Y))
    end
    Msg("=============")
end

------------------------------------------------------------
-- HOOKS
------------------------------------------------------------

local function SetupHooks()
    local hooks = {
        { "/Script/ReadyOrNot.ReadyOrNotGameMode:PlayerKilled", "PlayerKilled" },
        { "/Script/ReadyOrNot.ReadyOrNotCharacter:OnKilled", "OnKilled" },
        { "/Script/ReadyOrNot.ReadyOrNotCharacter:Multicast_OnKilled", "MC_OnKilled" },
        { "/Script/ReadyOrNot.ReadyOrNotCharacter:Server_Kill", "Server_Kill" },
        { "/Script/ReadyOrNot.ReadyOrNotGameMode:SpawnPlayerCharacter", "SpawnChar" },
    }

    for _, h in ipairs(hooks) do
        Safe(function()
            RegisterHook(h[1], function(self)
                if not PVP.enabled then return end
                Debug("Hook: " .. h[2])
                if h[2] == "OnKilled" then
                    local name = "?"
                    pcall(function() name = ShortName(self:get()) end)
                    Toast(name .. " eliminiert!")
                    CheckRoundEnd()
                elseif h[2] ~= "SpawnChar" then
                    CheckRoundEnd()
                else
                    if CONFIG.FRIENDLY_FIRE then SetFriendlyFire(true) end
                end
            end)
            Log("Hook OK: " .. h[2])
        end)
    end
end

------------------------------------------------------------
-- CHARACTER WATCHER
------------------------------------------------------------

local function SetupWatcher()
    Safe(function()
        NotifyOnNewObject("/Script/ReadyOrNot.PlayerCharacter", function(newChar)
            if not PVP.enabled then return end
            Safe(function() newChar.bNoTeamDamage = not CONFIG.FRIENDLY_FIRE end)
        end)
        Log("Watcher OK")
    end)
end

------------------------------------------------------------
-- HOTKEYS
------------------------------------------------------------

local function SetupHotkeys()
    RegisterKeyBind(Key.F5, function()
        PVP.menuOpen = not PVP.menuOpen
        if PVP.menuOpen then
            PVP.menuPage = "main"
            ShowMenu()
        else
            Msg("Menu geschlossen")
        end
    end)

    RegisterKeyBind(Key.F6, function() ShowScoreboard() end)
    RegisterKeyBind(Key.F7, function() ShowDebugInfo() end)

    RegisterKeyBind(Key.NUM_ONE, function() HandleMenu(1) end)
    RegisterKeyBind(Key.NUM_TWO, function() HandleMenu(2) end)
    RegisterKeyBind(Key.NUM_THREE, function() HandleMenu(3) end)
    RegisterKeyBind(Key.NUM_FOUR, function() HandleMenu(4) end)
    RegisterKeyBind(Key.NUM_FIVE, function() HandleMenu(5) end)
    RegisterKeyBind(Key.NUM_SIX, function() HandleMenu(6) end)
    RegisterKeyBind(Key.NUM_SEVEN, function() HandleMenu(7) end)
    RegisterKeyBind(Key.NUM_EIGHT, function() HandleMenu(8) end)
    RegisterKeyBind(Key.NUM_NINE, function() HandleMenu(9) end)

    Log("Hotkeys OK: F5=Menu F6=Score F7=Debug Num1-9=Input")
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------

math.randomseed(os.time())
Log("========================================")
Log("  PVP MOD v3.1 - Ready or Not")
Log("========================================")
SetupHooks()
SetupWatcher()
SetupHotkeys()
Log("========================================")
Log("  F5=Menu  F6=Score  F7=Debug")
Log("  Nachrichten erscheinen hier in der")
Log("  UE4SS Konsole (dieses Fenster)!")
Log("========================================")
