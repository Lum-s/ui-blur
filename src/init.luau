--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsClient(), "UIBlur must be required from the client")

local utilitiesModule = script:WaitForChild("Utilities")
assert(utilitiesModule:IsA("ModuleScript"), "Utilities must be a ModuleScript")
local Utilities = require(utilitiesModule)

local normalFolderInstance = script:WaitForChild("Normal")
local fragmentedFolderInstance = script:WaitForChild("Fragmented")
assert(normalFolderInstance:IsA("Folder"), "Normal must be a Folder")
assert(fragmentedFolderInstance:IsA("Folder"), "Fragmented must be a Folder")

local normalFolder: Folder = normalFolderInstance
local fragmentedFolder: Folder = fragmentedFolderInstance

local normalCreatorModule = normalFolder:WaitForChild("CreateTemplates")
local fragmentedCreatorModule = fragmentedFolder:WaitForChild("CreateTemplates")
assert(normalCreatorModule:IsA("ModuleScript"), "Normal.CreateTemplates must be a ModuleScript")
assert(fragmentedCreatorModule:IsA("ModuleScript"), "Fragmented.CreateTemplates must be a ModuleScript")

local createNormalTemplates = require(normalCreatorModule) :: (Folder) -> ()
local createFragmentedTemplates = require(fragmentedCreatorModule) :: (Folder) -> ()

createNormalTemplates(normalFolder)
createFragmentedTemplates(fragmentedFolder)

local PROJECTION_DEPTH = 0.02
local BASE_SCALE = 6.8
local MAX_GLASS_OPACITY = 0.02
local MIN_PART_SIZE = 0.001
local MIN_GRAPHICS_QUALITY = 8

export type BlurOptions = {
	-- Uses the fragmented mesh set when true.
	Fragmented: boolean?,
	-- Places this blur in the color-inversion container when true.
	Inverted: boolean?,
	-- Expands the rendered blur outside the GuiObject. Values below zero are clamped to zero.
	StrokeSize: number?,
	-- Per-instance blur strength from 0 (off) to 1 (full). Values are clamped.
	Intensity: number?,
	-- Initial rendering state. Defaults to true.
	Enabled: boolean?,
}

export type Blur = {
	--- Permanently releases the blur model and every instance connection.
	Destroy: (self: Blur) -> (),
	--- Returns whether this blur is enabled.
	GetEnabled: (self: Blur) -> boolean,
	--- Returns the per-instance intensity in the range 0–1.
	GetIntensity: (self: Blur) -> number,
	--- Returns the unscaled stroke size supplied by the caller.
	GetStrokeSize: (self: Blur) -> number,
	--- Enables rounded geometry when the GuiObject has a UICorner.
	SetCornered: (self: Blur, cornered: boolean) -> (),
	--- Enables or disables rendering without destroying the blur.
	SetEnabled: (self: Blur, enabled: boolean) -> (),
	--- Sets per-instance blur intensity. Values are clamped to 0–1.
	SetIntensity: (self: Blur, intensity: number) -> (),
	--- Sets the outward blur expansion. Values below zero are clamped to zero.
	SetStrokeSize: (self: Blur, strokeSize: number) -> (),
}

export type UIBlurModule = {
	--- Creates a lifecycle-managed blur for a GuiObject inside a ScreenGui.
	new: (guiObject: GuiObject, options: BlurOptions?) -> Blur,
	--- Destroys every blur currently managed by this module.
	DestroyAll: () -> (),
	--- Returns the shared DepthOfField intensity in the range 0–1.
	GetGlobalIntensity: () -> number,
	--- Sets the shared DepthOfField intensity. Values are clamped to 0–1.
	SetGlobalIntensity: (intensity: number) -> (),
}

-- Backward-compatible public type names.
export type UIBlur = Blur
export type UIBlurArguments = BlurOptions

type FrameCache = {
	AbsolutePosition: Vector2?,
	AbsoluteRotation: number?,
	AbsoluteSize: Vector2?,
	CameraCFrame: CFrame?,
	CornerDiameter: number?,
	FieldOfView: number?,
	ViewportSize: Vector2?,
}

type BlurData = {
	_blurEffect: BlurEffect?,
	_cache: FrameCache,
	_connections: { RBXScriptConnection },
	_cornered: boolean,
	_corners: { Part },
	_destroyed: boolean,
	_dirty: boolean,
	_enabled: boolean,
	_fragmented: boolean,
	_guiObject: GuiObject,
	_intensity: number,
	_inverted: boolean,
	_mainPlane: Part,
	_model: Model,
	_planes: { Part },
	_rendered: boolean,
	_screenGui: ScreenGui?,
	_strokeSize: number,
	_uiCorner: UICorner?,
}

type BlurInternal = Blur & BlurData

type AutoRecord = {
	Blur: Blur,
	Connections: { RBXScriptConnection },
	Marker: BlurEffect,
}

--[=[
	A client-side UI blur renderer that projects lightweight geometry in front of
	the current camera. Each blur follows its target [GuiObject] through animation,
	reparenting, visibility changes, camera movement, and destruction.

	All instances share one render connection. Static UI is cached, so geometry is
	only rewritten when a relevant UI or camera value changes.

	@class UIBlur
	@client
]=]
local BlurClass = {}
BlurClass.__index = BlurClass

--[=[
	Options accepted by [UIBlur.new]. Every field is optional.

	@interface BlurOptions
	@within UIBlur
	@field Fragmented boolean? -- Use the fragmented mesh set. Defaults to `false`.
	@field Inverted boolean? -- Render through the color-inversion container. Defaults to `false`.
	@field StrokeSize number? -- Outward blur expansion. Negative values are clamped to zero.
	@field Intensity number? -- Per-instance strength from `0` to `1`. Defaults to `1`.
	@field Enabled boolean? -- Initial rendering state. Defaults to `true`.
]=]

--[=[
	Creates and starts managing a blur for `guiObject`.

	The target must already be a descendant of a [ScreenGui]. The returned object
	cleans itself up when the target is destroyed.

	```lua
	local blur = UIBlur.new(frame, {
		Intensity = 0.8,
		StrokeSize = 1,
		Fragmented = false,
	})
	```

	@function new
	@within UIBlur
	@param guiObject GuiObject -- UI object whose bounds should be blurred.
	@param options BlurOptions? -- Optional initial configuration.
	@return UIBlur -- Lifecycle-managed blur instance.
	@error "GuiObject must be a descendant of a ScreenGui" -- The target is not mounted in screen UI.
	@tag constructor
	@client
]=]

--[=[
	Changes this blur's strength without affecting other blur instances. Values
	outside `0–1` are clamped. A value of `0` makes the blur geometry invisible.

	```lua
	blur:SetIntensity(0.5)
	```

	@method SetIntensity
	@within UIBlur
	@param intensity number -- New per-instance strength from `0` to `1`.
	@tag configuration
	@client
]=]

--[=[
	Returns this blur's current normalized strength.

	```lua
	local intensity = blur:GetIntensity()
	```

	@method GetIntensity
	@within UIBlur
	@return number -- Current value from `0` to `1`.
	@tag configuration
	@client
]=]

--[=[
	Enables or disables rendering without releasing the instance. Re-enabling
	forces the geometry to synchronize with the latest UI state.

	```lua
	blur:SetEnabled(menu.Visible)
	```

	@method SetEnabled
	@within UIBlur
	@param enabled boolean -- Whether this blur may render.
	@tag configuration
	@client
]=]

--[=[
	Returns whether this blur is enabled.

	@method GetEnabled
	@within UIBlur
	@return boolean -- Current enabled state.
	@tag configuration
	@client
]=]

--[=[
	Changes the outward expansion around the target UI. Negative and NaN values
	are normalized to zero.

	```lua
	blur:SetStrokeSize(2)
	```

	@method SetStrokeSize
	@within UIBlur
	@param strokeSize number -- Unscaled expansion value.
	@tag configuration
	@client
]=]

--[=[
	Returns the unscaled stroke size supplied by the caller.

	@method GetStrokeSize
	@within UIBlur
	@return number -- Current non-negative stroke size.
	@tag configuration
	@client
]=]

--[=[
	Enables or disables rounded blur geometry. Rounded geometry is only enabled
	when the target currently contains a [UICorner]. Child additions and removals
	are detected automatically, so most callers do not need this method.

	@method SetCornered
	@within UIBlur
	@param cornered boolean -- Whether rounded geometry should be used.
	@tag configuration
	@client
]=]

--[=[
	Permanently disconnects this blur and destroys its render model. Calling
	`Destroy` more than once is safe.

	```lua
	blur:Destroy()
	```

	@method Destroy
	@within UIBlur
	@tag lifecycle
	@client
]=]

--[=[
	Changes the shared [DepthOfFieldEffect] strength used by every blur instance.
	Values outside `0–1` are clamped.

	```lua
	UIBlur.SetGlobalIntensity(0.75)
	```

	@function SetGlobalIntensity
	@within UIBlur
	@param intensity number -- Shared depth-of-field strength from `0` to `1`.
	@tag configuration
	@client
]=]

--[=[
	Returns the current shared [DepthOfFieldEffect] strength.

	@function GetGlobalIntensity
	@within UIBlur
	@return number -- Current global value from `0` to `1`.
	@tag configuration
	@client
]=]

--[=[
	Destroys every blur currently managed by this module, including automatically
	created instances.

	```lua
	UIBlur.DestroyAll()
	```

	@function DestroyAll
	@within UIBlur
	@tag lifecycle
	@client
]=]

local activeBlurs: { [BlurInternal]: boolean } = {}
local automaticRecords: { [GuiObject]: AutoRecord } = {}
local renderConnection: RBXScriptConnection? = nil

local currentCamera: Camera? = Workspace.CurrentCamera
local gameSettings = UserSettings().GameSettings
local qualityLevel = gameSettings.SavedQualityLevel
local globalIntensity = 1
local invertedCount = 0

local container = Instance.new("Folder")
container.Name = "UIBlur"
container.Parent = currentCamera

local invertedContainer = Instance.new("Model")
invertedContainer.Name = "Inverted"
invertedContainer.Parent = container

local depthOfField = Instance.new("DepthOfFieldEffect")
depthOfField.Name = "UIBlur"
depthOfField.FarIntensity = 0
depthOfField.FocusDistance = 0
depthOfField.InFocusRadius = 0
depthOfField.NearIntensity = globalIntensity
depthOfField.Parent = Lighting

local registerBlur: (blur: BlurInternal) -> ()
local unregisterBlur: (blur: BlurInternal) -> ()

local function normalizeIntensity(intensity: number): number
	if intensity ~= intensity then
		return 0
	end
	return math.clamp(intensity, 0, 1)
end

local function intensityToTransparency(intensity: number): number
	return 1 - normalizeIntensity(intensity) * MAX_GLASS_OPACITY
end

local function graphicsQualityAllowsBlur(): boolean
	return qualityLevel.Value == 0 or qualityLevel.Value >= MIN_GRAPHICS_QUALITY
end

local function cloneTemplate(fragmented: boolean, name: "Corner" | "Plane"): Part
	local sourceFolder = if fragmented then fragmentedFolder else normalFolder
	local template = sourceFolder:FindFirstChild(name)
	assert(template and template:IsA("Part"), `{sourceFolder.Name}.{name} must be a Part`)

	local clone = template:Clone()
	clone.Material = Enum.Material.Glass
	return clone
end

local function ensureInverter()
	local existing = invertedContainer:FindFirstChild("Inverter")
	if existing and existing:IsA("Highlight") then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "Inverter"
	highlight.Adornee = invertedContainer
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.new(0.5, 0.5, 0.5)
	highlight.FillTransparency = -1
	highlight.OutlineColor = Color3.new(0, 0, 0)
	highlight.OutlineTransparency = 1
	highlight.Parent = invertedContainer
end

local function removeInverter()
	local inverter = invertedContainer:FindFirstChild("Inverter")
	if inverter then
		inverter:Destroy()
	end
end

local function setPartTransparency(part: Part, transparency: number)
	if part.Transparency ~= transparency then
		part.Transparency = transparency
	end
end

local function setAllTransparency(self: BlurInternal, transparency: number)
	setPartTransparency(self._mainPlane, transparency)
	for _, part in self._planes do
		setPartTransparency(part, transparency)
	end
	for _, part in self._corners do
		setPartTransparency(part, transparency)
	end
end

local function hide(self: BlurInternal)
	if not self._rendered then
		return
	end

	setAllTransparency(self, 1)
	self._rendered = false
end

local function refreshDecorators(self: BlurInternal)
	local corner = self._guiObject:FindFirstChildWhichIsA("UICorner")
	self._uiCorner = if corner and corner:IsA("UICorner") then corner else nil
	self:SetCornered(self._uiCorner ~= nil)

	local blurEffect = self._guiObject:FindFirstChildWhichIsA("BlurEffect")
	self._blurEffect = if blurEffect and blurEffect:IsA("BlurEffect") then blurEffect else nil
	self._dirty = true
end

local function updateCorners(self: BlurInternal, cornerDiameter: number, size3D: Vector2)
	local cornerSize = cornerDiameter / 2
	local rightVector = self._mainPlane.CFrame.RightVector
	local upVector = self._mainPlane.CFrame.UpVector
	local transparency = intensityToTransparency(self._intensity)

	for _, corner in self._corners do
		Utilities.SetPartSize(corner, Vector3.new(cornerSize, cornerSize, MIN_PART_SIZE))
		corner.PivotOffset = CFrame.new(cornerSize / 2, cornerSize / 2, 0)
		setPartTransparency(corner, transparency)
	end

	self._corners[1]:PivotTo(
		self._mainPlane.CFrame + rightVector * size3D.X / 2 + upVector * size3D.Y / 2
	)
	self._corners[2]:PivotTo(
		(self._mainPlane.CFrame - rightVector * size3D.X / 2 + upVector * size3D.Y / 2)
			* CFrame.Angles(0, 0, math.pi / 2)
	)
	self._corners[3]:PivotTo(
		(self._mainPlane.CFrame - rightVector * size3D.X / 2 - upVector * size3D.Y / 2)
			* CFrame.Angles(0, 0, math.pi)
	)
	self._corners[4]:PivotTo(
		(self._mainPlane.CFrame + rightVector * size3D.X / 2 - upVector * size3D.Y / 2)
			* CFrame.Angles(0, 0, -math.pi / 2)
	)
end

local function updateSidePlanes(self: BlurInternal, cornerDiameter: number, size3D: Vector2)
	local sideWidth = cornerDiameter / 2
	local rightVector = self._mainPlane.CFrame.RightVector
	local upVector = self._mainPlane.CFrame.UpVector
	local transparency = intensityToTransparency(self._intensity)

	Utilities.SetPartSize(
		self._planes[1],
		Vector3.new(sideWidth, math.max(size3D.Y - sideWidth * 2, MIN_PART_SIZE), MIN_PART_SIZE)
	)
	Utilities.SetPartSize(
		self._planes[2],
		Vector3.new(math.max(size3D.X - sideWidth * 2, MIN_PART_SIZE), sideWidth, MIN_PART_SIZE)
	)
	Utilities.SetPartSize(self._planes[3], self._planes[1].Size)
	Utilities.SetPartSize(self._planes[4], self._planes[2].Size)

	self._planes[1].CFrame = self._mainPlane.CFrame
		+ rightVector * (size3D.X / 2 - sideWidth / 2)
	self._planes[2].CFrame = self._mainPlane.CFrame
		+ upVector * (size3D.Y / 2 - sideWidth / 2)
	self._planes[3].CFrame = self._mainPlane.CFrame
		- rightVector * (size3D.X / 2 - sideWidth / 2)
	self._planes[4].CFrame = self._mainPlane.CFrame
		- upVector * (size3D.Y / 2 - sideWidth / 2)

	for _, plane in self._planes do
		setPartTransparency(plane, transparency)
	end
end

local function frameChanged(
	self: BlurInternal,
	camera: Camera,
	absolutePosition: Vector2,
	absoluteSize: Vector2,
	absoluteRotation: number,
	cornerDiameter: number
): boolean
	local cache = self._cache
	return self._dirty
		or not self._rendered
		or cache.AbsolutePosition ~= absolutePosition
		or cache.AbsoluteSize ~= absoluteSize
		or cache.AbsoluteRotation ~= absoluteRotation
		or cache.CameraCFrame ~= camera.CFrame
		or cache.CornerDiameter ~= cornerDiameter
		or cache.FieldOfView ~= camera.FieldOfView
		or cache.ViewportSize ~= camera.ViewportSize
end

local function updateFrameCache(
	self: BlurInternal,
	camera: Camera,
	absolutePosition: Vector2,
	absoluteSize: Vector2,
	absoluteRotation: number,
	cornerDiameter: number
)
	local cache = self._cache
	cache.AbsolutePosition = absolutePosition
	cache.AbsoluteSize = absoluteSize
	cache.AbsoluteRotation = absoluteRotation
	cache.CameraCFrame = camera.CFrame
	cache.CornerDiameter = cornerDiameter
	cache.FieldOfView = camera.FieldOfView
	cache.ViewportSize = camera.ViewportSize
	self._dirty = false
end

local function updateBlur(self: BlurInternal, camera: Camera?, qualityEnabled: boolean)
	if self._destroyed then
		return
	end

	local screenGui = self._screenGui
	local markerAllowsBlur = self._blurEffect == nil or self._blurEffect.Enabled
	local shouldRender = self._enabled
		and qualityEnabled
		and camera ~= nil
		and screenGui ~= nil
		and markerAllowsBlur
		and self._guiObject.Parent ~= nil
		and Utilities.IsVisibleInHierarchy(self._guiObject, screenGui :: ScreenGui)

	if not shouldRender then
		hide(self)
		return
	end

	local activeCamera = camera :: Camera
	local absolutePosition = self._guiObject.AbsolutePosition
	local absoluteSize = self._guiObject.AbsoluteSize
	local absoluteRotation = self._guiObject.AbsoluteRotation
	local cornerDiameter = if self._cornered and self._uiCorner
		then Utilities.GetCornerDiameter(self._uiCorner)
		else 0

	if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
		hide(self)
		return
	end
	if activeCamera.ViewportSize.Y <= 0 then
		hide(self)
		return
	end

	if not frameChanged(
		self,
		activeCamera,
		absolutePosition,
		absoluteSize,
		absoluteRotation,
		cornerDiameter
	) then
		return
	end

	local center = Utilities.ProjectIn3D(
		activeCamera,
		absolutePosition + absoluteSize / 2,
		PROJECTION_DEPTH
	)
	local scaleFactor = (BASE_SCALE + Utilities.MapStrokeSize(self._strokeSize))
		* PROJECTION_DEPTH
		* math.tan(math.rad(activeCamera.FieldOfView / 2))
		* 2
		/ activeCamera.ViewportSize.Y
	local mainCFrame = CFrame.new(center, center - activeCamera.CFrame.LookVector)
		* CFrame.Angles(0, 0, math.rad(absoluteRotation))
	local size3D = Vector2.new(absoluteSize.X * scaleFactor, absoluteSize.Y * scaleFactor)
	local transparency = intensityToTransparency(self._intensity)

	self._mainPlane.CFrame = mainCFrame

	if self._cornered and #self._planes == 4 and #self._corners == 4 then
		local boundedDiameter = math.min(cornerDiameter * scaleFactor, size3D.X, size3D.Y)
		local mainWidth = size3D.X - boundedDiameter
		local mainHeight = size3D.Y - boundedDiameter

		Utilities.SetPartSize(
			self._mainPlane,
			Vector3.new(math.max(mainWidth, MIN_PART_SIZE), math.max(mainHeight, MIN_PART_SIZE), MIN_PART_SIZE)
		)
		setPartTransparency(
			self._mainPlane,
			if mainWidth <= MIN_PART_SIZE or mainHeight <= MIN_PART_SIZE then 1 else transparency
		)
		updateCorners(self, boundedDiameter, size3D)
		updateSidePlanes(self, boundedDiameter, size3D)
	else
		Utilities.SetPartSize(
			self._mainPlane,
			Vector3.new(size3D.X, size3D.Y, MIN_PART_SIZE)
		)
		setPartTransparency(self._mainPlane, transparency)
	end

	self._rendered = true
	updateFrameCache(
		self,
		activeCamera,
		absolutePosition,
		absoluteSize,
		absoluteRotation,
		cornerDiameter
	)
end

function BlurClass.SetCornered(self: BlurInternal, cornered: boolean)
	if self._destroyed then
		return
	end

	local shouldBeCornered = cornered and self._uiCorner ~= nil
	if self._cornered == shouldBeCornered then
		return
	end

	self._cornered = shouldBeCornered
	if shouldBeCornered then
		for _ = 1, 4 do
			local plane = cloneTemplate(self._fragmented, "Plane")
			plane.Parent = self._model
			table.insert(self._planes, plane)
		end
		for _ = 1, 4 do
			local cornerPart = cloneTemplate(self._fragmented, "Corner")
			cornerPart.Parent = self._model
			table.insert(self._corners, cornerPart)
		end
	else
		for _, plane in self._planes do
			plane:Destroy()
		end
		for _, cornerPart in self._corners do
			cornerPart:Destroy()
		end
		table.clear(self._planes)
		table.clear(self._corners)
	end

	self._dirty = true
end

function BlurClass.SetStrokeSize(self: BlurInternal, strokeSize: number)
	if self._destroyed then
		return
	end

	local nextStrokeSize = if strokeSize ~= strokeSize then 0 else math.max(strokeSize, 0)
	if self._strokeSize ~= nextStrokeSize then
		self._strokeSize = nextStrokeSize
		self._dirty = true
	end
end

function BlurClass.GetStrokeSize(self: BlurInternal): number
	return self._strokeSize
end

function BlurClass.SetIntensity(self: BlurInternal, intensity: number)
	if self._destroyed then
		return
	end

	local nextIntensity = normalizeIntensity(intensity)
	if self._intensity ~= nextIntensity then
		self._intensity = nextIntensity
		self._dirty = true
	end
end

function BlurClass.GetIntensity(self: BlurInternal): number
	return self._intensity
end

function BlurClass.SetEnabled(self: BlurInternal, enabled: boolean)
	if self._destroyed or self._enabled == enabled then
		return
	end

	self._enabled = enabled
	self._dirty = true
	if not enabled then
		hide(self)
	end
end

function BlurClass.GetEnabled(self: BlurInternal): boolean
	return self._enabled
end

function BlurClass.Destroy(self: BlurInternal)
	if self._destroyed then
		return
	end

	self._destroyed = true
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	unregisterBlur(self)
	self._model:Destroy()

	if self._inverted then
		invertedCount = math.max(invertedCount - 1, 0)
		if invertedCount == 0 then
			removeInverter()
		end
	end
end

registerBlur = function(blur: BlurInternal)
	activeBlurs[blur] = true
	if renderConnection then
		return
	end

	renderConnection = RunService.PreRender:Connect(function()
		local qualityEnabled = graphicsQualityAllowsBlur()
		for activeBlur in activeBlurs do
			updateBlur(activeBlur, currentCamera, qualityEnabled)
		end
	end)
end

unregisterBlur = function(blur: BlurInternal)
	activeBlurs[blur] = nil
	if next(activeBlurs) == nil and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

function BlurClass.new(guiObject: GuiObject, options: BlurOptions?): Blur
	assert(guiObject:IsA("GuiObject"), "UIBlur.new expects a GuiObject")

	local screenGui = Utilities.FindAncestorScreenGui(guiObject)
	assert(screenGui, "GuiObject must be a descendant of a ScreenGui")

	local resolvedOptions: BlurOptions = if options then options else {}
	local fragmented = resolvedOptions.Fragmented == true
	local inverted = resolvedOptions.Inverted == true
	local mainPlane = cloneTemplate(fragmented, "Plane")
	local model = Instance.new("Model")

	mainPlane.Parent = model
	model.Name = guiObject.Name
	model.PrimaryPart = mainPlane
	model.Parent = if inverted then invertedContainer else container

	local data: BlurData = {
		_blurEffect = nil,
		_cache = {},
		_connections = {},
		_cornered = false,
		_corners = {},
		_destroyed = false,
		_dirty = true,
		_enabled = resolvedOptions.Enabled ~= false,
		_fragmented = fragmented,
		_guiObject = guiObject,
		_intensity = normalizeIntensity(resolvedOptions.Intensity or 1),
		_inverted = inverted,
		_mainPlane = mainPlane,
		_model = model,
		_planes = {},
		_rendered = false,
		_screenGui = screenGui,
		_strokeSize = math.max(resolvedOptions.StrokeSize or 0, 0),
		_uiCorner = nil,
	}
	local self = (setmetatable(data, BlurClass) :: unknown) :: BlurInternal

	refreshDecorators(self)

	if inverted then
		invertedCount += 1
		ensureInverter()
	end

	table.insert(self._connections, guiObject.Destroying:Connect(function()
		self:Destroy()
	end))
	table.insert(self._connections, guiObject.AncestryChanged:Connect(function()
		if self._destroyed then
			return
		end
		self._screenGui = Utilities.FindAncestorScreenGui(guiObject)
		self._dirty = true
	end))
	table.insert(self._connections, guiObject:GetPropertyChangedSignal("Name"):Connect(function()
		if not self._destroyed then
			self._model.Name = guiObject.Name
		end
	end))
	table.insert(self._connections, guiObject.ChildAdded:Connect(function(child)
		if child:IsA("UICorner") or child:IsA("BlurEffect") then
			refreshDecorators(self)
		end
	end))
	table.insert(self._connections, guiObject.ChildRemoved:Connect(function(child)
		if child:IsA("UICorner") or child:IsA("BlurEffect") then
			task.defer(function()
				if not self._destroyed then
					refreshDecorators(self)
				end
			end)
		end
	end))

	registerBlur(self)
	return self
end

function BlurClass.SetGlobalIntensity(intensity: number)
	globalIntensity = normalizeIntensity(intensity)
	depthOfField.NearIntensity = globalIntensity
end

function BlurClass.GetGlobalIntensity(): number
	return globalIntensity
end

function BlurClass.DestroyAll()
	for blur in activeBlurs do
		blur:Destroy()
	end

	for guiObject, record in automaticRecords do
		for _, connection in record.Connections do
			connection:Disconnect()
		end
		automaticRecords[guiObject] = nil
	end
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	currentCamera = Workspace.CurrentCamera
	container.Parent = currentCamera
	for blur in activeBlurs do
		blur._dirty = true
	end
end)

gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
	qualityLevel = gameSettings.SavedQualityLevel
	for blur in activeBlurs do
		blur._dirty = true
	end
end)

local player = Players.LocalPlayer
assert(player, "UIBlur requires Players.LocalPlayer")
local playerGuiInstance = player:WaitForChild("PlayerGui")
assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be a PlayerGui")
local playerGui: PlayerGui = playerGuiInstance

local syncAutomatic: (guiObject: GuiObject) -> ()
local rebuildAutomatic: (guiObject: GuiObject) -> ()

local function readBooleanAttribute(instance: Instance, name: string): boolean?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "boolean" then value else nil
end

local function readNumberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function optionsFromMarker(marker: BlurEffect): BlurOptions
	return {
		Enabled = readBooleanAttribute(marker, "Enabled"),
		Fragmented = readBooleanAttribute(marker, "Fragmented"),
		Intensity = readNumberAttribute(marker, "Intensity"),
		Inverted = readBooleanAttribute(marker, "Inverted"),
		StrokeSize = readNumberAttribute(marker, "StrokeSize"),
	}
end

local function removeAutomatic(guiObject: GuiObject)
	local record = automaticRecords[guiObject]
	if not record then
		return
	end

	for _, connection in record.Connections do
		connection:Disconnect()
	end
	record.Blur:Destroy()
	automaticRecords[guiObject] = nil
end

syncAutomatic = function(guiObject: GuiObject)
	if not guiObject:IsDescendantOf(playerGui) then
		removeAutomatic(guiObject)
		return
	end

	local foundMarker = guiObject:FindFirstChildWhichIsA("BlurEffect")
	local marker = if foundMarker and foundMarker:IsA("BlurEffect") then foundMarker else nil
	local currentRecord = automaticRecords[guiObject]
	if currentRecord and currentRecord.Marker == marker then
		return
	end

	removeAutomatic(guiObject)
	if not marker then
		return
	end

	local blur = BlurClass.new(guiObject, optionsFromMarker(marker))
	local record: AutoRecord = {
		Blur = blur,
		Connections = {},
		Marker = marker,
	}
	automaticRecords[guiObject] = record

	for _, attributeName in { "Enabled", "Fragmented", "Intensity", "Inverted", "StrokeSize" } do
		table.insert(record.Connections, marker:GetAttributeChangedSignal(attributeName):Connect(function()
			rebuildAutomatic(guiObject)
		end))
	end
end

rebuildAutomatic = function(guiObject: GuiObject)
	removeAutomatic(guiObject)
	syncAutomatic(guiObject)
end

if script:GetAttribute("AutoAddEnabled") == true then
	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("BlurEffect") then
			local parent = descendant.Parent
			if parent and parent:IsA("GuiObject") then
				syncAutomatic(parent)
			end
		end
	end

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BlurEffect") then
			local parent = descendant.Parent
			if parent and parent:IsA("GuiObject") then
				syncAutomatic(parent)
			end
		end
	end)
	playerGui.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("BlurEffect") then
			local parent = descendant.Parent
			if parent and parent:IsA("GuiObject") then
				task.defer(function()
					syncAutomatic(parent)
				end)
			end
		end
	end)
end

return BlurClass :: UIBlurModule
