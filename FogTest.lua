-- /glab fogtest: measures which settings really change the fog here, instead of guessing.
-- It hides the interface, changes one setting at a time, takes a screenshot soon after the
-- change (A) and again a few seconds later (B), puts everything back, and takes a baseline shot
-- before the next setting. StorageInvestigation\fog-test\analyze_fogtest.py compares the shots.
--
-- Test sets: full (/glab fogtest), quick (a subset), more (ways to add haze: horizon start
-- steps, bloom, contrast, gamma; added after the first run showed horizon start holds).
--
-- GraphicsLabDB.fogtest (the last run):
--   version, build, started, finished, stopped (reason, nil when it ran to the end), mode
--   zone, subzone, mapID, indoors, gameTime, raidSettings
--   cases   = { "key|label|status|cvar=requested>stored;..." }  status: done, skipped:<why>
--   shots   = { "n|caseKey|tag|stamp|epoch|fps" }  tag: base, A, B; stamp = MMDDYY_HHMMSS or "failed"
--   changes = { "caseKey|cvar|before|after" }  everything a case changed, side effects included
--   restore = { [cvar] = value }  only while running, so a /reload mid-test can put things back
--   running = true while a test is in progress

local _, ns = ...

local A_DELAY, HOLD = 0.45, 4          -- A shot soon after the change; B shot this long after it
local SETTLE, SETTLE_SLOW = 1.3, 2.5   -- wait after putting things back (view distance needs longer)
local MIN_GAP = 1.15                   -- screenshot file names have 1 s resolution: never share one
local SHOT_TIMEOUT = 6
local RESTORE_PASSES = 4

local function NearHorizonClip(base)
	return tostring(math.floor((tonumber(base.horizonclip) or 8000) * 0.95))
end

-- Each case changes its settings in order. A value may be a function of the baseline values.
-- quick = part of "/glab fogtest quick". slow = changes view distance, so waits longer after.
-- resend = seconds between re-sends while holding.
local CASES = {
	{ key = "volfog_off", label = "Volumetric fog off", quick = true, set = { { "volumeFog", "0" } } },
	{ key = "volfog_q0", label = "Volumetric fog quality 0", quick = true, set = { { "volumeFogLevel", "0" } } },
	{ key = "volfog_q1", label = "Volumetric fog quality 1", set = { { "volumeFogLevel", "1" } } },
	{ key = "volfog_q4", label = "Volumetric fog quality 4", set = { { "volumeFogLevel", "4" } } },
	{ key = "compute_0", label = "Compute effects off", quick = true, set = { { "graphicsComputeEffects", "0" } } },
	{ key = "volfog_indoors", label = "Volumetric fog indoors off", indoors = true, set = { { "volumeFogInterior", "0" } } },
	{ key = "sunshafts_0", label = "Sun shafts off", set = { { "sunShafts", "0" } } },
	{ key = "particulates_0", label = "Particulates off", set = { { "particulatesEnabled", "0" } } },
	{ key = "particles_10", label = "Particle density 10", set = { { "particleDensity", "10" } } },
	{ key = "weather_0", label = "Weather off", set = { { "weatherDensity", "0" } } },
	{ key = "lightmode_0", label = "Lighting mode Fair", set = { { "graphicsLightMode", "0" } } },
	{ key = "lightmode_2", label = "Lighting mode High", set = { { "graphicsLightMode", "2" } } },
	{ key = "hstart_300", label = "Horizon start 300", quick = true, set = { { "horizonStart", "300" } } },
	{ key = "hstart_300_resend", label = "Horizon start 300, re-sent every 0.5 s", resend = 0.5, set = { { "horizonStart", "300" } } },
	{ key = "hstart_far", label = "Horizon start next to horizon clip", quick = true, set = { { "horizonStart", NearHorizonClip } } },
	{ key = "fullfog_off", label = "Full-fog distance off", quick = true, set = { { "disableHorizonStart", "1" } } },
	{ key = "hclip_1500", label = "Horizon clip 1500", slow = true, set = { { "horizonClip", "1500" } } },
	{ key = "farclip_1000", label = "Far clip 1000", quick = true, slow = true, set = { { "farclip", "1000" } } },
	{ key = "farclip_16000", label = "Far clip 16000", slow = true, set = { { "farclip", "16000" }, { "horizonClip", "16000" } } },
	{ key = "viewdist_1", label = "View distance 1 (Blizzard slider)", slow = true, set = { { "graphicsViewDistance", "0" } } },
	{ key = "viewdist_10", label = "View distance 10 (Blizzard slider)", quick = true, slow = true, set = { { "graphicsViewDistance", "9" } } },
}

-- Ways to make it hazier: horizon start steps (to scale a fog slider), glow and image settings,
-- and one combination to see whether they add up.
local MORE = {
	{ key = "hstart_50", label = "Horizon start 50", set = { { "horizonStart", "50" } } },
	{ key = "hstart_150", label = "Horizon start 150", set = { { "horizonStart", "150" } } },
	{ key = "hstart_600", label = "Horizon start 600", set = { { "horizonStart", "600" } } },
	{ key = "hstart_1200", label = "Horizon start 1200", set = { { "horizonStart", "1200" } } },
	{ key = "bloom_1", label = "Bloom on", set = { { "bloomEnable", "1" } } },
	{ key = "bloom_3", label = "Bloom on, intensity 3", set = { { "bloomEnable", "1" }, { "bloomUserMult", "3" } } },
	{ key = "contrast_35", label = "Contrast 35", set = { { "Contrast", "35" } } },
	{ key = "gamma_13", label = "Gamma 1.3", set = { { "Gamma", "1.3" } } },
	{ key = "hstart_300_bloom", label = "Horizon start 300 with bloom on", set = { { "horizonStart", "300" }, { "bloomEnable", "1" } } },
}

local function CasesFor(mode)
	if mode == "more" then return MORE end
	local list = {}
	for _, c in ipairs(CASES) do
		if mode ~= "quick" or c.quick then list[#list + 1] = c end
	end
	return list
end
ns.fogTestCases = CASES
ns.fogTestMore = MORE

local run        -- the test in progress
local catcher    -- keyboard watcher; parented to WorldFrame so it still works with the UI hidden
local watcher    -- movement / interface watcher

---------------------------------------------------------------------------
-- Settings: baseline, differences, putting things back
---------------------------------------------------------------------------

-- Graphics-type settings only: game, sound and network settings can change on their own and
-- must never be "put back".
local SCOPE = { Graphics = true, Default = true, Hidden = true }

local function Capture()
	local values = {}
	for key, e in pairs(ns.registry) do
		if SCOPE[e.category] or ns.specs[key] then values[key] = C_CVar.GetCVar(e.name) end
	end
	return values
end

-- Blizzard's combined settings rewrite their sub-settings, so they go back first:
-- overall quality, then the other graphics* sliders, then everything else.
local function Priority(key)
	if key == "graphicsquality" or key == "raidgraphicsquality" then return 0 end
	if key:find("^graphics") or key:find("^raidgraphics") then return 1 end
	return 2
end

local function Diff(baseline)
	local out = {}
	for key, value in pairs(baseline) do
		local e = ns.registry[key]
		local name = e and e.name or key
		local cur = C_CVar.GetCVar(name)
		if cur ~= nil and not ns.Same(cur, value) then
			out[#out + 1] = { key = key, name = name, base = value, now = cur }
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = Priority(a.key), Priority(b.key)
		if pa ~= pb then return pa < pb end
		return a.key < b.key
	end)
	return out
end

-- Remember what to put back if the test is cut short by a /reload.
local function NoteForRestore(r)
	for _, d in ipairs(Diff(r.baseline)) do
		if r.rec.restore[d.name] == nil then r.rec.restore[d.name] = d.base end
	end
end

local function PutBack(r, caseKey)
	local logged = false
	for _ = 1, RESTORE_PASSES do
		local diff = Diff(r.baseline)
		if #diff == 0 then return true end
		if caseKey and not logged then
			logged = true
			for _, d in ipairs(diff) do
				r.rec.changes[#r.rec.changes + 1] = ("%s|%s|%s|%s"):format(caseKey, d.name, d.base, d.now)
			end
		end
		for _, d in ipairs(diff) do
			if not ns.Same(C_CVar.GetCVar(d.name), d.base) then ns.WriteUntracked(d.name, d.base) end
		end
	end
	local left = Diff(r.baseline)
	for _, d in ipairs(left) do
		ns.Print("could not put %s back to %s (it is %s).", d.name, d.base, d.now)
	end
	return #left == 0
end

---------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------

local function HideUI(r)
	if UIParent:IsShown() then
		pcall(SetUIVisibility, false)
		r.uiHidden = not UIParent:IsShown()
	end
	if SetInWorldUIVisibility then r.inWorldHidden = pcall(SetInWorldUIVisibility, false) end
end

local function ShowUI(r)
	if r.inWorldHidden then pcall(SetInWorldUIVisibility, true) end
	if r.uiHidden and not UIParent:IsShown() then pcall(SetUIVisibility, true) end
end

local function Moving()
	return (GetUnitSpeed("player") or 0) > 0 or IsFalling() or UnitOnTaxi("player")
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

local Finish

local function Resume()
	local r = run
	if not r then return end
	r.token = nil
	local ok, err = coroutine.resume(r.co)
	if run ~= r then return end
	if not ok then
		Finish("error: " .. tostring(err))
	elseif coroutine.status(r.co) == "dead" then
		Finish(r.stopReason)
	end
end

-- Only inside the test coroutine.
local function Sleep(seconds)
	local r = run
	local token = {}
	r.token = token
	C_Timer.After(math.max(0, seconds), function()
		if run == r and r.token == token then Resume() end
	end)
	coroutine.yield()
end

local function SleepUntil(t)
	local left = t - GetTime()
	if left > 0 then Sleep(left) end
end

local function Shot(caseKey, tag)
	local r = run
	SleepUntil(r.lastShot + MIN_GAP)
	r.shotResult, r.shotStamp, r.shotEpoch, r.expectShot = nil, nil, nil, true
	local epoch = time()
	Screenshot()
	if r.shotResult == nil then
		r.waitingShot = true
		local token = {}
		r.token = token
		C_Timer.After(SHOT_TIMEOUT, function()
			if run == r and r.token == token then
				r.shotResult = "timeout"
				Resume()
			end
		end)
		coroutine.yield()
	end
	r.expectShot, r.waitingShot = false, false
	r.lastShot = GetTime()
	r.count = r.count + 1
	local stamp = r.shotResult == "ok" and r.shotStamp or "failed"
	r.rec.shots[#r.rec.shots + 1] = ("%d|%s|%s|%s|%d|%.1f"):format(r.count, caseKey, tag, stamp,
		r.shotEpoch or epoch, GetFramerate() or 0)
	if r.shotResult == "ok" then r.good = r.good + 1 end
end

local function OnShotEvent(ok)
	local r = run
	if not r or not r.expectShot or r.shotResult ~= nil then return end
	r.shotResult = ok and "ok" or "failed"
	r.shotStamp, r.shotEpoch = date("%m%d%y_%H%M%S"), time()
	if r.waitingShot and coroutine.status(r.co) == "suspended" then
		r.waitingShot = false
		Resume()
	end
end

local function Writes(r, case)
	local base, writes = r.baseline, {}
	local function add(name, value)
		local b = base[name:lower()]
		if b ~= nil and not ns.Same(b, value) then writes[#writes + 1] = { name, value } end
	end
	for _, pair in ipairs(case.set) do
		local value = pair[2]
		if type(value) == "function" then value = value(base) end
		local entry = ns.Lookup(pair[1])
		if entry then
			add(entry.name, value)
			-- The RAID copies only apply when raid settings are switched on.
			if r.raid then
				local twin = ns.RaidTwin(entry.name)
				if twin then add(twin, value) end
			end
		end
	end
	return writes
end

local function RunCase(r, case)
	if case.indoors and not IsIndoors() then return "skipped:outdoors" end
	local writes = Writes(r, case)
	if #writes == 0 then return "skipped:already set or missing" end
	-- Start so the A shot lands just after the minimum gap since the last shot.
	SleepUntil(r.lastShot + MIN_GAP - A_DELAY)
	local parts = {}
	for _, w in ipairs(writes) do
		r.rec.restore[w[1]] = r.rec.restore[w[1]] or r.baseline[w[1]:lower()]
		ns.WriteUntracked(w[1], w[2])
		parts[#parts + 1] = ("%s=%s>%s"):format(w[1], w[2], tostring(C_CVar.GetCVar(w[1])))
	end
	NoteForRestore(r)
	local t0 = GetTime()
	Sleep(A_DELAY)
	Shot(case.key, "A")
	while not r.stopReason and GetTime() < t0 + HOLD - 0.01 do
		local left = t0 + HOLD - GetTime()
		Sleep(case.resend and math.min(case.resend, left) or left)
		if case.resend then
			for _, w in ipairs(writes) do ns.Resend(w[1], w[2]) end
		end
	end
	Shot(case.key, "B")
	PutBack(r, case.key)
	Sleep(case.slow and SETTLE_SLOW or SETTLE)
	Shot(case.key, "base")
	return "done", table.concat(parts, ";")
end

local function Body()
	local r = run
	HideUI(r)
	Sleep(1)
	Shot("start", "base")
	Shot("start", "base")
	for _, case in ipairs(r.cases) do
		if r.stopReason then return end
		local status, parts = RunCase(r, case)
		r.rec.cases[#r.rec.cases + 1] = ("%s|%s|%s|%s"):format(case.key, case.label, status, parts or "")
	end
end

function Finish(reason)
	local r = run
	if not r then return end
	run = nil
	if watcher then watcher:Cancel(); watcher = nil end
	catcher:EnableKeyboard(false)
	catcher:Hide()
	local clean = PutBack(r)
	ShowUI(r)
	local rec = r.rec
	rec.running, rec.restore = nil, nil
	rec.finished = date("%Y-%m-%d %H:%M:%S")
	rec.stopped = reason
	-- Late change events from the restore should not count as outside changes.
	C_Timer.After(0.5, function() if not run then ns.testActive = false end end)
	local seconds = math.floor(GetTime() - r.startedAt + 0.5)
	if reason then
		ns.Print("fog test stopped (%s) after %d screenshots. Settings are back.", reason, r.good)
	else
		ns.Print("fog test finished: %d screenshots in %d seconds. Settings are back%s.",
			r.good, seconds, clean and "" or ", except the ones listed above")
		StaticPopup_Show("GRAPHICSLAB_FOGTEST_DONE", r.good)
	end
	if ns.Render then ns.Render() end
end

local function Stop(reason)
	if not run then return end
	run.stopReason = reason
	Finish(reason)
end
ns.StopFogTest = function() Stop("stopped by you") end
function ns.FogTestRunning() return run ~= nil end

-- mode: "full" (default), "quick" or "more".
function ns.EstimateFogTest(mode)
	local seconds = 3
	for _, c in ipairs(CasesFor(mode)) do
		seconds = seconds + A_DELAY + HOLD + (c.slow and SETTLE_SLOW or SETTLE) + 1
	end
	return math.floor(seconds + 0.5)
end

function ns.StartFogTest(mode)
	mode = mode or "full"
	if run then return ns.Print("a fog test is already running.") end
	if InCombatLockdown() then return ns.Print("the fog test can't run in combat.") end
	if Moving() then return ns.Print("stand still first, then start the fog test.") end
	local cases = CasesFor(mode)
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local rec = {
		version = 2, build = (select(2, GetBuildInfo())), started = date("%Y-%m-%d %H:%M:%S"),
		mode = mode, zone = GetRealZoneText(), subzone = GetSubZoneText(), mapID = mapID,
		indoors = IsIndoors() or nil, gameTime = ("%02d:%02d"):format(GetGameTime()),
		raidSettings = C_CVar.GetCVar("RAIDsettingsEnabled"),
		cases = {}, shots = {}, changes = {}, restore = {}, running = true,
	}
	ns.DB().fogtest = rec
	run = {
		rec = rec, cases = cases, baseline = Capture(), raid = rec.raidSettings == "1",
		lastShot = 0, count = 0, good = 0, startedAt = GetTime(),
	}
	run.co = coroutine.create(Body)
	ns.testActive = true
	catcher:Show()
	catcher:EnableKeyboard(true)
	catcher:SetPropagateKeyboardInput(true)
	watcher = C_Timer.NewTicker(0.25, function()
		if not run then return end
		if Moving() then
			Stop("you moved")
		elseif run.uiHidden and UIParent:IsShown() then
			Stop("the interface was shown")
		end
	end)
	ns.Print("fog test started (about %d seconds). Press any key to stop.", ns.EstimateFogTest(mode))
	Resume()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

catcher = CreateFrame("Frame", nil, WorldFrame)
catcher:SetSize(1, 1)
catcher:SetPoint("CENTER")
catcher:Hide()
catcher:SetScript("OnKeyDown", function() Stop("a key was pressed") end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:RegisterEvent("SCREENSHOT_SUCCEEDED")
ev:RegisterEvent("SCREENSHOT_FAILED")
ev:SetScript("OnEvent", function(_, event)
	if event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
		OnShotEvent(event == "SCREENSHOT_SUCCEEDED")
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Fires just before combat lockdown, while the interface can still be shown again.
		Stop("combat started")
	elseif event == "PLAYER_LEAVING_WORLD" then
		Stop("loading screen")
	elseif event == "PLAYER_LOGIN" then
		-- A /reload during a test: put the settings it had changed back.
		local rec = ns.DB().fogtest
		if rec and rec.running then
			local list = {}
			for name, value in pairs(rec.restore or {}) do list[#list + 1] = { name = name, key = name:lower(), value = value } end
			table.sort(list, function(a, b)
				local pa, pb = Priority(a.key), Priority(b.key)
				if pa ~= pb then return pa < pb end
				return a.key < b.key
			end)
			for _ = 1, 2 do
				for _, item in ipairs(list) do
					if not ns.Same(C_CVar.GetCVar(item.name), item.value) then ns.WriteUntracked(item.name, item.value) end
				end
			end
			if SetInWorldUIVisibility then pcall(SetInWorldUIVisibility, true) end
			rec.running, rec.restore = nil, nil
			rec.stopped = rec.stopped or "interrupted by a reload"
			ns.Print("the last fog test was cut short; its settings are back (%d).", #list)
		end
	end
end)

StaticPopupDialogs["GRAPHICSLAB_FOGTEST"] = {
	text = "Fog test (about %s seconds)\n\nGraphicsLab hides the interface, changes one fog setting at a time and takes screenshots. Everything is put back afterwards.\n\nStand still outdoors, look toward distant land with some sky, and don't touch the mouse or keyboard. Press any key to stop early.",
	button1 = START or "Start", button2 = CANCEL,
	OnAccept = function(_, mode)
		-- Let the popup close before the interface is hidden.
		C_Timer.After(0.3, function() ns.StartFogTest(mode) end)
	end,
	timeout = 0, whileDead = false, hideOnEscape = true,
}

StaticPopupDialogs["GRAPHICSLAB_FOGTEST_DONE"] = {
	text = "Fog test finished (%d screenshots).\n\nReload the interface now to save the results?",
	button1 = RELOADUI or "Reload", button2 = LATER or "Later",
	OnAccept = function() if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns.AskFogTest(mode)
	mode = mode or "full"
	if run then return ns.Print("a fog test is already running.") end
	StaticPopup_Show("GRAPHICSLAB_FOGTEST", ns.EstimateFogTest(mode), nil, mode)
end
