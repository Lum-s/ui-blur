--!strict

local templateFactoryModule = script.Parent.Parent:WaitForChild("TemplateFactory")
assert(templateFactoryModule:IsA("ModuleScript"), "TemplateFactory must be a ModuleScript")

local TemplateFactory = require(templateFactoryModule)

return function(parent: Folder)
	TemplateFactory.Populate(parent, {
		Corner = "rbxassetid://116663952860129",
		Plane = "rbxassetid://91153403946406",
	})
end
