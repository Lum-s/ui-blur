---
sidebar_position: 1
---

# Getting started

UIBlur projects lightweight glass geometry in front of the current camera to blur a `GuiObject`. It is a client-only library and must be required from a `LocalScript` or another client module.

## Create a blur

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIBlur = require(ReplicatedStorage.Packages.UIBlur)
local frame = script.Parent

local blur = UIBlur.new(frame, {
	Intensity = 0.8,
	StrokeSize = 1,
	Fragmented = false,
	Inverted = false,
	Enabled = true,
})
```

The target must be a `GuiObject` underneath a `ScreenGui`. All options are optional.

## What is tracked automatically?

The blur remains aligned while any of these values change:

- `AbsolutePosition`, including movement caused by ancestors
- `AbsoluteSize`, including `UIScale` and layout changes
- `AbsoluteRotation`
- `UICorner.CornerRadius`
- Ancestor visibility and `ScreenGui.Enabled`
- Camera transform, field of view, and viewport size
- The current `Workspace.CurrentCamera`

Destroying the target also destroys its blur. Temporary reparenting is supported: the blur hides while the target is outside a `ScreenGui` and resumes when it is mounted again.

## Intensity

Per-instance intensity controls one blur:

```lua
blur:SetIntensity(0.5)
```

Global intensity changes the shared depth-of-field effect:

```lua
UIBlur.SetGlobalIntensity(0.75)
```

Both values are clamped to the range `0–1`.

## Cleanup

Manual cleanup is optional when the target will be destroyed:

```lua
blur:Destroy()
```

To release every managed blur at once:

```lua
UIBlur.DestroyAll()
```

Calling `Destroy` repeatedly is safe.
