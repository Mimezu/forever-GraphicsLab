-- GraphicsLab's own menus and dialogs. Blizzard's context menus and popups opened from addon
-- code run the gamepad window manager under addon taint (the "A and B dead until /reload" bug),
-- so the window uses these instead. The mouse or the gamepad cursor clicks the rows; Escape, or
-- a click anywhere else, closes a menu. Dialogs close with their buttons, Escape, or Enter in
-- their text field.
--
-- Menu entries: { text, func }              an item: func() runs and the menu closes
--               { text, items = { ... } }   a submenu (opens on hover or click)
--               { text, radio = get, func } a choice; a dot marks it while get() is true
--               { text, check = get, func } a toggle; the menu stays open and redraws
--               { title = text }            a heading
--               { note = text }             a dim line
--               { divider = true }
--               disabled = true greys an item out.

local _, ns = ...

local ROW_H, PAD, MIN_W = 20, 8, 160
local GOLD, DIM, NOTE = { 1, 0.82, 0 }, { 0.5, 0.5, 0.5 }, { 0.6, 0.6, 0.6 }

local menu = { panels = {}, open = false }
ns.Popup = { menu = menu } -- (tests)

local function Backdrop(frame, dialog)
	if not frame.SetBackdrop then return end
	if dialog then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	else
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	end
end

local function Click()
	if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then pcall(PlaySound, SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
end

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

local function CloseFrom(level)
	for i = #menu.panels, level, -1 do menu.panels[i]:Hide() end
end

local function CloseMenu()
	CloseFrom(1)
	if menu.catcher then menu.catcher:Hide() end
	menu.open, menu.owner = false, nil
end
ns.CloseMenu = CloseMenu
function ns.MenuIsOpen() return menu.open end

local function Panel(level)
	if menu.panels[level] then return menu.panels[level] end
	local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(100 + level * 10)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	Backdrop(panel)
	panel.level, panel.rows = level, {}
	panel:Hide()
	menu.panels[level] = panel
	return panel
end

local ShowLevel

local function RowHover(row)
	local entry = row.entry
	if entry.items and not entry.disabled then
		ShowLevel(row.panel.level + 1, entry.items, row, "TOPLEFT", "TOPRIGHT", 2, PAD)
	else
		CloseFrom(row.panel.level + 1)
	end
end

local function RowClick(row)
	local entry, panel = row.entry, row.panel
	if entry.disabled then return end
	if entry.items then
		-- The gamepad cursor may click rather than hover: the click opens or closes the submenu.
		local sub = menu.panels[panel.level + 1]
		if sub and sub:IsShown() and sub.anchorRow == row then CloseFrom(panel.level + 1) else RowHover(row) end
		return
	end
	Click()
	if entry.check then
		-- A toggle: the menu stays open and shows the new state.
		if entry.func then entry.func() end
		local a = panel.anchor
		ShowLevel(panel.level, panel.entries, a[1], a[2], a[3], a[4], a[5])
		return
	end
	CloseMenu()
	if entry.func then entry.func() end
end

local function Row(panel, i)
	local row = panel.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, panel)
	row.panel = panel
	row:SetHeight(ROW_H)
	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.text:SetPoint("LEFT", 24, 0)
	row.text:SetPoint("RIGHT", -18, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetPoint("TOPLEFT", 4, 0); row.hover:SetPoint("BOTTOMRIGHT", -4, 0)
	row.hover:SetColorTexture(1, 0.82, 0, 0.12)
	-- Toggle box or radio ring, and the check or dot inside it.
	row.box = row:CreateTexture(nil, "ARTWORK")
	row.box:SetSize(16, 16)
	row.box:SetPoint("LEFT", 5, 0)
	row.tick = row:CreateTexture(nil, "OVERLAY")
	row.tick:SetSize(16, 16)
	row.tick:SetPoint("CENTER", row.box, "CENTER")
	row.arrow = row:CreateTexture(nil, "ARTWORK")
	row.arrow:SetSize(10, 10)
	row.arrow:SetPoint("RIGHT", -6, 0)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-icon-forwardarrow") then
		row.arrow:SetAtlas("common-icon-forwardarrow")
	else
		row.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	end
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetPoint("LEFT", 8, 0); row.line:SetPoint("RIGHT", -8, 0)
	row.line:SetHeight(1)
	row.line:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	row:SetScript("OnClick", RowClick)
	row:SetScript("OnEnter", RowHover)
	panel.rows[i] = row
	return row
end

local function SetMark(row, entry)
	local kind = entry.check and "check" or entry.radio and "radio"
	row.box:SetShown(kind ~= nil)
	if not kind then row.tick:Hide(); return end
	local on = kind == "check" and entry.check() == true or kind == "radio" and entry.radio() == true
	if kind == "check" then
		row.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
		row.box:SetTexCoord(0, 1, 0, 1)
		row.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		row.tick:SetTexCoord(0, 1, 0, 1)
	else
		row.box:SetTexture("Interface\\Buttons\\UI-RadioButton")
		row.box:SetTexCoord(0, 0.25, 0, 1)
		row.tick:SetTexture("Interface\\Buttons\\UI-RadioButton")
		row.tick:SetTexCoord(0.25, 0.5, 0, 1)
	end
	row.tick:SetShown(on)
end

-- A submenu opens to the right of its row, or to the left when it would leave the screen.
local function FitsRight(row, width)
	local right, edge = tonumber(row:GetRight()), tonumber(UIParent:GetRight())
	local scale, uiScale = tonumber(row:GetEffectiveScale()), tonumber(UIParent:GetEffectiveScale())
	if not right or not edge or not scale or not uiScale then return true end
	return (right + width) * scale <= edge * uiScale
end

ShowLevel = function(level, entries, anchor, point, relPoint, x, y)
	CloseFrom(level)
	local panel = Panel(level)
	local width, top = MIN_W, PAD
	for i, entry in ipairs(entries) do
		local row = Row(panel, i)
		row.entry = entry
		local kind = entry.divider and "divider" or entry.title and "title" or entry.note and "note" or "item"
		local height = kind == "divider" and 9 or kind == "note" and 16 or ROW_H
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -top)
		row:SetPoint("TOPRIGHT", 0, -top)
		row:SetHeight(height)
		row:EnableMouse(kind == "item")
		row.line:SetShown(kind == "divider")
		row.text:SetShown(kind ~= "divider")
		row.text:SetText(entry.text or entry.title or entry.note or "")
		row.text:SetFontObject(kind == "title" and "GameFontNormal" or kind == "note" and "GameFontHighlightSmall" or "GameFontHighlight")
		row.text:SetTextColor(unpack(kind == "note" and NOTE or kind == "title" and GOLD or entry.disabled and DIM or { 1, 1, 1 }))
		row.hover:SetShown(kind == "item" and not entry.disabled)
		if kind == "item" then SetMark(row, entry) else row.box:Hide(); row.tick:Hide() end
		row.arrow:SetShown(kind == "item" and entry.items ~= nil)
		row.arrow:SetAlpha(entry.disabled and 0.4 or 1)
		width = math.max(width, (tonumber(row.text:GetStringWidth()) or 0) + 24 + 18 + 8)
		top = top + height
		row:Show()
	end
	for i = #entries + 1, #panel.rows do panel.rows[i]:Hide() end
	panel:SetSize(width, top + PAD)
	panel.entries, panel.anchor = entries, { anchor, point, relPoint, x, y }
	panel.anchorRow = level > 1 and anchor or nil
	panel:ClearAllPoints()
	if level > 1 and not FitsRight(anchor, width) then
		panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -2, PAD)
	else
		panel:SetPoint(point, anchor, relPoint, x, y)
	end
	panel:Show()
	return panel
end

local function Catcher()
	if menu.catcher then return menu.catcher end
	-- Covers the screen under the menu: a click anywhere else closes it. Escape too, when the
	-- keyboard can be taken (not in combat); other keys pass through.
	local catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(90)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:SetScript("OnMouseDown", CloseMenu)
	catcher:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			pcall(self.SetPropagateKeyboardInput, self, false)
			CloseMenu()
		else
			pcall(self.SetPropagateKeyboardInput, self, true)
		end
	end)
	catcher:Hide()
	menu.catcher = catcher
	return catcher
end

-- The menu opens under its owner, or at the cursor (atCursor = true, for right-clicked rows).
-- The owner that opened it closes it again; so does hiding the owner.
function ns.OpenMenu(owner, entries, atCursor)
	if menu.open and menu.owner == owner then CloseMenu(); return end
	CloseMenu()
	local catcher = Catcher()
	menu.open, menu.owner = true, owner
	if not InCombatLockdown() then
		pcall(catcher.EnableKeyboard, catcher, true)
		pcall(catcher.SetPropagateKeyboardInput, catcher, true)
	end
	catcher:Show()
	if not owner.graphicsLabMenuHook then
		owner.graphicsLabMenuHook = true
		owner:HookScript("OnHide", function() if menu.owner == owner then CloseMenu() end end)
	end
	local x, y, scale = nil, nil, tonumber(UIParent:GetEffectiveScale())
	if atCursor and GetCursorPosition and scale and scale > 0 then
		x, y = GetCursorPosition()
		x, y = tonumber(x), tonumber(y)
	end
	if x and y then
		ShowLevel(1, entries, UIParent, "TOPLEFT", "BOTTOMLEFT", x / scale - 8, y / scale + 8)
	else
		ShowLevel(1, entries, owner, "TOPLEFT", "BOTTOMLEFT", 0, -2)
	end
end

---------------------------------------------------------------------------
-- Dialog
---------------------------------------------------------------------------

local dialog

local function Dialog()
	if dialog then return dialog end
	dialog = CreateFrame("Frame", "GraphicsLabDialog", UIParent, "BackdropTemplate")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	dialog:SetWidth(360)
	dialog:SetPoint("TOP", UIParent, "TOP", 0, -135)
	dialog:EnableMouse(true)
	dialog:SetClampedToScreen(true)
	Backdrop(dialog, true)
	dialog.text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	dialog.text:SetPoint("TOPLEFT", 24, -18)
	dialog.text:SetPoint("TOPRIGHT", -24, -18)
	dialog.text:SetJustifyH("CENTER")
	dialog.text:SetWordWrap(true)
	dialog.edit = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.edit:SetSize(260, 24)
	dialog.edit:SetAutoFocus(false)
	dialog.edit:SetMaxLetters(60)
	dialog.edit:SetPoint("TOP", dialog.text, "BOTTOM", 0, -10)
	dialog.accept = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.accept:SetSize(120, 22)
	dialog.cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.cancel:SetSize(120, 22)
	dialog.accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 16)
	dialog.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 16)

	function dialog.Accept()
		local text = dialog.edit:IsShown() and strtrim(dialog.edit:GetText() or "") or nil
		if text == "" then return end -- a name is needed; the dialog stays open
		local fn = dialog.onAccept
		dialog:Hide()
		if fn then fn(text) end
	end
	function dialog.Cancel()
		local fn = dialog.onCancel
		dialog:Hide()
		if fn then fn() end
	end
	dialog.accept:SetScript("OnClick", function() Click(); dialog.Accept() end)
	dialog.cancel:SetScript("OnClick", function() Click(); dialog.Cancel() end)
	dialog.edit:SetScript("OnEnterPressed", dialog.Accept)
	dialog.edit:SetScript("OnEscapePressed", dialog.Cancel)
	-- Escape closes the dialog when its text field does not have the keyboard.
	dialog:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			pcall(self.SetPropagateKeyboardInput, self, false)
			dialog.Cancel()
		else
			pcall(self.SetPropagateKeyboardInput, self, true)
		end
	end)
	dialog:SetScript("OnHide", function(self)
		self.onAccept, self.onCancel = nil, nil
		self.edit:ClearFocus()
		pcall(self.EnableKeyboard, self, false)
	end)
	dialog:Hide()
	ns.Popup.dialog = dialog
	return dialog
end

-- opts: text, accept, cancel (button labels), onAccept(text), onCancel, editBox = true,
-- default (the text field's starting text). One dialog at a time; a new one replaces it.
function ns.ShowDialog(opts)
	local d = Dialog()
	d:Hide()
	d.text:SetText(opts.text or "")
	d.accept:SetText(opts.accept or OKAY or "Okay")
	d.cancel:SetText(opts.cancel or CANCEL or "Cancel")
	d.onAccept, d.onCancel = opts.onAccept, opts.onCancel
	d.edit:SetShown(opts.editBox == true)
	d.edit:SetText(opts.editBox and (opts.default or "") or "")
	local textHeight = tonumber(d.text:GetStringHeight()) or 40
	d:SetHeight(18 + textHeight + (opts.editBox and 34 or 0) + 16 + 22 + 16)
	if not InCombatLockdown() then
		pcall(d.EnableKeyboard, d, true)
		pcall(d.SetPropagateKeyboardInput, d, true)
	end
	d:Show()
	if opts.editBox then d.edit:SetFocus(); d.edit:HighlightText() end
	return d
end

function ns.HideDialog()
	if dialog then dialog:Hide() end
end
