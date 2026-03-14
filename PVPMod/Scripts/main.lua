--[[
    PVP MOD v4.0 for Ready or Not

    F5          = EIN KNOPF: Startet PVP / Naechste Runde
    F6          = Scoreboard
    F7          = PVP Stoppen
    F8          = NPCs entfernen
--]]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local CONFIG = {
    ROUNDS_TO_WIN = 5,
    TEAM_SPAWN_RADIUS = 250,
    SPAWN_SCATTER_RANGE = 4000,
    DEBUG = true,
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
    teams = {},         -- steamName -> "Blue"/"Red"
    teamSpawns = { Blue = nil, Red = nil },
}

------------------------------------------------------------
-- LOGGING
------------------------------------------------------------

local function Log(msg)
    print(string.format("[PVP] %s\n", tostring(msg)))
end

local function Debug(msg)
    if CONFIG.DEBUG then
        print(string.format("[PVP-DBG] %s\n", tostring(msg)))
    end
end

local function Safe(fn)
    local ok, err = pcall(fn)
    if not ok and CONFIG.DEBUG then
        print(string.format("[PVP-ERR] %s\n", tostring(err)))
    end
    return ok
end

------------------------------------------------------------
-- TOAST - In-Game Nachrichten ueber das Spiel-HUD
------------------------------------------------------------

-- Findet das aktive HUD Widget (Blueprint-Klasse)
local function FindHUD()
    local hud = nil
    -- Versuche Blueprint-Klasse zuerst, dann C++ Klasse
    pcall(function() hud = FindFirstOf("W_HumanCharacter_HUD_V2_C") end)
    if not hud then
        pcall(function() hud = FindFirstOf("HumanCharacterHUD_V2") end)
    end
    return hud
end

local function Toast(msg)
    local text = tostring(msg)
    Log(text)
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local hud = FindHUD()
                if hud and hud:IsValid() then
                    hud:AddToast(text)
                    Debug("Toast gesendet: " .. text)
                else
                    Debug("HUD nicht gefunden fuer Toast")
                end
            end)
        end)
    end)
end

local function ScorePopup(msg)
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local hud = FindHUD()
                if hud and hud:IsValid() then
                    hud:AddScorePopup(FText(tostring(msg)))
                end
            end)
        end)
    end)
end

------------------------------------------------------------
-- HILFSFUNKTIONEN
------------------------------------------------------------

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

local function GetDistance(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    return math.sqrt(dx*dx + dy*dy)
end

------------------------------------------------------------
-- STEAM-NAMEN
-- Liest den echten Spielernamen aus PlayerState
------------------------------------------------------------

local function GetSteamName(playerChar)
    local name = "Unknown"

    -- Versuche den Namen ueber PlayerState zu holen
    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then
            for _, ps in pairs(states) do
                Safe(function()
                    -- GetPlayerName() gibt den Steam-Namen zurueck
                    local pName = ps:GetPlayerName()
                    if pName and tostring(pName) ~= "" then
                        -- Wir nehmen den ersten validen Namen den wir finden
                        -- und matchen ihn spaeter mit dem Character
                        local n = tostring(pName)
                        if n ~= "" and n ~= "None" then
                            name = n
                        end
                    end
                end)
            end
        end
    end)

    -- Fallback: PlayerNamePrivate Property
    if name == "Unknown" then
        Safe(function()
            local states = FindAllOf("PlayerState")
            if states then
                for _, ps in pairs(states) do
                    Safe(function()
                        local n = tostring(ps.PlayerNamePrivate)
                        if n and n ~= "" and n ~= "None" then
                            name = n
                        end
                    end)
                end
            end
        end)
    end

    return name
end

-- Alle Spieler mit Steam-Namen sammeln
local function GetAllPlayers()
    local players = {}

    -- Steam-Namen aus PlayerState holen (PlayerNamePrivate ist ein StrProperty)
    local steamNames = {}
    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then
            for _, ps in pairs(states) do
                Safe(function()
                    local n = ""
                    -- PlayerNamePrivate ist ein StrProperty -> gibt direkt String
                    Safe(function()
                        local raw = ps.PlayerNamePrivate
                        if raw then n = tostring(raw) end
                    end)
                    -- Fallback
                    if n == "" or n == "None" or string.find(n, "FString") then
                        n = "Spieler" .. (#steamNames + 1)
                    end
                    table.insert(steamNames, n)
                end)
            end
        end
    end)

    -- Characters sammeln und Namen zuordnen
    local idx = 1
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function()
                    local name = steamNames[idx] or ("Spieler" .. idx)
                    table.insert(players, { name = name, char = char })
                    idx = idx + 1
                end)
            end
        end
    end)

    return players
end

------------------------------------------------------------
-- SPAWN SYSTEM
------------------------------------------------------------

local function CollectSpawnPoints()
    PVP.spawnPoints = {}

    local basePos = nil
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function()
                    local loc = char:K2_GetActorLocation()
                    if loc then basePos = { X = loc.X, Y = loc.Y, Z = loc.Z } end
                end)
            end
        end
    end)

    if not basePos then return end

    -- Echte Spawn-Punkte suchen
    for _, cls in ipairs({ "PlayerStart", "ActorSpawnPoint", "PlayerStart_VIP_Spawn" }) do
        Safe(function()
            local found = FindAllOf(cls)
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

    -- Fallback: Generiere Punkte um Spielerposition
    if #PVP.spawnPoints == 0 then
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
    end

    Log(string.format("Spawns: %d", #PVP.spawnPoints))
end

local function PickTeamSpawnPoints()
    if #PVP.spawnPoints < 2 then return end
    local bestDist, bestA, bestB = 0, 1, 2
    for i = 1, #PVP.spawnPoints do
        for j = i + 1, #PVP.spawnPoints do
            local dist = GetDistance(PVP.spawnPoints[i], PVP.spawnPoints[j])
            if dist > bestDist then bestDist = dist; bestA = i; bestB = j end
        end
    end
    PVP.teamSpawns.Blue = PVP.spawnPoints[bestA]
    PVP.teamSpawns.Red = PVP.spawnPoints[bestB]
end

local function TeleportPlayer(char, team)
    local base = (team == "Blue") and PVP.teamSpawns.Blue or PVP.teamSpawns.Red
    if not base then base = RandomElement(PVP.spawnPoints) end
    if not base then return false end

    local ok = false
    Safe(function()
        local r = CONFIG.TEAM_SPAWN_RADIUS
        local a = math.random() * 2 * math.pi
        local d = math.random() * r
        char:K2_SetActorLocation({
            X = base.X + math.cos(a) * d,
            Y = base.Y + math.sin(a) * d,
            Z = base.Z
        }, false, {}, true)
        char:K2_SetActorRotation({ Pitch = 0, Yaw = math.random(0, 360), Roll = 0 }, true)
        ok = true
    end)
    return ok
end

------------------------------------------------------------
-- NPCs ENTFERNEN
------------------------------------------------------------

local function ClearNPCs()
    local removed = 0
    for _, cls in ipairs({ "CyberneticCharacter", "CivilianCharacter" }) do
        Safe(function()
            local npcs = FindAllOf(cls)
            if npcs then
                for _, npc in pairs(npcs) do
                    Safe(function()
                        npc:Kill()
                        removed = removed + 1
                    end)
                end
            end
        end)
    end
    Log(string.format("NPCs entfernt: %d", removed))
end

------------------------------------------------------------
-- FRIENDLY FIRE
------------------------------------------------------------

local function SetFriendlyFire(enabled)
    Safe(function()
        local chars = FindAllOf("ReadyOrNotCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function() char.bNoTeamDamage = not enabled end)
            end
        end
    end)
end

------------------------------------------------------------
-- TEAMS
-- ETeamType: 0=NONE, 1=SERT_RED, 2=SERT_BLUE
------------------------------------------------------------

local function ApplyTeam(playerChar, team)
    local enumVal = (team == "Blue") and 2 or 1
    Safe(function() playerChar.DefaultTeam = enumVal end)
end

-- Automatisch Teams zuweisen basierend auf Spieleranzahl
local function AutoAssignTeams()
    PVP.teams = {}
    local players = GetAllPlayers()
    players = ShuffleTable(players)

    for i, p in ipairs(players) do
        local team = (i % 2 == 1) and "Blue" or "Red"
        PVP.teams[p.name] = team
        ApplyTeam(p.char, team)
        Log(string.format("  %s -> %s", p.name, team))
    end

    local b, r = 0, 0
    for _, t in pairs(PVP.teams) do
        if t == "Blue" then b = b + 1 elseif t == "Red" then r = r + 1 end
    end

    Toast(string.format("Teams: BLUE %d vs RED %d", b, r))
end

local function GetTeam(name)
    return PVP.teams[name] or "Blue"
end

------------------------------------------------------------
-- RESPAWN
------------------------------------------------------------

local function RespawnPlayers()
    -- Nur Health resetten, kein RespawnAllPlayers (friert das Spiel ein)
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function() char:ResetHealth() end)
            end
        end
    end)
    Debug("Health reset")
end

------------------------------------------------------------
-- RUNDEN
------------------------------------------------------------

local function CheckRoundEnd()
    if not PVP.roundActive then return end

    local players = GetAllPlayers()
    if #players == 0 then return end

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

    if aliveBlue == 0 and aliveRed > 0 then
        PVP.roundActive = false
        PVP.scores.Red = PVP.scores.Red + 1
        Toast(string.format("TEAM RED GEWINNT RUNDE %d!", PVP.currentRound))
        ScorePopup(string.format("BLUE %d - %d RED", PVP.scores.Blue, PVP.scores.Red))
        if PVP.scores.Red >= CONFIG.ROUNDS_TO_WIN then
            Toast("TEAM RED GEWINNT DAS MATCH!")
        end
    elseif aliveRed == 0 and aliveBlue > 0 then
        PVP.roundActive = false
        PVP.scores.Blue = PVP.scores.Blue + 1
        Toast(string.format("TEAM BLUE GEWINNT RUNDE %d!", PVP.currentRound))
        ScorePopup(string.format("BLUE %d - %d RED", PVP.scores.Blue, PVP.scores.Red))
        if PVP.scores.Blue >= CONFIG.ROUNDS_TO_WIN then
            Toast("TEAM BLUE GEWINNT DAS MATCH!")
        end
    end
end

------------------------------------------------------------
-- HAUPTFUNKTION: EIN KNOPF MACHT ALLES
-- Erkennt automatisch ob neues Match oder naechste Runde
------------------------------------------------------------

local function PVP_GO()
    if not PVP.enabled then
        -- NEUES MATCH
        PVP.enabled = true
        PVP.currentRound = 0
        PVP.roundActive = false
        PVP.scores = { Blue = 0, Red = 0 }

        CollectSpawnPoints()
        AutoAssignTeams()

        Log("=== NEUES PVP MATCH ===")
    end

    if PVP.roundActive then
        Toast("Runde laeuft noch!")
        return
    end

    -- Match vorbei? Reset
    if PVP.scores.Blue >= CONFIG.ROUNDS_TO_WIN or PVP.scores.Red >= CONFIG.ROUNDS_TO_WIN then
        PVP.currentRound = 0
        PVP.scores = { Blue = 0, Red = 0 }
        AutoAssignTeams()
        Log("=== NEUES MATCH (Reset) ===")
    end

    -- RUNDE STARTEN
    PVP.currentRound = PVP.currentRound + 1
    Log(">> Schritt 1: NPCs killen...")

    -- 1) NPCs weg (VOR roundActive damit kills nicht runde beenden)
    ClearNPCs()
    Log(">> Schritt 2: Health Reset...")

    -- 2) Health reset (nur wenn nicht erste Runde)
    if PVP.currentRound > 1 then
        RespawnPlayers()
    end

    -- Jetzt erst Runde aktivieren
    PVP.roundActive = true
    Log(">> Schritt 3: Teams setzen...")

    -- 3) Teams setzen
    local players = GetAllPlayers()
    for _, p in ipairs(players) do
        ApplyTeam(p.char, GetTeam(p.name))
    end
    Log(">> Schritt 4: Friendly Fire...")

    -- 4) Friendly Fire
    SetFriendlyFire(true)
    Log(">> Schritt 5: Teleport...")

    -- 5) Neue Spawns waehlen + Teleport
    PickTeamSpawnPoints()
    if PVP.teamSpawns.Blue then
        Log(string.format("  BLUE Spawn: %.0f, %.0f", PVP.teamSpawns.Blue.X, PVP.teamSpawns.Blue.Y))
    end
    if PVP.teamSpawns.Red then
        Log(string.format("  RED Spawn: %.0f, %.0f", PVP.teamSpawns.Red.X, PVP.teamSpawns.Red.Y))
    end
    local count = 0
    for _, p in ipairs(players) do
        local team = GetTeam(p.name)
        Log(string.format("  TP: %s [%s]", p.name, team))
        if TeleportPlayer(p.char, team) then count = count + 1 end
    end

    Log(">> Runde gestartet!")
    Toast(string.format("RUNDE %d - FIGHT!", PVP.currentRound))
    ScorePopup(string.format("BLUE %d - %d RED", PVP.scores.Blue, PVP.scores.Red))
end

------------------------------------------------------------
-- SCOREBOARD
------------------------------------------------------------

local function ShowScoreboard()
    Log("========== SCOREBOARD ==========")
    Log(string.format("Runde %d/%d | BLUE %d - %d RED",
        PVP.currentRound, CONFIG.ROUNDS_TO_WIN, PVP.scores.Blue, PVP.scores.Red))
    Log("--------------------------------")

    local players = GetAllPlayers()
    for _, p in ipairs(players) do
        local team = GetTeam(p.name)
        local dead = false
        Safe(function() dead = p.char:IsDeadOrUnconscious() end)
        Log(string.format("  [%s] %s %s", team, p.name, dead and "- TOT" or "- LEBT"))
    end

    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then
            Log("--- Stats ---")
            for _, ps in pairs(states) do
                Safe(function()
                    local n = ""
                    Safe(function() n = tostring(ps:GetPlayerName()) end)
                    if n == "" or n == "None" then
                        Safe(function() n = tostring(ps.PlayerNamePrivate) end)
                    end
                    local k, d = 0, 0
                    Safe(function() k = ps.Kills end)
                    Safe(function() d = ps.Deaths end)
                    Log(string.format("  %s: K:%d D:%d", n, k, d))
                end)
            end
        end
    end)

    Toast(string.format("BLUE %d - %d RED | Runde %d", PVP.scores.Blue, PVP.scores.Red, PVP.currentRound))
    Log("================================")
end

------------------------------------------------------------
-- HOOKS
------------------------------------------------------------

local function SetupHooks()
    -- NUR PlayerKilled hooken - das feuert nur fuer echte Spieler, nicht NPCs
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotGameMode:PlayerKilled", function(self)
            if not PVP.enabled then return end
            Log(">> Spieler getoetet!")
            Toast("Spieler eliminiert!")
            CheckRoundEnd()
        end)
        Log("Hook: PlayerKilled")
    end)

    -- Spawn Hook fuer Friendly Fire
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotGameMode:SpawnPlayerCharacter", function(self)
            if not PVP.enabled then return end
            SetFriendlyFire(true)
        end)
        Log("Hook: SpawnChar")
    end)
end

------------------------------------------------------------
-- CHARACTER WATCHER
------------------------------------------------------------

local function SetupWatcher()
    Safe(function()
        NotifyOnNewObject("/Script/ReadyOrNot.PlayerCharacter", function(newChar)
            if not PVP.enabled then return end
            Safe(function() newChar.bNoTeamDamage = false end)
        end)
        Log("Watcher OK")
    end)
end

------------------------------------------------------------
-- HOTKEYS - Simpel!
------------------------------------------------------------

local function SetupHotkeys()
    -- F5: EIN KNOPF = Alles automatisch
    RegisterKeyBind(Key.F5, function()
        PVP_GO()
    end)

    -- F6: Scoreboard
    RegisterKeyBind(Key.F6, function()
        ShowScoreboard()
    end)

    -- F7: PVP Stoppen
    RegisterKeyBind(Key.F7, function()
        PVP.enabled = false
        PVP.roundActive = false
        SetFriendlyFire(false)
        Toast("PVP GESTOPPT")
    end)

    -- F8: NPCs entfernen
    RegisterKeyBind(Key.F8, function()
        ClearNPCs()
        Toast("NPCs entfernt!")
    end)

    Log("Hotkeys: F5=GO! F6=Score F7=Stop F8=ClearNPCs")
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------

math.randomseed(os.time())
Log("========================================")
Log("  PVP MOD v4.0 - Ready or Not")
Log("  EIN KNOPF EDITION")
Log("========================================")
SetupHooks()
SetupWatcher()
SetupHotkeys()
Log("========================================")
Log("  F5 = PVP STARTEN / NAECHSTE RUNDE")
Log("  F6 = Scoreboard")
Log("  F7 = PVP Stoppen")
Log("  F8 = NPCs entfernen")
Log("  Toast-Nachrichten erscheinen im Spiel!")
Log("========================================")
