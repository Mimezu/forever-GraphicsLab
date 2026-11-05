-- GraphicsLab window: category list, searchable rows of live CVar controls, restore and snapshot tools.

local _, ns = ...

local ROW_H, MAX_ROWS = 40, 300
local CONTROL_X = 290
local COLOR_CHANGED = { 1, 0.62, 0.15 }

local frame, scroll, content, statusText, searchBox, changedOnly, navButtons, UpdateStatus
local rows, current = {}, "fog"

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------

local VISUAL = "fog|light|shadow|ssao|assao|cacao|bloom|sun|sky|cloud|horizon|clip|lod|mip|texture|particle|weather|water|ripple|reflect|refract|liquid|render|resample|aa|msaa|hdr|gamma|bright|contrast|outline|ffx|vrs|specular|glow|ground|doodad|wmo|terrain|entity|camera|fov|gx|volume|light"

local function IsVisual(name)
	local low = name:lower()
	for word in VISUAL:gmatch("[^|]+") do
		if low:find(word, 1, true) then return true end
	end
end

-- Pick a control for CVars that have no curated spec, using ranges from their help text.
local function AutoSpec(e)
	local help = e.help or ""
	local lo, hi = help:match("%[%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*%]")
	if not lo then lo, hi = help:match("%((%-?%d+%.?%d*)%s*%-%s*(%d+%.?%d*)%)") end
	lo, hi = tonumber(lo), tonumber(hi)
	local value, default = ns.Get(e.name), ns.Default(e.name)
	if help:find("%(0/1%)") then
		return { cvar = e.name, kind = "bool" }
	elseif lo and hi and hi > lo then
		local integral = math.floor(lo) == lo and math.floor(hi) == hi and hi - lo <= 200
		return { cvar = e.name, kind = "range", min = lo, max = hi, step = integral and 1 or (hi - lo) / 200 }
	elseif (value == "0" or value == "1") and (default == "0" or default == "1") then
		return { cvar = e.name, kind = "bool" }
	end
	return { cvar = e.name, kind = "text" }
end

local function SpecFor(e)
	local spec = ns.specs[e.key or e.name:lower()]
	if spec then return spec end
	-- The control type for an uncurated CVar is stable for the session.
	e.autoSpec = e.autoSpec or AutoSpec(e)
	return e.autoSpec
end

-- The whole registry sorted by lowercase name, rebuilt only when entries are added.
local sortedAll, sortedVersion
local function AllSorted()
	if sortedAll and sortedVersion == ns.registryVersion then return sortedAll end
	sortedAll, sortedVersion = {}, ns.registryVersion
	for _, e in pairs(ns.registry) do sortedAll[#sortedAll + 1] = e end
	table.sort(sortedAll, function(a, b) return a.key < b.key end)
	return sortedAll
end

local function SortedEntries(filter)
	local list = {}
	for _, e in ipairs(AllSorted()) do
		if filter(e.key, e) then list[#list + 1] = e end
	end
	return list
end

-- Lowercase text searched for an entry; its parts do not change during a session.
local function SearchText(e, spec)
	if not e.searchText then
		e.searchText = (e.name .. " " .. (spec.label or "") .. " " .. (e.help or "") .. " " .. (spec.note or "")):lower()
	end
	return e.searchText
end

local VIEWS = {
	{ key = "changed", title = "Changed", filter = function(key) return ns.IsChanged(key) end },
	{ key = "allgfx", title = "All graphics", filter = function(key, e)
		return e.category == "Graphics" or ns.specs[key] or (e.category == "Default" and IsVisual(e.name))
	end },
	{ key = "hidden", title = "Hidden (probed)", filter = function(_, e) return e.hidden end },
	{ key = "everything", title = "Everything", filter = function() return true end },
}

local function BuildItems()
	local search = searchBox and searchBox:GetText():lower() or ""
	local items = {}
	if search ~= "" then
		for _, e in ipairs(AllSorted()) do
			local spec = SpecFor(e)
			if SearchText(e, spec):find(search, 1, true) then items[#items + 1] = { entry = e, spec = spec } end
		end
	else
		for _, cat in ipairs(ns.categories) do
			if cat.key == current then
				for _, spec in ipairs(cat) do
					local e = ns.Lookup(spec.cvar)
					if e then items[#items + 1] = { entry = e, spec = spec } end
				end
			end
		end
		for _, view in ipairs(VIEWS) do
			if view.key == current then
				for _, e in ipairs(SortedEntries(view.filter)) do items[#items + 1] = { entry = e, spec = SpecFor(e) } end
			end
		end
	end
	if changedOnly and changedOnly:GetChecked() then
		local kept = {}
		for _, item in ipairs(items) do
			if ns.IsChanged(item.entry.name) then kept[#kept + 1] = item end
		end
		items = kept
	end
	return items
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function FormatNumber(v, step)
	v = tonumber(v)
	if not v then return "" end
	if step and step >= 1 then return tostring(math.floor(v + 0.5)) end
	return (("%.4f"):format(v):gsub("%.?0+$", ""))
end

local function ApplyName(name, value)
	local ok, now = ns.Set(name, value)
	if not ok then
		ns.Print("%s was not changed (locked, secure, or invalid value).", name)
	elseif now and not ns.Same(now, value) then
		ns.Print("%s: the client stored %s instead of %s.", name, tostring(now), tostring(value))
	end
end

local function Apply(row, value) ApplyName(row.item.entry.name, value) end

local function ShowTooltip(row)
	local item = row.item
	local e, spec = item.entry, item.spec
	if spec.kind == "presets" then
		GameTooltip:SetOwner(row, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 2)
		GameTooltip:SetText(spec.label, 1, 1, 1)
		if spec.note then GameTooltip:AddLine(spec.note, 1, 0.82, 0, true) end
		for _, preset in ipairs(spec.presets) do
			local parts = {}
			for cvar, value in pairs(preset[2]) do parts[#parts + 1] = cvar .. " " .. value end
			table.sort(parts)
			GameTooltip:AddDoubleLine(preset[1], table.concat(parts, ", "), 0.7, 0.7, 0.7, 1, 1, 1)
		end
		GameTooltip:Show()
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_NONE")
	GameTooltip:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 2)
	GameTooltip:SetText(spec.label or e.name, 1, 1, 1)
	GameTooltip:AddLine(e.name .. (e.hidden and "  |cffff9f26(hidden)|r" or "") .. "  |cff888888" .. (e.category or "") .. "|r", 0.6, 0.8, 1)
	if spec.note then GameTooltip:AddLine(spec.note, 1, 0.82, 0, true) end
	if e.help then GameTooltip:AddLine(e.help, 0.9, 0.9, 0.9, true) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Current", tostring(ns.Get(e.name)), 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine("Game default", tostring(ns.Default(e.name)), 0.7, 0.7, 0.7, 1, 1, 1)
	local orig = ns.Original(e.name)
	if orig then GameTooltip:AddDoubleLine("Your original", orig, 0.7, 0.7, 0.7, unpack(COLOR_CHANGED)) end
	if ns.IsKept(e.name) then
		GameTooltip:AddLine(ns.IsResent(e.name)
			and "Kept: put back when something changes it, and re-sent every second."
			or "Kept: put back when something changes it.", 0.4, 0.8, 1, true)
	end
	if spec.flags and spec.flags.restart then GameTooltip:AddLine("Takes effect after a client restart.", 1, 0.4, 0.4) end
	GameTooltip:AddLine("Right-click for more options.", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

-- Right-click menu of a row (GraphicsLab's own menu, see Popup.lua).
local function RowMenu(row)
	if row.item.spec.kind == "presets" then return end
	local name = row.item.entry.name
	local default = ns.Default(name)
	local entries = {
		{ title = name },
		{ text = "Restore my original value", func = function() ns.ResetOne(name) end },
		{ text = "Set to game default", func = function() ApplyName(name, default) end, disabled = default == nil },
		{ divider = true },
		{ text = "Keep my value",
			check = function() return ns.IsKept(name) end,
			func = function() ns.SetKept(name, not ns.IsKept(name)) end },
	}
	if ns.CanResend(name) then
		entries[#entries + 1] = { text = "Also re-send it every second (experimental)",
			check = function() return ns.IsResent(name) end,
			func = function() ns.SetResent(name, not ns.IsResent(name)) end }
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { text = "Print name to chat", func = function() ns.Print("/console %s %s", name, tostring(ns.Get(name))) end }
	ns.OpenMenu(row, entries, true)
end

local function CreateRow(i)
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT", content, "RIGHT")
	row:RegisterForClicks("RightButtonUp")
	row:SetScript("OnClick", RowMenu)
	row:SetScript("OnEnter", ShowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetPoint("TOPLEFT", 0, -4)
	row.mark:SetPoint("BOTTOMLEFT", 0, 4)
	row.mark:SetWidth(3)
	row.mark:SetColorTexture(unpack(COLOR_CHANGED))

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("TOPLEFT", 10, -6)
	row.label:SetWidth(CONTROL_X - 20)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
	row.sub:SetWidth(CONTROL_X - 20)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)

	row.reset = CreateFrame("Button", nil, row)
	row.reset:SetSize(18, 18)
	row.reset:SetPoint("RIGHT", -8, 0)
	row.reset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
	row.reset:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	row.reset:SetScript("OnClick", function() ns.ResetOne(row.item.entry.name) end)
	row.reset:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Restore your original value: " .. tostring(ns.Original(row.item.entry.name)))
		GameTooltip:Show()
	end)
	row.reset:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function EnsureCheck(row)
	if row.check then return row.check end
	local c = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	c:SetPoint("LEFT", CONTROL_X, 0)
	c:SetScript("OnClick", function(self) Apply(row, self:GetChecked() and "1" or "0") end)
	row.check = c
	return c
end

local function EnsureEdit(row)
	if row.edit then return row.edit end
	local ed = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	ed:SetSize(70, 20)
	ed:SetAutoFocus(false)
	ed:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		Apply(row, self:GetText())
	end)
	ed:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		self:SetText(ns.Get(row.item.entry.name) or "")
	end)
	row.edit = ed
	return ed
end

local function EnsureSlider(row)
	if row.slider then return row.slider end
	local s = CreateFrame("Slider", nil, row, "MinimalSliderTemplate")
	s:SetWidth(190)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:SetPoint("LEFT", CONTROL_X, 0)
	s:SetScript("OnValueChanged", function(_, value)
		if row.binding then return end
		local step = row.item.spec.step
		row.edit:SetText(FormatNumber(value, step))
		-- Throttle: dragging fires many events; apply the latest value shortly after movement settles.
		row.pending = { name = row.item.entry.name, value = FormatNumber(value, step) }
		if not row.timer then
			row.timer = C_Timer.NewTimer(0.12, function()
				row.timer = nil
				local p = row.pending
				row.pending = nil
				if p then ApplyName(p.name, p.value) end
			end)
		end
	end)
	row.slider = s
	return s
end

local function EnsureDrop(row)
	if row.drop then return row.drop end
	local d = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	d:SetSize(200, 22)
	d:SetPoint("LEFT", CONTROL_X, 0)
	d:SetScript("OnClick", function(self)
		local spec, name = row.item.spec, row.item.entry.name
		local entries = {}
		for _, opt in ipairs(spec.options) do
			entries[#entries + 1] = { text = opt.text,
				radio = function() return ns.Same(ns.Get(name), opt.value) end,
				func = function() ApplyName(name, opt.value) end }
		end
		ns.OpenMenu(self, entries)
	end)
	row.drop = d
	return d
end

local function PresetMatches(preset)
	for cvar, value in pairs(preset[2]) do
		if not ns.Same(ns.Get(cvar), value) then return false end
	end
	return true
end

local function EnsurePresets(row)
	if row.presetButtons then return row.presetButtons end
	local holder = CreateFrame("Frame", nil, row)
	holder:SetPoint("LEFT", CONTROL_X, 0)
	holder:SetSize(300, 24)
	holder.buttons = {}
	for i = 1, 5 do
		local b = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
		b:SetSize(72, 22)
		b:SetPoint("LEFT", (i - 1) * 76, 0)
		b.wash = b:CreateTexture(nil, "OVERLAY")
		b.wash:SetPoint("TOPLEFT", 3, -3); b.wash:SetPoint("BOTTOMRIGHT", -3, 3)
		b.wash:SetColorTexture(1, 0.72, 0.2, 0.22)
		b:SetScript("OnClick", function(self)
			for cvar, value in pairs(self.preset[2]) do ApplyName(cvar, value) end
			ns.Print("%s: %s.", row.item.spec.label, self.preset[1])
		end)
		holder.buttons[i] = b
	end
	row.presetButtons = holder
	return holder
end

local function Refresh(row)
	local item = row.item
	local e, spec = item.entry, item.spec
	local value = ns.Get(e.name)
	local changed = ns.IsChanged(e.name)
	row.binding = true

	if spec.kind == "presets" then
		row.mark:Hide(); row.reset:Hide()
		row.label:SetText(spec.label)
		row.sub:SetText("One click; raid versions follow when linked")
		for i, b in ipairs(row.presetButtons.buttons) do
			local preset = spec.presets[i]
			b.preset = preset
			b:SetShown(preset ~= nil)
			if preset then
				b:SetText(preset[1])
				b.wash:SetShown(PresetMatches(preset))
			end
		end
		row.binding = false
		return
	end
	row.mark:SetShown(changed)
	row.reset:SetShown(changed)
	local tag = (spec.flags and spec.flags.restart) and " |cffff6666(restart)|r" or ""
	row.label:SetText((spec.label or e.name) .. tag)
	local kept = ns.IsKept(e.name) and (ns.IsResent(e.name) and "  |cff66ccffkept, re-sent|r" or "  |cff66ccffkept|r") or ""
	local gameMax = spec.flags and spec.flags.gameMax
	local beyond = ""
	if gameMax then
		beyond = "  |cff777777game max " .. gameMax .. "|r"
		if (tonumber(value) or 0) > gameMax then beyond = beyond .. "  |cffff9f26beyond game|r" end
	end
	row.sub:SetText(e.name .. "  |cff777777default " .. tostring(ns.Default(e.name)) .. "|r"
		.. (e.hidden and "  |cffff9f26hidden|r" or "") .. beyond .. kept)

	if spec.kind == "bool" then
		row.check:SetChecked(value == "1")
	elseif spec.kind == "range" then
		local v = tonumber(value) or spec.min
		row.slider:SetMinMaxValues(spec.min, spec.max)
		row.slider:SetValueStep(spec.step)
		row.slider:SetValue(math.max(spec.min, math.min(spec.max, v)))
		if not row.edit:HasFocus() then row.edit:SetText(value or "") end
	elseif spec.kind == "enum" then
		local text = tostring(value)
		for _, opt in ipairs(spec.options) do
			if ns.Same(opt.value, value) then text = opt.text end
		end
		row.drop:SetText(text)
	elseif not row.edit:HasFocus() then
		row.edit:SetText(value or "")
	end
	row.binding = false
end

local function Bind(row, item)
	row.item = item
	for _, key in ipairs({ "check", "slider", "edit", "drop", "presetButtons" }) do
		if row[key] then row[key]:Hide() end
	end
	local kind = item.spec.kind
	if kind == "presets" then
		EnsurePresets(row):Show()
	elseif kind == "bool" then
		EnsureCheck(row):Show()
	elseif kind == "range" then
		EnsureSlider(row):Show()
		local ed = EnsureEdit(row)
		ed:ClearAllPoints()
		ed:SetPoint("LEFT", row.slider, "RIGHT", 14, 0)
		ed:SetWidth(70)
		ed:Show()
	elseif kind == "enum" then
		EnsureDrop(row):Show()
	else
		local ed = EnsureEdit(row)
		ed:ClearAllPoints()
		ed:SetPoint("LEFT", CONTROL_X + 6, 0)
		ed:SetWidth(200)
		ed:Show()
	end
	Refresh(row)
	row:Show()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function UpdateNav()
	for _, b in ipairs(navButtons) do
		local active = b.key == current and (searchBox:GetText() == "")
		b.text:SetTextColor(active and 1 or 0.8, active and 0.82 or 0.8, active and 0 or 0.8)
		b.sel:SetShown(active)
	end
end

local hiddenCount, hiddenVersion = 0, nil
function UpdateStatus()
	local n = frame.itemCount or 0
	if hiddenVersion ~= ns.registryVersion then
		hiddenCount, hiddenVersion = 0, ns.registryVersion
		for _, e in pairs(ns.registry) do
			if e.hidden then hiddenCount = hiddenCount + 1 end
		end
	end
	local hidden = hiddenCount
	local extra = n > MAX_ROWS and ("  |cffff9f26showing %d of %d, refine the search|r"):format(MAX_ROWS, n) or ""
	statusText:SetText(("%d settings  |  %d changed  |  %d kept  |  %d hidden%s%s"):format(
		n, ns.ChangedCount(), ns.KeptCount(), hidden, ns.DB().probe and "" or " (not probed)", extra))
end

local function Render()
	if not frame or not frame:IsShown() then return end
	local items = BuildItems()
	local shown = math.min(#items, MAX_ROWS)
	for i = 1, shown do
		rows[i] = rows[i] or CreateRow(i)
		Bind(rows[i], items[i])
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	content:SetHeight(math.max(1, shown * ROW_H))
	frame.itemCount = #items
	UpdateStatus()
	UpdateNav()
end
ns.Render = Render

-- Bulk operations (restore all, load snapshot) notify once per CVar; rebuild the
-- list at most once per frame instead of once per notification.
local renderQueued = false
local function QueueRender()
	if renderQueued then return end
	renderQueued = true
	C_Timer.After(0, function()
		renderQueued = false
		Render()
	end)
end

local function RefreshVisible(name)
	if not frame or not frame:IsShown() then return end
	if not name or current == "changed" or changedOnly:GetChecked() then return QueueRender() end
	local key = name:lower()
	for _, row in ipairs(rows) do
		-- Preset rows depend on several CVars; refresh them on any change.
		if row:IsShown() and row.item and (row.item.entry.key == key or row.item.spec.kind == "presets") then Refresh(row) end
	end
	UpdateStatus()
end
ns.OnChange(RefreshVisible)

-- Confirmations and the snapshot name are GraphicsLab's own dialogs (Popup.lua).
local function AskRestore(n)
	ns.ShowDialog({
		text = ("Restore all %d changed settings to the values you had before GraphicsLab changed them?"):format(n),
		accept = YES or "Yes", cancel = NO or "No",
		onAccept = function() ns.Print("restored %d settings.", ns.RestoreAll()) end,
	})
end

local function SaveSnapshotNamed(label)
	ns.SaveSnapshot(label)
	ns.Print("saved snapshot '%s'.", label)
end

local function AskSaveSnapshot()
	ns.ShowDialog({
		text = "Name this snapshot:",
		accept = SAVE or "Save", cancel = CANCEL or "Cancel",
		editBox = true, default = date("Snapshot %m-%d %H:%M"),
		onAccept = function(label)
			if not ns.Snapshots()[label] then return SaveSnapshotNamed(label) end
			ns.ShowDialog({
				text = ("Replace the existing snapshot '%s' with the current settings?"):format(label),
				accept = YES or "Yes", cancel = NO or "No",
				onAccept = function() SaveSnapshotNamed(label) end,
			})
		end,
	})
end

local function AskDeleteSnapshot(label)
	ns.ShowDialog({
		text = ("Delete the snapshot '%s'?"):format(label),
		accept = DELETE or "Delete", cancel = CANCEL or "Cancel",
		onAccept = function()
			ns.DeleteSnapshot(label)
			ns.Print("deleted snapshot '%s'.", label)
		end,
	})
end

local function SnapshotMenu(owner)
	local entries = { { text = "Save current settings...", func = AskSaveSnapshot } }
	local names = {}
	for label in pairs(ns.Snapshots()) do names[#names + 1] = label end
	table.sort(names)
	if #names > 0 then
		entries[#entries + 1] = { divider = true }
		entries[#entries + 1] = { title = "Load" }
		for _, label in ipairs(names) do
			local snap = ns.Snapshots()[label]
			entries[#entries + 1] = { text = label .. "  |cff888888" .. snap.date .. "|r", func = function()
				ns.Print("loaded '%s': %d settings changed.", label, ns.LoadSnapshot(label))
			end }
		end
		entries[#entries + 1] = { divider = true }
		local del = {}
		for _, label in ipairs(names) do
			del[#del + 1] = { text = label, func = function() AskDeleteSnapshot(label) end }
		end
		entries[#entries + 1] = { text = "Delete", items = del }
	end
	ns.OpenMenu(owner, entries)
end

local function FogTestMenu(owner)
	local entries = { { title = "Fog test" } }
	if ns.FogTestRunning() then
		entries[#entries + 1] = { text = "Stop the running test", func = function() ns.StopFogTest() end }
		return ns.OpenMenu(owner, entries)
	end
	entries[#entries + 1] = { text = ("Full test (about %d seconds)"):format(ns.EstimateFogTest("full")), func = function() ns.AskFogTest("full") end }
	entries[#entries + 1] = { text = ("Quick test (about %d seconds)"):format(ns.EstimateFogTest("quick")), func = function() ns.AskFogTest("quick") end }
	entries[#entries + 1] = { text = ("More haze tests (about %d seconds)"):format(ns.EstimateFogTest("more")), func = function() ns.AskFogTest("more") end }
	local rec = ns.DB().fogtest
	if rec and rec.started then
		entries[#entries + 1] = { divider = true }
		entries[#entries + 1] = { title = ("Last run: %s, %s%s"):format(rec.started, rec.zone or "?",
			rec.stopped and (" (stopped: " .. rec.stopped .. ")") or "") }
	end
	ns.OpenMenu(owner, entries)
end

local function MakeButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function MakeCheck(parent, text, get, set, tip)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c.text:SetText(text)
	c:SetChecked(get())
	c:SetScript("OnClick", function(self) set(self:GetChecked()) end)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", GameTooltip_Hide)
	return c
end

local function CreateMainFrame()
	frame = CreateFrame("Frame", "GraphicsLabFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:Hide()
	frame:SetSize(900, 620)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	local db = ns.DB()
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint(1)
		db.window = { point = point, relativePoint = relativePoint, x = x, y = y }
	end)
	local saved = db.window
	if type(saved) == "table" and type(saved.point) == "string" and type(saved.x) == "number" and type(saved.y) == "number" then
		frame:ClearAllPoints()
		frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
	end
	frame:SetScript("OnShow", Render)
	frame:HookScript("OnHide", ns.CloseMenu)
	tinsert(UISpecialFrames, "GraphicsLabFrame")
	frame.TitleText:SetText("GraphicsLab - extended graphics settings")

	-- Navigation
	navButtons = {}
	local nav = {}
	for _, cat in ipairs(ns.categories) do
		-- Skip topics whose settings this client doesn't have (the hidden-CVar list, for one).
		local any = false
		for _, spec in ipairs(cat) do
			if ns.Lookup(spec.cvar) then any = true; break end
		end
		if any then nav[#nav + 1] = { key = cat.key, title = cat.title } end
	end
	nav[#nav + 1] = false
	for _, view in ipairs(VIEWS) do nav[#nav + 1] = view end
	local y = -34
	for _, n in ipairs(nav) do
		if n then
			local b = CreateFrame("Button", nil, frame)
			b:SetSize(170, 20)
			b:SetPoint("TOPLEFT", 12, y)
			b.key = n.key
			b.sel = b:CreateTexture(nil, "BACKGROUND")
			b.sel:SetAllPoints()
			b.sel:SetColorTexture(1, 0.82, 0, 0.12)
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			b.text:SetPoint("LEFT", 8, 0)
			b.text:SetText(n.title)
			b:SetScript("OnClick", function()
				current = n.key
				searchBox:SetText("")
				searchBox:ClearFocus()
				scroll:SetVerticalScroll(0)
				Render()
			end)
			navButtons[#navButtons + 1] = b
			y = y - 21
		else
			y = y - 10
		end
	end

	-- Top bar
	searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(260, 20)
	searchBox:SetPoint("TOPLEFT", 200, -32)
	-- Wait for a pause in typing before searching ~1.8k entries.
	local searchToken = 0
	searchBox:HookScript("OnTextChanged", function()
		searchToken = searchToken + 1
		local token = searchToken
		C_Timer.After(0.15, function()
			if token ~= searchToken then return end
			scroll:SetVerticalScroll(0)
			Render()
		end)
	end)

	changedOnly = MakeCheck(frame, "Changed only", function() return false end, Render,
		"Only show settings that differ from your original values.")
	changedOnly:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)

	local link = MakeCheck(frame, "Link raid settings", function() return db.linkRaid end,
		function(v) db.linkRaid = v and true or false end,
		"Also write the matching RAID* setting (used when raid graphics are active), e.g. horizonStart -> RAIDhorizonStart.")
	link:SetPoint("LEFT", changedOnly.text, "RIGHT", 14, 0)

	local reapply = MakeCheck(frame, "Reapply at login", function() return db.reapply end,
		function(v) db.reapply = v and true or false end,
		"Re-set your changes at login. Some hidden CVars are not saved by the game and would otherwise reset. Changes made later in the Blizzard options still win.")
	reapply:SetPoint("LEFT", link.text, "RIGHT", 14, 0)

	-- Rows
	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 196, -60)
	scroll:SetPoint("BOTTOMRIGHT", -32, 44)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(900 - 196 - 32, 1)
	scroll:SetScrollChild(content)

	-- Bottom bar
	local restore = MakeButton(frame, "Restore originals", 140, function()
		local n = ns.ChangedCount()
		if n == 0 then return ns.Print("nothing to restore.") end
		AskRestore(n)
	end)
	restore:SetPoint("BOTTOMLEFT", 12, 12)
	local snaps = MakeButton(frame, "Snapshots", 110, function(self) SnapshotMenu(self) end)
	snaps:SetPoint("LEFT", restore, "RIGHT", 6, 0)
	local probe = MakeButton(frame, "Probe hidden", 120, function() ns.Probe() end)
	probe:SetPoint("LEFT", snaps, "RIGHT", 6, 0)
	probe:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Probe hidden", 1, 1, 1)
		GameTooltip:AddLine("Checks which of the Experimental (hidden) settings this build has. Same as /glab probe.", 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	probe:SetScript("OnLeave", GameTooltip_Hide)
	local fogtest = MakeButton(frame, "Fog test", 90, function(self) FogTestMenu(self) end)
	fogtest:SetPoint("LEFT", probe, "RIGHT", 6, 0)
	fogtest:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Fog test", 1, 1, 1)
		GameTooltip:AddLine("Finds out which settings really change the fog where you stand: hides the interface, changes one setting at a time and takes screenshots. Everything is put back afterwards.", 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	fogtest:SetScript("OnLeave", GameTooltip_Hide)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	statusText:SetPoint("LEFT", fogtest, "RIGHT", 14, 0)
	statusText:SetPoint("RIGHT", -16, 0)
	statusText:SetJustifyH("LEFT")
end

function ns.Toggle()
	-- New frames start out shown, so the window is created hidden and then opened once;
	-- toggling a fresh frame used to hide it and needed a second /glab.
	if not frame then
		CreateMainFrame()
		frame:Show()
		return
	end
	frame:SetShown(not frame:IsShown())
end

SLASH_GRAPHICSLAB1 = "/glab"
SLASH_GRAPHICSLAB2 = "/graphicslab"
SlashCmdList.GRAPHICSLAB = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "restore" then
		ns.Print("restored %d settings.", ns.RestoreAll())
	elseif msg == "trace" then
		ns.ToggleTrace()
	elseif msg == "trace clear" then
		ns.ClearTrace()
	elseif msg == "probe" then
		ns.Probe()
	elseif msg == "fogtest" or msg == "fogtest full" then
		ns.AskFogTest("full")
	elseif msg == "fogtest quick" or msg == "fogtest more" then
		ns.AskFogTest(msg:match("%w+$"))
	elseif msg == "fogtest stop" then
		ns.StopFogTest()
	elseif msg == "help" then
		ns.Print("/glab - open the window. /glab fogtest [quick | more | stop] - test which fog settings work here. "
			.. "/glab restore - restore all originals. /glab trace - log setting changes. /glab probe - check which hidden (experimental) settings this build has.")
	else
		ns.Toggle()
	end
end
