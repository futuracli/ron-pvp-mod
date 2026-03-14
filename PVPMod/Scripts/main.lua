--[[
    PVP MOD v6.0 for Ready or Not

    INSERT     = Menu oeffnen/schliessen
    Numpad 1-9 = Menu Auswahl
    F5         = Quick Start / Naechste Runde
    F6         = Scoreboard
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

local MENU = { open = false, page = "main" }

------------------------------------------------------------
-- LOGGING
------------------------------------------------------------

local function Log(msg) print(string.format("[PVP] %s\n", tostring(msg))) end

local function Safe(fn)
    local ok, err = pcall(fn)
    if not ok then print(string.format("[PVP-ERR] %s\n", tostring(err))) end
    return ok
end

------------------------------------------------------------
-- TOAST
------------------------------------------------------------

local function FindAllHUDs()
    local huds = nil
    pcall(function() huds = FindAllOf("W_HumanCharacter_HUD_V2_C") end)
    if not huds then pcall(function() huds = FindAllOf("HumanCharacterHUD_V2") end) end
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
                        pcall(function() if hud:IsValid() then hud:AddToast(text) end end)
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
                        pcall(function() if hud:IsValid() then hud:AddScorePopup(FText(tostring(msg))) end end)
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
    return math.sqrt((a.X-b.X)^2 + (a.Y-b.Y)^2)
end

------------------------------------------------------------
-- SPIELER
------------------------------------------------------------

local function GetAllPlayers()
    local players = {}
    local names = {}

    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then
            for _, ps in pairs(states) do
                Safe(function()
                    local n = ""
                    Safe(function()
                        local raw = ps.PlayerNamePrivate
                        if raw then n = tostring(raw) end
                        if string.find(n, "FString") or string.find(n, "0x") then n = "" end
                    end)
                    if n == "" or n == "None" then
                        Safe(function()
                            local r = ps:GetPlayerName()
                            if r then
                                local s = tostring(r)
                                if not string.find(s, "FString") then n = s end
                            end
                        end)
                    end
                    if n == "" or n == "None" then n = "Spieler" .. (#names + 1) end
                    table.insert(names, n)
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
                    table.insert(players, { name = names[idx] or ("Spieler"..idx), char = char })
                    idx = idx + 1
                end)
            end
        end
    end)

    return players
end

------------------------------------------------------------
-- SPAWNS
------------------------------------------------------------

local function CollectSpawnPoints()
    PVP.spawnPoints = {}
    local basePos = nil

    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then
            for _, c in pairs(chars) do
                Safe(function()
                    local loc = c:K2_GetActorLocation()
                    if loc then basePos = { X=loc.X, Y=loc.Y, Z=loc.Z } end
                end)
            end
        end
    end)
    if not basePos then return end

    for _, cls in ipairs({"PlayerStart","ActorSpawnPoint","PlayerStart_VIP_Spawn"}) do
        Safe(function()
            local found = FindAllOf(cls)
            if found then
                for _, obj in pairs(found) do
                    Safe(function()
                        local loc = obj:K2_GetActorLocation()
                        if loc then table.insert(PVP.spawnPoints, {X=loc.X,Y=loc.Y,Z=loc.Z}) end
                    end)
                end
            end
        end)
    end

    if #PVP.spawnPoints == 0 then
        for i = 1, 12 do
            local a = (i/12) * 2 * math.pi + math.random() * 0.5
            local d = CONFIG.SPAWN_SCATTER_RANGE * (0.4 + math.random() * 0.6)
            table.insert(PVP.spawnPoints, {
                X = basePos.X + math.cos(a)*d,
                Y = basePos.Y + math.sin(a)*d,
                Z = basePos.Z
            })
        end
    end
    Log(string.format("Spawns: %d", #PVP.spawnPoints))
end

local function PickTeamSpawns()
    if #PVP.spawnPoints < 2 then return end
    local best, bA, bB = 0, 1, 2
    for i = 1, #PVP.spawnPoints do
        for j = i+1, #PVP.spawnPoints do
            local d = GetDistance(PVP.spawnPoints[i], PVP.spawnPoints[j])
            if d > best then best=d; bA=i; bB=j end
        end
    end
    PVP.teamSpawns.Blue = PVP.spawnPoints[bA]
    PVP.teamSpawns.Red = PVP.spawnPoints[bB]
end

local function TeleportPlayer(char, team)
    local base = (team=="Blue") and PVP.teamSpawns.Blue or PVP.teamSpawns.Red
    if not base then base = RandomElement(PVP.spawnPoints) end
    if not base then return false end
    local ok = false
    Safe(function()
        local r = CONFIG.TEAM_SPAWN_RADIUS
        local a = math.random() * 2 * math.pi
        local d = math.random() * r
        char:K2_SetActorLocation({X=base.X+math.cos(a)*d, Y=base.Y+math.sin(a)*d, Z=base.Z}, false, {}, true)
        char:K2_SetActorRotation({Pitch=0, Yaw=math.random(0,360), Roll=0}, true)
        ok = true
    end)
    return ok
end

------------------------------------------------------------
-- NPCs / FRIENDLY FIRE / TEAMS
------------------------------------------------------------

local function ClearNPCs()
    local n = 0
    for _, cls in ipairs({"CyberneticCharacter","CivilianCharacter"}) do
        Safe(function()
            local npcs = FindAllOf(cls)
            if npcs then for _, npc in pairs(npcs) do
                Safe(function() npc:K2_SetActorLocation({X=0,Y=0,Z=-50000}, false, {}, true); n=n+1 end)
            end end
        end)
    end
    Log(string.format("NPCs weg: %d", n))
end

local function SetFriendlyFire(on)
    Safe(function()
        local chars = FindAllOf("ReadyOrNotCharacter")
        if chars then for _, c in pairs(chars) do
            Safe(function() c.bNoTeamDamage = not on end)
        end end
    end)
end

local function ApplyTeam(char, team)
    local v = (team=="Blue") and 2 or 1
    Safe(function() char.DefaultTeam = v end)
    Safe(function() char:HandleTeamChanged(v) end)
end

local function GetTeam(name) return PVP.teams[name] or "Blue" end

local function AutoAssignTeams()
    PVP.teams = {}
    local players = ShuffleTable(GetAllPlayers())
    for i, p in ipairs(players) do
        local t = (i%2==1) and "Blue" or "Red"
        PVP.teams[p.name] = t
        ApplyTeam(p.char, t)
        Log(string.format("  %s -> %s", p.name, t))
    end
    local b,r = 0,0
    for _,t in pairs(PVP.teams) do if t=="Blue" then b=b+1 else r=r+1 end end
    Toast(string.format("Teams: BLUE %d vs RED %d", b, r))
end

------------------------------------------------------------
-- RUNDEN
------------------------------------------------------------

local PVP_GO -- forward declaration

local function CheckRoundEnd()
    if not PVP.roundActive then return end
    local players = GetAllPlayers()
    if #players == 0 then return end

    local aB, aR = 0, 0
    for _, p in ipairs(players) do
        local dead = false
        Safe(function() dead = p.char:IsDeadOrUnconscious() end)
        if not dead then
            if GetTeam(p.name)=="Blue" then aB=aB+1 else aR=aR+1 end
        end
    end

    local winner = nil
    if aB==0 and aR>0 then winner="Red"
    elseif aR==0 and aB>0 then winner="Blue" end

    if winner then
        PVP.roundActive = false
        PVP.scores[winner] = PVP.scores[winner] + 1
        Toast(string.format("TEAM %s GEWINNT RUNDE %d!", winner:upper(), PVP.currentRound))
        ScorePopup(string.format("BLUE %d - %d RED", PVP.scores.Blue, PVP.scores.Red))

        if PVP.scores[winner] >= CONFIG.ROUNDS_TO_WIN then
            Toast(string.format("TEAM %s GEWINNT DAS MATCH!", winner:upper()))
            Toast("Neues Match in 8 Sek...")
            ExecuteWithDelay(8000, function()
                ExecuteInGameThread(function()
                    PVP.scores = {Blue=0,Red=0}; PVP.currentRound = 0; PVP.enabled = false
                    PVP_GO()
                end)
            end)
        else
            Toast("Naechste Runde in 5 Sek...")
            ExecuteWithDelay(5000, function()
                ExecuteInGameThread(function() PVP_GO() end)
            end)
        end
    end
end

PVP_GO = function()
    if not PVP.enabled then
        PVP.enabled = true; PVP.currentRound = 0; PVP.roundActive = false
        PVP.scores = {Blue=0,Red=0}
        CollectSpawnPoints(); AutoAssignTeams()
        Log("=== NEUES MATCH ===")
    end

    if PVP.roundActive then Toast("Runde laeuft!"); return end

    if PVP.scores.Blue >= CONFIG.ROUNDS_TO_WIN or PVP.scores.Red >= CONFIG.ROUNDS_TO_WIN then
        PVP.currentRound = 0; PVP.scores = {Blue=0,Red=0}; AutoAssignTeams()
    end

    PVP.currentRound = PVP.currentRound + 1
    ClearNPCs()
    if PVP.currentRound > 1 then
        Safe(function()
            local chars = FindAllOf("PlayerCharacter")
            if chars then for _,c in pairs(chars) do Safe(function() c:ResetHealth() end) end end
        end)
    end

    PVP.roundActive = true
    local players = GetAllPlayers()
    for _, p in ipairs(players) do ApplyTeam(p.char, GetTeam(p.name)) end
    SetFriendlyFire(true)

    PickTeamSpawns()
    local count = 0
    for _, p in ipairs(players) do
        if TeleportPlayer(p.char, GetTeam(p.name)) then count=count+1 end
    end

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
        local dead = false
        Safe(function() dead = p.char:IsDeadOrUnconscious() end)
        Log(string.format("  [%s] %s %s", GetTeam(p.name), p.name, dead and "TOT" or "LEBT"))
    end
    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then for _, ps in pairs(states) do Safe(function()
            local n = "?"
            Safe(function() n = tostring(ps.PlayerNamePrivate) end)
            if n=="" or n=="None" or string.find(n,"FString") then n="?" end
            local k,d = 0,0
            Safe(function() k = ps.Kills end)
            Safe(function() d = ps.Deaths end)
            Log(string.format("  %s: K:%d D:%d", n, k, d))
        end) end end
    end)
    Toast(string.format("BLUE %d - %d RED | Runde %d", PVP.scores.Blue, PVP.scores.Red, PVP.currentRound))
    Log("================================")
end

------------------------------------------------------------
-- MENU (Insert + Numpad, alles ueber Toast)
------------------------------------------------------------

local function ShowMenu()
    if MENU.page == "main" then
        Toast("===== PVP MENU =====")
        Toast(string.format("[%s] Runde %d/%d | BLUE %d - RED %d | DMG %.0fx",
            PVP.enabled and "AN" or "AUS", PVP.currentRound, CONFIG.ROUNDS_TO_WIN,
            PVP.scores.Blue, PVP.scores.Red, CONFIG.DAMAGE_MULTIPLIER))
        Toast("[1] Start/Runde  [2] Stop")
        Toast("[3] Teams  [4] Runden  [5] Schaden")
        Toast("[6] NPCs weg  [7] Score  [0] Schliessen")
    elseif MENU.page == "teams" then
        Toast("===== TEAMS =====")
        local players = GetAllPlayers()
        for i, p in ipairs(players) do
            Toast(string.format("  %d. %s [%s]", i, p.name, GetTeam(p.name)))
        end
        Toast("[1] Auto  [2] Tauschen")
        Toast("[3] Sp.1 switch  [4] Sp.2 switch")
        Toast("[5] Sp.3 switch  [6] Sp.4 switch")
        Toast("[0] Zurueck")
    elseif MENU.page == "rounds" then
        Toast(string.format("===== RUNDEN: %d =====", CONFIG.ROUNDS_TO_WIN))
        Toast("[1] 3  [2] 5  [3] 7  [4] 10")
        Toast("[0] Zurueck")
    elseif MENU.page == "damage" then
        Toast(string.format("===== SCHADEN: %.0fx =====", CONFIG.DAMAGE_MULTIPLIER))
        Toast("[1] 1x  [2] 2x  [3] 5x  [4] 10x")
        Toast("[0] Zurueck")
    end
end

local function MenuInput(key)
    if not MENU.open then return end

    -- 0 = Zurueck/Schliessen
    if key == 0 then
        if MENU.page == "main" then
            MENU.open = false; Toast("Menu zu")
        else
            MENU.page = "main"; ShowMenu()
        end
        return
    end

    if MENU.page == "main" then
        if key==1 then PVP_GO(); MENU.open = false
        elseif key==2 then
            PVP.enabled=false; PVP.roundActive=false; SetFriendlyFire(false)
            Toast("PVP GESTOPPT"); MENU.open = false
        elseif key==3 then MENU.page="teams"; ShowMenu()
        elseif key==4 then MENU.page="rounds"; ShowMenu()
        elseif key==5 then MENU.page="damage"; ShowMenu()
        elseif key==6 then ClearNPCs(); Toast("NPCs weg!")
        elseif key==7 then ShowScoreboard()
        end

    elseif MENU.page == "teams" then
        if key==1 then AutoAssignTeams(); ShowMenu()
        elseif key==2 then
            for name, team in pairs(PVP.teams) do
                PVP.teams[name] = (team=="Blue") and "Red" or "Blue"
            end
            local players = GetAllPlayers()
            for _, p in ipairs(players) do ApplyTeam(p.char, GetTeam(p.name)) end
            Toast("Teams getauscht!"); ShowMenu()
        elseif key>=3 and key<=6 then
            local idx = key - 2
            local players = GetAllPlayers()
            if idx <= #players then
                local p = players[idx]
                PVP.teams[p.name] = (GetTeam(p.name)=="Blue") and "Red" or "Blue"
                ApplyTeam(p.char, PVP.teams[p.name])
                Toast(p.name .. " -> " .. PVP.teams[p.name])
            else
                Toast("Spieler "..idx.." nicht da")
            end
            ShowMenu()
        end

    elseif MENU.page == "rounds" then
        local opts = {3, 5, 7, 10}
        if key >= 1 and key <= 4 then
            CONFIG.ROUNDS_TO_WIN = opts[key]
            Toast("Runden: " .. opts[key]); ShowMenu()
        end

    elseif MENU.page == "damage" then
        local opts = {1.0, 2.0, 5.0, 10.0}
        if key >= 1 and key <= 4 then
            CONFIG.DAMAGE_MULTIPLIER = opts[key]
            Toast(string.format("Schaden: %.0fx", opts[key])); ShowMenu()
        end
    end
end

------------------------------------------------------------
-- HOOKS
------------------------------------------------------------

local function SetupHooks()
    -- Eigenbeschuss Fix: IsOnSameTeam(A, B) -> false
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotCharacter:IsOnSameTeam", function(self, A, B, ReturnValue)
            if not PVP.enabled then return end
            if ReturnValue then ReturnValue:set(false) end
        end)
        Log("Hook: IsOnSameTeam -> false")
    end)

    Safe(function()
        RegisterHook("/Script/ReadyOrNot.BpGameplayHelperLib:IsFriendly", function(self, GS, T1, T2, Ret)
            if not PVP.enabled then return end
            if Ret then Ret:set(false) end
        end)
        Log("Hook: IsFriendly -> false")
    end)

    Safe(function()
        RegisterHook("/Script/ReadyOrNot.BpGameplayHelperLib:IsFriendlyWithMe", function(self, GS, T, Ret)
            if not PVP.enabled then return end
            if Ret then Ret:set(false) end
        end)
        Log("Hook: IsFriendlyWithMe -> false")
    end)

    -- Kill Detection
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotGameMode:PlayerKilled", function(self)
            if not PVP.enabled then return end
            Toast("Spieler eliminiert!")
            CheckRoundEnd()
        end)
        Log("Hook: PlayerKilled")
    end)

    -- Damage Multiplier
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotCharacter:Multicast_TakeDamage", function(self)
            if not PVP.enabled or CONFIG.DAMAGE_MULTIPLIER <= 1.0 then return end
            Safe(function()
                local char = self:get()
                if char and char:IsValid() then
                    local extra = math.floor(CONFIG.DAMAGE_MULTIPLIER) - 1
                    for i = 1, extra do
                        Safe(function()
                            local comps = FindAllOf("CharacterHealthComponent")
                            if comps then for _, hc in pairs(comps) do
                                Safe(function() hc:DecreaseLimbHealth(0, 10.0) end)
                            end end
                        end)
                    end
                end
            end)
        end)
        Log("Hook: Damage Multiplier")
    end)

    -- Spawn: re-apply friendly fire
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
-- HOTKEYS
------------------------------------------------------------

local function SetupHotkeys()
    -- INSERT: Menu
    RegisterKeyBind(Key.INS, function()
        MENU.open = not MENU.open
        if MENU.open then MENU.page = "main"; ShowMenu()
        else Toast("Menu zu") end
    end)

    -- F5: Quick Start
    RegisterKeyBind(Key.F5, function() PVP_GO() end)

    -- F6: Scoreboard
    RegisterKeyBind(Key.F6, function() ShowScoreboard() end)

    -- Numpad 0-9
    RegisterKeyBind(Key.NUM_ZERO, function() MenuInput(0) end)
    RegisterKeyBind(Key.NUM_ONE, function() MenuInput(1) end)
    RegisterKeyBind(Key.NUM_TWO, function() MenuInput(2) end)
    RegisterKeyBind(Key.NUM_THREE, function() MenuInput(3) end)
    RegisterKeyBind(Key.NUM_FOUR, function() MenuInput(4) end)
    RegisterKeyBind(Key.NUM_FIVE, function() MenuInput(5) end)
    RegisterKeyBind(Key.NUM_SIX, function() MenuInput(6) end)
    RegisterKeyBind(Key.NUM_SEVEN, function() MenuInput(7) end)
    RegisterKeyBind(Key.NUM_EIGHT, function() MenuInput(8) end)
    RegisterKeyBind(Key.NUM_NINE, function() MenuInput(9) end)

    Log("Keys: INS=Menu F5=Go F6=Score Numpad=Input")
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------

math.randomseed(os.time())
Log("========================================")
Log("  PVP MOD v6.0 - Ready or Not")
Log("========================================")
SetupHooks()
SetupWatcher()
SetupHotkeys()
Log("========================================")
Log("  INSERT = PVP Menu (im Spiel sichtbar)")
Log("  F5 = Quick Start")
Log("  F6 = Scoreboard")
Log("========================================")
