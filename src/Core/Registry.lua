--[[
	Skin registry. Skins register themselves here; UI:RegisterSkin(skin) adds custom ones.
]]
local Registry = { Skins = {}, Order = {} }

function Registry:Register(skin)
	assert(type(skin) == "table" and type(skin.Name) == "string", "skin needs a Name")
	if not self.Skins[skin.Name] then
		table.insert(self.Order, skin.Name)
	end
	self.Skins[skin.Name] = skin
	return skin
end

function Registry:Get(name)
	return self.Skins[name]
end

function Registry:List()
	return table.clone(self.Order)
end

return Registry
