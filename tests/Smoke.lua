-- Run from the addon folder: lua5.1 tests/Smoke.lua
-- Loads GraphicsLab against a mocked Forever client (CVars with engine side effects, events,
-- timers, screenshots, interface visibility) and checks: /glab opens on the first try, kept
-- values come back, re-send, and the fog test (sequence, restore, stops, /reload recovery).
-- The whole suite runs twice: CVAR_UPDATE delivered during SetCVar, and delivered a frame later.

local realPrint = print
local assertions = 0
local function check(value, message)
	assertions = assertions + 1
	if not value then error(message, 2) end
end

local ADDON = "GraphicsLab"
local FILES = { "Specs.lua", "Core.lua", "Candidates.lua", "Trace.lua", "FogTest.lua", "UI.lua" }

local function Suite(deferEvents)
	---------------------------------------------------------------------------
	-- Time and timers
	---------------------------------------------------------------------------
	local now, timers, seq = 1000, {}, 0
	local function schedule(delay, fn)
		seq = seq + 1
		timers[#timers + 1] = { at = now + math.max(0, delay), fn = fn, seq = seq }
	end
	local function advance(seconds)
		local target = now + seconds
		while true do
			local idx, best
			for i, t in ipairs(timers) do
				if t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
					idx, best = i, t
				end
			end
			if not best then break end
			table.remove(timers, idx)
			if best.at > now then now = best.at end
			best.fn()
		end
		now = target
	end
	GetTime = function() return now end
	C_Timer = {
		After = function(d, fn) schedule(d, fn) end,
		NewTicker = function(d, fn)
			local t = { cancelled = false }
			local function tick() if not t.cancelled then fn(t); schedule(d, tick) end end
			schedule(d, tick)
			function t:Cancel() self.cancelled = true end
			return t
		end,
		NewTimer = function(d, fn)
			local t = { cancelled = false }
			schedule(d, function() if not t.cancelled then fn(t) end end)
			function t:Cancel() self.cancelled = true end
			return t
		end,
	}
	date = function(fmt) return os.date(fmt, math.floor(now)) end
	time = function() return math.floor(now) end

	---------------------------------------------------------------------------
	-- Frames and events
	---------------------------------------------------------------------------
	local listeners = {}
	local function fire(event, ...)
		for _, f in ipairs(listeners) do
			if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
		end
	end
	local function emit(event, ...)
		if deferEvents then
			local args, n = { ... }, select("#", ...)
			schedule(0, function() fire(event, unpack(args, 1, n)) end)
		else
			fire(event, ...)
		end
	end

	local Universal
	Universal = setmetatable({}, { __index = function() return Universal end, __call = function() return Universal end })
	local allFrames = {}
	local M = {}
	local function NewFrame(kind, name, parent)
		-- Unknown CamelCase keys (API methods, template children) are harmless stubs;
		-- unknown lowercase keys are plain missing fields.
		local f = setmetatable({ kind = kind, scripts = {}, events = {}, shown = true, name = name, parent = parent },
			{ __index = function(_, k)
				if M[k] then return M[k] end
				if type(k) == "string" and k:match("^%u") then return Universal end
			end })
		allFrames[#allFrames + 1] = f
		if name then _G[name] = f end
		return f
	end
	function M:Show() if not self.shown then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
	function M:Hide() if self.shown then self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
	function M:SetShown(v) if v then self:Show() else self:Hide() end end
	function M:IsShown() return self.shown end
	function M:IsVisible() return self.shown end
	local updaters = {}
	function M:SetScript(k, fn)
		self.scripts[k] = fn
		if k == "OnUpdate" and fn then updaters[#updaters + 1] = self end
	end
	function M:GetScript(k) return self.scripts[k] end
	function M:HookScript(k, fn)
		local old = self.scripts[k]
		self.scripts[k] = function(...) if old then old(...) end fn(...) end
	end
	function M:RegisterEvent(e)
		self.events[e] = true
		if not self.listening then self.listening = true; listeners[#listeners + 1] = self end
	end
	function M:UnregisterEvent(e) self.events[e] = nil end
	function M:SetText(t) self.text = t end
	function M:GetText() return self.text or "" end
	function M:SetChecked(v) self.checked = v and true or false end
	function M:GetChecked() return self.checked end
	function M:HasFocus() return false end
	function M:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
	function M:CreateFontString() return NewFrame("FontString") end
	function M:CreateTexture() return NewFrame("Texture") end
	function M:EnableKeyboard(v) self.keyboard = v end
	function M:SetPropagateKeyboardInput(v) self.propagate = v end
	function M:GetParent() return self.parent end
	function M:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
	function M:GetValue() return self.value end
	CreateFrame = function(kind, name, parent) return NewFrame(kind, name, parent) end
	-- A 60 fps frame loop for OnUpdate scripts.
	local frames = 0
	local function frameTick()
		frames = frames + 1
		for _, f in ipairs(updaters) do
			if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1 / 60) end
		end
		schedule(1 / 60, frameTick)
	end
	schedule(1 / 60, frameTick)
	function GetFramerate() return 60 end
	UIParent = NewFrame("Frame", "UIParent")
	WorldFrame = NewFrame("Frame", "WorldFrame")
	GameTooltip = NewFrame("GameTooltip", "GameTooltip")
	function GameTooltip_Hide() end

	---------------------------------------------------------------------------
	-- CVars with engine side effects
	---------------------------------------------------------------------------
	local CATEGORY_ID = { Graphics = 1, Game = 4, Default = 5, Sound = 7 }
	local cvarList = {
		{ "volumeFog", "1", "Graphics" }, { "RAIDVolumeFog", "1", "Graphics" },
		{ "volumeFogLevel", "3", "Graphics" }, { "RAIDVolumeFogLevel", "3", "Graphics" },
		{ "volumeFogInterior", "1", "Graphics" }, { "gxMTVolFog", "1", "Graphics" },
		{ "horizonStart", "2400", "Default" }, { "RAIDhorizonStart", "1900", "Default" },
		{ "horizonClip", "8000", "Default" }, { "RAIDhorizonClip", "7000", "Default" },
		{ "farclip", "8000", "Default" }, { "RAIDfarclip", "7000", "Default" },
		{ "disableHorizonStart", "0", "Graphics" }, { "nearclip", "0.2", "Graphics" },
		{ "graphicsViewDistance", "7", "Default" }, { "raidGraphicsViewDistance", "6", "Default" },
		{ "graphicsComputeEffects", "3", "Default" }, { "raidGraphicsComputeEffects", "3", "Default" },
		{ "graphicsLightMode", "1", "Default" }, { "raidGraphicsLightMode", "2", "Default" },
		{ "graphicsQuality", "8", "Default" }, { "RAIDsettingsEnabled", "0", "Graphics" },
		{ "sunShafts", "2", "Default" }, { "RAIDsunShafts", "2", "Default" },
		{ "particulatesEnabled", "1", "Graphics" }, { "RAIDParticulatesEnabled", "1", "Graphics" },
		{ "particleDensity", "80", "Graphics" }, { "weatherDensity", "3", "Default" }, { "RAIDweatherDensity", "3", "Default" },
		{ "SkyCloudLOD", "0", "Graphics" }, { "ffxGlow", "1", "Graphics" }, { "bloomEnable", "0", "Graphics" }, { "bloomUserMult", "1", "Graphics" },
		{ "Contrast", "51", "Default" }, { "Gamma", "1", "Default" },
		{ "cameraSavedDistance", "8.0", "Game" }, { "Sound_MasterVolume", "1.0", "Sound" },
		{ "groundEffectDensity", "48", "Default" }, { "groundEffectDist", "320", "Default" }, { "groundEffectFade", "70", "Graphics" },
		{ "RAIDgroundEffectDensity", "48", "Default" }, { "RAIDgroundEffectDist", "200", "Default" }, { "RAIDgroundEffectFade", "70", "Graphics" },
	}
	local cvars, defaults, category = {}, {}, {}
	for _, c in ipairs(cvarList) do cvars[c[1]], defaults[c[1]], category[c[1]] = c[2], c[2], c[3] end
	local writes = {}
	local function set(name, value)
		if cvars[name] == nil then return false end
		value = tostring(value)
		if name == "farclip" and tonumber(value) and tonumber(value) > 10000 then value = "10000" end
		local changed = cvars[name] ~= value
		cvars[name] = value
		writes[#writes + 1] = name .. "=" .. value
		if changed then emit("CVAR_UPDATE", name, value) end
		if name == "graphicsViewDistance" then
			local level = tonumber(value) + 1
			set("farclip", tostring(level * 1000))
			set("horizonStart", tostring(level * 300))
			set("horizonClip", tostring(level * 1000))
		elseif name == "graphicsComputeEffects" then
			set("volumeFogLevel", value)
		end
		return true
	end
	-- An engine-side change that fires no event.
	local function silent(name, value) cvars[name] = tostring(value) end
	C_CVar = {
		GetCVar = function(name) return cvars[name] end,
		SetCVar = function(name, value) return set(name, value) end,
		GetCVarInfo = function(name) return cvars[name], defaults[name] end,
		GetCVarDefault = function(name) return defaults[name] end,
	}
	SetCVar = function(name, value) return C_CVar.SetCVar(name, value) end
	ConsoleGetAllCommands = function()
		local out = {}
		for _, c in ipairs(cvarList) do
			out[#out + 1] = { command = c[1], commandType = 0, category = CATEGORY_ID[c[3]], help = "" }
		end
		return out
	end

	---------------------------------------------------------------------------
	-- Client
	---------------------------------------------------------------------------
	local printed, popups, shots = {}, {}, 0
	local speed, combat, uiWorld, reloads = 0, false, true, 0
	print = function(msg) printed[#printed + 1] = msg end
	GetBuildInfo = function() return "1.60.1", "70009", "Sep 24 2026", 16001 end
	debugstack = function() return "" end
	hooksecurefunc = function(a, b, c)
		local tbl, key, fn = a, b, c
		if type(a) == "string" then tbl, key, fn = _G, a, b end
		local orig = tbl[key]
		tbl[key] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
	end
	ConsoleExec = nil
	function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	function wipe(t) for k in pairs(t) do t[k] = nil end return t end
	function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
	tinsert = table.insert
	UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
	function StaticPopup_Show(which, a1, a2, data) popups[#popups + 1] = { which = which, a1 = a1, data = data } end
	MenuUtil = Universal
	YES, NO, SAVE, CANCEL, DELETE = "Yes", "No", "Save", "Cancel", "Delete"
	function InCombatLockdown() return combat end
	function GetUnitSpeed() return speed end
	function IsFalling() return false end
	function UnitOnTaxi() return false end
	function IsIndoors() return false end
	function GetRealZoneText() return "Elwynn Forest" end
	function GetSubZoneText() return "Goldshire" end
	function GetGameTime() return 12, 30 end
	C_Map = { GetBestMapForUnit = function() return 1429 end }
	C_UI = { Reload = function() reloads = reloads + 1 end }
	function Screenshot()
		shots = shots + 1
		schedule(0.15, function() fire("SCREENSHOT_SUCCEEDED") end)
	end
	function SetUIVisibility(v) UIParent.shown = v end
	function SetInWorldUIVisibility(v) uiWorld = v end

	local ns
	local function Load()
		listeners = {}
		ns = {}
		for _, file in ipairs(FILES) do assert(loadfile(file))(ADDON, ns) end
		fire("ADDON_LOADED", ADDON)
		fire("PLAYER_LOGIN")
		fire("PLAYER_ENTERING_WORLD")
		advance(10) -- hidden-CVar probe runs 3 s after login
	end
	local function snapshot() local t = {} for k, v in pairs(cvars) do t[k] = v end return t end
	local function same(a, b)
		for k, v in pairs(a) do if b[k] ~= v then return false, k .. " is " .. tostring(b[k]) .. ", expected " .. v end end
		return true
	end
	local function lastPrint() return printed[#printed] or "" end

	GraphicsLabDB = nil
	Load()
	local mode = deferEvents and "deferred events" or "immediate events"
	check(ns.DB().probe and #ns.DB().probe.names == 0, mode .. ": probe finds no hidden CVars in the mock")

	---------------------------------------------------------------------------
	-- /glab opens on the first try
	---------------------------------------------------------------------------
	SlashCmdList.GRAPHICSLAB("")
	check(GraphicsLabFrame and GraphicsLabFrame:IsShown(), mode .. ": the first /glab opens the window")
	check((GraphicsLabFrame.itemCount or 0) > 0, mode .. ": opening renders the rows")
	SlashCmdList.GRAPHICSLAB("")
	check(not GraphicsLabFrame:IsShown(), mode .. ": the second /glab closes it")
	SlashCmdList.GRAPHICSLAB("")
	check(GraphicsLabFrame:IsShown(), mode .. ": the third /glab opens it again")

	---------------------------------------------------------------------------
	-- Ground clutter: presets past the game's slider, raid copies, game-max tag
	---------------------------------------------------------------------------
	local clutterNav
	for _, fr in ipairs(allFrames) do if fr.key == "clutter" and fr.scripts.OnClick then clutterNav = fr end end
	check(clutterNav, mode .. ": Ground Clutter category in the navigation")
	clutterNav.scripts.OnClick(clutterNav)
	local function PresetButton(label)
		for _, fr in ipairs(allFrames) do
			if fr.preset and fr.preset[1] == label and fr.shown then return fr end
		end
	end
	local fuller = PresetButton("Fuller")
	check(fuller, mode .. ": Fuller preset button shown")
	fuller.scripts.OnClick(fuller)
	advance(0.05)
	check(cvars.groundEffectDensity == "256" and cvars.groundEffectDist == "500" and cvars.groundEffectFade == "370",
		mode .. ": Fuller writes 256 / 500 / 370")
	check(cvars.RAIDgroundEffectDensity == "256" and cvars.RAIDgroundEffectDist == "500", mode .. ": linked raid copies follow the preset")
	check(fuller.wash.shown, mode .. ": the active preset is highlighted")
	local beyond = false
	for _, fr in ipairs(allFrames) do
		if fr.text and tostring(fr.text):find("groundEffectDensity", 1, true) and tostring(fr.text):find("beyond game", 1, true) then beyond = true end
	end
	check(beyond, mode .. ": density row says it is beyond the game's slider")
	check(ns.specs.groundeffectdensity.kind == "range", mode .. ": the preset row never replaces the density slider spec")
	local gameMax = PresetButton("Game max")
	gameMax.scripts.OnClick(gameMax)
	advance(0.05)
	check(cvars.groundEffectDensity == "48" and cvars.groundEffectDist == "320" and cvars.groundEffectFade == "70", mode .. ": Game max returns to the slider's top")
	check(gameMax.wash.shown and not fuller.wash.shown, mode .. ": highlight follows the matching preset")

	---------------------------------------------------------------------------
	-- Keep my value
	---------------------------------------------------------------------------
	ns.Set("horizonStart", "5000")
	check(cvars.horizonStart == "5000" and cvars.RAIDhorizonStart == "5000", mode .. ": linked raid copy set")
	ns.SetKept("horizonStart", true)
	check(ns.IsKept("horizonStart") and ns.IsKept("RAIDhorizonStart"), mode .. ": keep covers the raid copy")
	C_CVar.SetCVar("horizonStart", "800")
	advance(0.05)
	check(cvars.horizonStart == "5000", mode .. ": kept value comes back after an outside change")
	check(lastPrint():find("kept horizonStart at 5000", 1, true), mode .. ": tells once that it kept the value")
	local told = #printed
	C_CVar.SetCVar("horizonStart", "700")
	advance(0.05)
	check(cvars.horizonStart == "5000" and #printed == told, mode .. ": tells only once per session")
	silent("horizonStart", "900")
	advance(1.05)
	check(cvars.horizonStart == "5000", mode .. ": the 1 s check catches changes without an event")
	silent("RAIDhorizonStart", "100")
	fire("PLAYER_ENTERING_WORLD")
	check(cvars.RAIDhorizonStart == "5000", mode .. ": loading screens put kept values back")
	ns.Set("horizonStart", "6000")
	advance(1.05)
	check(cvars.horizonStart == "6000" and ns.DB().keep.horizonstart == "6000", mode .. ": keep follows GraphicsLab changes")
	check(ns.DB().original.horizonstart == "2400", mode .. ": the original stays the pre-GraphicsLab value")

	check(not ns.CanResend("volumeFog") and ns.CanResend("horizonStart"), mode .. ": only sliders can be re-sent")
	ns.Set("horizonStart", "7000")
	ns.SetResent("horizonStart", true)
	check(ns.IsKept("horizonStart") and ns.IsResent("horizonStart"), mode .. ": re-send implies keep")
	local mark = #writes
	advance(1.05)
	local sawNudge, sawBack = false, false
	for i = mark + 1, #writes do
		if writes[i] == "horizonStart=7000.001" then sawNudge = true end
		if sawNudge and writes[i] == "horizonStart=7000" then sawBack = true end
	end
	check(sawNudge and sawBack and cvars.horizonStart == "7000", mode .. ": re-send nudges then restores the value")
	ns.SetResent("horizonStart", false)
	check(ns.IsKept("horizonStart") and not ns.IsResent("horizonStart"), mode .. ": turning re-send off still keeps")
	ns.SetKept("horizonStart", false)
	check(not ns.IsKept("horizonStart") and not ns.IsKept("RAIDhorizonStart"), mode .. ": unkeep clears both copies")

	-- Storm guard: the game fighting back every frame.
	ns.Set("farclip", "9000")
	ns.SetKept("farclip", true)
	for i = 1, 25 do
		C_CVar.SetCVar("farclip", tostring(4000 + i))
		advance(0.05)
	end
	check(not ns.IsKept("farclip"), mode .. ": stops keeping a value the game keeps changing")
	check(ns.IsKept("RAIDfarclip"), mode .. ": the raid copy keeps its own count")
	ns.SetKept("RAIDfarclip", false)

	---------------------------------------------------------------------------
	-- Trace sees GraphicsLab's own writes
	---------------------------------------------------------------------------
	ns.ToggleTrace()
	ns.Set("nearclip", "0.3")
	local traced = false
	for _, line in ipairs(ns.DB().trace) do if line:find("GraphicsLab set nearclip = 0.3", 1, true) then traced = true end end
	check(traced, mode .. ": trace logs GraphicsLab's own writes")
	ns.ToggleTrace()
	ns.ClearTrace()

	---------------------------------------------------------------------------
	-- Fog test: quick run end to end
	---------------------------------------------------------------------------
	-- Make the baseline differ from the view-distance preset so restore order matters.
	ns.Set("volumeFogLevel", "4")
	local base = snapshot()
	SlashCmdList.GRAPHICSLAB("fogtest quick")
	check(popups[#popups].which == "GRAPHICSLAB_FOGTEST" and popups[#popups].data == "quick", mode .. ": /glab fogtest quick asks first")
	StaticPopupDialogs.GRAPHICSLAB_FOGTEST.OnAccept(nil, popups[#popups].data)
	advance(0.35)
	check(ns.FogTestRunning() and ns.testActive, mode .. ": test started after the popup closed")
	advance(1.5)
	check(not UIParent:IsShown() and uiWorld == false, mode .. ": interface hidden during the test")
	local keptBefore = cvars.horizonStart
	advance(200)
	check(not ns.FogTestRunning(), mode .. ": quick test finishes")
	check(UIParent:IsShown() and uiWorld == true, mode .. ": interface shown again")
	local ok, why = same(base, cvars)
	check(ok, mode .. ": every setting is back after the test (" .. tostring(why) .. ")")
	check(cvars.horizonStart == keptBefore, mode .. ": kept value untouched by the test")
	local rec = GraphicsLabDB.fogtest
	check(rec.finished and not rec.stopped and not rec.running and rec.restore == nil, mode .. ": record closed cleanly")
	local done, skipped = 0, 0
	for _, line in ipairs(rec.cases) do
		if line:find("|done|", 1, true) then done = done + 1 elseif line:find("|skipped", 1, true) then skipped = skipped + 1 end
	end
	check(done >= 7 and done + skipped == 8, mode .. ": quick test runs its 8 cases (" .. done .. " done)")
	check(#rec.shots == 2 + 3 * done, mode .. ": 2 start shots plus base/A/B per case (" .. #rec.shots .. ")")
	check(shots == #rec.shots, mode .. ": one screenshot call per recorded shot")
	local stamps = {}
	for _, line in ipairs(rec.shots) do
		local stamp = line:match("^%d+|[^|]+|[^|]+|([^|]+)|")
		check(stamp ~= "failed", mode .. ": no failed shots")
		check(not stamps[stamp], mode .. ": no two screenshots share a file name second (" .. stamp .. ")")
		stamps[stamp] = true
	end
	local sawPreset, sawClamp, sawCompute = false, false, false
	for _, line in ipairs(rec.changes) do
		if line:match("^viewdist_10|farclip|[%d.]+|10000$") then sawPreset = true end
		if line == "compute_0|volumeFogLevel|4|0" then sawCompute = true end
	end
	for _, line in ipairs(rec.cases) do
		if line:find("farclip_1000|", 1, true) == 1 and line:find("farclip=1000>1000", 1, true) then sawClamp = true end
	end
	check(sawPreset, mode .. ": side effects of the view distance slider are logged")
	check(sawCompute, mode .. ": side effects of compute effects are logged")
	check(sawClamp, mode .. ": requested and stored values are logged")
	check(lastPrint():find("fog test finished", 1, true), mode .. ": prints the result")
	check(popups[#popups].which == "GRAPHICSLAB_FOGTEST_DONE", mode .. ": offers a reload to save the results")
	advance(1)
	check(not ns.testActive, mode .. ": change tracking resumes after the test")
	StaticPopupDialogs.GRAPHICSLAB_FOGTEST_DONE.OnAccept()
	check(reloads == 1, mode .. ": the done popup reloads")

	-- Outside changes are tracked again afterwards.
	C_CVar.SetCVar("volumeFogLevel", "2")
	advance(0.05)
	check(ns.DB().applied.volumefoglevel == "2", mode .. ": outside changes win again after the test")
	ns.Set("volumeFogLevel", "4")

	---------------------------------------------------------------------------
	-- Fog test: the "more" set (ways to add haze)
	---------------------------------------------------------------------------
	base = snapshot()
	SlashCmdList.GRAPHICSLAB("fogtest more")
	check(popups[#popups].data == "more", mode .. ": /glab fogtest more asks first")
	StaticPopupDialogs.GRAPHICSLAB_FOGTEST.OnAccept(nil, "more")
	advance(150)
	check(not ns.FogTestRunning(), mode .. ": the more set finishes")
	local okMore, whyMore = same(base, cvars)
	check(okMore, mode .. ": every setting is back after the more set (" .. tostring(whyMore) .. ")")
	rec = GraphicsLabDB.fogtest
	check(rec.mode == "more" and not rec.stopped, mode .. ": more set recorded")
	local doneMore = 0
	for _, line in ipairs(rec.cases) do if line:find("|done|", 1, true) then doneMore = doneMore + 1 end end
	check(doneMore == #ns.fogTestMore, mode .. ": all " .. #ns.fogTestMore .. " extra cases ran (" .. doneMore .. ")")
	local combo = false
	for _, line in ipairs(rec.cases) do
		if line:find("hstart_300_bloom|", 1, true) == 1 and line:find("horizonStart=300>300;bloomEnable=1>1", 1, true) then combo = true end
	end
	check(combo, mode .. ": the combination case sets both settings")
	check(rec.shots[1]:match("|60%.0$"), mode .. ": shots record the frame rate")
	advance(1)
	check(not ns.testActive, mode .. ": tracking resumes after the more set")

	---------------------------------------------------------------------------
	-- Fog test: stops
	---------------------------------------------------------------------------
	local function startFull()
		base = snapshot()
		ns.StartFogTest("full")
		advance(9)
		check(ns.FogTestRunning(), mode .. ": full test running")
	end
	local function checkStopped(reason)
		check(not ns.FogTestRunning(), mode .. ": stopped by " .. reason)
		check(UIParent:IsShown(), mode .. ": interface back after " .. reason)
		local ok2, why2 = same(base, cvars)
		check(ok2, mode .. ": settings back after " .. reason .. " (" .. tostring(why2) .. ")")
		check(GraphicsLabDB.fogtest.stopped == reason, mode .. ": stop reason recorded: " .. tostring(GraphicsLabDB.fogtest.stopped))
		advance(1)
		check(not ns.testActive, mode .. ": tracking resumes after " .. reason)
	end

	startFull()
	fire("PLAYER_REGEN_DISABLED")
	checkStopped("combat started")

	startFull()
	local catcher
	for _, f in ipairs(allFrames) do if f.parent == WorldFrame and f.scripts.OnKeyDown then catcher = f end end
	check(catcher and catcher.keyboard and catcher.propagate, mode .. ": key watcher active and passing keys on")
	catcher.scripts.OnKeyDown(catcher, "W")
	checkStopped("a key was pressed")
	check(not catcher.keyboard, mode .. ": key watcher off afterwards")

	startFull()
	speed = 7
	advance(0.3)
	speed = 0
	checkStopped("you moved")

	startFull()
	SlashCmdList.GRAPHICSLAB("fogtest stop")
	checkStopped("stopped by you")

	combat = true
	ns.StartFogTest("full")
	check(not ns.FogTestRunning() and lastPrint():find("combat", 1, true), mode .. ": refuses to start in combat")
	combat = false

	---------------------------------------------------------------------------
	-- Fog test: /reload in the middle puts things back at the next login
	---------------------------------------------------------------------------
	base = snapshot()
	ns.StartFogTest("full")
	-- Run until a case has changed something.
	local changedNow = false
	for _ = 1, 400 do
		advance(0.1)
		if not same(base, cvars) then changedNow = true; break end
	end
	check(changedNow, mode .. ": a case changed a setting")
	check(GraphicsLabDB.fogtest.running and next(GraphicsLabDB.fogtest.restore), mode .. ": restore list saved while running")
	-- The reload: old timers and frames are gone, the interface comes back, the addon loads again.
	timers = {}
	updaters = {}
	schedule(1 / 60, frameTick)
	UIParent.shown = true
	Load()
	local ok3, why3 = same(base, cvars)
	check(ok3, mode .. ": a /reload mid-test puts the changed settings back (" .. tostring(why3) .. ")")
	check(GraphicsLabDB.fogtest.stopped == "interrupted by a reload" and not GraphicsLabDB.fogtest.running, mode .. ": interrupted run recorded")
	check(uiWorld == true, mode .. ": in-world interface shown again after the reload")

	---------------------------------------------------------------------------
	-- Restore originals clears keeps
	---------------------------------------------------------------------------
	ns.SetKept("horizonStart", true)
	ns.RestoreAll()
	check(not ns.IsKept("horizonStart") and ns.KeptCount() == 0, mode .. ": restore originals stops keeping")
	check(cvars.horizonStart == "2400" and cvars.volumeFogLevel == "3", mode .. ": restore originals restores values")
end

Suite(false)
Suite(true)
realPrint(("GraphicsLab smoke: %d checks passed"):format(assertions))
