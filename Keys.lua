-- GraphicsLab's key, minimap button and page in the game's AddOns settings.
--   Key setter: the window's key (Bindings.xml) drawn on a button; click, then press a key.
--   Escape or a left/right click cancels, modifiers combine, right-click clears. A key that
--   already does something else is asked about first. Never in combat.
--   Minimap button: click opens the window, drag moves it round the minimap.
--   GraphicsLabDB.minimap = { hide = bool, angle = degrees }

local _, ns = ...

local ACTION = "GRAPHICSLAB_TOGGLE"
local TITLE = "GraphicsLab"
local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

BINDING_CATEGORY_GRAPHICSLAB = TITLE
BINDING_HEADER_GRAPHICSLAB = TITLE
BINDING_NAME_GRAPHICSLAB_TOGGLE = "Toggle window"

function GraphicsLab_Toggle() ns.Toggle() end

---------------------------------------------------------------------------
-- Key setter
---------------------------------------------------------------------------

local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
local BUTTONS = { MiddleButton = "BUTTON3" }

local function KeyText(key)
	return key and (GetBindingText and GetBindingText(key) or key) or nil
end

function ns.BoundKey() return KeyText(GetBindingKey(ACTION)) end

local function Combo(key)
	local mods = ""
	if IsAltKeyDown() then mods = mods .. "ALT-" end
	if IsControlKeyDown() then mods = mods .. "CTRL-" end
	if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
	if IsMetaKeyDown and IsMetaKeyDown() then mods = mods .. "META-" end
	return mods .. key
end

local setters = {}
local function RefreshSetters() for _, s in ipairs(setters) do s:Refresh() end end

-- Binds `key` to the window in place of the key it had. false while in combat.
function ns.BindKey(key)
	if InCombatLockdown() then return false end
	for _, old in ipairs({ GetBindingKey(ACTION) }) do SetBinding(old) end
	if key then SetBinding(key, ACTION) end
	SaveBindings(GetCurrentBindingSet())
	RefreshSetters()
	return true
end

-- What `key` does now, when that is not the window's toggle.
local function TakenBy(key)
	local action = GetBindingAction(key)
	if not action or action == "" or action == ACTION then return nil end
	return _G["BINDING_NAME_" .. action] or action
end

local function Offer(key)
	local taken = TakenBy(key)
	if not taken then
		ns.BindKey(key)
		return
	end
	ns.ShowDialog({
		text = ("%s is %s.\nUse it here instead?"):format(KeyText(key), taken),
		accept = "Replace", cancel = CANCEL or "Cancel",
		onAccept = function()
			if not ns.BindKey(key) then ns.Print("not in combat.") end
		end,
	})
end

local listening
local catcher

local function StopListening()
	local s = listening
	listening = nil
	if catcher then
		catcher:EnableKeyboard(false)
		catcher:Hide()
	end
	if s then s:Refresh() end
end
ns.StopListening = StopListening
function ns.KeyCatcherForTests() return catcher end

local function Take(key)
	StopListening()
	Offer(key)
end

local function Catcher()
	if catcher then return catcher end
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:EnableMouse(true)
	catcher:Hide()
	catcher:SetScript("OnKeyDown", function(self, key)
		pcall(self.SetPropagateKeyboardInput, self, false)
		if key == "ESCAPE" then return StopListening() end
		if MODIFIERS[key] then return end
		Take(Combo(key))
	end)
	catcher:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" or button == "RightButton" then return StopListening() end
		Take(Combo(BUTTONS[button] or button:upper()))
	end)
	catcher:SetScript("OnMouseWheel", function(_, delta)
		Take(Combo(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
	end)
	catcher:SetScript("OnHide", function() if listening then StopListening() end end)
	return catcher
end

local function Listen(s)
	if InCombatLockdown() then return ns.Print("not in combat.") end
	if listening then StopListening() end
	listening = s
	local c = Catcher()
	c:Show()
	c:EnableKeyboard(true)
	pcall(c.EnableMouseWheel, c, true)
	s:Refresh()
end

-- A "Key" label and a button showing the bound key.
function ns.KeySetter(parent, width)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(width or 170, 22)
	s.label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.label:SetPoint("LEFT", 2, 0)
	s.label:SetText("Key")
	s.button = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
	s.button:SetHeight(22)
	s.button:SetPoint("LEFT", 34, 0)
	s.button:SetPoint("RIGHT")
	s.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	s.button:SetScript("OnClick", function(_, mouse)
		if listening == s then return StopListening() end
		if mouse == "RightButton" then
			if not ns.BindKey(nil) then ns.Print("not in combat.") end
			return
		end
		Listen(s)
	end)
	s.button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(BINDING_NAME_GRAPHICSLAB_TOGGLE, 1, 1, 1)
		GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	s.button:SetScript("OnLeave", GameTooltip_Hide)
	function s:Refresh()
		if listening == self then
			self.button:SetText("Press a key")
		else
			self.button:SetText(ns.BoundKey() or "Not set")
		end
	end
	s:SetScript("OnShow", s.Refresh)
	s:SetScript("OnHide", function() if listening == s then StopListening() end end)
	s:Refresh()
	setters[#setters + 1] = s
	return s
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local mini

local function MiniDB()
	local db = ns.DB()
	if type(db.minimap) ~= "table" then db.minimap = {} end
	if type(db.minimap.angle) ~= "number" then db.minimap.angle = 205 end
	return db.minimap
end

local function PlaceMini()
	local angle = math.rad(MiniDB().angle)
	local radius = (Minimap:GetWidth() or 140) / 2 + 10
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragMini()
	local mx, my = Minimap:GetCenter()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	MiniDB().angle = math.deg(math.atan2(y / scale - my, x / scale - mx)) % 360
	PlaceMini()
end

local function CreateMini()
	mini = CreateFrame("Button", "GraphicsLabMinimapButton", Minimap)
	mini:SetSize(31, 31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = mini:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	local icon = mini:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = mini:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	mini:SetScript("OnClick", function() ns.Toggle() end)
	mini:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragMini) end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(TITLE, 1, 1, 1)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", GameTooltip_Hide)
	PlaceMini()
end

local checks = {}
function ns.MinimapShown() return not MiniDB().hide end

function ns.SetMinimapShown(on)
	MiniDB().hide = not on
	if on and not mini then CreateMini() end
	if mini then mini:SetShown(on and true or false) end
	for _, c in ipairs(checks) do c:SetChecked(on and true or false) end
end

-- A "Minimap icon" checkbox kept in step with every other one.
function ns.MinimapCheck(parent)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c.text:SetText("Minimap icon")
	c:SetChecked(ns.MinimapShown())
	c:SetScript("OnClick", function(self) ns.SetMinimapShown(self:GetChecked()) end)
	checks[#checks + 1] = c
	return c
end

---------------------------------------------------------------------------
-- Page in Esc > Options > AddOns
---------------------------------------------------------------------------

local function RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local panel = CreateFrame("Frame")
	local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", 16, -16)
	heading:SetText(TITLE)
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(140, 26)
	open:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -14)
	open:SetText("Open")
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		ns.Open()
	end)
	local slash = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	slash:SetPoint("LEFT", open, "RIGHT", 12, 0)
	slash:SetText("/glab")
	local check = ns.MinimapCheck(panel)
	check:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -2, -14)
	local key = ns.KeySetter(panel, 200)
	key:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 2, -10)
	ns.settingsPanel = panel
	ns.settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
	Settings.RegisterAddOnCategory(ns.settingsCategory)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("UPDATE_BINDINGS")
loader:SetScript("OnEvent", function(_, event)
	if event == "UPDATE_BINDINGS" then return RefreshSetters() end
	if ns.MinimapShown() then ns.SetMinimapShown(true) end
	local ok, err = pcall(RegisterSettings)
	if not ok then ns.Print("settings page: %s", tostring(err)) end
end)
