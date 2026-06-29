-- =====================================================
-- Warden - UI_TabComp.lua
-- Direction IV rebuild, faithful to wireframes.html V4 + user ask for 5-man:
--
--   Header: [comp] [input] [presets ] [size ] ....... [ grid][ table]
--
--   ┌─ Raid grid ───────────────────────────────┐ ┌ Slot detail ─ (gold)
--   │ G1 - heals  G2 - flex  G3 - melee ...     │ │ Slot - G1 pos 1
--   │ [slot][slot][slot][slot][slot]            │ │ [class tag] [spec tag]
--   │ [slot][slot][slot][slot][slot] ...          │ │ blessings: ...
--   │                                            │ │ aura/resist: ...
--   │ ─ tray ─                                   │ │ [move][dup][remove]
--   │ DRAG ->  [chip][chip]...[chip]  shift - N    │ ├ Coverage ───────
--   └────────────────────────────────────────────┘ │ Kingsok Mightok ...
--                                                  ├ Summary ────────
--                                                  │ filled 24/25   Build
--                                                  │ [save][load][clear][cleanup]
--
--   Bottom strip: Re-Spec - Stop - Buffs - BL - ☐ Auto-spec
--
-- Sizes: 5 (1x5), 10 (2x5), 25 (5x5), 40 (8x5).
-- Saved comps stored as { rows=[{class,spec,count,opt1,opt2}], size=5|10|25|40 }.
-- =====================================================

local _, ns = ...
ns.UI.Tabs      = ns.UI.Tabs      or {}
ns.UI.Tabs.Comp = ns.UI.Tabs.Comp or {}

-- ----------------------------------------------------------
-- Small utils
-- ----------------------------------------------------------
local function Trim(s)
    s = s or ""
    s = string.gsub(s, "^%s+", ""); s = string.gsub(s, "%s+$", "")
    return s
end

-- splitSet + CLASS_ICON live in Data.lua now (ns.Data.SplitSet / ns.Data.CLASS_ICON).
local splitSet = ns.Data.SplitSet
local CLASS_ICON = ns.Data.CLASS_ICON

local function joinSet(set, orderedKeys)
    local parts = {}
    if orderedKeys then
        for _, k in ipairs(orderedKeys) do if set[k] then table.insert(parts, k) end end
    else
        for k in pairs(set) do table.insert(parts, k) end
        table.sort(parts)
    end
    return #parts > 0 and table.concat(parts, ",") or "(none)"
end

local function getSortedCompNames()
    local t = {}
    local db = ns.Persistence.DB
    if db and db.comps then
        for name in pairs(db.comps) do table.insert(t, name) end
    end
    table.sort(t)
    return t
end

-- Group saved comps by size. Prefers the stored `comp.size` field; falls
-- back to a trailing " 10" / " 25" in the name; else infers from the total
-- row count rounding up to 5 / 10 / 25 / 40. Returns a map
-- { [size] = sorted-name-list } plus the sorted list of sizes present.
local function inferCompSize(name, comp)
    if type(comp) == "table" and tonumber(comp.size) then
        return tonumber(comp.size)
    end
    local tail = type(name) == "string" and tonumber(name:match("(%d+)%s*$"))
    if tail == 5 or tail == 10 or tail == 25 or tail == 40 then return tail end
    local total = 0
    if type(comp) == "table" and type(comp.rows) == "table" then
        for _, r in ipairs(comp.rows) do total = total + (tonumber(r.count) or 1) end
    end
    if total <= 5 then return 5 end
    if total <= 10 then return 10 end
    if total <= 25 then return 25 end
    return 40
end

local function getCompNamesGroupedBySize()
    local groups, sizes = {}, {}
    local db = ns.Persistence.DB
    if not (db and db.comps) then return groups, sizes end
    for name, comp in pairs(db.comps) do
        local size = inferCompSize(name, comp)
        groups[size] = groups[size] or {}
        table.insert(groups[size], name)
    end
    for size in pairs(groups) do table.insert(sizes, size) end
    table.sort(sizes)
    for _, s in ipairs(sizes) do table.sort(groups[s]) end
    return groups, sizes
end

local colorClass = ns.ColorClass

-- ----------------------------------------------------------
-- Size layouts per PATCH_NOTES §8: columns = groups (G1..Gn across the top),
-- rows = positions within a group (5 positions per subgroup). Slot placement
-- is column-major so slot[1..5] are the 5 positions of G1, slot[6..10] are
-- G2, etc. Group semantics (G1 = heals, G5 = lust) live in `labels` per size.
--   5-man  -> 1 col, 5 rows
--  10-man  -> 2 cols, 5 rows
--  25-man  -> 5 cols, 5 rows
--  40-man  -> 8 cols, 5 rows
-- ----------------------------------------------------------
-- TASKS.md §2.1: stop hard-naming groups (the addon shouldn't dictate that
-- "G3 is melee"). Column headers are just G1..Gn now; current fill count
-- appears as a "G1 \194\183 5" meta so users still see group fullness.
local SIZE_LAYOUT = {
    [5]  = { cols = 1, rows = 5, labels = { "G1" } },
    [10] = { cols = 2, rows = 5, labels = { "G1", "G2" } },
    [25] = { cols = 5, rows = 5, labels = { "G1", "G2", "G3", "G4", "G5" } },
    [40] = { cols = 8, rows = 5, labels = { "G1", "G2", "G3", "G4",
                                            "G5", "G6", "G7", "G8" } },
}

-- ----------------------------------------------------------
-- Module state
-- ----------------------------------------------------------
local state = {
    pane       = nil,
    size       = 25,
    cols       = 5,
    rows       = 5,
    slots      = {},
    selected   = nil,
    nameBox    = nil,
    sizeSeg    = nil,
    presetDrop = nil,
    gridPanel  = nil,
    gridInner  = nil,
    chipPanel  = nil,
    sidebar    = {},
    slotFrames = {},
    chipFrames = {},
    -- FEATURE-01 Part B: drag-and-drop bookkeeping. Set by chip
    -- OnDragStart, consumed by slot OnMouseUp / chip OnDragStop.
    drag       = nil,   -- { classToken = "PALADIN" } | nil
    dragGhost  = nil,   -- floating class-icon that tracks the cursor
}

-- Forward declarations
local refreshAll, selectSlot, readPlan, loadFromRows
local buildSlotWidget, refreshSlotWidget
-- ensureDragGhost was declared as a lower-file `local function`, which in
-- Lua means closures captured BEFORE that line (like the slot OnDragStart
-- at the top of the file) see a nil. Forward-declare it here so the slot
-- and chip drag handlers can reference it without error.
local ensureDragGhost
local refreshCoverage, refreshSummary, refreshSlotDetail
local applySizeLayout

-- ----------------------------------------------------------
-- Size layout
-- ----------------------------------------------------------
applySizeLayout = function(size)
    local L = SIZE_LAYOUT[size] or SIZE_LAYOUT[25]
    state.size, state.cols, state.rows = size, L.cols, L.rows
    -- Resize slots array to match
    if #state.slots > size then
        for i = size + 1, #state.slots do state.slots[i] = nil end
    end
    for i = 1, size do state.slots[i] = state.slots[i] or nil end
    if state.selected and state.selected > size then state.selected = nil end
end

-- ----------------------------------------------------------
-- Slot widget (faithful to wireframe .slot)
-- BUG-04: the old layout centered classLbl / specLbl over the slot so the
-- top bar + any icon would visually bleed into the first characters. We
-- now draw a 14x14 class-circle icon in the top-left and left-anchor the
-- labels to the right of the icon so they can never sit underneath it.
-- FEATURE-02: a small "P" chip in the top-right flags a slot that
-- represents a human player (not a bot to summon).
-- FEATURE-01 Part A + B: placeholder is now a single "+" glyph (no more
-- "+ drop here" clipped text) and slots accept class chip drops.
-- ----------------------------------------------------------
buildSlotWidget = function(parent, index)
    local f = CreateFrame("Button", "WardenSlot" .. index, parent)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    -- Class-color bar across the top
    local bar = f:CreateTexture(nil, "OVERLAY")
    bar:SetTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetHeight(3)
    bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  3, -3)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    f.bar = bar

    -- Class circle icon (14x14, top-left). Cropped from
    -- UI-Classes-Circles atlas via CLASS_ICON.
    local iconTex = f:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(14, 14)
    iconTex:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
    iconTex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    f.iconTex = iconTex

    -- Class label (class-colored, left-anchored to the right of the icon)
    local classLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classLbl:SetPoint("LEFT", iconTex, "RIGHT", 4, 4)
    classLbl:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    classLbl:SetJustifyH("LEFT")
    classLbl:SetWordWrap(false)
    classLbl:SetDrawLayer("OVERLAY", 2)
    f.classLbl = classLbl

    -- Spec subtitle (muted, below class label)
    local specLbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    specLbl:SetPoint("LEFT", iconTex, "RIGHT", 4, -8)
    specLbl:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    specLbl:SetJustifyH("LEFT")
    specLbl:SetWordWrap(false)
    specLbl:SetDrawLayer("OVERLAY", 2)
    f.specLbl = specLbl

    -- FEATURE-02: per-slot P badge (human-player marker). 14x14 in the
    -- top-right corner, hidden unless slot.isPlayer.
    local pBadge = CreateFrame("Frame", nil, f)
    pBadge:SetSize(14, 14)
    pBadge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -6)
    pBadge:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pBadge:SetBackdropColor(0.10, 0.06, 0.02, 1)
    pBadge:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)
    pBadge:Hide()
    local pText = pBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pText:SetPoint("CENTER", pBadge, "CENTER", 0, 0)
    pText:SetText("P")
    pText:SetTextColor(1, 0.82, 0, 1)
    pBadge.text = pText
    f.pBadge = pBadge

    -- Short "+" placeholder (shown when empty).
    local emptyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    emptyLbl:SetPoint("CENTER", f, "CENTER", 0, 0)
    emptyLbl:SetText("+")
    emptyLbl:SetTextColor(0.45, 0.38, 0.28, 1)
    emptyLbl:SetWordWrap(false)
    f.emptyLbl = emptyLbl

    f.index = index
    f.__wardenSlotIndex = index  -- drag-drop lookup tag

    -- FEATURE-01 Part B: drag-drop onto/out of this slot.
    --   * Chip dragged + released over this slot -> OnMouseUp assigns
    --     (no srcIdx => new assignment).
    --   * Slot dragged + released over another slot -> OnMouseUp swaps.
    --   * Slot dragged + released over empty area -> slot OnDragStop
    --     unassigns the source (see below).
    f:RegisterForDrag("LeftButton")

    f._justDropped = false
    f:SetScript("OnMouseUp", function(self, button)
        if state.drag and state.drag.classToken and button == "LeftButton" then
            local srcIdx = state.drag.srcIdx
            if srcIdx and srcIdx == self.index then
                -- Released on the same slot we started the drag from; treat
                -- this as a no-op (not a move).
                state.drag = nil
                if state.dragGhost then state.dragGhost:Hide() end
                state.highlightDropTargets(false)
                refreshAll()
            else
                state.assignDragToSlot(self.index)
            end
            self._justDropped = true
        end
    end)

    -- FEATURE-01 Part B step 4: only filled slots can be dragged (you can't
    -- drag an empty placeholder). OnDragStart captures the source index +
    -- class so subsequent moves/unassigns know what to do.
    f:SetScript("OnDragStart", function(self)
        local slot = state.slots[self.index]
        if not slot or not slot.classToken then return end
        state.drag = { classToken = slot.classToken, srcIdx = self.index }
        local g = ensureDragGhost(self)
        local tc = CLASS_ICON[slot.classToken]
        if tc and g.icon then g.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        g:Show()
        state.highlightDropTargets(true)
    end)

    -- OnDragStop on slot fires when the user releases the mouse after a
    -- slot-drag. WoW 3.3.5a dispatch order is: OnDragStop on the SOURCE
    -- fires BEFORE OnMouseUp on the destination, so we can't rely on the
    -- target's OnMouseUp to have already consumed state.drag - that was
    -- the root cause of "every drag becomes a drag-out". Ask the cursor
    -- directly via GetMouseFocus() instead: if it's over another slot,
    -- this is a move/swap, otherwise it's a real drag-out.
    f:SetScript("OnDragStop", function(self)
        if not state.drag then
            if state.dragGhost then state.dragGhost:Hide() end
            state.highlightDropTargets(false)
            return
        end

        local focus  = GetMouseFocus and GetMouseFocus()
        local dstIdx = focus and focus.__wardenSlotIndex
        local srcIdx = state.drag.srcIdx

        if dstIdx and dstIdx ~= srcIdx then
            -- Cursor was over a real slot -> let the shared helper do the
            -- swap (for slot drags) or the new assignment (for chip drags).
            state.assignDragToSlot(dstIdx)
        elseif srcIdx == self.index then
            -- Slot drag released on empty canvas / same slot -> unassign.
            state.slots[self.index] = nil
            if state.selected == self.index then state.selected = nil end
            ns.MsgInfo(string.format("Removed slot %d via drag-out.", self.index))
            state.drag = nil
            refreshAll()
        else
            -- Defensive: not our drag (some other slot is the source) and
            -- we didn't land on a valid target - just clear.
            state.drag = nil
        end

        if state.dragGhost then state.dragGhost:Hide() end
        state.highlightDropTargets(false)
    end)

    f:SetScript("OnClick", function(self, button)
        if self._justDropped then
            self._justDropped = false
            return
        end
        if button == "RightButton" then
            state.slots[self.index] = nil
            if state.selected == self.index then state.selected = nil end
            refreshAll()
        else
            selectSlot(self.index)
        end
    end)
    f:SetScript("OnEnter", function(self)
        if state.drag and state.drag.classToken then
            -- Emphasize the hovered drop target (brighter gold than the
            -- global empty-slot highlight set by highlightDropTargets).
            self:SetBackdropBorderColor(1, 1, 0.2, 1)
        elseif state.slots[self.index] then
            self:SetBackdropColor(0.20, 0.15, 0.08, 1)
        else
            self:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)
        end
        -- BUG-04 step 4: in compact (size 40) grid the text is truncated.
        -- Tooltip shows the full class/spec on hover so users can still
        -- read what's in a cell.
        local slot = state.slots[self.index]
        if slot and state.size == 40 then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(
                colorClass(slot.classToken,
                    ns.Data.CLASS_LABEL[slot.classToken] or slot.classToken),
                1, 1, 1)
            GameTooltip:AddLine(colorClass(slot.classToken, slot.spec or "-"),
                0.9, 0.9, 0.9)
            if slot.isPlayer then
                GameTooltip:AddLine("|cffffd100[PLAYER slot]|r", 1, 0.82, 0)
            end
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        refreshSlotWidget(self, state.slots[self.index])
        GameTooltip:Hide()
    end)

    return f
end

refreshSlotWidget = function(f, slot)
    local isSelected = (state.selected == f.index)
    if slot then
        local c  = RAID_CLASS_COLORS and RAID_CLASS_COLORS[slot.classToken]
        local tc = CLASS_ICON[slot.classToken]
        f:SetBackdropColor(0.10, 0.08, 0.05, 1)
        if isSelected then
            f:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            f:SetBackdropBorderColor(0.16, 0.12, 0.08, 1)
        end
        if c then
            f.bar:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, 1)
        else
            f.bar:SetVertexColor(0.5, 0.5, 0.5, 1)
        end
        f.bar:Show()
        if tc then
            f.iconTex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            f.iconTex:Show()
        else
            f.iconTex:Hide()
        end
        f.classLbl:SetText(colorClass(slot.classToken, ns.Data.CLASS_LABEL[slot.classToken] or slot.classToken))
        f.specLbl:SetText(slot.spec or "?")
        f.emptyLbl:Hide()
        f.classLbl:Show(); f.specLbl:Show()
        if slot.isPlayer then f.pBadge:Show() else f.pBadge:Hide() end
    else
        f:SetBackdropColor(0.08, 0.06, 0.04, 0.8)
        if isSelected then
            f:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            -- Dashed-border effect: use a slightly lighter color than filled slots
            f:SetBackdropBorderColor(0.28, 0.22, 0.15, 1)
        end
        f.bar:Hide()
        f.iconTex:Hide()
        f.classLbl:Hide(); f.specLbl:Hide()
        f.pBadge:Hide()
        f.emptyLbl:Show()
    end
end

-- ----------------------------------------------------------
-- Grid layout (column headers + slots)
-- ----------------------------------------------------------
local function layoutGrid()
    local inner = state.gridInner
    if not inner then return end
    local cW, cH = inner:GetWidth(), inner:GetHeight()
    local cols, rows = state.cols, state.rows
    local gap        = 4

    -- Column header labels (TOP bar, one per group). Spec §8.
    local labels = (SIZE_LAYOUT[state.size] or SIZE_LAYOUT[25]).labels or {}
    inner._colLbls = inner._colLbls or {}
    -- Hide any stray row labels from the short-lived left-gutter layout
    if inner._rowLbls then
        for _, lbl in pairs(inner._rowLbls) do lbl:Hide() end
    end

    local headerH = 16
    local slotW   = math.floor((cW - (cols + 1) * gap) / cols)
    local slotH   = math.floor((cH - headerH - (rows + 1) * gap) / rows)
    if slotH < 32 then slotH = 32 end

    -- Count filled slots per group so we can render "G1 \194\183 5" meta.
    local filledPerGroup = {}
    for i = 1, state.size do
        if state.slots[i] then
            local g = math.floor((i - 1) / rows) + 1
            filledPerGroup[g] = (filledPerGroup[g] or 0) + 1
        end
    end

    for c = 1, 8 do
        local lbl = inner._colLbls[c]
        if not lbl then
            lbl = inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            lbl:SetTextColor(0.72, 0.58, 0.21, 1)
            lbl:SetJustifyH("CENTER")
            inner._colLbls[c] = lbl
        end
        if c <= cols then
            lbl:ClearAllPoints()
            lbl:SetPoint("TOP", inner, "TOPLEFT",
                gap + (c - 1) * (slotW + gap) + slotW / 2, -2)
            local base = labels[c] or ("G" .. c)
            local n    = filledPerGroup[c] or 0
            lbl:SetText(base .. " \194\183 " .. n)
            lbl:Show()
        else
            lbl:Hide()
        end
    end

    -- Column-major placement: slot 1..rows fill G1 top-to-bottom, then G2.
    -- This matches the spec and the WoW raid-frame layout used by players.
    for i = 1, 40 do
        local f = state.slotFrames[i]
        if i <= state.size then
            if not f then
                f = buildSlotWidget(inner, i)
                state.slotFrames[i] = f
            end
            local group  = math.floor((i - 1) / rows)   -- 0..cols-1
            local posInG = (i - 1) % rows               -- 0..rows-1
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", inner, "TOPLEFT",
                gap + group * (slotW + gap),
                -(headerH + gap + posInG * (slotH + gap)))
            f:SetSize(slotW, slotH)
            f:Show()
            refreshSlotWidget(f, state.slots[i])
        elseif f then
            f:Hide()
        end
    end
end

-- ----------------------------------------------------------
-- Chip widgets (tray)
-- ----------------------------------------------------------
local function defaultSpecFor(classToken)
    return (ns.Data.DEFAULT_SPEC_PVE and ns.Data.DEFAULT_SPEC_PVE[classToken])
        or (ns.Data.CLASS_SPECS[classToken] and ns.Data.CLASS_SPECS[classToken][1])
        or ""
end

local function addClassToNextSlot(classToken, count)
    count = count or 1
    local added = 0
    for i = 1, state.size do
        if not state.slots[i] then
            state.slots[i] = {
                classToken = classToken,
                spec       = defaultSpecFor(classToken),
                opt1       = "(none)", opt2 = "(none)",
                isPlayer   = false,
            }
            added = added + 1
            if added >= count then break end
        end
    end
    if added < count then
        ns.MsgWarn(string.format("Only %d slot(s) free - added %d of %d.",
            added, added, count))
    elseif added > 0 then
        ns.MsgInfo(string.format("Added %d x %s.", added,
            ns.Data.CLASS_LABEL[classToken] or classToken))
    end
    refreshAll()
end

StaticPopupDialogs["WARDEN_CHIP_COUNT"] = {
    text         = "How many %s to add?",
    button1      = OKAY, button2 = CANCEL,
    hasEditBox   = 1, maxLetters = 2,
    OnShow       = function(self) self.editBox:SetText("5"); self.editBox:HighlightText() end,
    OnAccept     = function(self, data)
        local n = tonumber(self.editBox:GetText()) or 1
        if data and data.classToken then addClassToNextSlot(data.classToken, n) end
    end,
    EditBoxOnEnterPressed = function(self, data)
        local n = tonumber(self:GetText()) or 1
        if data and data.classToken then addClassToNextSlot(data.classToken, n) end
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
    enterClicksFirstButton = 1,
}

-- ----------------------------------------------------------
-- FEATURE-01 Part B: drag-and-drop state + ghost frame.
-- ----------------------------------------------------------
ensureDragGhost = function(parent)
    if state.dragGhost then return state.dragGhost end
    local g = CreateFrame("Frame", "WardenDragGhost", UIParent)
    g:SetSize(22, 22)
    g:SetFrameStrata("TOOLTIP")
    g:Hide()
    local tex = g:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(g)
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    g.icon = tex
    g:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        local scale = UIParent:GetEffectiveScale()
        local x, y  = GetCursorPosition()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale - 12)
    end)
    state.dragGhost = g
    return g
end

-- Highlight all empty drop targets during an active drag (FEATURE-01
-- Part B step 3). Called by chip/slot OnDragStart with `on=true` and
-- OnDragStop with `on=false`. `on=false` restores each slot's normal
-- border via refreshSlotWidget.
state.highlightDropTargets = function(on)
    for _, slotF in pairs(state.slotFrames) do
        if slotF and slotF.index and slotF:IsShown() then
            if on and not state.slots[slotF.index] then
                slotF:SetBackdropBorderColor(0.72, 0.58, 0.21, 1) -- gold-dim glow
            else
                refreshSlotWidget(slotF, state.slots[slotF.index])
            end
        end
    end
end

-- Assign the currently-dragged class to a slot index. Handles two paths:
--   1. Chip-drag: state.drag.srcIdx is nil -> new assignment.
--   2. Slot-drag: state.drag.srcIdx is set -> swap source and destination
--      so the user can move a filled class to a different slot.
state.assignDragToSlot = function(index)
    if not state.drag or not state.drag.classToken then return end
    local srcIdx = state.drag.srcIdx
    local ct     = state.drag.classToken

    if srcIdx and srcIdx ~= index then
        -- Swap the two slots so the user can drag a filled class onto
        -- another filled or empty slot without losing the existing one.
        local srcSlot = state.slots[srcIdx]
        local dstSlot = state.slots[index]
        state.slots[index]  = srcSlot
        state.slots[srcIdx] = dstSlot
        state.selected      = index
        ns.MsgInfo(string.format("Moved %s from slot %d to slot %d.",
            ns.Data.CLASS_LABEL[ct] or ct, srcIdx, index))
    else
        -- New assignment (chip drop onto slot; overwrites if filled).
        state.slots[index] = {
            classToken = ct,
            spec       = defaultSpecFor(ct),
            opt1       = "(none)", opt2 = "(none)",
            isPlayer   = false,
        }
        ns.MsgInfo(string.format("Dropped %s into slot %d.",
            ns.Data.CLASS_LABEL[ct] or ct, index))
    end

    state.drag = nil
    if state.dragGhost then state.dragGhost:Hide() end
    state.highlightDropTargets(false)
    refreshAll()
end

local function buildChipWidget(parent, classToken)
    local f = CreateFrame("Button", "WardenChip_" .. classToken, parent)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.12, 0.10, 0.06, 0.95)
    f:SetBackdropBorderColor(0.16, 0.12, 0.08, 1)
    f:SetSize(70, 22)

    -- Class color swatch (8x8 circle, but WoW can't do circles without a texture;
    -- use a small square as the swatch approximation).
    -- P1 review: chip tray was too saturated and competed with the grid.
    -- Desaturate both the swatch and the label ~30% by mixing toward gray.
    local function desat(v) return v * 0.70 + 0.20 end
    local sw = f:CreateTexture(nil, "OVERLAY")
    sw:SetTexture("Interface\\Buttons\\WHITE8x8")
    sw:SetSize(8, 8)
    sw:SetPoint("LEFT", f, "LEFT", 6, 0)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then sw:SetVertexColor(desat(c.r or 1), desat(c.g or 1), desat(c.b or 1), 1) end

    -- Build label text color against a desaturated class color so the chip
    -- reads as "available palette" instead of "active raid member".
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    local className = ns.Data.CLASS_LABEL[classToken] or classToken
    if c then
        lbl:SetText(string.format("|cff%02x%02x%02x%s|r",
            math.floor(desat(c.r or 1) * 255 + 0.5),
            math.floor(desat(c.g or 1) * 255 + 0.5),
            math.floor(desat(c.b or 1) * 255 + 0.5),
            className))
    else
        lbl:SetText(className)
    end

    f:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            local dialog = StaticPopup_Show("WARDEN_CHIP_COUNT",
                ns.Data.CLASS_LABEL[classToken] or classToken)
            if dialog then dialog.data = { classToken = classToken } end
        else
            addClassToNextSlot(classToken, 1)
        end
    end)
    -- FEATURE-01 Part B: OnDragStart flips state.drag + shows a ghost icon
    -- tracking the cursor and lights up all empty slots in gold
    -- (highlightDropTargets). OnDragStop clears state.drag and restores
    -- borders; if OnMouseUp on a slot already consumed state.drag, no
    -- further work is needed beyond the cleanup.
    f:SetScript("OnDragStart", function(self)
        state.drag = { classToken = classToken }   -- no srcIdx -> new assignment
        local g = ensureDragGhost(self)
        local tc = CLASS_ICON[classToken]
        if tc and g.icon then g.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        g:Show()
        state.highlightDropTargets(true)
    end)
    f:SetScript("OnDragStop", function(self)
        -- Same event-order gotcha as the slot OnDragStop: on WoW 3.3.5a
        -- the source's OnDragStop fires before the destination's
        -- OnMouseUp, so we can't assume the target already consumed the
        -- drag. Peek at the cursor focus and route the drop ourselves.
        if state.drag then
            local focus  = GetMouseFocus and GetMouseFocus()
            local dstIdx = focus and focus.__wardenSlotIndex
            if dstIdx then
                state.assignDragToSlot(dstIdx)
            else
                state.drag = nil
            end
        end
        if state.dragGhost then state.dragGhost:Hide() end
        state.highlightDropTargets(false)
    end)
    f:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.22, 0.17, 0.10, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.Data.CLASS_LABEL[classToken] or classToken, 1, 1, 1)
        GameTooltip:AddLine("Click: add 1 to next empty slot", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Shift-click: prompt for N copies", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag onto a slot: drop class there (overwrites)", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.10, 0.06, 0.95)
        GameTooltip:Hide()
    end)
    return f
end

-- ----------------------------------------------------------
-- Plan I/O
-- ----------------------------------------------------------
readPlan = function()
    -- BUG-07: explicit numeric loop so a nil hole in state.slots doesn't
    -- truncate the plan (ipairs stops at first nil). FEATURE-02: carry
    -- isPlayer so Engine.buildQueues can skip human-player slots.
    local plan = {}
    for i = 1, state.size do
        local slot = state.slots[i]
        if slot and slot.classToken then
            table.insert(plan, {
                classToken = slot.classToken,
                spec       = slot.spec,
                count      = 1,
                opt1       = slot.opt1 or "(none)",
                opt2       = slot.opt2 or "(none)",
                isPlayer   = slot.isPlayer and true or false,
            })
        end
    end
    -- Player auto-move target group: if any slot is flagged [P], compute
    -- which subgroup it lives in (column-major layout; `state.rows` slots
    -- per column = per subgroup). Engine.StartBuild reads this and runs
    -- SetRaidSubgroup AFTER any ConvertToRaid, so the move also works
    -- when the Build converts from party->raid (the UI-side move below
    -- can only see a raid that already exists).
    local rows = state.rows or 5
    for i = 1, state.size do
        local slot = state.slots[i]
        if slot and slot.isPlayer then
            plan.playerTargetGroup = math.floor((i - 1) / rows) + 1
            break
        end
    end
    return plan
end

-- ----------------------------------------------------------
-- FEATURE-03: full comp export/import. The old WRDN1 format lost the
-- comp name, the isPlayer flag, and slot positions (any gap in the grid
-- collapsed to a contiguous list). WRDN2 encodes all of that so a paste
-- round-trip reproduces the grid 1:1:
--     WRDN2:<size>|<name>|<idx>=<CLASS>:<spec>:<opt1>:<opt2>:<p>;...
-- WRDN1 imports still work (backward compat); they are packed into a
-- contiguous 1..N sequence and `isPlayer` defaults to false.
-- ----------------------------------------------------------
local function exportCompString()
    local size = state.size or 25
    local name = state.nameBox and (state.nameBox:GetText() or "") or ""
    -- Strip separators that would break the on-the-wire grammar.
    name = (name or ""):gsub("|", ""):gsub(";", "")
    local parts = { "WRDN2:" .. size .. "|" .. name .. "|" }
    local first = true
    for i = 1, size do
        local slot = state.slots[i]
        if slot and slot.classToken then
            local o1 = slot.opt1 or "(none)"
            local o2 = slot.opt2 or "(none)"
            local pl = slot.isPlayer and "1" or "0"
            local tok = string.format("%d=%s:%s:%s:%s:%s",
                i, slot.classToken, slot.spec or "", o1, o2, pl)
            parts[#parts + 1] = (first and "" or ";") .. tok
            first = false
        end
    end
    return table.concat(parts)
end

-- Returns: slotsByIdx, size, droppedCount, compName     (success)
--          nil, errorReason                              (failure)
-- slotsByIdx is a sparse table [i] = { classToken, spec, opt1, opt2, isPlayer }.
local function importCompString(str)
    if type(str) ~= "string" or str == "" then
        return nil, "Empty string."
    end

    -- WoW's chat/edit boxes treat `|` as a formatting escape and sometimes
    -- double it on paste (`|` -> `||`). Normalize before parsing so a
    -- user who round-trips through chat still gets a valid import.
    str = str:gsub("||", "|")

    local function validClass(c) return c and ns.Data.CLASS_SPECS[c] end
    local function validSpec(c, s)
        for _, sp in ipairs(ns.Data.CLASS_SPECS[c] or {}) do
            if sp == s then return true end
        end
        return false
    end
    local VALID_SIZE = { [5] = true, [10] = true, [25] = true, [40] = true }

    -- Try WRDN2 first (name + positions + isPlayer).
    local v2 = str:match("^WRDN2:")
    if v2 then
        -- Canonical: WRDN2:<size>|<name>|<body>
        local size, name, body = str:match("^WRDN2:(%d+)|([^|]*)|(.*)$")
        if not size then
            -- Forgiving fallback: chat edit boxes sometimes swallow a pipe.
            -- Extract leading digits as size, treat the rest of the first
            -- segment as a garbled name, and take everything after the one
            -- remaining pipe as the slot body.
            local sNum, rest, b2 = str:match("^WRDN2:(%d+)([^|]*)|(.*)$")
            if sNum then size, name, body = sNum, rest or "", b2 or "" end
        end
        if not size then return nil, "Malformed WRDN2 header." end
        size = tonumber(size)
        if not VALID_SIZE[size] then
            return nil, "Invalid size: " .. tostring(size)
        end
        local byIdx, dropped = {}, 0
        if body and body ~= "" then
            for tok in string.gmatch(body, "[^;]+") do
                local idxStr, payload = tok:match("^(%d+)=(.*)$")
                if not idxStr then
                    return nil, "Bad token: " .. tok
                end
                local idx = tonumber(idxStr)
                local c, s, o1, o2, pl = strsplit(":", payload)
                if not validClass(c) then
                    return nil, "Unknown class token: " .. tostring(c)
                end
                if not validSpec(c, s) then
                    return nil, "Unknown spec for " .. c .. ": " .. tostring(s)
                end
                if idx and idx >= 1 and idx <= size then
                    byIdx[idx] = {
                        classToken = c, spec = s,
                        opt1 = (o1 ~= nil and o1 ~= "") and o1 or "(none)",
                        opt2 = (o2 ~= nil and o2 ~= "") and o2 or "(none)",
                        isPlayer = (pl == "1"),
                    }
                else
                    dropped = dropped + 1
                end
            end
        end
        return byIdx, size, dropped, (name ~= "" and name) or nil
    end

    -- WRDN1 backward compatibility (no name, no positions, no isPlayer).
    local v1 = str:match("^WRDN1:")
    if v1 then
        local size, body = str:match("^WRDN1:(%d+)|(.*)$")
        if not size then return nil, "Malformed WRDN1 header." end
        size = tonumber(size)
        if not VALID_SIZE[size] then
            return nil, "Invalid size: " .. tostring(size)
        end
        local byIdx, dropped, seq = {}, 0, 0
        if body and body ~= "" then
            for tok in string.gmatch(body, "[^;]+") do
                local c, s, o1, o2 = strsplit(":", tok)
                if not validClass(c) then
                    return nil, "Unknown class token: " .. tostring(c)
                end
                if not validSpec(c, s) then
                    return nil, "Unknown spec for " .. c .. ": " .. tostring(s)
                end
                seq = seq + 1
                if seq <= size then
                    byIdx[seq] = {
                        classToken = c, spec = s,
                        opt1 = (o1 ~= nil and o1 ~= "") and o1 or "(none)",
                        opt2 = (o2 ~= nil and o2 ~= "") and o2 or "(none)",
                        isPlayer = false,
                    }
                else
                    dropped = dropped + 1
                end
            end
        end
        return byIdx, size, dropped, nil
    end

    return nil, "Unknown format (expected WRDN1: or WRDN2:)."
end

-- Forward-decl the indexed loader so this popup OnAccept can reference it.
local loadFromSlotsByIdx

StaticPopupDialogs["WARDEN_COMP_IMPORT"] = {
    text           = "Paste comp string:",
    button1        = ACCEPT, button2 = CANCEL,
    hasEditBox     = true, editBoxWidth = 350,
    OnShow         = function(self) if self.editBox then self.editBox:SetFocus() end end,
    OnAccept       = function(self)
        local s = self.editBox and self.editBox:GetText() or ""
        local byIdx, sizeOrErr, dropped, name = importCompString(s)
        if not byIdx then
            ns.MsgErr("Import failed: " .. tostring(sizeOrErr))
            return
        end
        loadFromSlotsByIdx(byIdx, sizeOrErr)
        if name and state.nameBox then state.nameBox:SetText(name) end
        state.selected = nil
        refreshAll()
        local filled = 0
        for i = 1, sizeOrErr do if byIdx[i] then filled = filled + 1 end end
        ns.MsgInfo(string.format("Imported %d slot(s), size %d%s.%s",
            filled, sizeOrErr,
            (name and (" ('" .. name .. "')")) or "",
            (dropped or 0) > 0 and (" Dropped " .. dropped .. " overflow.") or ""))
    end,
    EditBoxOnEnterPressed  = function(self) self:GetParent().button1:Click() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["WARDEN_COMP_EXPORT"] = {
    text           = "Copy comp string (Ctrl+C):",
    button1        = CLOSE,
    hasEditBox     = true, editBoxWidth = 350,
    OnShow         = function(self)
        self.editBox:SetText(self.data or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Saved-comp delete confirmation. `data` carries the comp name; the OnAccept
-- callback is injected at click-time so the popup doesn't need upvalues into
-- the refreshPresetDropdown closure.
StaticPopupDialogs["WARDEN_COMP_DELETE"] = {
    text           = "Delete saved comp '%s'? This cannot be undone.",
    button1        = YES, button2 = NO,
    OnAccept       = function(self) if self.onConfirm then self.onConfirm(self.data) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Rename a saved comp. `data` carries the OLD name (also fills the %s in the
-- prompt); the new name comes from the edit box; onConfirm is injected at
-- click-time so the popup needs no upvalues into the BuildInto closure.
StaticPopupDialogs["WARDEN_COMP_RENAME"] = {
    text                   = "Rename comp '%s' to:",
    button1                = ACCEPT, button2 = CANCEL,
    hasEditBox             = true, editBoxWidth = 220,
    OnShow                 = function(self) if self.editBox then self.editBox:SetFocus() end end,
    OnAccept               = function(self)
        local newName = self.editBox and self.editBox:GetText() or ""
        if self.onConfirm then self.onConfirm(self.data, newName) end
    end,
    EditBoxOnEnterPressed  = function(self) self:GetParent().button1:Click() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

loadFromRows = function(rows, size)
    wipe(state.slots)
    if type(rows) ~= "table" then return end
    local total = 0
    for _, r in ipairs(rows) do total = total + (tonumber(r.count) or 1) end
    local newSize = size
    if not newSize then
        if total <= 5 then newSize = 5
        elseif total <= 10 then newSize = 10
        elseif total <= 25 then newSize = 25
        else newSize = 40 end
    end
    applySizeLayout(newSize)
    if state.sizeSeg then state.sizeSeg:SetActive(state.size) end
    for _, r in ipairs(rows) do
        local count = tonumber(r.count) or 1
        for _ = 1, count do
            if #state.slots >= state.size then break end
            table.insert(state.slots, {
                classToken = r.classToken,
                spec       = r.spec,
                opt1       = r.opt1 or "(none)",
                opt2       = r.opt2 or "(none)",
                isPlayer   = r.isPlayer and true or false,
            })
        end
    end
end

-- FEATURE-03: positional loader. Used for WRDN2 imports and for saved
-- comps that have a `slotsByIdx` side table. Preserves slot positions,
-- so a gap in the middle of the grid round-trips correctly.
loadFromSlotsByIdx = function(byIdx, size)
    wipe(state.slots)
    if type(byIdx) ~= "table" then return end
    applySizeLayout(size or 25)
    if state.sizeSeg then state.sizeSeg:SetActive(state.size) end
    for i = 1, state.size do
        local r = byIdx[i]
        if r then
            state.slots[i] = {
                classToken = r.classToken,
                spec       = r.spec,
                opt1       = r.opt1 or "(none)",
                opt2       = r.opt2 or "(none)",
                isPlayer   = r.isPlayer and true or false,
            }
        end
    end
end

-- Prefer positional data when present; fall back to legacy rows.
local function loadComp(comp)
    if type(comp) ~= "table" then return end
    if type(comp.slotsByIdx) == "table" then
        loadFromSlotsByIdx(comp.slotsByIdx, comp.size)
    else
        loadFromRows(comp.rows, comp.size)
    end
end

-- ----------------------------------------------------------
-- Sidebar - slot detail (gold border)
-- ----------------------------------------------------------
local function buildSlotDetail(parent)
    local d = {}

    -- Header title (overrides panel header text when a slot is selected)
    d.titleLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.titleLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -2)
    d.titleLbl:SetText("select a slot")
    d.titleLbl:SetTextColor(0.61, 0.55, 0.40)

    -- Tag line: [class tag] [spec tag]
    d.classTag = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.classTag:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -16)

    d.specTag = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.specTag:SetPoint("LEFT", d.classTag, "RIGHT", 8, 0)

    -- All four slot-detail dropdowns are the SAME width (130) and stacked
    -- vertically with equal spacing so expanded menus no longer clip labels
    -- below. Anchor offsets no longer include the old -8 (which compensated
    -- for the now-hidden Blizzard chrome).
    local DROP_W = 130
    local DROP_GAP = 6

    -- Class label + dropdown. BUG-05 UX clarification: the dropdown is for
    -- CHANGING the class of a filled slot, not just viewing it. Label it
    -- accordingly so the purpose is obvious.
    d.classLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.classLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -32)
    d.classLbl:SetText("CHANGE CLASS")
    d.classLbl:SetTextColor(ns.Tokens.gold_dim[1], ns.Tokens.gold_dim[2],
                            ns.Tokens.gold_dim[3], 1)
    d.classDrop = CreateFrame("Frame", "WardenDetailClass", parent, "UIDropDownMenuTemplate")
    d.classDrop:SetPoint("TOPLEFT", d.classLbl, "BOTTOMLEFT", -16, -2)
    ns.UI.Dropdown.style(d.classDrop, DROP_W)

    d.specLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.specLbl:SetPoint("TOPLEFT", d.classDrop, "BOTTOMLEFT", 16, -DROP_GAP)
    d.specLbl:SetText("SPEC")
    d.specLbl:SetTextColor(ns.Tokens.gold_dim[1], ns.Tokens.gold_dim[2],
                            ns.Tokens.gold_dim[3], 1)
    d.specDrop = CreateFrame("Frame", "WardenDetailSpec", parent, "UIDropDownMenuTemplate")
    d.specDrop:SetPoint("TOPLEFT", d.specLbl, "BOTTOMLEFT", -16, -2)
    ns.UI.Dropdown.style(d.specDrop, DROP_W)

    d.blessLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.blessLbl:SetPoint("TOPLEFT", d.specDrop, "BOTTOMLEFT", 16, -DROP_GAP)
    d.blessLbl:SetText("BLESSING / TOTEM")
    d.blessLbl:SetTextColor(ns.Tokens.gold_dim[1], ns.Tokens.gold_dim[2],
                             ns.Tokens.gold_dim[3], 1)
    d.opt1Drop = CreateFrame("Frame", "WardenDetailOpt1", parent, "UIDropDownMenuTemplate")
    d.opt1Drop:SetPoint("TOPLEFT", d.blessLbl, "BOTTOMLEFT", -16, -2)
    ns.UI.Dropdown.style(d.opt1Drop, DROP_W)

    d.auraLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.auraLbl:SetPoint("TOPLEFT", d.opt1Drop, "BOTTOMLEFT", 16, -DROP_GAP)
    d.auraLbl:SetText("AURA / RESIST")
    d.auraLbl:SetTextColor(ns.Tokens.gold_dim[1], ns.Tokens.gold_dim[2],
                            ns.Tokens.gold_dim[3], 1)
    d.opt2Drop = CreateFrame("Frame", "WardenDetailOpt2", parent, "UIDropDownMenuTemplate")
    d.opt2Drop:SetPoint("TOPLEFT", d.auraLbl, "BOTTOMLEFT", -16, -2)
    ns.UI.Dropdown.style(d.opt2Drop, DROP_W)

    -- Move / Duplicate / Remove / [P] row. Widths tuned to total 212px (44 +
    -- 4 + 60 + 4 + 48 + 4 + 48) so the [P] button is not clipped by the side
    -- panel ScrollFrame's right edge (scroll child is ~224 wide).
    d.moveBtn = ns.UI.Button.stone(parent, "move", 44, 20)
    d.moveBtn:SetPoint("TOPLEFT", d.opt2Drop, "BOTTOMLEFT", 16, -8)
    d.moveBtn:SetScript("OnClick", function()
        if not state.selected or not state.slots[state.selected] then return end
        -- Move = shift slot to next empty position at end
        local src = state.selected
        local s   = state.slots[src]
        state.slots[src] = nil
        for i = 1, state.size do
            if not state.slots[i] then
                state.slots[i] = s
                state.selected = i
                break
            end
        end
        refreshAll()
    end)

    d.dupBtn = ns.UI.Button.stone(parent, "duplicate", 60, 20)
    d.dupBtn:SetPoint("LEFT", d.moveBtn, "RIGHT", 4, 0)  -- 44+4+60 = 108
    d.dupBtn:SetScript("OnClick", function()
        if not state.selected or not state.slots[state.selected] then return end
        local s = state.slots[state.selected]
        for i = 1, state.size do
            if not state.slots[i] then
                state.slots[i] = {
                    classToken = s.classToken, spec = s.spec,
                    opt1 = s.opt1, opt2 = s.opt2,
                    isPlayer = s.isPlayer and true or false,
                }
                break
            end
        end
        refreshAll()
    end)

    d.removeBtn = ns.UI.Button.warn(parent, "remove", 48, 20)
    d.removeBtn:SetPoint("LEFT", d.dupBtn, "RIGHT", 4, 0)  -- 108+4+48 = 160
    d.removeBtn:SetScript("OnClick", function()
        if state.selected then
            state.slots[state.selected] = nil
            state.selected = nil
            refreshAll()
        end
    end)

    -- FEATURE-02: toggle the slot's isPlayer flag. Label flips between
    -- "[P] on" (gold) and "[P] off" (muted) so the current state is
    -- obvious without an extra checkbox widget.
    d.playerBtn = ns.UI.Button.stone(parent, "[P] off", 48, 20)
    d.playerBtn:SetPoint("LEFT", d.removeBtn, "RIGHT", 4, 0)  -- 160+4+48 = 212
    d.playerBtn:SetScript("OnClick", function()
        if not state.selected or not state.slots[state.selected] then return end
        local s = state.slots[state.selected]
        s.isPlayer = not (s.isPlayer == true)
        refreshAll()
    end)

    return d
end

local function populateSlotClassDrop(d)
    UIDropDownMenu_Initialize(d.classDrop, function()
        for _, c in ipairs(ns.Data.CLASS_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = colorClass(c, ns.Data.CLASS_LABEL[c] or c), c
            info.func = function(self)
                local slot = state.slots[state.selected]
                if not slot then return end
                slot.classToken = self.value
                slot.spec       = defaultSpecFor(self.value)
                slot.opt1, slot.opt2 = "(none)", "(none)"
                refreshAll()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

local function populateSlotSpecDrop(d, slot)
    UIDropDownMenu_Initialize(d.specDrop, function()
        if not slot then return end
        for _, sp in ipairs(ns.Data.CLASS_SPECS[slot.classToken] or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = colorClass(slot.classToken, sp), sp
            info.func = function(self) slot.spec = self.value; refreshAll() end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

local function populateSlotOptDrop(drop, slot, key, list, isTotems)
    if not list or #list == 0 or not slot then
        UIDropDownMenu_Initialize(drop, function() end)
        UIDropDownMenu_SetText(drop, "(n/a)")
        if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(drop) end
        return
    end
    if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(drop) end

    -- Single-select per user request: picking an option replaces the slot's
    -- opt value and closes the menu. "(none)" clears the value. The pick is
    -- radio-style (only one check mark at a time).
    UIDropDownMenu_Initialize(drop, function()
        do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = "(none)"
            info.checked  = (slot[key] == nil or slot[key] == "" or slot[key] == "(none)")
            info.func = function()
                slot[key] = "(none)"
                UIDropDownMenu_SetText(drop, "(none)")
                CloseDropDownMenus()
                refreshSlotDetail(); refreshCoverage()
            end
            UIDropDownMenu_AddButton(info)
        end
        for _, option in ipairs(list) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = option
            info.checked = (slot[key] == option)
            info.func    = function()
                slot[key] = option
                UIDropDownMenu_SetText(drop, option)
                CloseDropDownMenus()
                refreshCoverage()
            end
            if isTotems and ns.Data.TOTEM_TOOLTIPS and ns.Data.TOTEM_TOOLTIPS[option] then
                info.tooltipTitle, info.tooltipText, info.tooltipOnButton =
                    option, ns.Data.TOTEM_TOOLTIPS[option], 1
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(drop, slot[key] or "(none)")
end

refreshSlotDetail = function()
    local d = state.sidebar.detail
    if not d then return end

    if not state.selected or not state.slots[state.selected] then
        d.titleLbl:SetText("select a slot")
        d.classTag:SetText(""); d.specTag:SetText("")
        d.classDrop:Hide(); d.specDrop:Hide()
        d.opt1Drop:Hide(); d.opt2Drop:Hide()
        d.classLbl:Hide(); d.specLbl:Hide()
        d.blessLbl:Hide(); d.auraLbl:Hide()
        d.moveBtn:Hide(); d.dupBtn:Hide(); d.removeBtn:Hide()
        if d.playerBtn then d.playerBtn:Hide() end
        return
    end
    local slot = state.slots[state.selected]
    -- Column-major addressing: group = which column, pos = which row within
    -- that column (PATCH_NOTES §8).
    local group  = math.floor((state.selected - 1) / state.rows) + 1
    local posInG = ((state.selected - 1) % state.rows) + 1

    local playerTag = slot.isPlayer and "  |cffffd100[PLAYER]|r" or ""
    d.titleLbl:SetText(string.format("SLOT - G%d pos %d%s", group, posInG, playerTag))
    d.classTag:SetText(colorClass(slot.classToken, ns.Data.CLASS_LABEL[slot.classToken] or slot.classToken))
    d.specTag:SetText(colorClass(slot.classToken, slot.spec or "-"))

    d.classDrop:Show(); d.specDrop:Show()
    d.opt1Drop:Show(); d.opt2Drop:Show()
    d.classLbl:Show(); d.specLbl:Show()
    d.blessLbl:Show(); d.auraLbl:Show()
    d.moveBtn:Show(); d.dupBtn:Show(); d.removeBtn:Show()

    -- FEATURE-02: reflect current isPlayer state on the toggle button.
    if d.playerBtn then
        d.playerBtn:Show()
        if slot.isPlayer then
            d.playerBtn:SetText("[P] on")
            local fs = d.playerBtn:GetFontString()
            if fs then fs:SetTextColor(1.00, 0.82, 0.00, 1) end
        else
            d.playerBtn:SetText("[P] off")
            local fs = d.playerBtn:GetFontString()
            if fs then fs:SetTextColor(0.61, 0.55, 0.40, 1) end
        end
    end

    populateSlotClassDrop(d)
    UIDropDownMenu_SetText(d.classDrop,
        colorClass(slot.classToken, ns.Data.CLASS_LABEL[slot.classToken] or slot.classToken))
    populateSlotSpecDrop(d, slot)
    UIDropDownMenu_SetText(d.specDrop, colorClass(slot.classToken, slot.spec or "-"))

    local opt1List, opt2List, isTotems = ns.Data.GetOptionsForClassSpec(slot.classToken, slot.spec)
    populateSlotOptDrop(d.opt1Drop, slot, "opt1", opt1List, isTotems)
    populateSlotOptDrop(d.opt2Drop, slot, "opt2", opt2List, false)
end

-- ----------------------------------------------------------
-- Sidebar - coverage pills (blessings - totems - resists)
-- ----------------------------------------------------------
-- v1.1: the 15 mock coverage chips in mock order, as a single flat group
-- (the "COVERAGE" header already labels the section). Each key is a logical
-- flag set by scanCoverageMap from the providers already present in the comp.
local COV_GROUPS = {
    { title = nil, items = {
        { label = "Kings",    key = "kings"    },
        { label = "Might",    key = "might"    },
        { label = "Wisdom",   key = "wisdom"   },
        { label = "Sanct.",   key = "sanct"    },
        { label = "Devot.",   key = "devot"    },
        { label = "Retrib.",  key = "retrib"   },
        { label = "B.Shout",  key = "bshout"   },
        { label = "Command",  key = "command"  },
        { label = "MoW",      key = "mow"      },
        { label = "Windf.",   key = "windf"    },
        { label = "ManaSpr",  key = "manaspr"  },
        { label = "AotW",     key = "aotw"     },
        { label = "ShadRes",  key = "shadres"  },
        { label = "FireRes",  key = "fireres"  },
        { label = "FrostRes", key = "frostres" },
    }},
}

-- Build the coverage flag set from the current comp. Each provider maps to one
-- or more of the 15 mock chips (see WARDEN_1.1_PLAN.md workstream C3).
local function scanCoverageMap()
    local f = {}
    for _, slot in ipairs(state.slots) do
        if slot and slot.classToken then
            local cls  = slot.classToken
            local o1   = splitSet(slot.opt1)
            local o2   = splitSet(slot.opt2)
            local spec = slot.spec or ""
            if cls == "PALADIN" then
                if o1.kings        then f.kings    = true end
                if o1.might        then f.might    = true end
                if o1.wisdom       then f.wisdom   = true end
                if o1.sanctuary    then f.sanct    = true end
                if o2.devotion     then f.devot    = true end
                if o2.retribution  then f.retrib   = true end
                if o2["fire res"]  then f.fireres  = true end
                if o2["frost res"] then f.frostres = true end
            elseif cls == "WARRIOR" then
                if o1.battle       then f.bshout   = true end
                if o1.commanding   then f.command  = true end
            elseif cls == "DRUID" then
                f.mow = true  -- Mark of the Wild: any Druid presence
            elseif cls == "SHAMAN" then
                -- Shaman opt1 is a totem set; enh spec also brings windfury.
                if o1.melee                       then f.windf    = true end
                if spec:find("enh", 1, true)      then f.windf    = true end
                if o1.caster or o1.healing        then f.manaspr  = true end
                if o1["fire res"]                 then f.fireres  = true end
                if o1["frost res"]                then f.frostres = true end
            elseif cls == "HUNTER" then
                if o1.aotw         then f.aotw     = true end
            elseif cls == "PRIEST" then
                if o2["shadow res"] then f.shadres = true end
            end
        end
    end
    return f
end

-- Cell color sets for the raid-grid coverage panel. A provided buff lights
-- its tile green (like a healthy raid-frame cell); a missing buff stays a
-- dim red-brown tile. Carrying state in the tile fill + rim (not glyphs) is
-- what makes the panel scan like the raid grid at a glance.
local COV_OK_BG,   COV_OK_RIM,   COV_OK_TXT   = {0.10, 0.26, 0.09}, {0.20, 0.78, 0.27}, {0.74, 1.00, 0.66}
local COV_MISS_BG, COV_MISS_RIM, COV_MISS_TXT = {0.14, 0.07, 0.06}, {0.42, 0.22, 0.18}, {0.60, 0.42, 0.38}

local function paintCovCell(cell, ok)
    local bg  = ok and COV_OK_BG  or COV_MISS_BG
    local rim = ok and COV_OK_RIM or COV_MISS_RIM
    local txt = ok and COV_OK_TXT or COV_MISS_TXT
    cell.frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.92)
    cell.frame:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
    cell.label:SetTextColor(txt[1], txt[2], txt[3], 1)
end

refreshCoverage = function()
    local c = state.sidebar.coverage
    if not c then return end
    local map = scanCoverageMap()
    local gi = 1
    for _, g in ipairs(COV_GROUPS) do
        local gr = c.groups[gi]; gi = gi + 1
        if gr then
            for i, item in ipairs(g.items) do
                local cell = gr.cells[i]
                if cell then paintCovCell(cell, map[item.key] and true or false) end
            end
        end
    end
end

-- ----------------------------------------------------------
-- Sidebar - summary (filled N/M + Build + save/load/clear/cleanup)
-- ----------------------------------------------------------
refreshSummary = function()
    local s = state.sidebar.summary
    if not s then return end
    local filled = 0
    for _, slot in ipairs(state.slots) do if slot then filled = filled + 1 end end
    -- TASKS.md §2.5: widen the slash separator so "24 / 25" is scannable.
    s.numLbl:SetText(string.format("|cffffd100%d|r |cff9b8b67/ %d|r", filled, state.size))
    if s.buildBtn then
        if filled > 0 then s.buildBtn:Enable() else s.buildBtn:Disable() end
    end
end

-- ----------------------------------------------------------
-- Master refresh
-- ----------------------------------------------------------
selectSlot = function(idx)
    state.selected = idx
    refreshAll()
end

refreshAll = function()
    layoutGrid()
    refreshSlotDetail()
    refreshCoverage()
    refreshSummary()
end

-- ----------------------------------------------------------
-- Preset dropdown
-- ----------------------------------------------------------
-- Is the current grid non-empty? Used to gate the load-confirm popup.
local function compHasSlots()
    for _, s in ipairs(state.slots) do if s then return true end end
    return false
end

-- Confirm before an instance preset replaces a non-empty comp. The actual
-- load closure is passed as `data` and fired on accept. Empty comps skip this
-- and load directly (see the dropdown entry below).
StaticPopupDialogs["WARDEN_COMP_LOAD_CONFIRM"] = {
    text         = "Replace the current comp with \"%s\"?\nUnsaved slots will be lost.",
    button1      = YES, button2 = NO, timeout = 0,
    whileDead    = true, hideOnEscape = true,
    OnAccept     = function(_, data) if data then data() end end,
}

local function refreshPresetDropdown()
    if not state.presetDrop then return end
    UIDropDownMenu_Initialize(state.presetDrop, function()
        local function title(t)
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.isTitle, info.notCheckable = t, true, true
            UIDropDownMenu_AddButton(info)
        end
        local function entry(name, comp, markSaved)
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = name, name
            info.func = function()
                local function doLoad()
                    loadComp(comp)
                    if state.nameBox then state.nameBox:SetText(name) end
                    if markSaved and ns.Persistence.DB then
                        ns.Persistence.DB.lastComp = name
                    end
                    UIDropDownMenu_SetText(state.presetDrop, "presets ")
                    state.selected = nil
                    refreshAll()
                end
                -- Confirm only when the current comp is non-empty; empty loads
                -- replace nothing, so they go straight through.
                if compHasSlots() then
                    StaticPopup_Show("WARDEN_COMP_LOAD_CONFIRM", name, nil, doLoad)
                else
                    doLoad()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
        local groups, sizes = getCompNamesGroupedBySize()
        if #sizes == 0 then
            title("No saved comps")
        else
            for _, size in ipairs(sizes) do
                title(string.format("Saved comps (%d-man)", size))
                for _, n in ipairs(groups[size]) do
                    entry(n, ns.Persistence.DB.comps[n], true)
                end
            end
        end
    end)
    UIDropDownMenu_SetText(state.presetDrop, "presets ")
end

-- ----------------------------------------------------------
-- BuildInto
-- ----------------------------------------------------------
function ns.UI.Tabs.Comp.BuildInto(pane)
    state.pane = pane
    applySizeLayout(25)

    local PW, PH = pane:GetWidth(), pane:GetHeight()

    -- ============================================================
    -- Header row: comp name + presets + size + grid/table toggle
    -- ============================================================
    local headerY = -10
    local compLbl = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    compLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, headerY)
    compLbl:SetText("COMP")
    compLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    local nameBox = CreateFrame("EditBox", "WardenCompNameBox", pane, "InputBoxTemplate")
    nameBox:SetSize(200, 20)
    nameBox:SetPoint("LEFT", compLbl, "RIGHT", 10, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetTextInsets(6, 6, 0, 0)
    nameBox:SetText(ns.Persistence.DB and ns.Persistence.DB.lastComp or "")
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    state.nameBox = nameBox

    local presetDrop = CreateFrame("Frame", "WardenCompPresetDrop", pane, "UIDropDownMenuTemplate")
    -- Previous y-offset was +2 which pushed the dropdown visibly above the
    -- nameBox baseline. Drop to -4 so the preset + size dropdowns sit
    -- level with the input field rather than floating above it.
    presetDrop:SetPoint("LEFT", nameBox, "RIGHT", -4, -4)
    ns.UI.Dropdown.style(presetDrop, 110)
    state.presetDrop = presetDrop

    -- Segmented 5 / 10 / 25 / 40 strip (replaces the old size dropdown).
    -- Active = stone-tile fill + gold rim + gold text; inactive = gold_dim.
    local sizeSeg = ns.UI.Segmented.Create(pane, {
        { key = 5,  label = "5"  },
        { key = 10, label = "10" },
        { key = 25, label = "25" },
        { key = 40, label = "40" },
    }, function(key)
        applySizeLayout(key)
        refreshAll()
    end)
    sizeSeg:SetSize(132, 22)
    sizeSeg:SetPoint("LEFT", presetDrop, "RIGHT", 4, 4)
    sizeSeg:SetActive(state.size)
    state.sizeSeg = sizeSeg

    -- Table view removed per user request - grid is the only view.

    -- ============================================================
    -- Main panel - grid (left) + sidebar (right).
    -- TASKS.md §2.2: sidebar widened 240->260, mainH 370->420, and the
    -- three old detail/coverage/summary panels become a single scrollable
    -- stack so nothing overlaps.
    -- ============================================================
    local mainY = -38
    local mainH = 420
    local sidebarW = 260
    local gridW    = PW - 24 - sidebarW - 6

    -- Grid panel
    local gridPanel = ns.UI.Panel.Create(pane, gridW, mainH, "Raid grid")
    gridPanel:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, mainY)
    state.gridPanel = gridPanel

    -- Carve out inner area (top = grid, bottom = tray)
    local gridInner = CreateFrame("Frame", nil, gridPanel.content)
    gridInner:SetPoint("TOPLEFT",  gridPanel.content, "TOPLEFT",  0, 0)
    gridInner:SetPoint("TOPRIGHT", gridPanel.content, "TOPRIGHT", 0, 0)
    gridInner:SetHeight(mainH - 80) -- reserve ~80 for tray
    state.gridInner = gridInner

    -- Tray row
    local trayRow = CreateFrame("Frame", nil, gridPanel.content)
    trayRow:SetPoint("TOPLEFT",  gridInner, "BOTTOMLEFT",  0, -2)
    trayRow:SetPoint("BOTTOMRIGHT", gridPanel.content, "BOTTOMRIGHT", 0, 0)

    -- "DRAG ->" lead label
    local dragLbl = trayRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dragLbl:SetPoint("LEFT", trayRow, "LEFT", 2, 6)
    dragLbl:SetText("CLICK ->")
    dragLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    -- 10 chips (2 rows of 5 for width)
    local chipStartX = 54
    local chipW, chipH, chipGap = 66, 22, 3
    for i, c in ipairs(ns.Data.CLASS_ORDER) do
        local chip = buildChipWidget(trayRow, c)
        chip:SetSize(chipW, chipH)
        local col = (i - 1) % 5
        local row = math.floor((i - 1) / 5)
        chip:SetPoint("TOPLEFT", trayRow, "TOPLEFT",
            chipStartX + col * (chipW + chipGap),
            -row * (chipH + 2))
        state.chipFrames[i] = chip
    end

    -- Previous "shift+click - N copies" BOTTOMRIGHT label sat on top of the
    -- last chip in row 2 (DK) because the trayRow is only ~52px tall once
    -- the gridInner claims the rest of the panel. The same hint is already
    -- surfaced on chip hover (see buildChipWidget tooltip), so drop the
    -- redundant label to reclaim the space.

    -- ============================================================
    -- Sidebar - single outer panel wrapping a scrollable stack (TASKS.md §2.2).
    -- Stack order inside scroll: Slot detail -> Coverage -> Summary -> File row.
    -- ============================================================
    local sideX = PW - sidebarW - 12

    local sidePanel = ns.UI.Panel.Create(pane, sidebarW, mainH, "")
    sidePanel:SetPoint("TOPLEFT", pane, "TOPLEFT", sideX, mainY)
    sidePanel:SetBackdropBorderColor(0.72, 0.58, 0.21, 1) -- gold outer rim

    local sideScroll = CreateFrame("ScrollFrame", "WardenCompSideScroll",
                                    sidePanel.content, "UIPanelScrollFrameTemplate")
    sideScroll:SetPoint("TOPLEFT",     sidePanel.content, "TOPLEFT",      0,  0)
    sideScroll:SetPoint("BOTTOMRIGHT", sidePanel.content, "BOTTOMRIGHT", -22, 0)

    local sideChild = CreateFrame("Frame", "WardenCompSideChild", sideScroll)
    sideChild:SetSize(sidebarW - 28, 10)
    sideScroll:SetScrollChild(sideChild)

    -- --- Section 1: Slot detail (no inner panel, just stacked widgets) ---
    -- BUG-05: previous 170px host overflowed into the COVERAGE section
    -- once the slot detail expanded with class/spec/opt1/opt2 dropdowns +
    -- move/dup/remove/[P] buttons. Re-measured after the native-chrome
    -- dropdown rewrite (v6): four label+drop rows stack taller, and the
    -- action-button row has to clear the last drop with an 8px gap. 285
    -- leaves a comfortable margin before COVERAGE starts.
    local DETAIL_H = 285
    local detailHost = CreateFrame("Frame", nil, sideChild)
    detailHost:SetPoint("TOPLEFT",  sideChild, "TOPLEFT",  4, -4)
    detailHost:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", -4, -4)
    detailHost:SetHeight(DETAIL_H)

    local detailHeader = detailHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailHeader:SetPoint("TOPLEFT", detailHost, "TOPLEFT", 0, -2)
    detailHeader:SetText("SLOT DETAIL")
    detailHeader:SetTextColor(1, 0.82, 0)

    local detailContent = CreateFrame("Frame", nil, detailHost)
    detailContent:SetPoint("TOPLEFT",     detailHost, "TOPLEFT",      0, -18)
    detailContent:SetPoint("BOTTOMRIGHT", detailHost, "BOTTOMRIGHT",  0,   0)
    state.sidebar.detail = buildSlotDetail(detailContent)

    -- --- Section 2: Coverage (FIXED - pinned to the sidebar bottom stack,
    -- not inside the scroll, so it stays visible while Slot Detail scrolls).
    -- Anchored at the end of BuildInto once the whole fixed stack exists.
    -- v1.2 (raid-grid pass): COVERAGE is its own bordered square holding a
    -- grid of buff tiles - like the raid grid, each cell lights green when the
    -- comp provides that buff and stays a dim red-brown when it's missing.
    -- Reads at a glance; refreshCoverage repaints the tiles (see paintCovCell).
    local covHost = CreateFrame("Frame", nil, sidePanel.content)
    covHost:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    covHost:SetBackdropColor(0.10, 0.08, 0.05, 0.85)
    covHost:SetBackdropBorderColor(0.72, 0.58, 0.21, 0.55) -- gold-dim rim = "its own square"

    local covHeader = covHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    covHeader:SetPoint("TOPLEFT", covHost, "TOPLEFT", 8, -5)
    covHeader:SetText("COVERAGE")
    covHeader:SetTextColor(1, 0.82, 0)

    local covRule = covHost:CreateTexture(nil, "ARTWORK")
    covRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    covRule:SetVertexColor(0.72, 0.58, 0.21, 0.35)
    covRule:SetHeight(1)
    covRule:SetPoint("TOPLEFT", covHeader, "BOTTOMLEFT", 0, -3)
    covRule:SetPoint("RIGHT",   covHost,   "RIGHT",     -8, 0)

    do
        local c = { groups = {} }
        local items = COV_GROUPS[1].items
        local gr = { cells = {} }
        local COLS    = 3
        local cellH   = 17
        local gap     = 3
        local pad     = 6
        local contentW = sidebarW - 2 * pad - 12  -- minus rim + scrollbar room
        local colW = math.floor((contentW - (COLS - 1) * gap) / COLS)
        local topY = -22                          -- below header + rule
        for i, item in ipairs(items) do
            local col = (i - 1) % COLS
            local row = math.floor((i - 1) / COLS)
            local cell = CreateFrame("Frame", nil, covHost)
            cell:SetSize(colW, cellH)
            cell:SetPoint("TOPLEFT", covHost, "TOPLEFT",
                pad + col * (colW + gap),
                topY - row * (cellH + gap))
            cell:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            local lbl = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("CENTER", cell, "CENTER", 0, 0)
            lbl:SetText(item.label)
            local rec = { frame = cell, label = lbl }
            paintCovCell(rec, false) -- seed missing; refreshCoverage repaints
            gr.cells[i] = rec
        end
        local rows = math.ceil(#items / COLS)
        covHost:SetHeight(22 + rows * (cellH + gap) + pad)
        table.insert(c.groups, gr)
        state.sidebar.coverage = c
    end

    -- --- Section 3: Summary (FIXED - filled counter, pinned below coverage in
    -- the bottom stack). The Build button moved down to the bottom action row
    -- (with Create / Stop Build) so all the primary actions sit together;
    -- this section is now just the filled N/M readout.
    local sumHost = CreateFrame("Frame", nil, sidePanel.content)
    sumHost:SetHeight(26)

    local numLbl = sumHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    numLbl:SetPoint("LEFT", sumHost, "LEFT", 2, 0)
    numLbl:SetText("|cffffd1000|r |cff9b8b67/  25|r")
    numLbl:SetTextColor(1, 0.82, 0)

    local filledCap = sumHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    filledCap:SetPoint("LEFT", numLbl, "RIGHT", 6, 0)
    filledCap:SetText("filled")
    filledCap:SetTextColor(0.61, 0.55, 0.40)

    -- runBuild: the actual build kickoff, factored out of the click handler
    -- so both the direct path and the safe-summon confirmation popup can run
    -- the exact same logic.
    local function runBuild(plan)
        -- BUG-#4: if the user placed the [P] (isPlayer) slot in e.g.
        -- group 3 (caster group) but the player is currently in group 1,
        -- bots spawn into G1 first and push the caster group off by one.
        -- Fix: move the player to the target subgroup BEFORE queuing
        -- spawns. `plan.playerTargetGroup` is set by readPlan when a
        -- [P] slot exists. Two paths:
        --   (a) already in raid -> MovePlayerToGroup runs now, inline.
        --   (b) party -> raid via StartBuild -> ConvertToRaid: the raid
        --       doesn't exist yet, so MovePlayerToGroup here no-ops.
        --       StartBuild schedules a deferred MovePlayerToGroup after
        --       ConvertToRaid has propagated.
        if plan.playerTargetGroup and ns.Engine and ns.Engine.MovePlayerToGroup then
            ns.Engine.MovePlayerToGroup(plan.playerTargetGroup)
        end

        ns.Engine.StartBuild(plan)
    end

    -- Safe-summon guard: clicking Build while already in a group/raid kicks
    -- off the add/remove churn of StartBuild over your live roster, which can
    -- wipe a raid on a stray click. Confirm first - mirrors the prompt the
    -- competing addon shows on its "Create" button. (data carries the plan;
    -- OnAccept receives it as the 2nd arg, same pattern WoW uses elsewhere.)
    StaticPopupDialogs["WARDEN_CONFIRM_BUILD"] = {
        text         = "You're already in a group/raid.\nBuild will re-summon bots over the current roster. Proceed?",
        button1      = YES, button2 = NO, timeout = 0,
        whileDead    = true, hideOnEscape = true,
        OnAccept     = function(_, data) runBuild(data) end,
    }

    -- buildBtn itself is created in the bottom action row (see below); its
    -- click handler reuses runBuild + WARDEN_CONFIRM_BUILD defined here.
    state.sidebar.summary = { numLbl = numLbl }

    -- ----------------------------------------------------------
    -- Pin Coverage + Summary to the bottom of the sidebar so they're always
    -- visible, and constrain the scroll to the space above so only Slot Detail
    -- scrolls. FILE actions + the Queue/Create/Stop controls now live in the
    -- bottom action bar (built just below), which frees the sidebar for the
    -- Coverage table + Summary + a taller Slot Detail.
    -- ----------------------------------------------------------
    sumHost:SetPoint("BOTTOMLEFT",  sidePanel.content, "BOTTOMLEFT",  4, 4)
    sumHost:SetPoint("BOTTOMRIGHT", sidePanel.content, "BOTTOMRIGHT", -4, 4)

    covHost:SetPoint("BOTTOMLEFT",  sumHost, "TOPLEFT",  0, 8)
    covHost:SetPoint("BOTTOMRIGHT", sumHost, "TOPRIGHT", 0, 8)

    -- Scroll occupies the top region, ending just above the coverage block.
    sideScroll:ClearAllPoints()
    sideScroll:SetPoint("TOPLEFT",  sidePanel.content, "TOPLEFT",  0, 0)
    sideScroll:SetPoint("TOPRIGHT", sidePanel.content, "TOPRIGHT", -22, 0)
    sideScroll:SetPoint("BOTTOM",   covHost, "TOP", 0, 6)

    -- ============================================================
    -- Bottom action bar - the wide strip beneath the grid + sidebar.
    -- Top row: FILE actions (save/load/import/export/delete/clear/cleanup/
    -- rename) in one horizontal line. Bottom row: Queue/Pending status (left)
    -- + the Build / Create / Stop Build action group (right). Consolidating
    -- these here gets them out of the sidebar and the floating page bottom,
    -- giving the rest more room.
    -- ============================================================
    local actionBar = CreateFrame("Frame", "WardenCompActionBar", pane)
    actionBar:SetHeight(60)
    actionBar:SetPoint("BOTTOMLEFT",  pane, "BOTTOMLEFT",  12, 6)
    actionBar:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 6)
    state.actionBar = actionBar

    local barBg = actionBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetVertexColor(0.10, 0.08, 0.05, 0.55)
    barBg:SetAllPoints(actionBar)

    local barRule = actionBar:CreateTexture(nil, "ARTWORK")
    barRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    barRule:SetVertexColor(0.72, 0.58, 0.21, 0.45)
    barRule:SetHeight(1)
    barRule:SetPoint("TOPLEFT",  actionBar, "TOPLEFT",  0, 0)
    barRule:SetPoint("TOPRIGHT", actionBar, "TOPRIGHT", 0, 0)

    -- File row: one horizontal row of 8 uniform buttons along the bar top.
    -- v1.2 (spacing pass): instead of a fixed 76px width that left a ragged
    -- trailing gap before the right edge, derive the button width from the
    -- pane so the eight buttons justify edge-to-edge - the last one (rename)
    -- now lines up with the Stop Build right margin below it.
    local FILE_COUNT   = 8
    local FILE_BTN_H   = 20
    local FILE_BTN_GAP = 5
    local FILE_LABEL_RESERVE = 34   -- "FILE" label + 8px gap to first button
    local fileAvail    = (PW - 36) - FILE_LABEL_RESERVE
    local FILE_BTN_W   = math.floor((fileAvail - (FILE_COUNT - 1) * FILE_BTN_GAP) / FILE_COUNT)

    local fileHost = CreateFrame("Frame", nil, actionBar)
    fileHost:SetHeight(FILE_BTN_H)
    fileHost:SetPoint("TOPLEFT",  actionBar, "TOPLEFT",  6, -6)
    fileHost:SetPoint("TOPRIGHT", actionBar, "TOPRIGHT", -6, -6)

    local fileHeader = fileHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fileHeader:SetPoint("LEFT", fileHost, "LEFT", 0, 0)
    fileHeader:SetText("FILE")
    fileHeader:SetTextColor(0.72, 0.58, 0.21, 1)

    local saveBtn   = ns.UI.Button.stone(fileHost, "save",    FILE_BTN_W, FILE_BTN_H)
    local loadBtn   = ns.UI.Button.stone(fileHost, "load",    FILE_BTN_W, FILE_BTN_H)
    local importBtn = ns.UI.Button.stone(fileHost, "import",  FILE_BTN_W, FILE_BTN_H)
    local exportBtn = ns.UI.Button.stone(fileHost, "export",  FILE_BTN_W, FILE_BTN_H)
    local deleteBtn = ns.UI.Button.warn (fileHost, "delete",  FILE_BTN_W, FILE_BTN_H)
    local clearBtn  = ns.UI.Button.stone(fileHost, "clear",   FILE_BTN_W, FILE_BTN_H)
    local cleanBtn  = ns.UI.Button.warn (fileHost, "cleanup", FILE_BTN_W, FILE_BTN_H,
                                         "WARDEN_CONFIRM_CLEANUP")
    local resyncBtn = ns.UI.Button.stone(fileHost, "resync",  FILE_BTN_W, FILE_BTN_H)

    saveBtn  :SetPoint("LEFT", fileHeader, "RIGHT", 8, 0)
    loadBtn  :SetPoint("LEFT", saveBtn,    "RIGHT", FILE_BTN_GAP, 0)
    importBtn:SetPoint("LEFT", loadBtn,    "RIGHT", FILE_BTN_GAP, 0)
    exportBtn:SetPoint("LEFT", importBtn,  "RIGHT", FILE_BTN_GAP, 0)
    deleteBtn:SetPoint("LEFT", exportBtn,  "RIGHT", FILE_BTN_GAP, 0)
    clearBtn :SetPoint("LEFT", deleteBtn,  "RIGHT", FILE_BTN_GAP, 0)
    cleanBtn :SetPoint("LEFT", clearBtn,   "RIGHT", FILE_BTN_GAP, 0)
    resyncBtn:SetPoint("LEFT", cleanBtn,   "RIGHT", FILE_BTN_GAP, 0)
    -- Hidden in v1.0.0 - feature kept in code, just not exposed in the UI.
    -- Re-show by deleting the next line.
    resyncBtn:Hide()

    -- Rename a saved comp. Occupies the 8th cell (same anchor as the hidden
    -- resync button) so no layout math changes.
    local renameBtn = ns.UI.Button.stone(fileHost, "rename", FILE_BTN_W, FILE_BTN_H)
    renameBtn:SetPoint("LEFT", cleanBtn, "RIGHT", FILE_BTN_GAP, 0)

    -- Resync: rearrange the LIVE raid so each member's subgroup matches
    -- the comp grid's slot positions. FIFO-matches each filled slot to
    -- a live raid member of the same class (the [P] slot moves the
    -- player specifically). Calls SetRaidSubgroup once per mismatch.
    -- No-op outside a raid or without leader/officer rights.
    resyncBtn:SetScript("OnClick", function()
        if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then
            ns.MsgWarn("Resync: not in a raid - join or convert first.")
            return
        end
        local canMove = (IsRaidLeader and IsRaidLeader() == 1)
                     or (IsRaidOfficer and IsRaidOfficer() == 1)
        if not canMove then
            ns.MsgWarn("Resync: need raid leader or officer rights.")
            return
        end

        -- Snapshot the live raid: per-class FIFO buckets of {raidIdx,
        -- currentGroup, name}. Player-flagged characters are excluded
        -- from the FIFO so they don't get yanked by a Resync.
        local rosterByClass = {}
        local meRaidIdx
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitIsPlayer(unit) then
                local _, cls = UnitClass(unit)
                local nm     = UnitName(unit) or "?"
                local _, _, sg = GetRaidRosterInfo(i)
                local flagged = ns.Persistence and ns.Persistence.IsPlayerName
                                and ns.Persistence.IsPlayerName(nm)
                if UnitIsUnit(unit, "player") then
                    meRaidIdx = i
                end
                if cls and not flagged and not UnitIsUnit(unit, "player") then
                    rosterByClass[cls] = rosterByClass[cls] or {}
                    table.insert(rosterByClass[cls],
                        { raidIdx = i, currentGroup = sg, name = nm })
                end
            end
        end

        local rows  = state.rows or 5
        local moves = {}            -- { {raidIdx, target, name}, ... }
        local inPlace, unmatched = 0, 0

        for i = 1, state.size do
            local slot = state.slots[i]
            if slot and slot.classToken then
                local target = math.floor((i - 1) / rows) + 1
                if slot.isPlayer then
                    if meRaidIdx then
                        local _, _, mySg = GetRaidRosterInfo(meRaidIdx)
                        if mySg ~= target then
                            table.insert(moves,
                                { raidIdx = meRaidIdx, target = target,
                                  name = UnitName("player") })
                        else inPlace = inPlace + 1 end
                    end
                else
                    local bucket = rosterByClass[slot.classToken]
                    local m = bucket and table.remove(bucket, 1) or nil
                    if m then
                        if m.currentGroup ~= target then
                            table.insert(moves,
                                { raidIdx = m.raidIdx, target = target,
                                  name = m.name })
                        else inPlace = inPlace + 1 end
                    else
                        unmatched = unmatched + 1
                    end
                end
            end
        end

        local applied, failed = 0, 0
        for _, mv in ipairs(moves) do
            if SetRaidSubgroup then
                local ok = pcall(SetRaidSubgroup, mv.raidIdx, mv.target)
                if ok then applied = applied + 1
                else failed = failed + 1 end
            end
        end

        ns.MsgInfo(string.format(
            "Resync: moved %d, in place %d, unmatched %d%s.",
            applied, inPlace, unmatched,
            failed > 0 and (", failed " .. failed) or ""))
        if ns.DebugF then
            ns.DebugF("comp", "resync: applied=%d inPlace=%d unmatched=%d failed=%d",
                applied, inPlace, unmatched, failed)
        end
    end)

    local function fileTip(btn, title, body)
        ns.UI.Tooltip.Attach(btn, title, body, "ANCHOR_TOP")
    end
    fileTip(saveBtn,   "Save comp to a local preset slot",
        "Writes the full comp (name, size, slot positions, isPlayer flags, buffs) to WardenDB under the name typed in the COMP box.")
    fileTip(loadBtn,   "Load a saved local preset",
        "Reads the comp saved under the name typed in the COMP box and applies it to the grid.")
    fileTip(importBtn, "Import a full comp from a string",
        "Paste a WRDN2: (or legacy WRDN1:) string; Warden rebuilds the entire comp including slot positions.")
    fileTip(exportBtn, "Export full comp to a shareable string",
        "Produces a WRDN2: string you can paste into chat / a channel for another user to import.")
    fileTip(deleteBtn, "Delete a saved comp",
        "Removes the comp named in the COMP box from WardenDB. Confirmation popup required. Default raid presets can be restored from Settings -> Maintenance -> Restore default presets.")
    fileTip(clearBtn,  "Clear the grid locally",
        "Empties every slot in memory. Does NOT send any command to the server.")
    fileTip(cleanBtn,  "Cleanup: remove all bots on the server",
        "Sends `.warstormbot bot remove *` to despawn every bot in the raid. Confirmation popup required.")
    fileTip(resyncBtn, "Resync raid layout to comp",
        "Push the LIVE raid's subgroups to match this comp. Each filled slot is FIFO-matched to a raid member of the same class; mismatched members get SetRaidSubgroup'd into the slot's column. The [P] slot moves you specifically. Requires raid leader or officer.")

    saveBtn:SetScript("OnClick", function()
        local name = Trim(state.nameBox:GetText())
        if ns.DebugF then ns.DebugF("comp", "save clicked: name=%q", tostring(name)) end
        if name == "" then ns.MsgErr("Enter a comp name first."); return end
        local db = ns.Persistence.DB
        if not db then return end
        -- FEATURE-03: save BOTH the legacy `rows` (count-based) AND the
        -- positional `slotsByIdx` so a round-trip preserves slot positions
        -- AND keeps old-reader compatibility.
        local rows, byIdx, filled = {}, {}, 0
        for i = 1, state.size do
            local slot = state.slots[i]
            if slot then
                table.insert(rows, {
                    classToken = slot.classToken, spec = slot.spec,
                    count = 1,
                    opt1 = slot.opt1, opt2 = slot.opt2,
                    isPlayer = slot.isPlayer and true or false,
                })
                byIdx[i] = {
                    classToken = slot.classToken, spec = slot.spec,
                    opt1 = slot.opt1, opt2 = slot.opt2,
                    isPlayer = slot.isPlayer and true or false,
                }
                filled = filled + 1
            end
        end
        db.comps[name] = { rows = rows, slotsByIdx = byIdx, size = state.size }
        db.lastComp = name
        refreshPresetDropdown()
        ns.MsgInfo(string.format("Saved comp: %s (%d slot(s), size %d).",
            name, filled, state.size))
    end)

    loadBtn:SetScript("OnClick", function()
        local name = Trim(state.nameBox:GetText())
        local db   = ns.Persistence.DB
        if not db then return end
        if name == "" then name = db.lastComp or "" end
        if ns.DebugF then ns.DebugF("comp", "load clicked: name=%q", tostring(name)) end
        if name ~= "" and type(db.comps[name]) == "table" then
            loadComp(db.comps[name])
            state.selected = nil
            refreshAll()
            ns.MsgInfo("Loaded comp: " .. name)
        else
            ns.MsgWarn("No comp named '" .. name .. "'.")
        end
    end)

    clearBtn:SetScript("OnClick", function()
        wipe(state.slots)
        state.selected = nil
        if ns.Engine and ns.Engine.ClearTracking then ns.Engine.ClearTracking() end
        refreshAll()
    end)

    deleteBtn:SetScript("OnClick", function()
        local name = Trim(state.nameBox:GetText())
        local db   = ns.Persistence.DB
        if not db then return end
        if name == "" then name = db.lastComp or "" end
        if name == "" then
            ns.MsgErr("Enter a comp name to delete.")
            return
        end
        if type(db.comps[name]) ~= "table" then
            ns.MsgWarn(string.format("No saved comp named '%s'.", name))
            return
        end
        local popup = StaticPopup_Show("WARDEN_COMP_DELETE", name)
        if popup then
            popup.data = name
            popup.onConfirm = function(n)
                if ns.Persistence.DB and ns.Persistence.DB.comps then
                    ns.Persistence.DB.comps[n] = nil
                    if ns.Persistence.DB.lastComp == n then
                        ns.Persistence.DB.lastComp = nil
                    end
                end
                refreshPresetDropdown()
                ns.MsgInfo("Deleted comp: " .. n)
            end
        end
    end)

    renameBtn:SetScript("OnClick", function()
        local name = Trim(state.nameBox:GetText())
        local db   = ns.Persistence.DB
        if not db then return end
        if name == "" then name = db.lastComp or "" end
        if name == "" then
            ns.MsgErr("Enter or select a comp to rename.")
            return
        end
        if type(db.comps[name]) ~= "table" then
            ns.MsgWarn(string.format("No saved comp named '%s'.", name))
            return
        end
        local popup = StaticPopup_Show("WARDEN_COMP_RENAME", name)
        if popup then
            popup.data = name
            popup.onConfirm = function(oldName, newName)
                newName = Trim(newName or "")
                if newName == "" then
                    ns.MsgErr("Rename cancelled: empty name.")
                    return
                end
                if newName == oldName then return end
                if type(db.comps[newName]) == "table" then
                    ns.MsgWarn(string.format("A comp named '%s' already exists.", newName))
                    return
                end
                db.comps[newName] = db.comps[oldName]
                db.comps[oldName] = nil
                if db.lastComp == oldName then db.lastComp = newName end
                if state.nameBox then state.nameBox:SetText(newName) end
                refreshPresetDropdown()
                ns.MsgInfo(string.format("Renamed comp '%s' -> '%s'.", oldName, newName))
            end
            if popup.editBox then
                popup.editBox:SetText(name)
                popup.editBox:HighlightText()
            end
        end
    end)

    importBtn:SetScript("OnClick", function() StaticPopup_Show("WARDEN_COMP_IMPORT") end)
    exportBtn:SetScript("OnClick", function()
        local s = exportCompString()
        -- Empty grid => header ends with "||"-style prefix with no slot tokens.
        if not s:find(";", 1, true) and not s:find("=", 1, true) then
            ns.MsgWarn("Grid is empty - nothing to export.")
            return
        end
        local p = StaticPopup_Show("WARDEN_COMP_EXPORT")
        if p then
            p.data = s
            if p.editBox then p.editBox:SetText(s); p.editBox:HighlightText() end
        end
    end)

    -- Scroll child now holds only the Slot Detail section; coverage / summary /
    -- file row live in the fixed bottom stack outside the scroll.
    sideChild:SetHeight(4 + DETAIL_H + 4)

    -- P1 review: the Re-Spec / Stop / Buffs / BL / Auto-spec strip used to
    -- live here, but it duplicated controls already available on the Controls
    -- tab (BL, Buffs) and on the Settings tab (Auto-spec) - and it doesn't
    -- belong on a composition-editor page conceptually. Removed.

    -- ----------------------------------------------------------
    -- Bottom action row: Queue/Pending status (left) + the primary action
    -- group [Build | Create | Stop Build] (right). All three are one height
    -- and equal width with even gaps, so they read as a single deliberate
    -- control cluster instead of scattered buttons. Build moved here from the
    -- sidebar so every "do it" button lives together on one line.
    -- ----------------------------------------------------------
    local ACT_BTN_W, ACT_BTN_H, ACT_GAP = 84, 22, 6

    -- Stop: aborts an in-progress Build by wiping the summon / spec / whisper
    -- queues (ns.Engine.Stop). Rightmost of the group.
    local stopBtn = ns.UI.Button.warn(pane, "Stop Build", ACT_BTN_W, ACT_BTN_H)
    stopBtn:SetPoint("BOTTOMRIGHT", actionBar, "BOTTOMRIGHT", -6, 6)
    stopBtn:SetScript("OnClick", function()
        if ns.Engine and ns.Engine.Stop then
            ns.Engine.Stop()
        end
    end)

    -- Create: one-click ORC-style sequence - remove ALL current bots, paced
    -- re-summon of this comp (auto-converts to raid + auto-specs + AI strats),
    -- then per-bot init=epic, autogear, and world buffs. Destructive, so it's
    -- always behind a confirm. NOTE: a full role-based raid re-sort is not part
    -- of this chain yet (that's the separate sort feature); the build still
    -- auto-moves the player to their [P] slot.
    local createBtn = ns.UI.Button.red(pane, "Create", ACT_BTN_W, ACT_BTN_H)
    createBtn:SetPoint("RIGHT", stopBtn, "LEFT", -ACT_GAP, 0)
    StaticPopupDialogs["WARDEN_CONFIRM_CREATE"] = {
        text         = "Create raid:\nremoves ALL current bots, re-summons this comp, gears them (init=epic + autogear) and applies world buffs. Proceed?",
        button1      = YES, button2 = NO, timeout = 0,
        whileDead    = true, hideOnEscape = true,
        OnAccept     = function(_, data)
            if ns.Engine and ns.Engine.CreateRaid then
                ns.Engine.CreateRaid(data, { initRarity = "epic" })
            end
        end,
    }
    createBtn:SetScript("OnClick", function()
        local plan = readPlan()
        if #plan == 0 then ns.MsgErr("Grid is empty - nothing to create."); return end
        StaticPopup_Show("WARDEN_CONFIRM_CREATE", nil, nil, plan)
    end)

    -- Build: the primary build kickoff, moved down from the sidebar so it sits
    -- in the action group. Reuses runBuild + WARDEN_CONFIRM_BUILD from above.
    local buildBtn = ns.UI.Button.red(pane, "Build", ACT_BTN_W, ACT_BTN_H)
    buildBtn:SetPoint("RIGHT", createBtn, "LEFT", -ACT_GAP, 0)
    local buildFS = buildBtn:GetFontString()
    if buildFS then buildFS:SetTextColor(1.00, 0.92, 0.75) end
    buildBtn:SetScript("OnClick", function()
        local plan = readPlan()
        if ns.DebugF then ns.DebugF("comp", "Build clicked: plan rows=%d", #plan) end
        if #plan == 0 then ns.MsgErr("Grid is empty - nothing to build."); return end
        if (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0) then
            StaticPopup_Show("WARDEN_CONFIRM_BUILD", nil, nil, plan)
            return
        end
        runBuild(plan)
    end)
    if state.sidebar.summary then state.sidebar.summary.buildBtn = buildBtn end

    -- Status line (muted) - left of the action row, vertically centered on the
    -- button cluster so the row reads as one band.
    local statusLbl = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusLbl:SetPoint("LEFT", actionBar, "BOTTOMLEFT", 8, 6 + ACT_BTN_H / 2)
    statusLbl:SetText("Queue: 0   Pending: 0")

    pane._statusAccum = 0
    pane:SetScript("OnUpdate", function(self, elapsed)
        self._statusAccum = (self._statusAccum or 0) + elapsed
        if self._statusAccum < 0.2 then return end
        self._statusAccum = 0
        if ns.Engine and ns.Engine.QueueDepth then
            statusLbl:SetText(string.format("Queue: %d   Pending: %d",
                ns.Engine.QueueDepth(),
                ns.Engine.PendingSpecCount and ns.Engine.PendingSpecCount() or 0))
        end
    end)

    -- Final wiring
    refreshPresetDropdown()
    refreshAll()
end

function ns.UI.Tabs.Comp.OnShow(pane)
    refreshAll()
end
