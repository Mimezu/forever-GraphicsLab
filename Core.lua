-- GraphicsLab core: CVar registry, hidden-CVar probe, change tracking, restore, snapshots and
-- "keep my value" (put a value back when the game or another addon changes it).
--
-- GraphicsLabDB layout:
--   original   = { [cvar] = value }  value before GraphicsLab first changed it ("Restore originals" target)
--   applied    = { [cvar] = value }  GraphicsLab's current overrides (re-applied at login when reapply = true)
--   keep       = { [cvar] = value }  values put back whenever something else changes them
--   keepResend = { [cvar] = true }   kept values that are also re-sent every second (experimental)
--   snapshots  = { [name] = { date, values = { [cvar] = value } } }
--   probe      = { build, names = { cvar, ... } }
--   fogtest    = the last fog test run (FogTest.lua)
--   linkRaid, reapply = booleans

local ADDON, ns = ...

local GetCVar, SetCVar, GetCVarInfo = C_CVar.GetCVar, C_CVar.SetCVar, C_CVar.GetCVarInfo
local GetAllCommands = ConsoleGetAllCommands or (C_Console and C_Console.GetAllCommands)

local CATEGORY = { [0] = "Debug", "Graphics", "Console", "Combat", "Game", "Default", "Net", "Sound", "Gm", "Reveal", "None" }
local PROBE_CHUNK = 2500

ns.registry = {}   -- [lower name] = { name, help, category, hidden }
ns.specs = {}      -- [lower name] = curated spec
ns.listeners = {}

local DB

function ns.Print(msg, ...)
	print("|cff7fd4ffGraphicsLab:|r " .. (select("#", ...) > 0 and msg:format(...) or msg))
end

function ns.OnChange(fn) ns.listeners[#ns.listeners + 1] = fn end
local function Notify(name) for _, fn in ipairs(ns.listeners) do fn(name) end end

local function Build() return (select(2, GetBuildInfo())) end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------

-- Bumped whenever an entry is added, so UI caches built from the registry can be reused.
ns.registryVersion = 0

local function Register(name, help, category, hidden)
	local key = name:lower()
	local e = ns.registry[key]
	if not e then
		e = { name = name, key = key }
		ns.registry[key] = e
		ns.registryVersion = ns.registryVersion + 1
	end
	e.help = e.help or (help ~= "" and help or nil)
	e.category = e.category or category
	e.hidden = e.hidden or hidden
	return e
end

function ns.Lookup(name) return name and ns.registry[name:lower()] end
function ns.Exists(name) return GetCVar(name) ~= nil end

local function BuildRegistry()
	if GetAllCommands then
		for _, info in ipairs(GetAllCommands()) do
			if info.commandType == 0 then Register(info.command, info.help, CATEGORY[info.category] or "?") end
		end
	end
	for _, cat in ipairs(ns.categories) do
		for _, spec in ipairs(cat) do
			-- Preset rows borrow a CVar as their anchor; never let them stand in for its control.
			if spec.kind ~= "presets" then ns.specs[spec.cvar:lower()] = spec end
			spec.category = cat
			if ns.Exists(spec.cvar) then Register(spec.cvar, nil, "Graphics", not ns.Lookup(spec.cvar)) end
		end
	end
	if DB.probe and DB.probe.build == Build() then
		for _, name in ipairs(DB.probe.names) do Register(name, nil, "Hidden", true) end
	end
end

-- Probes the candidates now when they are still loaded; otherwise forgets the
-- cached result so the next login/reload keeps the list and probes again.
function ns.RequestProbe()
	if ns.candidates then return ns.Probe() end
	DB.probe = nil
	ns.Print("hidden-CVar cache cleared. /reload to probe again.")
end

-- Probe exe-derived names with GetCVar (read-only) to find CVars the client does not list.
function ns.Probe(onDone)
	local cands = ns.candidates
	if not cands then
		ns.Print("candidate list already released; /reload to probe again.")
		return
	end
	local found, i = {}, 1
	local function Step()
		local stop = math.min(i + PROBE_CHUNK - 1, #cands)
		for j = i, stop do
			local name = cands[j]
			if not ns.registry[name:lower()] and GetCVar(name) ~= nil then
				found[#found + 1] = name
				Register(name, nil, "Hidden", true)
			end
		end
		i = stop + 1
		if i <= #cands then
			C_Timer.After(0, Step)
		else
			DB.probe = { build = Build(), names = found }
			ns.candidates = nil
			-- The login snapshot predates the probe; add the hidden CVars' pre-change values to it.
			local before = DB.snapshots["Before GraphicsLab"]
			if before then
				for _, name in ipairs(found) do
					local key = name:lower()
					if before.values[key] == nil then before.values[key] = DB.original[key] or GetCVar(name) end
				end
			end
			ns.Print("probe finished: %d hidden CVars found.", #found)
			Notify(nil)
			if onDone then onDone(found) end
		end
	end
	Step()
end

---------------------------------------------------------------------------
-- Reading / writing
---------------------------------------------------------------------------

function ns.Get(name) return GetCVar(name) end

local defaults = {}
-- Defaults never change during a session; cache them (list rows read them constantly).
function ns.Default(name)
	local key = name:lower()
	local cached = defaults[key]
	if cached ~= nil then return cached or nil end
	local ok, _, default = pcall(GetCVarInfo, name)
	if not (ok and default ~= nil) then
		default = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
	end
	defaults[key] = default == nil and false or default
	return default
end

function ns.Original(name) return DB.original[name:lower()] end
function ns.IsChanged(name) return DB.original[name:lower()] ~= nil end

local function Same(a, b)
	if a == b then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 1e-6
end
ns.Same = Same

local writing = false

-- Returns ok, actualValue. ok=false when the client refused the change (locked, secure, invalid).
-- The client may clamp the value; the returned value is what it actually stored.
local function RawSet(name, value)
	local key = name:lower()
	local before = GetCVar(name)
	if before == nil then return false end
	value = tostring(value)
	if Same(before, value) then return true, before end
	if DB.original[key] == nil then DB.original[key] = before end
	writing = true
	local ok, res = pcall(SetCVar, name, value)
	writing = false
	local now = GetCVar(name)
	if Same(now, DB.original[key]) then
		DB.original[key], DB.applied[key] = nil, nil
	else
		DB.applied[key] = now
	end
	-- A kept setting keeps whatever was last chosen here.
	if DB.keep[key] ~= nil then DB.keep[key] = now end
	Notify(name)
	return ok and res ~= false, now
end

-- Writes a value without recording it as a GraphicsLab change (fog test, keep, re-send).
function ns.WriteUntracked(name, value)
	writing = true
	local ok, res = pcall(SetCVar, name, tostring(value))
	writing = false
	return ok and res ~= false
end

function ns.RaidTwin(name)
	local key = name:lower()
	local twin = key:match("^graphics(.+)") and ("raidgraphics" .. key:sub(9)) or ("raid" .. key)
	local e = ns.registry[twin]
	return e and e.name
end

function ns.Set(name, value)
	local ok, now = RawSet(name, value)
	if DB.linkRaid then
		local twin = ns.RaidTwin(name)
		if twin then RawSet(twin, value) end
	end
	return ok, now
end

function ns.ResetOne(name)
	-- Going back to the original also stops keeping the changed value.
	ns.SetKept(name, false)
	local orig = DB.original[name:lower()]
	if orig then RawSet(name, orig) end
	-- The linked RAID twin has its own original; never copy this CVar's value into it.
	if DB.linkRaid then
		local twin = ns.RaidTwin(name)
		local twinOrig = twin and DB.original[twin:lower()]
		if twinOrig then RawSet(twin, twinOrig) end
	end
end

function ns.RestoreAll()
	wipe(DB.keep)
	wipe(DB.keepResend)
	ns.UpdateKeepTicker()
	local n = 0
	for key, value in pairs(CopyTable(DB.original)) do
		local e = ns.registry[key]
		RawSet(e and e.name or key, value)
		n = n + 1
	end
	wipe(DB.applied)
	Notify(nil)
	return n
end

function ns.ChangedCount()
	local n = 0
	for _ in pairs(DB.original) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------
-- Keep my value: put a kept value back when the game or another addon changes it, after
-- loading screens, and on a 1 s check. Optionally re-send it every second, for settings whose
-- value stays but whose effect fades (the game only applies some settings when they change).
---------------------------------------------------------------------------

local KEEP_TICK = 1
local STORM_LIMIT, STORM_WINDOW = 20, 10   -- more put-backs than this in the window: stop fighting
local keepTicker
local storms, told = {}, {}

-- Set while the fog test runs: it changes settings on purpose and puts them back itself.
ns.testActive = false

local function NameOf(key)
	local e = ns.registry[key]
	return e and e.name or key
end

local function Enforce(key)
	local target = DB.keep[key]
	if target == nil or ns.testActive then return end
	local name = NameOf(key)
	local cur = GetCVar(name)
	if cur == nil or Same(cur, target) then return end
	local now = GetTime()
	local storm = storms[key]
	if not storm or now - storm.since > STORM_WINDOW then
		storm = { since = now, n = 0 }
		storms[key] = storm
	end
	storm.n = storm.n + 1
	if storm.n > STORM_LIMIT then
		DB.keep[key], DB.keepResend[key] = nil, nil
		ns.Print("the game keeps changing %s, so GraphicsLab stopped keeping it.", name)
		ns.UpdateKeepTicker()
		Notify(name)
		return
	end
	ns.WriteUntracked(name, target)
	if not told[key] then
		told[key] = true
		ns.Print("kept %s at %s (something changed it to %s).", name, target, cur)
	end
end

-- Writing a slightly different number makes the game run its change handler again;
-- then the real value goes back. Used for kept values and by the fog test.
function ns.Resend(name, value)
	local v = tonumber(value)
	if not v then return end
	ns.WriteUntracked(name, v + 0.001)
	ns.WriteUntracked(name, value)
end

local function KeepTick()
	for key in pairs(DB.keep) do Enforce(key) end
	if ns.testActive then return end
	for key in pairs(DB.keepResend) do
		if DB.keep[key] ~= nil then ns.Resend(NameOf(key), DB.keep[key]) end
	end
end

local function EnforceAll()
	for key in pairs(DB.keep) do Enforce(key) end
end

function ns.UpdateKeepTicker()
	local any = next(DB.keep) ~= nil
	if any and not keepTicker then
		keepTicker = C_Timer.NewTicker(KEEP_TICK, KeepTick)
	elseif not any and keepTicker then
		keepTicker:Cancel()
		keepTicker = nil
	end
end

function ns.IsKept(name) return DB.keep[name:lower()] ~= nil end
function ns.IsResent(name) return DB.keepResend[name:lower()] == true end
function ns.KeptCount()
	local n = 0
	for _ in pairs(DB.keep) do n = n + 1 end
	return n
end

-- Only slider settings can be re-sent: nudging a list or on/off value would switch it.
function ns.CanResend(name)
	local spec = ns.specs[name:lower()]
	return spec ~= nil and spec.kind == "range"
end

local function KeepOne(name, on, resend)
	local key = name:lower()
	if on then
		local cur = GetCVar(name)
		if cur == nil then return end
		DB.keep[key] = DB.keep[key] or cur
		if resend ~= nil then DB.keepResend[key] = resend or nil end
	else
		DB.keep[key], DB.keepResend[key] = nil, nil
		storms[key], told[key] = nil, nil
	end
end

local function KeepWithTwin(name, on, resend)
	KeepOne(name, on, resend)
	if DB.linkRaid then
		local twin = ns.RaidTwin(name)
		if twin then KeepOne(twin, on, resend) end
	end
	ns.UpdateKeepTicker()
	Notify(name)
end

function ns.SetKept(name, on) KeepWithTwin(name, on, nil) end

function ns.SetResent(name, on)
	if on and not ns.CanResend(name) then return end
	if on then KeepWithTwin(name, true, true) elseif ns.IsKept(name) then KeepWithTwin(name, true, false) end
end

---------------------------------------------------------------------------
-- Snapshots: every curated, Graphics-category, hidden or currently changed CVar.
---------------------------------------------------------------------------

local function InSnapshotScope(key, e)
	return ns.specs[key] or e.category == "Graphics" or e.hidden or DB.original[key]
end

function ns.SaveSnapshot(label)
	local values = {}
	for key, e in pairs(ns.registry) do
		if InSnapshotScope(key, e) then values[key] = GetCVar(e.name) end
	end
	DB.snapshots[label] = { date = date("%Y-%m-%d %H:%M"), values = values }
end

function ns.LoadSnapshot(label)
	local snap = DB.snapshots[label]
	if not snap then return 0 end
	local n = 0
	for key, value in pairs(snap.values) do
		local e = ns.registry[key]
		if e and not Same(GetCVar(e.name), value) then
			RawSet(e.name, value)
			n = n + 1
		end
	end
	Notify(nil)
	return n
end

function ns.DeleteSnapshot(label) DB.snapshots[label] = nil end
function ns.Snapshots() return DB.snapshots end
function ns.DB() return DB end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local function Reapply()
	for key, value in pairs(DB.applied) do
		local e = ns.registry[key]
		local name = e and e.name or key
		local cur = GetCVar(name)
		if cur ~= nil and not Same(cur, value) then
			writing = true
			pcall(SetCVar, name, value)
			writing = false
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GX_RESTARTED")
f:RegisterEvent("CVAR_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		GraphicsLabDB = GraphicsLabDB or {}
		DB = GraphicsLabDB
		DB.original = DB.original or {}
		DB.applied = DB.applied or {}
		DB.keep = DB.keep or {}
		DB.keepResend = DB.keepResend or {}
		DB.snapshots = DB.snapshots or {}
		if DB.linkRaid == nil then DB.linkRaid = true end
		if DB.reapply == nil then DB.reapply = true end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "GX_RESTARTED" then
		-- Loading screens and graphics restarts are when the game re-applies its own values.
		if DB and next(DB.keep) then
			EnforceAll()
			C_Timer.After(2, EnforceAll)
		end
	elseif event == "PLAYER_LOGIN" then
		BuildRegistry()
		-- Capture the baseline before reapplying overrides, so a recreated
		-- "Before GraphicsLab" snapshot never contains GraphicsLab's own values.
		if not DB.snapshots["Before GraphicsLab"] then
			ns.SaveSnapshot("Before GraphicsLab")
			local values = DB.snapshots["Before GraphicsLab"].values
			for key, value in pairs(DB.original) do values[key] = value end
		end
		if DB.reapply then Reapply() end
		ns.UpdateKeepTicker()
		if not DB.probe or DB.probe.build ~= Build() then
			C_Timer.After(3, function() ns.Probe() end)
		else
			ns.candidates = nil
		end
	elseif event == "CVAR_UPDATE" and not writing and DB and not ns.testActive then
		local key = arg1 and arg1:lower()
		if not key then return end
		if DB.keep[key] ~= nil then
			-- Kept: put it back on the next frame, after whatever changed it has finished.
			C_Timer.After(0, function() Enforce(key) end)
			return
		end
		-- Something else (Blizzard options, another addon) changed a CVar: let that change win.
		if DB.original[key] ~= nil then
			local now = GetCVar(arg1)
			if Same(now, DB.original[key]) then
				DB.original[key], DB.applied[key] = nil, nil
			else
				DB.applied[key] = now
			end
			Notify(arg1)
		end
	end
end)
