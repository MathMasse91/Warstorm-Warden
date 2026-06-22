-- =====================================================
-- Warden - WardenSword_Actions.lua
-- Dispatch table for the mid-fight HUD. Every entry maps an action
-- label (what /ws <label> or a HUD button calls) to one engine call.
-- Keeping the table separate from the HUD frame lets Bindings.xml,
-- the slash command, and the buttons share one source of truth.
-- =====================================================

local _, ns = ...

ns.WardenSword = ns.WardenSword or {}

local A = {}

A.summon = function() ns.Engine.WhisperAll("summon") end
A.follow = function() ns.Engine.WhisperAll("follow") end
A.stay   = function() ns.Engine.WhisperAll("stay")   end
A.flee   = function() ns.Engine.WhisperAll("flee")   end
A.aoe    = function() return ns.Engine.ToggleAoE()   end
A.burn   = function() return ns.Engine.ToggleBurn()  end
A.skull  = function() ns.Engine.MarkAndAttack("skull") end
A.bl     = function() return ns.Engine.Bloodlust()   end

-- Role-scoped orders. mod-playerbots recognises `@tank attack`, `@heal stay`,
-- and `@dps attack`. Bracketed keys keep the dispatch-table call sites tight.
A["@tank follow"] = function() ns.Engine.WhisperRole("tank", "follow") end
A["@tank attack"] = function() ns.Engine.WhisperRole("tank", "attack") end
A["@tank stay"]   = function() ns.Engine.WhisperRole("tank", "stay")   end
A["@heal follow"] = function() ns.Engine.WhisperRole("heal", "follow") end
A["@heal attack"] = function() ns.Engine.WhisperRole("heal", "attack") end
A["@heal stay"]   = function() ns.Engine.WhisperRole("heal", "stay")   end
A["@dps follow"]  = function() ns.Engine.WhisperRole("dps",  "follow") end
A["@dps attack"]  = function() ns.Engine.WhisperRole("dps",  "attack") end
A["@dps stay"]    = function() ns.Engine.WhisperRole("dps",  "stay")   end

ns.WardenSword.Actions = A
