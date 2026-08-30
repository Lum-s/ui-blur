--!strict

local MIN_PART_SIZE = 0.001

local Utilities = {}

function Utilities.ProjectIn3D(camera: Camera, screenPosition: Vector2, depth: number): Vector3
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y, depth)
	return ray.Origin + ray.Direction * depth
end

function Utilities.MapStrokeSize(strokeSize: number): number
	return math.max(strokeSize, 0) * 0.2
end

function Utilities.GetCornerDiameter(uiCorner: UICorner): number
	local parent = uiCorner.Parent
	if not parent or not parent:IsA("GuiObject") then
		return 0
	end

	local shortestSide = math.min(parent.AbsoluteSize.X, parent.AbsoluteSize.Y)
	local radius = uiCorner.CornerRadius.Scale * shortestSide + uiCorner.CornerRadius.Offset
	return math.clamp(radius, 0, shortestSide / 2) * 2
end

function Utilities.FindAncestorScreenGui(instance: Instance): ScreenGui?
	local current = instance.Parent
	while current do
		if current:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end

	return nil
end

function Utilities.IsVisibleInHierarchy(guiObject: GuiObject, screenGui: ScreenGui): boolean
	if not screenGui.Enabled then
		return false
	end

	local current: Instance? = guiObject
	while current and current ~= screenGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end

	return current == screenGui
end

function Utilities.SetPartSize(part: Part, size: Vector3)
	local safeSize = Vector3.new(
		math.max(size.X, MIN_PART_SIZE),
		math.max(size.Y, MIN_PART_SIZE),
		math.max(size.Z, MIN_PART_SIZE)
	)

	part.Size = safeSize

	local mesh = part:FindFirstChild("Mesh")
	if mesh and mesh:IsA("SpecialMesh") then
		mesh.Scale = safeSize
	end
end

return Utilities
