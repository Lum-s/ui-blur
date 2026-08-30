--!strict

local templateFactoryModule = script.Parent.Parent:WaitForChild("TemplateFactory")
assert(templateFactoryModule:IsA("ModuleScript"), "TemplateFactory must be a ModuleScript")

local TemplateFactory = require(templateFactoryModule)

return function(parent: Folder)
	TemplateFactory.Populate(parent, {
		Corner = "rbxassetid://99074379768397",
		Plane = "rbxassetid://71290362392750",
	})
end
