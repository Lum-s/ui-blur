---
sidebar_position: 2
---

# Function examples

## `UIBlur.new`

Creates a blur and begins tracking the target UI. Use `Fragmented` for the alternate mesh set and `Inverted` for the highlight-based color inversion container.

```lua
local blur = UIBlur.new(contentFrame, {
	Fragmented = true,
	Inverted = false,
	Intensity = 1,
	StrokeSize = 0,
})
```

## `blur:SetIntensity` and `blur:GetIntensity`

Change one blur without affecting any other instance:

```lua
blur:SetIntensity(0.35)

print(blur:GetIntensity()) -- 0.35
```

A value of `0` hides the blur contribution while leaving the instance available for reuse.

## `UIBlur.SetGlobalIntensity` and `UIBlur.GetGlobalIntensity`

Change the shared `DepthOfFieldEffect` intensity:

```lua
UIBlur.SetGlobalIntensity(0.9)

print(UIBlur.GetGlobalIntensity()) -- 0.9
```

Per-instance and global intensity are independent. Global intensity affects every blur.

## `blur:SetEnabled` and `blur:GetEnabled`

Temporarily stop rendering without destroying the instance:

```lua
blur:SetEnabled(false)

if not blur:GetEnabled() then
	blur:SetEnabled(true)
end
```

When re-enabled, the blur synchronizes to the UI's current animated position and size.

## `blur:SetStrokeSize` and `blur:GetStrokeSize`

Expand the blur beyond the UI bounds:

```lua
blur:SetStrokeSize(2)

print(blur:GetStrokeSize()) -- 2
```

Negative values are normalized to zero.

## `blur:SetCornered`

Rounded geometry is enabled automatically when a `UICorner` is added. The method can explicitly disable and restore it:

```lua
blur:SetCornered(false)

-- Rounded rendering requires a UICorner under the target.
blur:SetCornered(true)
```

Adding, removing, replacing, or animating a `UICorner` is detected automatically.

## `blur:Destroy`

Release a single blur when its target UI will remain alive:

```lua
closeButton.Activated:Connect(function()
	blur:Destroy()
end)
```

Target destruction already calls this automatically.

## `UIBlur.DestroyAll`

Release every active blur during a complete UI teardown:

```lua
UIBlur.DestroyAll()
```

## Animated UI

No update calls are required during tweens. The shared renderer samples resolved GUI bounds on `PreRender` and writes geometry only when the sampled state changes.

```lua
local TweenService = game:GetService("TweenService")

local blur = UIBlur.new(panel, {
	Intensity = 0.8,
})

local tween = TweenService:Create(
	panel,
	TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	{
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 340),
		Rotation = 4,
	}
)

tween:Play()
```

The same behavior applies to ancestor animation, layout-driven movement, and camera animation.

## Dynamic UI creation

Create a blur as soon as a UI object is mounted beneath a `ScreenGui`. Cleanup occurs when the object is destroyed.

```lua
local function mountCard(parent: Instance)
	local card = cardTemplate:Clone()
	card.Parent = parent

	UIBlur.new(card, {
		Intensity = 0.65,
		StrokeSize = 1,
	})

	return card
end
```
