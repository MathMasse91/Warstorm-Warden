-- =====================================================
-- Warden - Engine.lua
-- Forked from WoW 3.3.5a raid addon.
-- Original authors: Patchs & Valleriaa.
-- =====================================================

local _, ns = ...

-- ----------------------------------------------------------
-- 3.3.5 compatibility helpers (namespaced; globals removed in this pass).
-- ----------------------------------------------------------
function ns.Engine.IsInRaid()
    if type(IsInRaid) == "function" then return IsInRaid() end
    if type(GetNumRaidMembers) == "function" then return GetNumRaidMembers() > 0 end
    return UnitInRaid and UnitInRaid("player") ~= nil
end

function ns.Engine.IsLeader()
    if type(UnitIsGroupLeader) == "function" then return UnitIsGroupLeader("player") end
    if type(IsPartyLeader) == "function" then return IsPartyLeader() end
    return false
end

-- Party -> raid auto-convert guard, shared verbatim by StartBuild, the roster
-- watcher, and the completer tick. Caller passes the resolved `autoRaid` flag
-- and `buildFitsInParty`; every other term is evaluated live here so all three
-- sites test the identical condition. ConvertToRaid is protected and silently
-- fails in combat, hence the InCombatLockdown() guard.
local function shouldConvertToRaid(autoRaid, buildFitsInParty)
    return autoRaid
       and not buildFitsInParty
       and not ns.Engine.IsInRaid()
       and GetNumPartyMembers() > 0
       and ns.Engine.IsLeader()
       and not InCombatLockdown()
end

-- ----------------------------------------------------------
-- Engine state
-- ----------------------------------------------------------
ns.Engine.state = {
    sendQueue       = {},      -- array of strings (SAY bot-add commands)
    specQueue       = {},      -- { [classToken] = { spec1, spec2, ... } } FIFO
    whisperQueue    = {},      -- array of { name, spec } pending spec whispers
    sending         = false,
    elapsed         = 0,
    whisperElapsed  = 0,
    buildActive     = false,
    buildStartedAt  = 0,
    lastAddSentAt   = 0,
    rosterBefore    = {},      -- { [guid] = true }
    specdGUIDs      = {},      -- { [guid] = true }
    assignedSpecs   = {},      -- { [guid] = { name, spec, classToken } } - session identity map
    counters        = { spawned = 0, specd = 0, skipped = 0 },
}

-- Tunables (seconds)
-- WHISPER_INTERVAL: raised to 0.45 (was 0.35) after 25-man stress tests where
-- a Re-Spec of every raid member plus the appended strategy whispers crossed
-- the server-side "10 whispers / 10s" anti-spam and muted the raid lead
-- mid-pull. 0.45 keeps the headroom without making a full Re-Spec
-- perceptibly slower.
local WHISPER_INTERVAL = 0.45
local BUILD_TIMEOUT    = 30     -- seconds after lastAddSent before specQueue is cleared
-- Wait-for-join pacing: after an addclass we hold the next invite until the
-- group actually grows by one (the bot joined). If it hasn't joined within
-- PER_INVITE_TIMEOUT we assume the invite was dropped (server lag), warn, and
-- move on so one missing bot can't stall the whole build.
local PER_INVITE_TIMEOUT = 8

-- ----------------------------------------------------------
-- Public API - send queue
-- ----------------------------------------------------------
-- channel/target are optional. When either is supplied the entry is stored as
-- a table { msg, channel, target } so the drain can route it (e.g. a WHISPER
-- to a named bot); legacy callers pass only `msg` and we keep inserting the
-- bare string, which the drain still handles. This lets WardenMantle + the
-- Spec tab funnel spec whispers through the same throttle as bot-add commands.
function ns.Engine.Queue(msg, channel, target)
    if type(msg) ~= "string" or msg == "" then return end
    if channel or target then
        table.insert(ns.Engine.state.sendQueue, { msg = msg, channel = channel, target = target })
    else
        table.insert(ns.Engine.state.sendQueue, msg)
    end
    ns.Engine.state.sending = true
    ns.Engine.ArmSendTicker()
end

function ns.Engine.QueueDepth()
    return #ns.Engine.state.sendQueue
end

-- ----------------------------------------------------------
-- Send-queue ticker - drains sendQueue at DB.interval. Self-disarms when
-- idle so we aren't dispatched every frame during normal play.
-- Re-armed by ns.Engine.Queue() and ns.Engine.StartBuild().
-- ----------------------------------------------------------
ns.Engine.ticker = CreateFrame("Frame", "WardenEngineTicker")

-- Current group size counting the player: raid size, or party members + 1,
-- or 1 when solo. Mirrors how a bot joining bumps the count by one.
local function groupSize()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return GetNumRaidMembers() end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return GetNumPartyMembers() + 1 end
    return 1
end

local function sendTick(self, elapsed)
    local s = ns.Engine.state
    if not s.sending or #s.sendQueue == 0 then
        s.sending = false
        self:SetScript("OnUpdate", nil) -- idle -> detach
        return
    end

    local db       = ns.Persistence.DB
    local interval = (db and tonumber(db.interval)) or 0.70
    if interval < 0.10 then interval = 0.10 end

    local now  = GetTime()
    local size = groupSize()

    -- Wait-for-join gate - ONLY during an active build, where each queued
    -- command is an addclass that grows the group. (Other queue users, e.g.
    -- InitBots' per-bot init commands, don't add members, so the gate must not
    -- apply to them - they drain on the plain interval below.)
    -- s.expectedSize is the size we should reach once the previously-sent bot
    -- joins; nil means nothing outstanding. Hold until the group catches up
    -- (anti-lag), or until the per-invite timeout fires and we give up on it.
    if s.buildActive and s.expectedSize and size < s.expectedSize then
        if (now - (s.lastAddSentAt or now)) > PER_INVITE_TIMEOUT then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff6060[Warden]|r A bot missed its invite (server lag?) - continuing.")
            if ns.LogF then
                ns.LogF("paced summon: invite timeout (size=%d expected=%d) - skipping wait",
                    size, s.expectedSize)
            end
            s.expectedSize = nil  -- stop waiting; fall through and send the next
        else
            return                -- still waiting for the previous bot to arrive
        end
    end

    -- Throttle: even when free to send, never fire faster than the configured
    -- min interval so back-to-back fast joins don't trip server anti-spam.
    s.elapsed = s.elapsed + elapsed
    if s.elapsed < interval then return end
    s.elapsed = 0

    -- Entries are either a bare string (bot-add command on the command
    -- channel) or a table { msg, channel, target } for routed sends such as
    -- spec whispers. Both drain on the same throttle.
    local item = table.remove(s.sendQueue, 1)
    local msg, ch, tgt
    if type(item) == "table" then
        msg, ch, tgt = item.msg, item.channel, item.target
    else
        msg = item
    end
    SendChatMessage(msg, ch or (db and db.commandChannel) or "SAY", nil, tgt)
    s.lastAddSentAt    = GetTime()
    s.counters.spawned = s.counters.spawned + 1
    -- Arm the join gate for the next send only while building (see above).
    s.expectedSize = s.buildActive and (size + 1) or nil
end

function ns.Engine.ArmSendTicker()
    ns.Engine.ticker:SetScript("OnUpdate", sendTick)
end

-- ----------------------------------------------------------
-- Internal: build specQueue + sendQueue from a plan
-- plan = { {classToken, spec, count, opt1?, opt2?}, ... }  (ordered)
-- specQueue entries carry { spec=..., opt1=..., opt2=... } so AI strategies
-- can be whispered alongside the spec.
-- ----------------------------------------------------------
local function buildQueues(plan)
    local s = ns.Engine.state
    wipe(s.sendQueue)
    wipe(s.specQueue)

    local addPattern = (ns.Persistence.DB and ns.Persistence.DB.addPattern)
        or ".warstormbot bot addclass %s"
    if not string.find(addPattern, "%%s") then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff0000[Warden]|r addPattern must include %s - aborting Build.")
        return 0
    end

    -- BUG-07: explicit numeric loop with nil guard so a hole in the plan
    -- array (which plain `for _, row in ipairs(plan)` would stop at) does
    -- NOT abort the whole summon sequence. Also guard every row field.
    -- FEATURE-02: skip rows flagged as human players - those slots are
    -- placeholders for real humans and must not be summoned by the bot
    -- command.
    local total = 0
    for i = 1, #plan do
        local row = plan[i]
        if row and not row.isPlayer then
            local count = tonumber(row.count) or 0
            local cmdToken = row.classToken and ns.Data.CLASS_CMD[row.classToken]
            if count > 0 and cmdToken and row.spec and row.spec ~= "" then
                s.specQueue[row.classToken] = s.specQueue[row.classToken] or {}
                local opt1Arr = ns.Data.CsvToArray(row.opt1)
                local opt2Arr = ns.Data.CsvToArray(row.opt2)
                for j = 1, count do
                    table.insert(s.sendQueue, string.format(addPattern, cmdToken))
                    table.insert(s.specQueue[row.classToken], {
                        spec = row.spec,
                        opt1 = ns.Data.PickRotated(opt1Arr, j),
                        opt2 = ns.Data.PickRotated(opt2Arr, j),
                    })
                end
                total = total + count
            end
        end
    end
    return total
end

-- ----------------------------------------------------------
-- Snapshot the current raid/party roster - used to ignore pre-existing members
-- ----------------------------------------------------------
local function snapshotRoster()
    local snap = {}
    if ns.Engine.IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            local guid = UnitGUID(unit)
            if guid then snap[guid] = true end
        end
    else
        -- Include player + party
        local playerGUID = UnitGUID("player")
        if playerGUID then snap[playerGUID] = true end
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local guid = UnitGUID(unit)
            if guid then snap[guid] = true end
        end
    end
    return snap
end

-- ----------------------------------------------------------
-- Public API: StartBuild
-- Returns the number of bots queued (0 if plan empty or invalid).
-- ----------------------------------------------------------
function ns.Engine.StartBuild(plan)
    local s = ns.Engine.state
    if ns.DebugF then
        local nPlan, nPlayer = 0, 0
        if type(plan) == "table" then
            nPlan = #plan
            for i = 1, nPlan do
                if plan[i] and plan[i].isPlayer then nPlayer = nPlayer + 1 end
            end
        end
        ns.DebugF("build", "StartBuild: %d rows (%d flagged isPlayer -> skip spawn), combat=%s",
            nPlan, nPlayer,
            (InCombatLockdown and InCombatLockdown()) and "Y" or "N")
        -- Dump the plan so we can see which class/spec is flagged isPlayer.
        -- Helps diagnose when a build spawns one too many bots - we'll see
        -- here whether the isPlayer flag actually survived save->load.
        for i = 1, nPlan do
            local r = plan[i]
            if r then
                ns.DebugF("build", "  row %d: %s/%s isPlayer=%s",
                    i, tostring(r.classToken), tostring(r.spec),
                    r.isPlayer and "Y" or "N")
            end
        end
    end

    -- Reset transient counters + queues
    s.counters.spawned = 0
    s.counters.specd   = 0
    s.counters.skipped = 0
    wipe(s.specdGUIDs)
    wipe(s.whisperQueue)
    s.whisperElapsed   = 0
    s.elapsed          = 0
    s.expectedSize     = nil   -- paced-summon gate: nothing outstanding yet

    s.rosterBefore = snapshotRoster()

    if ns.Log then
        local rosterCount = 0
        for _ in pairs(s.rosterBefore) do rosterCount = rosterCount + 1 end
        ns.LogF("StartBuild: plan has %d rows, roster snapshot size=%d", #plan, rosterCount)
        for i, row in ipairs(plan) do
            ns.LogF("  row %d: %s x%d -> '%s'", i, row.classToken, row.count or 0, row.spec or "")
        end
    end

    local total = buildQueues(plan)
    if total <= 0 then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffaa00[Warden]|r Build aborted: empty plan.")
        return 0
    end

    if ns.Log then
        local specQueueStr = ""
        for classToken, q in pairs(s.specQueue) do
            local specs = {}
            for _, entry in ipairs(q) do
                table.insert(specs, type(entry) == "table" and entry.spec or tostring(entry))
            end
            specQueueStr = specQueueStr .. string.format(" %s=[%s]", classToken, table.concat(specs, ","))
        end
        ns.LogF("buildQueues: total=%d sendQueue=%d specQueue={%s}", total, #s.sendQueue, specQueueStr)
    end

    -- Party -> raid if (a) the setting is on AND (b) the comp doesn't
    -- fit in a 5-man party. Count non-isPlayer rows: if `spawnCount+1`
    -- (the +1 = the real player) is at most 5, we stay in party mode
    -- instead of dragging a 5-man comp into an empty 25-slot raid frame.
    -- ConvertToRaid is a protected API on 3.3.5a - calling it during
    -- combat silently fails and leaves the caller thinking the party is
    -- raid-mode when it isn't, so always guard on combat lockdown.
    local spawnCount = 0
    if type(plan) == "table" then
        for i = 1, #plan do
            if plan[i] and not plan[i].isPlayer then spawnCount = spawnCount + 1 end
        end
    end
    s.buildFitsInParty = (spawnCount <= 4)  -- player + up to 4 bots = 5

    local db = ns.Persistence.DB
    local autoRaid = db and db.autoRaidDuringBuild ~= false
    if shouldConvertToRaid(autoRaid, s.buildFitsInParty) then
        ConvertToRaid()
    end

    -- Symmetric reverse: if the next build's comp fits in a party AND
    -- we're currently stuck in a raid (typical after a prior 10/25-man
    -- build), collapse the raid back to party mode. WoW only allows
    -- ConvertToParty when the raid already has <=5 members, so run
    -- Cleanup first if you still have stale bots in the raid.
    if autoRaid
       and s.buildFitsInParty
       and ns.Engine.IsInRaid()
       and ns.Engine.IsLeader()
       and not InCombatLockdown() then
        local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
        if raidCount > 0 and raidCount <= 5 and ConvertToParty then
            ConvertToParty()
        elseif raidCount > 5 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffffaa00[Warden]|r Can't collapse to party - raid has %d members (>5). "
                .. "Run Cleanup first if you want a party build.", raidCount))
        end
    end

    s.buildActive    = true
    s.buildStartedAt = GetTime()
    s.lastAddSentAt  = GetTime()
    s.sending        = true
    s.completerAccum = 0

    -- Player auto-move: if the comp flagged a [P] slot, move the player
    -- to that subgroup BEFORE any bot spawns so the bots fill around the
    -- player, not the other way around. UI_TabComp.Build already runs
    -- this same move for the "already in raid" case; we rerun it here
    -- (deferred 0.5s to let ConvertToRaid propagate) so the party->raid
    -- path is also covered. SetRaidSubgroup is a no-op when the player
    -- is already in the target group, so double-firing is harmless.
    if plan and plan.playerTargetGroup then
        ns.Engine.SchedulePlayerMove(plan.playerTargetGroup, 0.5)
    end

    -- Arm all tickers (they self-disarm when idle).
    ns.Engine.ArmSendTicker()
    ns.Engine.ArmWhisperTicker()
    ns.Engine.ArmCompleter()

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00ff00[Warden]|r Build started: %d bots queued.", total))
    return total
end

-- ----------------------------------------------------------
-- Player auto-move helpers
-- ----------------------------------------------------------
-- Synchronous move: runs immediately. No-ops if not in a raid, if the
-- player can't be located in the roster, or if we're already in the
-- target group.
function ns.Engine.MovePlayerToGroup(targetGroup)
    if not (targetGroup and SetRaidSubgroup and GetNumRaidMembers and GetRaidRosterInfo) then
        return false
    end
    if GetNumRaidMembers() == 0 then return false end
    local myRaidIdx
    for i = 1, GetNumRaidMembers() do
        if UnitIsUnit("raid" .. i, "player") then myRaidIdx = i; break end
    end
    if not myRaidIdx then return false end
    local _, _, currentGroup = GetRaidRosterInfo(myRaidIdx)
    if currentGroup == targetGroup then return true end
    local ok, err = pcall(SetRaidSubgroup, myRaidIdx, targetGroup)
    if ok then
        if ns.DebugF then
            ns.DebugF("build", "player auto-move: raid%d %d -> %d",
                myRaidIdx, currentGroup or -1, targetGroup)
        end
        return true
    end
    if ns.LogError then ns.LogError("player auto-move failed: " .. tostring(err)) end
    return false
end

-- Deferred move: waits `delay` seconds, then RETRIES MovePlayerToGroup every
-- `delay` seconds until it succeeds or a deadline passes. The retry matters
-- because a build that starts from solo / a small party has NO raid yet when
-- the first attempt fires - the party->raid conversion only completes once
-- enough bots have joined (see the roster watcher / completer). A single
-- one-shot attempt would no-op against the not-yet-existing raid and the
-- player would be stranded in the wrong subgroup. Polling moves them into
-- their [P] slot's group as soon as the raid actually forms.
-- MovePlayerToGroup returns true when the move lands OR the player is already
-- in the target group, and false while there's no raid / player not found -
-- so "retry until true" converges cleanly. Reuses one shared frame.
local _moveDelayFrame
function ns.Engine.SchedulePlayerMove(targetGroup, delay)
    if not targetGroup then return end
    if not _moveDelayFrame then
        _moveDelayFrame = CreateFrame("Frame", "WardenPlayerMoveDelay")
    end
    local f = _moveDelayFrame
    f._target     = targetGroup
    f._elapsed    = 0
    f._delay      = delay or 0.5
    f._sinceStart = 0
    f._deadline   = 15        -- keep trying up to 15s while the raid assembles
    f:SetScript("OnUpdate", function(self, dt)
        self._elapsed    = self._elapsed + dt
        self._sinceStart = self._sinceStart + dt
        if self._elapsed < self._delay then return end
        self._elapsed = 0
        if ns.Engine.MovePlayerToGroup(self._target) then
            self:SetScript("OnUpdate", nil)          -- moved / already in place
        elseif self._sinceStart >= self._deadline then
            self:SetScript("OnUpdate", nil)          -- raid never formed - give up
            if ns.LogF then
                ns.LogF("player auto-move: gave up after %ds (no raid?)", self._deadline)
            end
        end
    end)
end

-- ----------------------------------------------------------
-- Public API: ReSpecAll
-- Re-whispers the current plan's specs to every raid member (FIFO per class).
-- Useful when the server drops whispers: reloads the plan onto existing bots
-- without spawning new ones. Skips the player themselves.
-- Returns the number of whispers queued.
-- ----------------------------------------------------------
function ns.Engine.ReSpecAll(plan)
    if type(plan) ~= "table" or #plan == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffaa00[Warden]|r Re-Spec aborted: empty plan.")
        return 0
    end

    -- Expand plan into FIFO spec queue per class (for untracked units).
    -- opt1/opt2 rotate through CSV so 3 Paladins can carry kings/might/wisdom.
    -- BUG-07 / FEATURE-02: explicit numeric loop with full nil+isPlayer guards.
    local localQueue = {}
    for i = 1, #plan do
        local row = plan[i]
        if row and not row.isPlayer then
            local count = tonumber(row.count) or 0
            if count > 0 and row.classToken and row.spec and row.spec ~= "" then
                localQueue[row.classToken] = localQueue[row.classToken] or {}
                local opt1Arr = ns.Data.CsvToArray(row.opt1)
                local opt2Arr = ns.Data.CsvToArray(row.opt2)
                for j = 1, count do
                    table.insert(localQueue[row.classToken], {
                        spec = row.spec,
                        opt1 = ns.Data.PickRotated(opt1Arr, j),
                        opt2 = ns.Data.PickRotated(opt2Arr, j),
                    })
                end
            end
        end
    end

    local s            = ns.Engine.state
    local trackedCount = 0
    local fifoCount    = 0
    local seen         = {}

    local function enqueue(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        if UnitIsUnit(unit, "player") then return end
        local guid = UnitGUID(unit)
        if not guid or seen[guid] then return end
        seen[guid] = true

        local name = UnitName(unit)
        if not name then return end
        local _, classToken = UnitClass(unit)
        if not classToken then return end

        -- Pass 1: identity - use the spec we already assigned to this GUID.
        local tracked = s.assignedSpecs[guid]
        if tracked and tracked.spec then
            ns.Engine.PushWhisper({
                name = name, spec = tracked.spec,
                opt1 = tracked.opt1, opt2 = tracked.opt2,
                classToken = classToken,
            })
            tracked.name = name
            trackedCount = trackedCount + 1
            if ns.LogF then
                ns.LogF("ReSpecAll[track]: '%s' -> %s (class=%s opt1=%s opt2=%s)",
                    tracked.spec, name, classToken,
                    tostring(tracked.opt1), tostring(tracked.opt2))
            end
            return
        end

        -- Pass 2: fall back to FIFO match against the plan + record for future.
        local q = localQueue[classToken]
        if not q or #q == 0 then
            if ns.LogF then
                ns.LogF("ReSpecAll[skip]: %s (class=%s) - no plan slot", name, classToken)
            end
            return
        end
        local entry = table.remove(q, 1)
        local spec  = entry.spec
        local opt1, opt2 = entry.opt1, entry.opt2
        ns.Engine.PushWhisper({
            name = name, spec = spec, opt1 = opt1, opt2 = opt2, classToken = classToken,
        })
        s.assignedSpecs[guid] = {
            name = name, spec = spec, classToken = classToken,
            opt1 = opt1, opt2 = opt2,
        }
        fifoCount = fifoCount + 1
        if ns.LogF then
            ns.LogF("ReSpecAll[fifo]: '%s' -> %s (class=%s opt1=%s opt2=%s) [now tracked]",
                spec, name, classToken, tostring(opt1), tostring(opt2))
        end
    end

    if ns.Engine.IsInRaid() then
        for i = 1, GetNumRaidMembers() do enqueue("raid" .. i) end
    else
        for i = 1, GetNumPartyMembers() do enqueue("party" .. i) end
    end

    local leftover = 0
    for _, q in pairs(localQueue) do leftover = leftover + #q end
    local total = trackedCount + fifoCount

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00ff00[Warden]|r Re-Spec: %d bots queued (%d tracked, %d new FIFO, %d plan slots unmatched).",
        total, trackedCount, fifoCount, leftover))
    if ns.LogF then
        ns.LogF("ReSpecAll done: total=%d tracked=%d fifo=%d leftover=%d",
            total, trackedCount, fifoCount, leftover)
    end
    return total
end

-- ----------------------------------------------------------
-- Public API: ClearTracking
-- Wipes the GUID->spec identity map so subsequent ReSpecAll falls back to
-- pure FIFO matching against the current plan. Called by the panel when the
-- user loads a different comp or clears all rows.
-- ----------------------------------------------------------
function ns.Engine.ClearTracking()
    wipe(ns.Engine.state.assignedSpecs)
    if ns.Log then ns.Log("ClearTracking: assignedSpecs wiped") end
end

-- ----------------------------------------------------------
-- Public API: Stop - cancels pending adds and specs
-- ----------------------------------------------------------
function ns.Engine.Stop()
    local s = ns.Engine.state
    wipe(s.sendQueue)
    wipe(s.whisperQueue)
    wipe(s.specQueue)
    s.sending         = false
    s.buildActive     = false
    s.expectedSize    = nil
    -- Abort any pending one-click "Create" chain: drop the completion hook so
    -- autogear / world buffs don't still fire, and cancel queued timers.
    s.onBuildComplete = nil
    if ns.Engine.CancelTimers then ns.Engine.CancelTimers() end
    if ns.Log then ns.Log("Engine.Stop: all queues wiped") end
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffffaa00[Warden]|r Build stopped.")
end

-- ----------------------------------------------------------
-- Roster watcher - detects newly joined bots and whispers their spec
-- ----------------------------------------------------------
local watcher = CreateFrame("Frame", "WardenEngineWatcher")
watcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
watcher:RegisterEvent("RAID_ROSTER_UPDATE")

local function processUnit(unit)
    local s    = ns.Engine.state
    local guid = UnitGUID(unit)
    if not guid then return end
    if s.rosterBefore[guid] then return end
    if s.specdGUIDs[guid] then return end
    if not UnitIsPlayer(unit) then return end
    -- FEATURE-02: skip anybody flagged as a human player. Their slot is a
    -- placeholder in the comp and shouldn't receive the talents whisper.
    local _name = UnitName(unit)
    if _name and ns.Persistence and ns.Persistence.IsPlayerName
       and ns.Persistence.IsPlayerName(_name) then
        if ns.LogF then
            ns.LogF("processUnit: skipped '%s' (flagged as human player)", _name)
        end
        return
    end

    local _, classToken = UnitClass(unit)
    if not classToken then
        if ns.LogF then ns.LogF("processUnit: %s no class yet, will retry next event", unit) end
        return
    end
    local queue = s.specQueue[classToken]
    if not queue or #queue == 0 then
        if ns.LogF then ns.LogF("processUnit: %s class=%s specQueue empty - skipped", unit, classToken) end
        return
    end

    local entry = table.remove(queue, 1)
    local name  = UnitName(unit)
    if not name then
        -- Name not ready; put entry back at front so next event retries
        table.insert(queue, 1, entry)
        return
    end

    local spec = type(entry) == "table" and entry.spec or entry
    local opt1 = type(entry) == "table" and entry.opt1 or nil
    local opt2 = type(entry) == "table" and entry.opt2 or nil

    -- Don't whisper directly - enqueue to smooth out the rate
    ns.Engine.PushWhisper({
        name = name, spec = spec, opt1 = opt1, opt2 = opt2, classToken = classToken,
    })
    s.specdGUIDs[guid] = true
    s.assignedSpecs[guid] = {
        name = name, spec = spec, classToken = classToken, opt1 = opt1, opt2 = opt2,
    }
    if ns.LogF then
        ns.LogF("processUnit: queued whisper '%s' to %s (class=%s opt1=%s opt2=%s) [tracked]",
            spec, name, classToken, tostring(opt1), tostring(opt2))
    end
end

watcher:SetScript("OnEvent", function()
    local s  = ns.Engine.state
    local db = ns.Persistence.DB
    if not s.buildActive then return end
    if db and db.autoSpec == false then return end

    if ns.Engine.IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            processUnit("raid" .. i)
        end
    else
        for i = 1, GetNumPartyMembers() do
            processUnit("party" .. i)
        end
    end

    -- Auto-convert party -> raid during build. ConvertToRaid is protected
    -- and silently fails in combat; guard explicitly so the user isn't
    -- fooled into thinking the raid was formed mid-pull.
    -- Also respect `s.buildFitsInParty` so a 5-man comp (4 bots + player)
    -- stays in party mode - the setting is a "convert when needed", not
    -- a "convert always".
    if shouldConvertToRaid(db and db.autoRaidDuringBuild ~= false, s.buildFitsInParty) then
        ConvertToRaid()
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00[Warden]|r Party converted to raid.")
    end
end)

-- ----------------------------------------------------------
-- Whisper ticker - drains whisperQueue at WHISPER_INTERVAL. Self-disarms
-- when idle; re-armed by ns.Engine.PushWhisper() push sites.
-- ----------------------------------------------------------
local whisperTicker = CreateFrame("Frame", "WardenEngineWhisperTicker")

local function whisperTick(self, elapsed)
    local s = ns.Engine.state
    if #s.whisperQueue == 0 then
        s.whisperElapsed = 0
        self:SetScript("OnUpdate", nil) -- idle -> detach
        return
    end

    s.whisperElapsed = s.whisperElapsed + elapsed
    if s.whisperElapsed < WHISPER_INTERVAL then return end
    s.whisperElapsed = 0

    local item = table.remove(s.whisperQueue, 1)
    if item and item.name and item.spec then
        SendChatMessage("talents spec " .. item.spec, "WHISPER", nil, item.name)
        s.counters.specd = s.counters.specd + 1
        if ns.LogF then
            ns.LogF("whisper sent: 'talents spec %s' to %s (whispers left: %d)",
                item.spec, item.name, #s.whisperQueue)
        end

        -- Chase with mod-playerbots strategy commands (nc +bstats, nc totems melee, ...)
        -- Append to tail (not front): they chase by one throttle-tick per strat,
        -- which is invisible to users and avoids O(n) table shifts per spec.
        if item.classToken and ns.Data and ns.Data.BuildStratCommands then
            local cmds = ns.Data.BuildStratCommands(item.classToken, item.opt1, item.opt2, item.spec)
            for _, cmd in ipairs(cmds) do
                table.insert(s.whisperQueue, { name = item.name, strat = cmd })
            end
            if ns.LogF and #cmds > 0 then
                ns.LogF("  queued %d strat(s) for %s: %s",
                    #cmds, item.name, table.concat(cmds, " | "))
            end
        end
    elseif item and item.name and item.strat then
        SendChatMessage(item.strat, "WHISPER", nil, item.name)
        if ns.LogF then
            ns.LogF("strat whisper: '%s' -> %s", item.strat, item.name)
        end
    end
end

function ns.Engine.ArmWhisperTicker()
    whisperTicker:SetScript("OnUpdate", whisperTick)
end

-- Centralized whisper push - inserts into queue and arms the ticker.
-- All call sites that used to do `table.insert(s.whisperQueue, item)` directly
-- should go through this so the ticker reliably wakes up.
-- FEATURE-02: silently drop whispers aimed at a character flagged as a
-- human player, so a stray Re-Spec can never spec somebody's actual toon.
function ns.Engine.PushWhisper(item)
    if type(item) ~= "table" or not item.name then return end
    if ns.Persistence and ns.Persistence.IsPlayerName
       and ns.Persistence.IsPlayerName(item.name) then
        if ns.LogF then
            ns.LogF("PushWhisper: skipped '%s' (flagged as human player)", item.name)
        end
        if ns.DebugF then
            ns.DebugF("whisper", "push skipped '%s' (flagged as human player)", item.name)
        end
        return
    end
    table.insert(ns.Engine.state.whisperQueue, item)
    if ns.DebugF then
        ns.DebugF("whisper", "push '%s' spec=%s strat=%s (queue depth %d)",
            tostring(item.name), tostring(item.spec or "-"),
            tostring(item.strat or "-"), #ns.Engine.state.whisperQueue)
    end
    ns.Engine.ArmWhisperTicker()
end

-- Immediate, un-throttled whisper. Bypasses the whisperQueue ticker (which
-- waits a full WHISPER_INTERVAL and queues behind any pending spec whispers)
-- for latency-sensitive one-shots like WardenMantle's Summon, where any delay
-- feels broken. Still honors the human-player guard so it can't message a real
-- toon flagged as a player.
function ns.Engine.WhisperNow(name, msg)
    if type(name) ~= "string" or name == "" or not msg or msg == "" then return end
    if ns.Persistence and ns.Persistence.IsPlayerName
       and ns.Persistence.IsPlayerName(name) then
        if ns.LogF then
            ns.LogF("WhisperNow: skipped '%s' (flagged as human player)", name)
        end
        return
    end
    SendChatMessage(msg, "WHISPER", nil, name)
    if ns.LogF then ns.LogF("WhisperNow: '%s' -> %s", msg, name) end
end

-- ----------------------------------------------------------
-- Build-completion ticker - prints summary when queues are empty or timeout hit.
-- Self-disarms when build ends; re-armed by StartBuild().
-- ----------------------------------------------------------
local completer = CreateFrame("Frame", "WardenEngineCompleter")

local function completerTick(self, elapsed)
    local s = ns.Engine.state
    if not s.buildActive then
        s.completerAccum = 0
        self:SetScript("OnUpdate", nil) -- idle -> detach
        return
    end

    s.completerAccum = (s.completerAccum or 0) + elapsed
    if s.completerAccum < 1.0 then return end
    s.completerAccum = 0

    -- Timed ConvertToRaid fallback. The roster watcher converts party->raid on
    -- roster events, but if those don't fire (or a conversion silently failed
    -- inside a transient combat lockdown) a 10/25-man build could get stuck in
    -- party mode. The completer already ticks at a 1s cadence during a build,
    -- so retry conversion here - this is the timed fallback the event-driven
    -- path was missing.
    do
        local db = ns.Persistence.DB
        if shouldConvertToRaid(db and db.autoRaidDuringBuild ~= false, s.buildFitsInParty) then
            ConvertToRaid()
            if ns.LogF then ns.LogF("completer: timed ConvertToRaid fallback fired") end
        end
    end

    local pendingSpecs = 0
    for _, queue in pairs(s.specQueue) do
        pendingSpecs = pendingSpecs + #queue
    end

    local sendEmpty    = (#s.sendQueue == 0)
    local whisperEmpty = (#s.whisperQueue == 0)
    local timeout      = sendEmpty and (GetTime() - s.lastAddSentAt > BUILD_TIMEOUT)

    if sendEmpty and whisperEmpty and (pendingSpecs == 0 or timeout) then
        s.buildActive = false
        s.sending     = false
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[Warden]|r Build done: %d bots queued, %d spec'd, %d pending.",
            s.counters.spawned, s.counters.specd, pendingSpecs))
        if ns.LogF then
            ns.LogF("Build done: spawned=%d specd=%d pending=%d (timeout=%s)",
                s.counters.spawned, s.counters.specd, pendingSpecs, tostring(timeout))
        end
        if pendingSpecs > 0 then
            for classToken, queue in pairs(s.specQueue) do
                if #queue > 0 then
                    local first = queue[1]
                    local label = type(first) == "table" and first.spec or first
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(
                        "|cffff6060[Warden]|r No bot joined for: %dx %s/%s",
                        #queue, classToken, tostring(label)))
                end
            end
        end
        -- Clear specQueue after reporting
        wipe(s.specQueue)

        -- Fire-once chain hook, set by ns.Engine.CreateRaid for the one-click
        -- flow (per-bot init -> autogear -> world buffs). Cleared before the
        -- call so a callback that itself starts another build can't re-enter.
        if s.onBuildComplete then
            local cb = s.onBuildComplete
            s.onBuildComplete = nil
            local ok, err = pcall(cb)
            if not ok and ns.LogError then
                ns.LogError("onBuildComplete error: " .. tostring(err))
            end
        end
    end
end

function ns.Engine.ArmCompleter()
    completer:SetScript("OnUpdate", completerTick)
end

-- ----------------------------------------------------------
-- Public accessor for UI status line
-- ----------------------------------------------------------
function ns.Engine.PendingSpecCount()
    local n = 0
    for _, queue in pairs(ns.Engine.state.specQueue) do
        n = n + #queue
    end
    return n
end

-- ----------------------------------------------------------
-- Lightweight one-shot timer scheduler (ns.Engine.After).
-- A single shared frame drains a job list; it hides itself when empty so we
-- aren't dispatched every frame during normal play. Used to space the steps
-- of the one-click "Create" sequence. CancelTimers() drops all pending jobs
-- (called by Engine.Stop so a stopped Create can't fire later steps).
-- ----------------------------------------------------------
local _afterFrame = CreateFrame("Frame", "WardenAfterScheduler")
local _afterJobs  = {}
_afterFrame:Hide()
_afterFrame:SetScript("OnUpdate", function(self)
    if #_afterJobs == 0 then self:Hide(); return end
    local now = GetTime()
    for i = #_afterJobs, 1, -1 do
        if now >= _afterJobs[i].at then
            local job = table.remove(_afterJobs, i)
            local ok, err = pcall(job.fn)
            if not ok and ns.LogError then
                ns.LogError("After job error: " .. tostring(err))
            end
        end
    end
end)

function ns.Engine.After(delay, fn)
    if type(fn) ~= "function" then return end
    table.insert(_afterJobs, { at = GetTime() + (tonumber(delay) or 0), fn = fn })
    _afterFrame:Show()
end

function ns.Engine.CancelTimers()
    wipe(_afterJobs)
    _afterFrame:Hide()
end

-- ----------------------------------------------------------
-- Public API: InitBots - per-named-bot gear/init.
-- Sends `.warstormbot bot init=<rarity> <name>` for every bot in the current
-- group (skips the player and any human-flagged names), throttled through the
-- send queue so a 25-man init doesn't blast the server in one frame. Unlike
-- the global `init=<rarity>` (no name), this targets each bot individually -
-- matching how the bot core applies gear per character. Returns the count.
-- ----------------------------------------------------------
function ns.Engine.InitBots(rarity)
    rarity = (type(rarity) == "string" and rarity ~= "" and rarity) or "epic"
    local pattern = ".warstormbot bot init=" .. rarity .. " %s"
    local n = 0
    local function consider(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        if UnitIsUnit(unit, "player") then return end
        local name = UnitName(unit)
        if not name then return end
        if ns.Persistence and ns.Persistence.IsPlayerName
           and ns.Persistence.IsPlayerName(name) then return end
        ns.Engine.Queue(string.format(pattern, name))  -- drains on the command channel
        n = n + 1
    end
    if ns.Engine.IsInRaid() then
        for i = 1, GetNumRaidMembers() do consider("raid" .. i) end
    else
        for i = 1, GetNumPartyMembers() do consider("party" .. i) end
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00ff00[Warden]|r Init: queued init=%s for %d bot(s).", rarity, n))
    if ns.LogF then ns.LogF("InitBots: queued init=%s for %d bots", rarity, n) end
    return n
end

-- ----------------------------------------------------------
-- Public API: CreateRaid - the one-click "Create" sequence.
-- remove all bots -> (beat) -> paced StartBuild (which auto-converts to raid,
-- auto-specs, applies AI strategies) -> on completion: per-bot init -> autogear
-- -> world buffs. Each finisher is spaced via ns.Engine.After so the server
-- processes them in order. Note: a full role-based re-sort is NOT part of this
-- chain yet (that's the separate sort feature); StartBuild still auto-moves the
-- player to their [P] slot. opts = { initRarity = "epic" | nil }.
-- ----------------------------------------------------------
function ns.Engine.CreateRaid(plan, opts)
    opts = opts or {}
    local s    = ns.Engine.state
    local db   = ns.Persistence.DB
    local chan = (db and db.commandChannel) or "SAY"

    -- Clear any half-finished prior run so hooks/timers don't overlap.
    ns.Engine.CancelTimers()
    s.onBuildComplete = nil

    DEFAULT_CHAT_FRAME:AddMessage(
        "|cff00ff00[Warden]|r Create: removing existing bots...")
    SendChatMessage(".warstormbot bot remove *", chan)

    -- Chain the gear/buff finishers onto build completion.
    s.onBuildComplete = function()
        local rarity = opts.initRarity
        if rarity then ns.Engine.InitBots(rarity) end
        -- autogear then world buffs, spaced (and after init has a head start).
        ns.Engine.After(rarity and 2.0 or 0.5, function()
            if ns.Broadcast then ns.Broadcast("autogear") end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Warden]|r Create: sent autogear.")
        end)
        ns.Engine.After(rarity and 4.0 or 2.5, function()
            if ns.Broadcast then ns.Broadcast("nc +worldbuff") end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Warden]|r Create: world buffs sent. Done.")
        end)
    end

    -- Give the remove-all a beat to process, then kick off the paced build.
    ns.Engine.After(1.5, function() ns.Engine.StartBuild(plan) end)
end

-- ==========================================================
-- Broadcast helpers.
--
-- TWO separate paths, because the channel differs:
--
--   ns.Engine.Queue(msg)  - goes into the SEND queue, drained at
--                           DB.interval, dispatched on DB.commandChannel
--                           (default "SAY"). Used for bot-spawn commands
--                           like `.warstormbot bot addclass paladin` which
--                           must go to SAY to be seen by the server parser.
--
--   ns.Broadcast(msg)     - immediate SendChatMessage(msg, ns.Channel()).
--                           ns.Channel() returns RAID or PARTY based on
--                           current group context. Used for HUD actions
--                           (summon / follow / stay / flee / aoe / burn /
--                           skull / @role) which bots listen for on the
--                           group channel, NOT SAY. Skipping the queue is
--                           fine here: user clicks are rare, group-channel
--                           anti-spam is loose, and queueing these behind
--                           a Build would delay a mid-pull "flee".
-- ==========================================================

function ns.Engine.WhisperAll(msg)
    if not msg or msg == "" then return end
    ns.Broadcast(msg)
end

-- "@role action" broadcast; mod-playerbots routes by role token.
function ns.Engine.WhisperRole(role, action)
    if not role or role == "" or not action or action == "" then return end
    ns.Broadcast(string.format("@%s %s", role, action))
end

function ns.Engine.ToggleAoE()
    local db = ns.Persistence.DB
    if not db then return end
    db.aoe = not (db.aoe == true)
    ns.Broadcast(db.aoe and "co +aoe,-assist,-focus,?"
                         or "co -aoe,+assist,+focus,?")
    return db.aoe
end

function ns.Engine.ToggleBurn()
    local db = ns.Persistence.DB
    if not db then return end
    db.burn = not (db.burn == true)
    ns.Broadcast(db.burn and "co +boost,?" or "co -boost,?")
    return db.burn
end

function ns.Engine.MarkAndAttack(mark)
    mark = mark or "skull"
    ns.Broadcast("rti " .. mark)
    ns.Broadcast("attack rti target")
end

-- Kept as an alias because Bindings.xml + RTSC bindings still reference it.
function ns.Engine.Enqueue(msg, channel, target)
    if not msg or msg == "" then return end
    ns.Engine.Queue(msg, channel, target)
end

-- Bloodlust / Heroism toggle. Shaman-only; priest/mage equivalents don't
-- exist at this patch. The bot doesn't recognize `nc +bloodlust` - the
-- playerbots strategy vocabulary has no bloodlust flag. The real lever is
-- the spell exclude list: `ss +<id>` blocks a spell, `ss -<id>` unblocks
-- it. So "BL ON"  = remove from exclude (shaman will cast); "BL OFF" =
-- add to exclude (shaman won't cast).
--
-- Spell IDs are canonical WoW: Bloodlust=2825 (Horde), Heroism=32182
-- (Alliance). We pick based on the player's faction so each shaman only
-- gets the one relevant command (private-server cross-faction cases are
-- rare enough to not warrant the 2x whisper spam).
local BLOODLUST_ID = 2825
local HEROISM_ID   = 32182

function ns.Engine.Bloodlust()
    local db = ns.Persistence.DB
    if not db then return 0 end
    db.bloodlust = not (db.bloodlust == true)

    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local spellId = (faction == "Alliance") and HEROISM_ID or BLOODLUST_ID
    local cmd     = db.bloodlust and ("ss -" .. spellId) or ("ss +" .. spellId)

    local n = ns.WhisperClass and ns.WhisperClass("SHAMAN", cmd) or 0
    if ns.UI.Master and ns.UI.Master.Frame() then
        local f = ns.UI.Master.Frame()
        if f.footer and f.footer.refreshBL then f.footer.refreshBL() end
    end
    return n, db.bloodlust
end
