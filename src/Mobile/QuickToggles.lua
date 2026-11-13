--[[
	Quick toggles: Pinnable toggles can be pinned to the screen as small buttons.
	Tap = toggle (bounce), drag = move (threshold), long-press = menu (size S/M/L, transparency, unpin,
	edit mode). Edit mode shows a grid and snaps positions to it. Synced with the menu both ways.
]]
local Util = require("Core/Util")

local QT = {}
local GRID = 16

local function sizeOf(view)
	return Vector2.new(view.Root.Size.X.Offset, view.Root.Size.Y.Offset)
end

function QT.Render(mobile, ctx, el)
	local lib = mobile.Library
	local flag = el.Flag
	local data = mobile.Pins[flag]
	if not data then
		return
	end
	QT.Remove(mobile, flag, true)
	local view = ctx.Skin.QuickToggle(ctx, el, data.size or "M")
	local b = view.Root
	b.Parent = ctx.Layers.Mobile
	b.ZIndex = 4
	local p = mobile:Resolve(Vector2.new(data.x, data.y), sizeOf(view))
	b.Position = UDim2.fromOffset(p.X, p.Y)
	view:Update(el.Value, true)
	if data.alpha and data.alpha > 0 then
		view:SetAlpha(data.alpha)
	end
	local conn = el.Changed:Connect(function(v)
		view:Update(v)
		view:Bounce()
	end)
	local function clampSnap(pos)
		local x, y = pos.X.Offset, pos.Y.Offset
		if mobile.EditMode then
			x = math.floor(x / GRID + 0.5) * GRID
			y = math.floor(y / GRID + 0.5) * GRID
		end
		local r = mobile:Resolve(Vector2.new(x, y), sizeOf(view))
		if mobile.EditMode then
			return UDim2.fromOffset(r.X, r.Y)
		end
		return UDim2.fromOffset(x, y)
	end
	local drag = lib.Input:Drag(b, {
		Target = b,
		Threshold = 10,
		GetScale = function()
			return lib.CurrentScale
		end,
		Clamp = clampSnap,
		OnEnd = function(moved)
			if moved then
				local r = mobile:Resolve(Vector2.new(b.Position.X.Offset, b.Position.Y.Offset), sizeOf(view))
				b.Position = UDim2.fromOffset(r.X, r.Y)
				data.x, data.y = r.X, r.Y
			end
		end,
		OnTap = function()
			if mobile.EditMode or el:IsDisabled() then
				return
			end
			ctx:Sound("SoundToggle")
			el:Set(not el.Value)
		end,
		LongPress = function()
			local function setSize(s)
				data.size = s
				QT.Render(mobile, ctx, el)
			end
			ctx.Skin.ContextMenu(ctx, b, {
				{ Text = "Size: Small", Selected = data.size == "S", Callback = function()
					setSize("S")
				end },
				{ Text = "Size: Medium", Selected = data.size == "M", Callback = function()
					setSize("M")
				end },
				{ Text = "Size: Large", Selected = data.size == "L", Callback = function()
					setSize("L")
				end },
				{ Text = "Opacity: " .. math.floor((1 - (data.alpha or 0)) * 100) .. "%", Callback = function()
					local steps = { 0, 0.25, 0.5 }
					local i = (table.find(steps, data.alpha or 0) or 1) % #steps + 1
					data.alpha = steps[i]
					view:SetAlpha(data.alpha)
				end },
				{ Text = mobile.EditMode and "Finish editing" or "Edit layout", Callback = function()
					mobile:SetEditMode(not mobile.EditMode)
				end },
				{ Text = "Unpin", Danger = true, Callback = function()
					el:Pin(false)
				end },
			})
		end,
	})
	mobile.Views[flag] = { View = view, Conn = conn, Drag = drag }
	if mobile.EditMode then
		view:SetEditing(true)
	end
	return view
end

function QT.Remove(mobile, flag)
	local v = mobile.Views[flag]
	if v then
		v.Conn.Disconnect()
		v.Drag:Clean()
		v.View.Root:Destroy()
		mobile.Views[flag] = nil
	end
end

function QT.RenderAll(mobile, ctx)
	for flag in pairs(mobile.Pins) do
		local el = mobile.Library.Flags.Elements[flag]
		if el then
			QT.Render(mobile, ctx, el)
		end
	end
	if mobile.EditMode then
		QT.SetEditMode(mobile, true)
	end
end

function QT.Teardown(mobile)
	for flag in pairs(mobile.Views) do
		QT.Remove(mobile, flag)
	end
	if mobile.GridView then
		mobile.GridView:Destroy()
		mobile.GridView = nil
	end
end

-- edit mode: grid overlay + "Done" button, positions snap to the grid
function QT.SetEditMode(mobile, on)
	local ctx = mobile.Ctx
	if mobile.GridView then
		mobile.GridView:Destroy()
		mobile.GridView = nil
	end
	for _, v in pairs(mobile.Views) do
		v.View:SetEditing(on)
	end
	if not (on and ctx) then
		return
	end
	local screen = mobile.Library:ScreenSize()
	local grid = ctx:Frame(ctx.Layers.Mobile, { Name = "EditGrid", Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	for x = 0, screen.X, GRID * 4 do
		ctx:Frame(grid, { Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 1 }, "Accent", { Alpha = 0.85 })
	end
	for y = 0, screen.Y, GRID * 4 do
		ctx:Frame(grid, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), ZIndex = 1 }, "Accent", { Alpha = 0.85 })
	end
	for _, z in ipairs(mobile:SafeZones()) do
		local f = ctx:Frame(grid, { Position = UDim2.fromOffset(z.Min.X, z.Min.Y), Size = UDim2.fromOffset(z.Max.X - z.Min.X, z.Max.Y - z.Min.Y), ZIndex = 2 }, "Error", { Alpha = 0.85 })
		ctx:Text(f, { Text = "reserved (touch controls)", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }, "Error", "FontBody", "SmallTextSize")
	end
	local done = ctx:New("TextButton", {
		Parent = grid,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Util.GuiInset().Y + 10),
		Size = UDim2.fromOffset(160, 40),
		Text = "Done editing",
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		ZIndex = 3,
	}, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(done, "SmallCornerRadius")
	done.Activated:Connect(function()
		mobile:SetEditMode(false)
	end)
	mobile.GridView = grid
end

return QT
