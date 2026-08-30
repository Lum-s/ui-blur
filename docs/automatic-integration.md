---
sidebar_position: 3
---

# Automatic integration

Automatic mode turns `BlurEffect` children into declarative blur markers. It scans existing UI and watches `PlayerGui` for runtime additions and removals.

## Enable automatic mode

Set `AutoAddEnabled` on the module before requiring it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local moduleScript = ReplicatedStorage.Packages.UIBlur

moduleScript:SetAttribute("AutoAddEnabled", true)

local UIBlur = require(moduleScript)
```

## Add a marker

```lua
local marker = Instance.new("BlurEffect")
marker.Name = "UIBlurMarker"
marker:SetAttribute("Intensity", 0.8)
marker:SetAttribute("StrokeSize", 1)
marker:SetAttribute("Fragmented", false)
marker:SetAttribute("Inverted", false)
marker.Parent = frame
```

Supported marker attributes are:

| Attribute | Type | Description |
| --- | --- | --- |
| `Intensity` | `number` | Per-instance strength, clamped to `0–1`. |
| `StrokeSize` | `number` | Outward expansion, clamped to zero or greater. |
| `Fragmented` | `boolean` | Selects the fragmented mesh set. |
| `Inverted` | `boolean` | Uses the color-inversion container. |
| `Enabled` | `boolean` | Initial logical enabled state. |

Changing an attribute rebuilds the automatic instance with the new configuration. Changing the marker's native `Enabled` property immediately hides or shows its blur.

Removing the marker or destroying its target releases the automatic blur and its connections.

## Runtime lists

Markers can be included in cloned templates, so list entries require no imperative blur setup:

```lua
for _, item in inventoryItems do
	local row = rowTemplate:Clone()
	row.ItemName.Text = item.Name
	row.Parent = scrollingFrame
end
```

If `rowTemplate` contains a configured `BlurEffect` marker under the intended `GuiObject`, automatic mode discovers each cloned row after it enters `PlayerGui`.
