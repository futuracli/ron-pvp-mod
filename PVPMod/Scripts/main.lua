--[[
    PVP MOD v7.0 for Ready or Not
    EINFACH UND STABIL

    F5 = PVP Starten / Naechste Runde (EIN KNOPF)
    F6 = Scoreboard
    F7 = PVP Stoppen
    F8 = NPCs entfernen
--]]

local CONFIG = {
    ROUNDS_TO_WIN = 5,
    TEAM_SPAWN_RADIUS = 250,
    SPAWN_SCATTER_RANGE = 4000,
}

local PVP = {
    enabled = false,
    currentRound = 0,
    roundActive = false,
    scores = { Blue = 0, Red = 0 },
    spawnPoints = {},
    teams = {},
    teamSpawns = { Blue = nil, Red = nil },
}

-- Logging
local function Log(m) print("[PVP] " .. tostring(m) .. "\n") end
local function Safe(fn)
    local ok, err = pcall(fn)
    if not ok then print("[PVP-ERR] " .. tostring(err) .. "\n") end
    return ok
end

-- Toast (In-Game Text)
local function Toast(msg)
    Log(msg)
    pcall(function()
        ExecuteInGameThread(function()
            pcall(function()
                local huds = FindAllOf("W_HumanCharacter_HUD_V2_C")
                if not huds then huds = FindAllOf("HumanCharacterHUD_V2") end
                if huds then
                    for _, h in pairs(huds) do
                        pcall(function() if h:IsValid() then h:AddToast(tostring(msg)) end end)
                    end
                end
            end)
        end)
    end)
end

-- Helpers
local function RandomElement(t) if not t or #t == 0 then return nil end; return t[math.random(1,#t)] end
local function ShuffleTable(t) for i=#t,2,-1 do local j=math.random(1,i); t[i],t[j]=t[j],t[i] end; return t end
local function GetDistance(a,b) return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2) end

-- Spieler sammeln
local function GetAllPlayers()
    local players = {}
    local names = {}
    Safe(function()
        local states = FindAllOf("ReadyOrNotPlayerState")
        if states then for _, ps in pairs(states) do Safe(function()
            local n = ""
            Safe(function() n = tostring(ps.PlayerNamePrivate) end)
            if n=="" or n=="None" or string.find(n,"FString") or string.find(n,"0x") then
                n = "Spieler" .. (#names+1)
            end
            table.insert(names, n)
        end) end end
    end)
    local idx = 1
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then for _, c in pairs(chars) do Safe(function()
            table.insert(players, {name=names[idx] or ("Spieler"..idx), char=c})
            idx = idx + 1
        end) end end
    end)
    return players
end

-- Spawns
local function CollectSpawnPoints()
    PVP.spawnPoints = {}
    local base = nil
    Safe(function()
        local chars = FindAllOf("PlayerCharacter")
        if chars then for _, c in pairs(chars) do Safe(function()
            local l = c:K2_GetActorLocation()
            if l then base = {X=l.X,Y=l.Y,Z=l.Z} end
        end) end end
    end)
    if not base then return end
    for _, cls in ipairs({"PlayerStart","ActorSpawnPoint","PlayerStart_VIP_Spawn"}) do
        Safe(function()
            local f = FindAllOf(cls)
            if f then for _, o in pairs(f) do Safe(function()
                local l = o:K2_GetActorLocation()
                if l then table.insert(PVP.spawnPoints, {X=l.X,Y=l.Y,Z=l.Z}) end
            end) end end
        end)
    end
    if #PVP.spawnPoints == 0 then
        for i=1,12 do
            local a = (i/12)*2*math.pi + math.random()*0.5
            local d = CONFIG.SPAWN_SCATTER_RANGE * (0.4 + math.random()*0.6)
            table.insert(PVP.spawnPoints, {X=base.X+math.cos(a)*d, Y=base.Y+math.sin(a)*d, Z=base.Z})
        end
    end
    Log("Spawns: " .. #PVP.spawnPoints)
end

local function PickTeamSpawns()
    if #PVP.spawnPoints < 2 then return end
    local best,bA,bB = 0,1,2
    for i=1,#PVP.spawnPoints do for j=i+1,#PVP.spawnPoints do
        local d = GetDistance(PVP.spawnPoints[i], PVP.spawnPoints[j])
        if d > best then best=d; bA=i; bB=j end
    end end
    PVP.teamSpawns.Blue = PVP.spawnPoints[bA]
    PVP.teamSpawns.Red = PVP.spawnPoints[bB]
end

local function TeleportPlayer(char, team)
    local base = (team=="Blue") and PVP.teamSpawns.Blue or PVP.teamSpawns.Red
    if not base then base = RandomElement(PVP.spawnPoints) end
    if not base then return false end
    local ok = false
    Safe(function()
        local r=CONFIG.TEAM_SPAWN_RADIUS; local a=math.random()*2*math.pi; local d=math.random()*r
        char:K2_SetActorLocation({X=base.X+math.cos(a)*d, Y=base.Y+math.sin(a)*d, Z=base.Z}, false, {}, true)
        char:K2_SetActorRotation({Pitch=0, Yaw=math.random(0,360), Roll=0}, true)
        ok = true
    end)
    return ok
end

-- NPCs unter die Map
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
    Log("NPCs weg: " .. n)
end

-- Friendly Fire + Teams
local function SetFriendlyFire(on)
    Safe(function()
        local chars = FindAllOf("ReadyOrNotCharacter")
        if chars then for _, c in pairs(chars) do
            Safe(function() c.bNoTeamDamage = not on end)
        end end
    end)
end

local function ApplyTeam(char, team)
    Safe(function() char.DefaultTeam = (team=="Blue") and 2 or 1 end)
    Safe(function() char:HandleTeamChanged((team=="Blue") and 2 or 1) end)
end

local function GetTeam(name) return PVP.teams[name] or "Blue" end

local function AutoAssignTeams()
    PVP.teams = {}
    local players = ShuffleTable(GetAllPlayers())
    for i, p in ipairs(players) do
        local t = (i%2==1) and "Blue" or "Red"
        PVP.teams[p.name] = t
        ApplyTeam(p.char, t)
        Log(p.name .. " -> " .. t)
    end
    local b,r = 0,0
    for _,t in pairs(PVP.teams) do if t=="Blue" then b=b+1 else r=r+1 end end
    Toast("Teams: BLUE " .. b .. " vs RED " .. r)
end

-- Runden
local PVP_GO

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
    if aB==0 and aR>0 then winner="Red" elseif aR==0 and aB>0 then winner="Blue" end
    if winner then
        PVP.roundActive = false
        PVP.scores[winner] = PVP.scores[winner] + 1
        Toast("TEAM " .. winner:upper() .. " GEWINNT RUNDE " .. PVP.currentRound .. "!")
        Toast("BLUE " .. PVP.scores.Blue .. " - " .. PVP.scores.Red .. " RED")
        if PVP.scores[winner] >= CONFIG.ROUNDS_TO_WIN then
            Toast("TEAM " .. winner:upper() .. " GEWINNT DAS MATCH!")
            ExecuteWithDelay(8000, function()
                ExecuteInGameThread(function()
                    PVP.scores={Blue=0,Red=0}; PVP.currentRound=0; PVP.enabled=false; PVP_GO()
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
        PVP.enabled=true; PVP.currentRound=0; PVP.roundActive=false; PVP.scores={Blue=0,Red=0}
        CollectSpawnPoints(); AutoAssignTeams()
        Log("=== NEUES MATCH ===")
    end
    if PVP.roundActive then Toast("Runde laeuft!"); return end
    if PVP.scores.Blue >= CONFIG.ROUNDS_TO_WIN or PVP.scores.Red >= CONFIG.ROUNDS_TO_WIN then
        PVP.currentRound=0; PVP.scores={Blue=0,Red=0}; AutoAssignTeams()
    end

    PVP.currentRound = PVP.currentRound + 1
    ClearNPCs()
    if PVP.currentRound > 1 then
        -- Tote Spieler respawnen
        Safe(function()
            local gm = FindFirstOf("ReadyOrNotGameMode")
            if gm and gm:IsValid() then
                Safe(function() gm:RespawnDeadPlayers() end)
            end
        end)
        -- Health resetten fuer alle
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
    Toast("RUNDE " .. PVP.currentRound .. " - FIGHT!")
    Toast("BLUE " .. PVP.scores.Blue .. " - " .. PVP.scores.Red .. " RED")
end

-- Scoreboard
local function ShowScoreboard()
    Log("========== SCOREBOARD ==========")
    Log("Runde " .. PVP.currentRound .. "/" .. CONFIG.ROUNDS_TO_WIN ..
        " | BLUE " .. PVP.scores.Blue .. " - " .. PVP.scores.Red .. " RED")
    local players = GetAllPlayers()
    for _, p in ipairs(players) do
        local dead = false
        Safe(function() dead = p.char:IsDeadOrUnconscious() end)
        Log("  [" .. GetTeam(p.name) .. "] " .. p.name .. " " .. (dead and "TOT" or "LEBT"))
    end
    Toast("BLUE " .. PVP.scores.Blue .. " - " .. PVP.scores.Red .. " RED")
    Log("================================")
end

-- Hooks
local function SetupHooks()
    -- EIGENBESCHUSS FIX (Pre + Post Hook)
    Safe(function()
        local pre, post = RegisterHook("/Script/ReadyOrNot.ReadyOrNotCharacter:IsOnSameTeam", function(self)
            -- Pre-Hook: nichts tun
        end)
        Log("Hook: IsOnSameTeam pre=" .. tostring(pre) .. " post=" .. tostring(post))
    end)
    -- Nochmal als einzelner Hook mit Return-Value Override
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotCharacter:IsOnSameTeam", function(self, A, B, ReturnValue)
            if PVP.enabled and ReturnValue then
                ReturnValue:set(false)
                Log("IsOnSameTeam -> false gesetzt!")
            end
        end)
        Log("Hook: IsOnSameTeam override")
    end)
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.BpGameplayHelperLib:IsFriendly", function(self, GS, T1, T2, Ret)
            if PVP.enabled and Ret then Ret:set(false) end
        end)
        Log("Hook: IsFriendly -> false")
    end)
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.BpGameplayHelperLib:IsFriendlyWithMe", function(self, GS, T, Ret)
            if PVP.enabled and Ret then Ret:set(false) end
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
    -- Spawn
    Safe(function()
        RegisterHook("/Script/ReadyOrNot.ReadyOrNotGameMode:SpawnPlayerCharacter", function(self)
            if PVP.enabled then SetFriendlyFire(true) end
        end)
        Log("Hook: SpawnChar")
    end)
end

-- Watcher
Safe(function()
    NotifyOnNewObject("/Script/ReadyOrNot.PlayerCharacter", function(c)
        if PVP.enabled then Safe(function() c.bNoTeamDamage = false end) end
    end)
end)

-- Hotkeys
RegisterKeyBind(Key.F5, function() PVP_GO() end)
RegisterKeyBind(Key.F6, function() ShowScoreboard() end)
RegisterKeyBind(Key.F7, function()
    PVP.enabled=false; PVP.roundActive=false; SetFriendlyFire(false); Toast("PVP GESTOPPT")
end)
RegisterKeyBind(Key.F8, function() ClearNPCs(); Toast("NPCs entfernt!") end)

-- Init
math.randomseed(os.time())
Log("========================================")
Log("  PVP MOD v7.0 - Ready or Not")
Log("========================================")
SetupHooks()
Log("  F5 = PVP Starten / Naechste Runde")
Log("  F6 = Scoreboard")
Log("  F7 = PVP Stoppen")
Log("  F8 = NPCs entfernen")
Log("========================================")
