-- functional tests (run: python3 tools/preview/run.py tools/preview/tests.luau)
local passed, failed = 0, 0
local function check(name, cond, extra)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
	end
end

local UI = loadstring(MOCK.BundleSource)()
local Win = UI:CreateWindow({ Title = "Test", Skin = "Classic" })
local tab = Win:AddTab({ Name = "Main", Icon = "crosshair", Category = "Combat" })
local g = tab:AddGroup({ Name = "G" })
local cbCount = 0
local t = g:AddToggle({ Name = "T", Flag = "t", Default = false, Callback = function()
	cbCount += 1
end })
t:AddKeybind({ Flag = "t_key", Default = "E", Mode = "Toggle" })
t:AddColorPicker({ Flag = "t_col", Default = Color3.fromRGB(255, 0, 0) })
local s = g:AddSlider({ Name = "S", Flag = "s", Min = 0, Max = 100, Default = 50, Increment = 5 })
local d = g:AddDropdown({ Name = "D", Flag = "d", Values = { "A", "B", "C" }, Default = "B" })
local m = g:AddDropdown({ Name = "M", Flag = "m", Values = { "A", "B", "C" }, Multi = true, Default = { "A" } })
local tb = g:AddTextbox({ Name = "TB", Flag = "tb", Default = "hello" })
local ig = g:AddToggle({ Name = "IG", Flag = "ig", Default = false, IgnoreConfig = true, Callback = function()
	error("IgnoreConfig toggle callback must not fire on load")
end })
local ns = g:AddToggle({ Name = "NS", Flag = "ns", Default = false, NoSave = true })
Win:AddConfigTab()
Win:AddThemeTab()
MOCK.Advance(0.2)

-- value logic
s:Set(53)
check("slider rounds to increment", s.Value == 55, s.Value)
s:Set(500)
check("slider clamps", s.Value == 100, s.Value)
d:Set("Z")
check("dropdown rejects unknown values", d.Value == "A", d.Value)
m:Set({ C = true, A = true })
check("multi dropdown keeps value order", m.Value[1] == "A" and m.Value[2] == "C")
t:Set(true)
MOCK.Advance(0.1)
check("toggle callback fired", cbCount == 1, cbCount)
check("flags table updated", UI.Flags.Values.t == true)

-- keybind attached to toggle (Toggle mode)
MOCK.Key("E")
MOCK.Advance(0.05)
check("keybind toggles its toggle", t.Value == false)
MOCK.Key("RightShift")
check("menu key closes window", Win.Open == false)
MOCK.Key("RightShift")
check("menu key opens window", Win.Open == true)

-- config round trip
s:Set(35)
d:Set("C")
tb:Set("world")
t:Set(true)
UI:SetSkin("Modern", { Instant = true })
check("SetSkin keeps values", s.Value == 35 and d.Value == "C" and t.Value == true)
check("SetSkin keeps window tab", Win.ActiveTab == tab)
UI.Config:Save("roundtrip")
s:Set(5)
d:Set("A")
tb:Set("x")
t:Set(false)
ns:Set(true)
UI:SetSkin("Onetap", { Instant = true })
cbCount = 0
local ok = UI.Config:Load("roundtrip")
MOCK.Advance(0.1)
check("config load ok", ok == true)
check("config restores values", s.Value == 35 and d.Value == "C" and tb.Value == "world" and t.Value == true, s.Value .. " " .. tostring(d.Value) .. " " .. tb.Value)
check("config restores skin", UI.SkinName == "Modern", UI.SkinName)
check("load fires callbacks", cbCount >= 1, cbCount)
check("NoSave flag untouched", ns.Value == true)
check("color picker saved", UI.Flags.Values.t_col.Color == Color3.fromRGB(255, 0, 0))
check("keybind saved", UI.Flags.Values.t_key.Key == "E")
check("config listed", table.find(UI.Config:List(), "roundtrip") ~= nil)

-- IgnoreConfig loads silently
ig:Set(true, { Silent = true })
UI.Config:Save("ig")
ig:Set(false, { Silent = true })
UI.Config:Load("ig")
MOCK.Advance(0.1)
check("IgnoreConfig value loaded", ig.Value == true)

-- rename / duplicate / delete / autoload
check("rename", UI.Config:Rename("ig", "ig2") == true)
local okDup, newName = UI.Config:Duplicate("ig2")
check("duplicate", okDup == true and UI.Config:Exists(newName), newName)
UI.Config:SetAutoload("roundtrip")
check("autoload stored", UI.Config:GetAutoload() == "roundtrip")
check("settings.json written", MOCK.Files["NovaUI/settings.json"] ~= nil)
check("delete", UI.Config:Delete("ig2") == true and not UI.Config:Exists("ig2"))

-- corrupt file -> notification, no crash
MOCK.Files["NovaUI/123456/configs/broken.json"] = "{ this is not json"
local okBroken = UI.Config:Load("broken")
check("corrupt config rejected gracefully", okBroken == false)

-- migration v1 -> v2
MOCK.Files["NovaUI/123456/configs/old.json"] = MOCK.JSONEncode({ version = 1, skin = "Classic", values = { s = 75 } })
UI.Config:Load("old")
check("v1 config migrated", s.Value == 75, s.Value)
check("migrated skin applied", UI.SkinName == "Classic", UI.SkinName)

-- export / import
s:Set(20)
local str = UI.Config:Export()
check("export string has prefix", type(str) == "string" and str:sub(1, 9) == "NOVA-CFG:")
check("export copied to clipboard", MOCK.Clipboard == str)
s:Set(90)
UI.Config:Import(str)
check("import applies", s.Value == 20, s.Value)

-- theme
UI.Theme:Set("Accent", "#ff0000", { Instant = true })
local themeStr = UI.Theme:ExportString()
UI.Theme:Reset()
check("theme reset", UI.Theme:Get("Accent") ~= Color3.fromRGB(255, 0, 0))
UI.Theme:ImportString(themeStr)
check("theme import", UI.Theme:Get("Accent") == Color3.fromRGB(255, 0, 0))
local f = Instance.new("Frame")
UI.Theme:Bind(f, "BackgroundColor3", "Accent")
UI.Theme:Set("Accent", Color3.fromRGB(0, 255, 0), { Instant = true })
check("theme binding live", f.BackgroundColor3 == Color3.fromRGB(0, 255, 0))
UI.Theme:Set("Alpha.Accent", 0.5, { Instant = true })
check("color alpha drives transparency", math.abs(f.BackgroundTransparency - 0.5) < 1e-6, f.BackgroundTransparency)
UI.Theme:SavePreset("mine")
check("custom preset listed", table.find(UI.Theme:Presets(), "custom: mine") ~= nil)

-- per-skin theme overrides survive a skin round trip
UI:SetSkin("Fatal", { Instant = true })
UI:SetSkin("Classic", { Instant = true })
check("per-skin override kept", UI.Theme:Get("Accent") == Color3.fromRGB(0, 255, 0))

-- ESP settings
local esp = UI:GetESPSettings()
check("esp settings table", type(esp) == "table" and esp.BoxType ~= nil)

-- mobile pins
UI.Mobile:Pin(t)
check("pin stored", UI.Mobile:IsPinned(t))
UI.Config:Save("pins")
UI.Mobile:Unpin(t)
UI.Config:Load("pins")
check("pins restored from config", UI.Mobile:IsPinned(t))

-- search
check("search finds elements", #Win:Search("slid") == 0 and #Win:Search("TB") >= 1)

-- destroy
local gui = UI.ScreenGui
UI:Destroy()
check("destroy removes gui", gui.Parent == nil)
check("global cleared", getgenv().__NOVA_UI_INSTANCE == nil)

print(("TESTS: %d passed, %d failed"):format(passed, failed))
