-- /glab trace: diagnose settings that "don't stick".
-- Logs every Lua CVar write (with the calling addon/file), every CVAR_UPDATE event, and re-reads each
-- CVar GraphicsLab changes at +0.05s, +0.3s, +1s and +3s. Saved to GraphicsLabDB.trace on /reload.

local _, ns = ...

local MAX_LINES = 4000
local POLL_DELAYS = { 0.05, 0.3, 1, 3 }

local active, log, t0 = false, nil, 0

local function Add(fmt, ...)
	if not active or not log or #log >= MAX_LINES then return end
	log[#log + 1] = ("%7.2f  " .. fmt):format(GetTime() - t0, ...)
end

local function Caller()
	local stack = debugstack(3, 4, 0) or ""
	stack = stack:gsub("Interface/AddOns/", ""):gsub("%[string \"@?([^\"]+)\"%]", "%1"):gsub("\n+$", "")
	return (stack:gsub("\n", " <- "))
end

local function HookWrite(label)
	return function(name, value)
		if active then Add("%s %s = %s   by %s", label, tostring(name), tostring(value), Caller()) end
	end
end

hooksecurefunc(C_CVar, "SetCVar", HookWrite("C_CVar.SetCVar"))
if SetCVar then hooksecurefunc("SetCVar", HookWrite("SetCVar")) end
if ConsoleExec then
	hooksecurefunc("ConsoleExec", function(cmd)
		if active then Add("ConsoleExec %s   by %s", tostring(cmd), Caller()) end
	end)
end
if C_CVar.ResetCVar then hooksecurefunc(C_CVar, "ResetCVar", HookWrite("C_CVar.ResetCVar")) end

local f = CreateFrame("Frame")
f:RegisterEvent("CVAR_UPDATE")
f:SetScript("OnEvent", function(_, _, name)
	if active then Add("CVAR_UPDATE %s -> %s", tostring(name), tostring(name and C_CVar.GetCVar(name))) end
end)

ns.OnChange(function(name)
	if not active or not name then return end
	-- Core keeps its own copy of C_CVar.SetCVar, so its writes never reach the hooks above.
	Add("GraphicsLab set %s = %s", name, tostring(C_CVar.GetCVar(name)))
	for _, delay in ipairs(POLL_DELAYS) do
		C_Timer.After(delay, function()
			Add("  read %s = %s  (+%.2fs after GraphicsLab write)", name, tostring(C_CVar.GetCVar(name)), delay)
		end)
	end
end)

function ns.ToggleTrace()
	local DB = ns.DB()
	if active then
		active = false
		ns.Print("trace stopped (%d lines). /reload to write it to disk.", #log)
		return
	end
	log, t0, active = {}, GetTime(), true
	DB.trace = log
	Add("trace start, build %s", (select(2, GetBuildInfo())))
	ns.Print("trace ON. Change the settings that revert, wait ~5 seconds, then type /glab trace again and /reload.")
end

-- Drops the stored trace so it stops being written to SavedVariables.
function ns.ClearTrace()
	active, log = false, nil
	ns.DB().trace = nil
	ns.Print("trace cleared.")
end
