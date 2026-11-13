--[[
	Tab + SubTab logic. A tab always has at least one SubTab (created lazily);
	skins decide where sub-tab buttons are drawn and hide them when there is only one.
]]
local Group = require("Components/Group")

local SubTab = {}
SubTab.__index = SubTab

function SubTab.new(tab, opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	opts = opts or {}
	return setmetatable({ Tab = tab, Library = tab.Library, Name = opts.Name or "Main", Icon = opts.Icon, Groups = {} }, SubTab)
end

function SubTab:AddGroup(opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	local g = Group.new(self.Library, self, opts)
	table.insert(self.Groups, g)
	if self.PageView and self.Library.Renderer then
		self.Library.Renderer:RenderGroup(g)
	end
	return g
end
SubTab.AddSection = SubTab.AddGroup
SubTab.AddGroupbox = SubTab.AddGroup
function SubTab:AddLeftGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Left" })
end
function SubTab:AddRightGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Right" })
end

local Tab = {}
Tab.__index = Tab

function Tab.new(window, opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	opts = opts or {}
	return setmetatable({
		Window = window,
		Library = window.Library,
		Name = opts.Name or "Tab",
		Icon = opts.Icon or "dot",
		Category = opts.Category or opts.Section,
		Options = opts,
		SubTabs = {},
	}, Tab)
end

function Tab:AddSubTab(opts)
	local s = SubTab.new(self, opts)
	-- an implicit "Main" subtab that is still empty gets replaced by the first explicit one
	if #self.SubTabs == 1 and self.SubTabs[1].Implicit and #self.SubTabs[1].Groups == 0 then
		local old = self.SubTabs[1]
		self.SubTabs[1] = s
		if old.PageView and old.PageView.Root then
			old.PageView.Root:Destroy()
			old.PageView = nil
		end
	else
		table.insert(self.SubTabs, s)
	end
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderSubTab(s)
	end
	return s
end

function Tab:_default()
	if #self.SubTabs == 0 then
		local s = SubTab.new(self, { Name = "Main" })
		s.Implicit = true
		table.insert(self.SubTabs, s)
		if self.View and self.Library.Renderer then
			self.Library.Renderer:RenderSubTab(s)
		end
	end
	return self.SubTabs[1]
end

function Tab:AddGroup(opts)
	return self:_default():AddGroup(opts)
end
Tab.AddSection = Tab.AddGroup
Tab.AddGroupbox = Tab.AddGroup
function Tab:AddLeftGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Left" })
end
function Tab:AddRightGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Right" })
end

function Tab:Select(sub)
	self.Window:SelectTab(self, sub)
end

Tab.SubTab = SubTab
return Tab
