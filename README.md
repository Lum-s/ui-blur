# UIBlur

A strictly typed, client-side Roblox UI blur library. Blur geometry follows UI position, size, rotation, rounded corners, ancestor visibility, viewport changes, and camera movement. Instances clean themselves up when their target UI is destroyed.

## Usage

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIBlur = require(ReplicatedStorage.Packages.UIBlur)

local blur = UIBlur.new(script.Parent, {
	Intensity = 0.8,
	StrokeSize = 1,
	Fragmented = false,
	Inverted = false,
})

blur:SetIntensity(0.45)
blur:SetEnabled(false)
blur:SetEnabled(true)

-- Optional. Destruction is automatic when the target GuiObject is destroyed.
blur:Destroy()
```

`Intensity` is clamped to `0–1`. It controls one blur independently. The shared depth-of-field strength can also be changed:

```luau
UIBlur.SetGlobalIntensity(0.75)
```

## Typed API

```luau
export type BlurOptions = {
	Fragmented: boolean?,
	Inverted: boolean?,
	StrokeSize: number?,
	Intensity: number?,
	Enabled: boolean?,
}

UIBlur.new(guiObject: GuiObject, options: BlurOptions?): Blur
UIBlur.SetGlobalIntensity(intensity: number)
UIBlur.GetGlobalIntensity(): number
UIBlur.DestroyAll()

blur:SetIntensity(intensity: number)
blur:GetIntensity(): number
blur:SetStrokeSize(strokeSize: number)
blur:GetStrokeSize(): number
blur:SetEnabled(enabled: boolean)
blur:GetEnabled(): boolean
blur:SetCornered(cornered: boolean)
blur:Destroy()
```

Consumers can import the exported types directly from the module:

```luau
type Blur = UIBlur.Blur
type BlurOptions = UIBlur.BlurOptions
```

## Automatic integration

Set the module's `AutoAddEnabled` attribute to `true` to create blur instances for `BlurEffect` children found under GuiObjects in `PlayerGui`. Runtime additions and removals are tracked automatically.

The marker supports these attributes:

- `Intensity: number`
- `StrokeSize: number`
- `Fragmented: boolean`
- `Inverted: boolean`
- `Enabled: boolean`

Changing one of these attributes rebuilds that automatic blur with the new configuration. The marker's native `Enabled` property also controls whether its blur renders.

## Animation and lifecycle behavior

All blur instances share one `PreRender` connection. Each frame checks the UI and camera state, but geometry is only rewritten when a relevant value changes. This keeps tweens and continuously animated UI synchronized while avoiding repeated property writes for static UI.

The library handles:

- Position, size, and rotation animation
- Animated `UICorner.CornerRadius`
- Ancestor movement and visibility changes
- Reparenting between ScreenGuis
- CurrentCamera and viewport changes
- GuiObject and marker destruction

## Building

```bash
argon build ui-blur.project.json
```

Build the Moonwave documentation site with:

```bash
npx moonwave build
```
