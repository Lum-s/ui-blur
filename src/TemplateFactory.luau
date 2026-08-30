--!strict

export type MeshIds = {
	Corner: string,
	Plane: string,
}

local TEMPLATE_COLOR = Color3.new(
	0.6392157077789307,
	0.6352941393852234,
	0.6470588445663452
)
local TEMPLATE_POSITION = Vector3.new(-9.350002288818359, 0, 5.54656982421875)
local TEMPLATE_SIZE = Vector3.new(
	0.001000000047497451,
	0.001000000047497451,
	0.001000000047497451
)

local TemplateFactory = {}

local function createPart(name: string, meshId: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = TEMPLATE_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Position = TEMPLATE_POSITION
	part.Size = TEMPLATE_SIZE
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Mesh"
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = meshId
	mesh.Scale = TEMPLATE_SIZE
	mesh.Parent = part

	return part
end

function TemplateFactory.Populate(parent: Folder, meshIds: MeshIds)
	if not parent:FindFirstChild("Corner") then
		local corner = createPart("Corner", meshIds.Corner)
		corner.Parent = parent
	end

	if not parent:FindFirstChild("Plane") then
		local plane = createPart("Plane", meshIds.Plane)
		plane.Parent = parent
	end
end

return TemplateFactory
