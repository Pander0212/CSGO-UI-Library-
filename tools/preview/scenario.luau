-- runs example.lua through the Classic loader, then captures every skin + interaction states
local co = coroutine.create(function()
	local f = loadstring(MOCK.ExampleSource, "example")
	f()
	MOCK.ExampleDone = true
end)
local ok, err = coroutine.resume(co)
if not ok then
	print("EXAMPLE ERROR: " .. tostring(err))
end
MOCK.Advance(0.3)
local UI = getgenv().__NOVA_UI_INSTANCE
assert(UI, "library not loaded")
MOCK.Dump("classic_loader", UI.ScreenGui)
MOCK.Click(MOCK.FindText(UI.Layers.Loader, "load"))
MOCK.Advance(1.1)
MOCK.Dump("classic_loader_progress", UI.ScreenGui)
MOCK.Advance(4)
assert(MOCK.ExampleDone, "example did not finish")
MOCK.Advance(0.5)

local Win = UI.Window
local function shot(name)
	MOCK.Advance(0.6)
	MOCK.Dump(name, UI.ScreenGui)
end
-- clear transient notifications for clean shots
local function clearNotify()
	for _, n in ipairs(table.clone(UI.Renderer.Notifications)) do
		pcall(n.Close, n, true)
	end
	UI.Renderer.Notifications = {}
end

local SKINS = SCENARIO_SKINS or { "Classic", "Modern", "Onetap", "Fatal", "Dashboard" }
for _, skin in ipairs(SKINS) do
	local key = string.lower(skin)
	UI:SetSkin(skin, { Instant = true })
	clearNotify()
	Win:SelectTab("Aimbot")
	shot(key .. "_window")
	Win:SelectTab("Visuals")
	shot(key .. "_visuals")
	Win:SelectTab("Appearance")
	shot(key .. "_appearance")
	Win:SelectTab("Aimbot")
	-- open dropdown + color picker + popout
	local hitbox = UI.Flags.Elements.aim_hitbox
	if hitbox and hitbox.View and hitbox.View.Hit then
		MOCK.Click(hitbox.View.Hit)
	end
	shot(key .. "_dropdown")
	UI.Renderer:CloseOverlays()
	local fovc = UI.Flags.Elements.aim_fov_circle
	if fovc and fovc.View then
		MOCK.Click(fovc.View.Root)
	end
	shot(key .. "_colorpicker")
	UI.Renderer:CloseOverlays()
	UI:Notify({ Title = "Config", Content = "Saved 'legit' successfully.", Type = "Success" })
	UI:Notify({ Title = "Warning", Content = "Silent aim may be detected in this game.", Type = "Warning" })
	shot(key .. "_notify")
	clearNotify()
end

-- loaders of every skin -------------------------------------------------------------
UI:SetWatermark(false)
UI:SetKeybindList(false)
local PRODUCTS = {
	{ Name = "Universal", Status = "Undetected", Expires = "Never", Game = "All games" },
	{ Name = "Arsenal", Status = "Undetected", Expires = "31.12.2026", Game = "Arsenal", Icon = "crosshair" },
	{ Name = "Phantom Forces", Status = "Updating", Expires = "31.12.2026", Game = "Phantom Forces", Icon = "target" },
}
for _, skin in ipairs(SKINS) do
	local key = string.lower(skin)
	UI:SetSkin(skin, { Instant = true })
	Win:SetOpen(false, true)
	clearNotify()
	local h = UI:Loader({ Skin = skin, Yield = false, Title = "Nova UI", Products = PRODUCTS })
	MOCK.Advance(1.2)
	MOCK.Dump(key .. "_loader", UI.ScreenGui)
	h.Start(2)
	MOCK.Advance(1.3)
	MOCK.Dump(key .. "_loader_progress", UI.ScreenGui)
	MOCK.Advance(4)
end
Win:SetOpen(true, true)

-- mobile (phone landscape, touch) ------------------------------------------------------
MOCK.SetViewport(844, 390, true)
UI:SetMobileMode("Auto")
for _, flag in ipairs({ "aim_enabled", "trig_enabled", "mv_fly", "mv_speed" }) do
	local el = UI.Flags.Elements[flag]
	if el then
		UI.Mobile:Pin(el)
	end
end
UI.Flags.Elements.mv_fly:Set(true)
for _, skin in ipairs({ "Modern", "Classic", "Dashboard" }) do
	local key = string.lower(skin)
	UI:SetSkin(skin, { Instant = true })
	clearNotify()
	Win:SetOpen(true, true)
	Win:SelectTab("Aimbot")
	shot("mobile_" .. key .. "_window")
	Win:SetOpen(false, true)
	shot("mobile_" .. key .. "_hud")
end
UI.Mobile:SetEditMode(true)
shot("mobile_dashboard_editmode")
UI.Mobile:SetEditMode(false)
print("mobile scale", UI.CurrentScale)
