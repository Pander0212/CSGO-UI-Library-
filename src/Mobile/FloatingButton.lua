--[[
	Floating open button: draggable (mouse + touch, drag threshold), snaps to the nearest screen edge,
	avoids the default touch controls, position saved in config, look provided by the skin.
]]
local Util = require("Core/Util")
local Tween = require("Core/Tween")

local FB = {}

function FB.Render(mobile, ctx)
	local lib = mobile.Library
	local view = ctx.Skin.FloatingButton(ctx)
	local b = view.Root
	b.Parent = ctx.Layers.Notify
	b.ZIndex = 50
	local size = Vector2.new(b.Size.X.Offset, b.Size.Y.Offset)
	local screen = lib:ScreenSize()
	local inset = Util.GuiInset()
	local x = mobile.Button.X or (screen.X - size.X - 10)
	local y = mobile.Button.Y or (inset.Y + 70)
	local p = mobile:Resolve(Vector2.new(x, y), size)
	b.Position = UDim2.fromOffset(p.X, p.Y)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local function snap()
		local sc2 = lib:ScreenSize()
		local cur = Vector2.new(b.Position.X.Offset, b.Position.Y.Offset)
		local left = cur.X + size.X / 2 < sc2.X / 2
		local target = Vector2.new(left and 8 or (sc2.X - size.X - 8), cur.Y)
		target = mobile:Resolve(target, size)
		Tween.Play(b, { Position = UDim2.fromOffset(target.X, target.Y) }, 0.25, Enum.EasingStyle.Back)
		mobile.Button.X, mobile.Button.Y = target.X, target.Y
	end
	ctx.Maid:Give(lib.Input:Drag(b, {
		Target = b,
		Threshold = 10,
		GetScale = function()
			return lib.CurrentScale
		end,
		OnStart = function()
			Tween.Play(sc, { Scale = 0.92 }, 0.1)
		end,
		OnEnd = function(moved)
			Tween.Play(sc, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
			if moved then
				snap()
			end
		end,
		OnTap = function()
			ctx:Sound("SoundClick")
			if lib.Window then
				lib.Window:Toggle()
			end
		end,
		LongPress = function()
			-- long press: quick menu for quick toggles
			ctx.Skin.ContextMenu(ctx, b, {
				{ Text = lib.Window and lib.Window.Open and "Close menu" or "Open menu", Callback = function()
					lib.Window:Toggle()
				end },
				{ Text = mobile.EditMode and "Finish editing" or "Edit quick toggles", Callback = function()
					mobile:SetEditMode(not mobile.EditMode)
				end },
			})
		end,
	}))
	return view
end

return FB
