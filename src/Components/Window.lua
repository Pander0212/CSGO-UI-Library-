--[[
	Window logic: tabs, categories, open state, position/size state, toggle key.
	The view (layout) is produced by the active skin; on UI:SetSkin the view is rebuilt from
	this logic tree so all values, the active tab and the window position survive.
]]
local Tab = require("Components/Tab")
local Signal = require("Core/Signal")
local Util = require("Core/Util")

local Types = require("Components/Types")

local Window = {}
Window.__index = Window

local function Types_keyName(k)
	return Types.KeyName(k)
end

function Window.new(lib, opts)
	opts = opts or {}
	local self = setmetatable({
		Library = lib,
		Options = opts,
		Title = opts.Title or opts.Name,
		Tabs = {},
		Categories = {},
		Open = true,
		ToggleKey = Types_keyName(opts.ToggleKey) or "RightShift",
		State = { Position = nil, Sizes = {}, Tab = nil, Sub = nil },
		VisibilityChanged = Signal.new(),
		TabChanged = Signal.new(),
	}, Window)
	if opts.Size and typeof(opts.Size) == "UDim2" then
		self.State.Sizes["*"] = { opts.Size.X.Offset, opts.Size.Y.Offset }
	elseif typeof(opts.Size) == "Vector2" then
		self.State.Sizes["*"] = { opts.Size.X, opts.Size.Y }
	end
	return self
end

function Window:AddCategory(name)
	if not table.find(self.Categories, name) then
		table.insert(self.Categories, name)
	end
	return name
end

function Window:AddTab(opts)
	local tab = Tab.new(self, opts)
	if tab.Category then
		self:AddCategory(tab.Category)
	end
	table.insert(self.Tabs, tab)
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderTab(tab)
	end
	if not self.ActiveTab then
		self.ActiveTab = tab
	end
	return tab
end

function Window:GetTab(name)
	for _, t in ipairs(self.Tabs) do
		if t.Name == name then
			return t
		end
	end
	return nil
end

function Window:SelectTab(tab, sub)
	if type(tab) == "string" then
		tab = self:GetTab(tab)
	end
	if not tab then
		return
	end
	local subtab = sub
	if type(sub) == "string" then
		for _, s in ipairs(tab.SubTabs) do
			if s.Name == sub then
				subtab = s
			end
		end
	end
	tab:_default()
	subtab = subtab or tab.ActiveSub or tab.SubTabs[1]
	self.ActiveTab = tab
	tab.ActiveSub = subtab
	self.State.Tab = tab.Name
	self.State.Sub = subtab and subtab.Name
	if self.View and self.View.SelectTab then
		self.View:SelectTab(tab, subtab)
	end
	self.TabChanged:Fire(tab, subtab)
end

function Window:SetOpen(open, instant)
	self.Open = open ~= false
	if self.View and self.View.SetOpen then
		self.View:SetOpen(self.Open, instant)
	end
	self.VisibilityChanged:Fire(self.Open)
	if not self.Open then
		self.Library.Config:OnClose()
	end
end

function Window:Toggle()
	self:SetOpen(not self.Open)
end

function Window:SetToggleKey(key)
	self.ToggleKey = Types.KeyName(key)
end

-- size for the active skin: saved resize > CreateWindow size > theme default
function Window:GetSize()
	local lib = self.Library
	local s = self.State.Sizes[lib.SkinName] or self.State.Sizes["*"]
	local w, h
	if s then
		w, h = s[1], s[2]
	else
		w, h = lib.Theme:Get("WindowWidth"), lib.Theme:Get("WindowHeight")
	end
	-- fit the screen (mobile) below the top bar inset
	local vp = lib:ScreenSize()
	local top = Util.GuiInset().Y / (lib.CurrentScale or 1)
	w = math.min(w, vp.X - 16)
	h = math.min(h, vp.Y - top - 8)
	return Vector2.new(math.floor(w), math.floor(h))
end

function Window:SetSize(w, h)
	self.State.Sizes[self.Library.SkinName] = { w, h }
	if self.View and self.View.Root then
		self.View.Root.Size = UDim2.fromOffset(w, h)
	end
end

function Window:GetState()
	local pos = self.State.Position
	local size = self:GetSize()
	return {
		x = pos and pos.X or nil,
		y = pos and pos.Y or nil,
		w = size.X,
		h = size.Y,
		sizes = Util.DeepCopy(self.State.Sizes),
		tab = self.ActiveTab and self.ActiveTab.Name or nil,
		sub = self.ActiveTab and self.ActiveTab.ActiveSub and self.ActiveTab.ActiveSub.Name or nil,
		open = self.Open,
		key = self.ToggleKey,
	}
end

function Window:SetState(s)
	if type(s) ~= "table" then
		return
	end
	if tonumber(s.x) and tonumber(s.y) then
		self.State.Position = Vector2.new(s.x, s.y)
		if self.View and self.View.Root then
			self.View.Root.Position = UDim2.fromOffset(s.x, s.y)
		end
	end
	if type(s.sizes) == "table" then
		self.State.Sizes = s.sizes
		local cur = self:GetSize()
		if self.View and self.View.Root then
			self.View.Root.Size = UDim2.fromOffset(cur.X, cur.Y)
		end
	end
	if s.tab then
		self:SelectTab(s.tab, s.sub)
	end
end

-- position (top-left, in UI root space) – centered when never moved
function Window:GetPosition()
	if self.State.Position then
		return self.State.Position
	end
	local vp = self.Library:ScreenSize()
	local size = self:GetSize()
	-- centered in the area below the Roblox top bar (GuiService:GetGuiInset)
	local top = Util.GuiInset().Y / (self.Library.CurrentScale or 1)
	local y = top + math.max(0, (vp.Y - top - size.Y) / 2)
	return Vector2.new(math.floor((vp.X - size.X) / 2), math.floor(y))
end

function Window:AddThemeTab(opts)
	return require("Tabs/Appearance")(self, opts)
end

function Window:AddConfigTab(opts)
	return require("Tabs/ConfigTab")(self, opts)
end

function Window:Notify(opts)
	return self.Library:Notify(opts)
end

-- jump to an element (used by search)
function Window:Focus(element)
	local group = element.Group
	while group and group.IsPopout and group.Owner do
		group = group.Owner.Group
	end
	local sub = group and group.Page
	if not sub then
		return
	end
	self:SetOpen(true)
	self:SelectTab(sub.Tab, sub)
	if self.View and self.View.Focus then
		self.View:Focus(element)
	end
end

-- all searchable elements: { {Element, Path} }
function Window:Search(query)
	query = string.lower(query or "")
	local out = {}
	if query == "" then
		return out
	end
	for _, tab in ipairs(self.Tabs) do
		for _, sub in ipairs(tab.SubTabs) do
			for _, g in ipairs(sub.Groups) do
				for _, el in ipairs(g.Elements) do
					local name = tostring(el.Name or "")
					if el.Kind ~= "Divider" and string.find(string.lower(name), query, 1, true) then
						table.insert(out, { Element = el, Path = tab.Name .. " › " .. g.Name })
					end
				end
			end
		end
	end
	return out
end

return Window
