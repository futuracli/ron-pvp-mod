--[[
    PVP MOD v5.0 for Ready or Not

    F5 = PVP Starten / Naechste Runde
    F6 = Scoreboard
    F7 = PVP Stoppen
    F8 = NPCs entfernen
    F9 = Schaden aendern (1x/2x/5x/10x)
--]]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local CONFIG = {
    ROUNDS_TO_WIN = 5,
    TEAM_SPAWN_RADIUS = 250,
    SPAWN_SCATTER_RANGE = 4000,
    DAMAGE_MULTIPLIER = 1.0,
    DAMAGE_OPTIONS = { 1.0, 2.0, 5.0, 10.0 },
    DAMAGE_INDEX = 1,
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
    teams = {},
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
-- TOAST - In-Game Nachrichten
------------------------------------------------------------

local function FindAllHUDs()
    local huds = nil
    pcall(function() huds = FindAllOf("W_HumanCharacter_HUD_V2_C") end)
    if not huds then
        pcall(function() huds = FindAllOf("HumanCharacterHUD_V2") end)
    end
    return huds
end

local function Toast(msg)
    local text = tostring(msg)
    Log(text)
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local huds = FindAllHUDs()
                if huds then
                    for _, hud in pairs(huds) do
                        pcall(function()
                            if hud:IsValid() then hud:AddToast(text) end
                        end)
                    end
                end
            end)
        end)
    end)
end

local function ScorePopup(msg)
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local huds = FindAllHUDs()
                if huds then
                    for _, hud in pairs(huds) do
                        pcall(function()
                            if hud:IsValid() then hud:AddScorePopup(FText(tostring(msg))) end
                        end)
                    end
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
-- SPIELER SAMMELN mit Steam-Namen
------------------------------------------------------------

local function GetAllPlayers()
    local players = {}

    local steamNames = {}
    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then
            for _, ps in pairs(states) do
                Safe(function()
                    local n = ""
                    Safe(function()
                        local raw = ps.PlayerNamePrivate
                        if raw then
                            n = tostring(raw)
                            if string.find(n, "FString") or string.find(n, "0x") then n = "" end
                        end
                    end)
                    if n == "" or n == "None" then
                        Safe(function()
                            local result = ps:GetPlayerName()
                            if result then
                                local s = tostring(result)
                                if s ~= "" and s ~= "None" and not string.find(s, "FString") then n = s end
                            end
                        end)
                    end
                    if n == "" or n == "None" then n = "Spieler" .. (#steamNames + 1) end
                    table.insert(steamNames, n)
                end)
            end
        end
    end)

    local idx = 1
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function()
                    table.insert(players, { name = steamNames[idx] or ("Spieler" .. idx), char = char })
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
                        npc:K2_SetActorLocation({ X = 0, Y = 0, Z = -50000 }, false, {}, true)
                        removed = removed + 1
                    end)
                end
            end
        end)
    end
    Log(string.format("NPCs weggebeamt: %d", removed))
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
    Safe(function() playerChar:HandleTeamChanged(enumVal) end)
end

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
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, char in pairs(chars) do
                Safe(function() char:ResetHealth() end)
            end
        end
    end)
end

------------------------------------------------------------
-- RUNDEN
------------------------------------------------------------

-- Forward declaration
local PVP_GO

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

    Debug(string.format("Alive: B=%d R=%d", aliveBlue, aliveRed))

    local winner = nil
    if aliveBlue == 0 and aliveRed > 0 then winner = "Red"
    elseif aliveRed == 0 and aliveBlue > 0 then winner = "Blue" end

    if winner then
        PVP.roundActive = false
        PVP.scores[winner] = PVP.scores[winner] + 1
        Toast(string.format("TEAM %s GEWINNT RUNDE %d!", string.upper(winner), PVP.currentRound))
        ScorePopup(string.format("BLUE %d - %d RED", PVP.scores.Blue, PVP.scores.Red))

        if PVP.scores[winner] >= CONFIG.ROUNDS_TO_WIN then
            Toast(string.format("TEAM %s GEWINNT DAS MATCH!", string.upper(winner)))
            Toast("Neues Match in 8 Sekunden...")
            Log(">> Auto-Restart: Match Ende")
            ExecuteWithDelay(8000, function()
                Log(">> Auto-Restart: Match Reset!")
                ExecuteInGameThread(function()
                    PVP.scores = { Blue = 0, Red = 0 }
                    PVP.currentRound = 0
                    PVP.enabled = false
                    PVP_GO()
                end)
            end)
        else
            Toast("Naechste Runde in 5 Sekunden...")
            Log(">> Auto-Restart: Naechste Runde in 5s")
            ExecuteWithDelay(5000, function()
                Log(">> Auto-Restart: Runde startet!")
                ExecuteInGameThread(function()
                    PVP_GO()
                end)
            end)
        end
    end
end

------------------------------------------------------------
-- HAUPTFUNKTION
------------------------------------------------------------

PVP_GO = function()
    if not PVP.enabled then
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

    -- 1) NPCs weg (VOR roundActive)
    ClearNPCs()

    -- 2) Health reset (ab Runde 2)
    if PVP.currentRound > 1 then
        RespawnPlayers()
    end

    -- Jetzt Runde aktivieren
    PVP.roundActive = true

    -- 3) Teams setzen
    local players = GetAllPlayers()
    for _, p in ipairs(players) do
        ApplyTeam(p.char, GetTeam(p.name))
    end

    -- 4) Friendly Fire
    SetFriendlyFire(true)

    -- 5) Teleport
    PickTeamSpawnPoints()
    local count = 0
    for _, p in ipairs(players) do
        local team = GetTeam(p.name)
        if TeleportPlayer(p.char, team) then count = count + 1 end
    end

    Log(string.format("Runde %d | %d Spieler teleportiert", PVP.currentRound, count))
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
            for _, ps in pairs(states) do
                Safe(function()
                    local n = "?"
                    Safe(function() n = tostring(ps.PlayerNamePrivate) end)
                    if n == "" or n == "None" or string.find(n, "FString") then n = "?" end
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
    -- EIGENBESCHUSS FIX: IsOnSameTeam(A, B) -> bool
    -- Parameter: self, A, B, ReturnValue (ReturnValue ist der LETZTE param)
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotCharacter:IsOnSameTeam", function(self, A, B, ReturnValue)
            if not PVP.enabled then return end
            if ReturnValue then ReturnValue:set(false) end
        end)
        Log("Hook: IsOnSameTeam(A,B) -> false")
    end)

    -- IsFriendly(GameState, TeamOne, TeamTwo) -> bool
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.BpGameplayHelperLib:IsFriendly", function(self, GameState, TeamOne, TeamTwo, ReturnValue)
            if not PVP.enabled then return end
            if ReturnValue then ReturnValue:set(false) end
        end)
        Log("Hook: IsFriendly -> false")
    end)

    -- IsFriendlyWithMe(GameState, TeamType) -> bool
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.BpGameplayHelperLib:IsFriendlyWithMe", function(self, GameState, TeamType, ReturnValue)
            if not PVP.enabled then return end
            if ReturnValue then ReturnValue:set(false) end
        end)
        Log("Hook: IsFriendlyWithMe -> false")
    end)

    -- PlayerKilled
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotGameMode:PlayerKilled", function(self)
            if not PVP.enabled then return end
            Log(">> Spieler getoetet!")
            Toast("Spieler eliminiert!")
            CheckRoundEnd()
        end)
        Log("Hook: PlayerKilled")
    end)

    -- Damage Multiplier: Extra Schaden bei TakeDamage
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotCharacter:Multicast_TakeDamage", function(self)
            if not PVP.enabled then return end
            if CONFIG.DAMAGE_MULTIPLIER > 1.0 then
                Safe(function()
                    local char = self:get()
                    if char and char:IsValid() then
                        -- Bei 2x: 1 extra hit, bei 5x: 4 extra, bei 10x: 9 extra
                        local extraHits = math.floor(CONFIG.DAMAGE_MULTIPLIER) - 1
                        for i = 1, extraHits do
                            Safe(function()
                                -- Kopf-Schaden simulieren fuer schnelleren Kill
                                local healthComps = FindAllOf("CharacterHealthComponent")
                                if healthComps then
                                    for _, hc in pairs(healthComps) do
                                        Safe(function()
                                            -- DecreaseLimbHealth(Limb, Amount)
                                            -- Limb 0 = Head
                                            hc:DecreaseLimbHealth(0, 10.0)
                                        end)
                                    end
                                end
                            end)
                        end
                    end
                end)
            end
        end)
        Log("Hook: TakeDamage (Multiplier)")
    end)

    -- Spawn Hook
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
-- UE WIDGET MENU (echtes In-Game Menu)
-- Erstellt ein UE UserWidget und zeigt es im Viewport
------------------------------------------------------------

local PVP_WIDGET = nil

local function CreatePVPWidget()
    if PVP_WIDGET then return PVP_WIDGET end

    Safe(function()
        ExecuteInGameThread(function()
            Safe(function()
                local pc = FindFirstOf("ReadyOrNotPlayerController")
                if not pc or not pc:IsValid() then
                    Debug("Kein PlayerController fuer Widget")
                    return
                end

                -- Versuche CreateWidgetForPlayer mit bekanntem Widget
                -- Das Spiel hat eine Widget-Registry
                local widget = nil
                Safe(function()
                    widget = pc:CreateWidgetForPlayer("W_PVP_RoundEnd", false, false)
                end)

                if widget and widget:IsValid() then
                    PVP_WIDGET = widget
                    Log("Widget erstellt: W_PVP_RoundEnd")
                else
                    -- Fallback: StaticConstructObject fuer UserWidget
                    Safe(function()
                        local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
                        if widgetClass then
                            widget = StaticConstructObject(widgetClass, pc, FName("PVPMenuWidget"))
                            if widget and widget:IsValid() then
                                PVP_WIDGET = widget
                                Log("Widget erstellt via StaticConstructObject")
                            end
                        end
                    end)
                end
            end)
        end)
    end)

    return PVP_WIDGET
end

local function ShowWidget()
    Safe(function()
        ExecuteInGameThread(function()
            Safe(function()
                if PVP_WIDGET and PVP_WIDGET:IsValid() then
                    PVP_WIDGET:AddToViewport(100)
                    Log("Widget sichtbar")
                else
                    CreatePVPWidget()
                    if PVP_WIDGET and PVP_WIDGET:IsValid() then
                        PVP_WIDGET:AddToViewport(100)
                    else
                        Debug("Widget konnte nicht erstellt werden")
                    end
                end
            end)
        end)
    end)
end

local function HideWidget()
    Safe(function()
        ExecuteInGameThread(function()
            Safe(function()
                if PVP_WIDGET and PVP_WIDGET:IsValid() then
                    PVP_WIDGET:RemoveFromParent()
                    Log("Widget versteckt")
                end
            end)
        end)
    end)
end

------------------------------------------------------------
-- IN-GAME MENU (Insert Taste)
-- Zeigt Optionen als Toast, Numpad waehlt aus
------------------------------------------------------------

local MENU = {
    open = false,
    page = "main",
}

local function ShowMenuPage()
    if MENU.page == "main" then
        Toast("=== PVP MENU ===")
        Toast(string.format("Status: %s | Runde %d/%d | B%d-R%d",
            PVP.enabled and "AN" or "AUS", PVP.currentRound, CONFIG.ROUNDS_TO_WIN,
            PVP.scores.Blue, PVP.scores.Red))
        Toast("[1] PVP Start/Runde [2] Stop")
        Toast("[3] Teams [4] Runden [5] Schaden")
        Toast("[6] NPCs weg [7] Scoreboard")
        Toast("[Insert] Menu schliessen")
    elseif MENU.page == "teams" then
        Toast("=== TEAMS ===")
        local players = GetAllPlayers()
        for i, p in ipairs(players) do
            Toast(string.format("%d. %s -> %s", i, p.name, GetTeam(p.name)))
        end
        Toast("[1] Auto-Teams [2] Tauschen")
        Toast("[3] Sp1 wechseln [4] Sp2 wechseln")
        Toast("[9] Zurueck")
    elseif MENU.page == "rounds" then
        Toast(string.format("=== RUNDEN: %d ===", CONFIG.ROUNDS_TO_WIN))
        Toast("[1] 3 Runden [2] 5 Runden [3] 7 Runden")
        Toast("[9] Zurueck")
    elseif MENU.page == "damage" then
        Toast(string.format("=== SCHADEN: %.0fx ===", CONFIG.DAMAGE_MULTIPLIER))
        Toast("[1] 1x [2] 2x [3] 5x [4] 10x")
        Toast("[9] Zurueck")
    end
end

local function HandleMenuInput(key)
    if not MENU.open then return false end

    if MENU.page == "main" then
        if key == 1 then PVP_GO(); MENU.open = false
        elseif key == 2 then
            PVP.enabled = false; PVP.roundActive = false
            SetFriendlyFire(false); Toast("PVP GESTOPPT"); MENU.open = false
        elseif key == 3 then MENU.page = "teams"; ShowMenuPage()
        elseif key == 4 then MENU.page = "rounds"; ShowMenuPage()
        elseif key == 5 then MENU.page = "damage"; ShowMenuPage()
        elseif key == 6 then ClearNPCs(); Toast("NPCs entfernt!")
        elseif key == 7 then ShowScoreboard()
        end
    elseif MENU.page == "teams" then
        if key == 1 then AutoAssignTeams(); ShowMenuPage()
        elseif key == 2 then
            for name, team in pairs(PVP.teams) do
                PVP.teams[name] = (team == "Blue") and "Red" or "Blue"
            end
            Toast("Teams getauscht!")
            ShowMenuPage()
        elseif key == 3 then
            local players = GetAllPlayers()
            if #players >= 1 then
                local p = players[1]
                PVP.teams[p.name] = (GetTeam(p.name) == "Blue") and "Red" or "Blue"
                ApplyTeam(p.char, PVP.teams[p.name])
                Toast(p.name .. " -> " .. PVP.teams[p.name])
            end
            ShowMenuPage()
        elseif key == 4 then
            local players = GetAllPlayers()
            if #players >= 2 then
                local p = players[2]
                PVP.teams[p.name] = (GetTeam(p.name) == "Blue") and "Red" or "Blue"
                ApplyTeam(p.char, PVP.teams[p.name])
                Toast(p.name .. " -> " .. PVP.teams[p.name])
            end
            ShowMenuPage()
        elseif key == 9 then MENU.page = "main"; ShowMenuPage()
        end
    elseif MENU.page == "rounds" then
        if key == 1 then CONFIG.ROUNDS_TO_WIN = 3; Toast("Runden: 3")
        elseif key == 2 then CONFIG.ROUNDS_TO_WIN = 5; Toast("Runden: 5")
        elseif key == 3 then CONFIG.ROUNDS_TO_WIN = 7; Toast("Runden: 7")
        elseif key == 9 then MENU.page = "main"; ShowMenuPage()
        end
    elseif MENU.page == "damage" then
        if key == 1 then CONFIG.DAMAGE_MULTIPLIER = 1.0; Toast("Schaden: 1x")
        elseif key == 2 then CONFIG.DAMAGE_MULTIPLIER = 2.0; Toast("Schaden: 2x")
        elseif key == 3 then CONFIG.DAMAGE_MULTIPLIER = 5.0; Toast("Schaden: 5x")
        elseif key == 4 then CONFIG.DAMAGE_MULTIPLIER = 10.0; Toast("Schaden: 10x")
        elseif key == 9 then MENU.page = "main"; ShowMenuPage()
        end
    end

    return true
end

------------------------------------------------------------
-- HOTKEYS
------------------------------------------------------------

local function SetupHotkeys()
    -- INSERT: In-Game Menu (Widget + Toast Fallback)
    RegisterKeyBind(Key.INS, function()
        MENU.open = not MENU.open
        if MENU.open then
            MENU.page = "main"
            -- Versuche echtes Widget
            ShowWidget()
            -- Toast als Fallback/Ergaenzung
            ShowMenuPage()
        else
            HideWidget()
            Toast("Menu geschlossen")
        end
    end)

    -- F5: Quick Start (auch ohne Menu)
    RegisterKeyBind(Key.F5, function() PVP_GO() end)

    -- F6: Scoreboard
    RegisterKeyBind(Key.F6, function() ShowScoreboard() end)

    -- Numpad 1-9: Menu Input
    RegisterKeyBind(Key.NUM_ONE, function() HandleMenuInput(1) end)
    RegisterKeyBind(Key.NUM_TWO, function() HandleMenuInput(2) end)
    RegisterKeyBind(Key.NUM_THREE, function() HandleMenuInput(3) end)
    RegisterKeyBind(Key.NUM_FOUR, function() HandleMenuInput(4) end)
    RegisterKeyBind(Key.NUM_FIVE, function() HandleMenuInput(5) end)
    RegisterKeyBind(Key.NUM_SIX, function() HandleMenuInput(6) end)
    RegisterKeyBind(Key.NUM_SEVEN, function() HandleMenuInput(7) end)
    RegisterKeyBind(Key.NUM_EIGHT, function() HandleMenuInput(8) end)
    RegisterKeyBind(Key.NUM_NINE, function() HandleMenuInput(9) end)

    Log("Hotkeys: INSERT=Menu F5=GO F6=Score Numpad=Input")
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------

math.randomseed(os.time())
Log("========================================")
Log("  PVP MOD v5.1 - Ready or Not")
Log("========================================")
SetupHooks()
SetupWatcher()
SetupHotkeys()
Log("========================================")
Log("  INSERT = In-Game PVP Menu")
Log("  F5 = Quick Start / Naechste Runde")
Log("  F6 = Scoreboard")
Log("  Numpad 1-9 = Menu Auswahl")
Log("========================================")
