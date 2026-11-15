--[[
	BaitRoller — left-column single-reel bait roller.

	Lives in StarterGui.BaitRoller (ScreenGui) as its LocalScript and builds the
	whole HUD at runtime. It's a tall sidebar on the LEFT edge (~left fifth of the
	screen, full height) with gold marquee bulbs around the reel — sized to match the
	roll-simulator reference the user gave.

	The column runs reel → pity chips → AUTO ROLL → ROLL → BAITS. That last button
	opens PlayerGui.BaitsMenu, which InventoryController builds (the bait catalogue and
	publishBaitStats live there); the reel gave up the height for it — see CELL_H.

	Each spin is exactly 3 seconds, easing out (fast start, slow finish).

	Odds run 1/2 (Breadcrumbs) up to 1/435,000,000 (Leviathan Bait). Pity counters
	guarantee an Uncommon+ every 10, a Rare+ every 100, an Epic+ every 1,000.

	Client-side demo state for now — if a RemoteEvent exists at
	ReplicatedStorage.BaitRemotes.Rolled it fires the result to the server.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

----------------------------------------------------------------------
-- STYLE
----------------------------------------------------------------------

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(11, 26, 46)
local PANEL_TOP = Color3.fromRGB(64, 138, 208)
local PANEL_BOTTOM = Color3.fromRGB(26, 74, 142)
local REEL_BG = Color3.fromRGB(38, 100, 170)
local REEL_BG2 = Color3.fromRGB(22, 66, 126)
local CYAN = Color3.fromRGB(74, 210, 238)
local GOLD = Color3.fromRGB(248, 196, 62)
local DIM = Color3.fromRGB(150, 160, 180)

local RARITY = {
	Common = { rank = 1, color = Color3.fromRGB(198, 206, 220) },
	Uncommon = { rank = 2, color = Color3.fromRGB(88, 220, 110) },
	Rare = { rank = 3, color = Color3.fromRGB(74, 158, 250) },
	Epic = { rank = 4, color = Color3.fromRGB(186, 108, 250) },
	Legendary = { rank = 5, color = Color3.fromRGB(250, 190, 52) },
	Mythic = { rank = 6, color = Color3.fromRGB(252, 74, 110) },
	Divine = { rank = 7, color = Color3.fromRGB(120, 246, 246) },
}

local BAITS = {
	{ name = "Breadcrumbs", icon = "\240\159\141\158", odds = 2, rarity = "Common", buff = "+2% Luck" },
	{ name = "Grub", icon = "\240\159\144\155", odds = 5, rarity = "Common", buff = "+5% Hook Speed" },
	{ name = "Minnow", icon = "\240\159\144\159", odds = 20, rarity = "Uncommon", buff = "+10% Value" },
	{ name = "Shrimp", icon = "\240\159\166\144", odds = 60, rarity = "Uncommon", buff = "+15% Luck" },
	{ name = "Squid", icon = "\240\159\166\145", odds = 250, rarity = "Rare", buff = "+25% Hook Speed" },
	{ name = "Octopus Ink", icon = "\240\159\144\153", odds = 1200, rarity = "Rare", buff = "+40% Value" },
	{ name = "Glowworm", icon = "\226\156\168", odds = 6000, rarity = "Epic", buff = "+60% Luck" },
	{ name = "Golden Roe", icon = "\240\159\165\154", odds = 30000, rarity = "Epic", buff = "+80% Value" },
	{ name = "Black Pearl", icon = "\240\159\146\142", odds = 200000, rarity = "Legendary", buff = "+150% Luck" },
	{ name = "Siren Song", icon = "\240\159\142\181", odds = 1500000, rarity = "Legendary", buff = "+200% Hook Speed" },
	{ name = "Abyssal Chum", icon = "\240\159\140\138", odds = 12000000, rarity = "Mythic", buff = "+300% Value" },
	{ name = "Leviathan Bait", icon = "\240\159\144\139", odds = 435000000, rarity = "Divine", buff = "+1000% Luck" },
}

local PITY = {
	{ every = 10, rank = 2, label = "10", short = "10" },
	{ every = 100, rank = 3, label = "100", short = "100" },
	{ every = 1000, rank = 4, label = "1,000", short = "1K" },   -- short: a phone's chip (pityText)
}

-- Layout: fixed-design pixels, scaled to fit the viewport height.
local PANEL_W = 360
local PANEL_H = 884
local REEL_W = 300
-- 2026-09-03: CELL_H went 210 -> 176 to make room for the BAITS button, then back up to 184
-- once the column was laid out properly from the BOTTOM margin - the first pass left 52px of
-- dead blue under the button, and the reel is the only thing that wants that space.
--
-- THE COLUMN IS SPACED FROM THE BOTTOM UP, and these are the offsets that produced:
--   reel          20 .. 584        (REEL_TOP .. REEL_TOP + REEL_H)
--   pity chips   +26 -> 610..654   ⚠️ +26, NOT +20: the marquee's bottom bulb row sits at
--                                  REEL_H + 15 with a 6px radius, i.e. +21, so +20 put a row
--                                  of gold bulbs 1px INTO the chips. +26 clears it by 5.
--   AUTO ROLL    +82 -> 666..718
--   ROLL        +144 -> 728..798
--   BAITS       +224 -> 808..874
--   bottom margin 10. Change any button height and RE-DERIVE these; do not nudge them.
--
-- ⚠️ THE COLUMN IS NOW FULL. The furniture below the reel is a fixed 290px (26+44+12+52+10+
-- 70+10+66), so REEL_H = 884 - 20 - 290 - margin = 574 - margin, and the margin is down to 10.
-- The ONLY way to a materially taller reel from here is to shrink a control, and the obvious
-- candidates are the worst ones to touch: ROLL and AUTO ROLL already render 134x29 and 134x22
-- on an 812x375 phone, both under the 44px touch floor and both leaning on TouchKit pads.
--
-- ⚠️ REEL_H MUST STAY EXACTLY THREE CELLS. The selector band is drawn at
-- 0.5 +/- (CELL_H/2)/REEL_H and centreOffsetFor() assumes the winning cell lands dead centre,
-- so any other ratio stops the reel off the line. That is why CELL_H is the knob and REEL_H
-- follows it. Everything INSIDE a cell is a fraction of CELL_H (see `cs` below), so changing
-- it never means re-tuning the icon and the two labels by hand.
local CELL_H = 188
local REEL_H = CELL_H * 3
local REEL_TOP = 20

-- The spin: one 3-second ease-out — fast at the start, crawling into the row.
local SPIN_TIME = 3.0
local STRIP_LEN = 60
local START_INDEX = 2
local END_INDEX = STRIP_LEN - 3 -- 57

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(inst, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 16) }, inst)
end

local function outline(inst, thickness, color)
	return new("UIStroke", {
		Color = color or INK,
		Thickness = thickness or 4,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, inst)
end

local function gradient(inst, top, bottom)
	return new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, inst)
end

-- Glossy plastic sheen across the top of a button. Add BEFORE the label so the
-- label draws on top (equal ZIndex siblings render in child order).
local function gloss(inst, heightScale)
	local g = new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -10, heightScale or 0.44, 0),
		Position = UDim2.new(0.5, 0, 0, 5),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = inst.ZIndex,
	}, inst)
	corner(g, UDim.new(1, 0))
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.32),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, g)
	return g
end

local function txt(parent, props, strokeThickness)
	props = props or {}
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	local label = new("TextLabel", props, parent)
	if (strokeThickness or 0) > 0 then
		new("UIStroke", { Color = INK, Thickness = strokeThickness, LineJoinMode = Enum.LineJoinMode.Round }, label)
	end
	return label
end

local function fmtOdds(n)
	for _, u in ipairs({ { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
		if n >= u[1] then
			return string.format("%.2f%s", n / u[1], u[2])
		end
	end
	return string.format("%d", n)
end

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

----------------------------------------------------------------------
-- ROLL MATH
----------------------------------------------------------------------

for _, b in ipairs(BAITS) do
	b.weight = 1 / b.odds
	b.rank = RARITY[b.rarity].rank
	b.color = RARITY[b.rarity].color
end

local function pickBait(minRank)
	local pool, poolWeight = {}, 0
	for _, b in ipairs(BAITS) do
		if not minRank or b.rank >= minRank then
			table.insert(pool, b)
			poolWeight += b.weight
		end
	end
	if #pool == 0 then
		return BAITS[#BAITS]
	end
	local r = math.random() * poolWeight
	local acc = 0
	for _, b in ipairs(pool) do
		acc += b.weight
		if r <= acc then
			return b
		end
	end
	return pool[#pool]
end

----------------------------------------------------------------------
-- SCREEN GUI
----------------------------------------------------------------------

local gui
if script.Parent:IsA("ScreenGui") then
	gui = script.Parent
	for _, c in ipairs(gui:GetChildren()) do
		if c ~= script then
			c:Destroy()
		end
	end
	gui.Enabled = true
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets   -- the HUD's shared origin (HUD_CONTRACT §1)
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
else
	local old = playerGui:FindFirstChild("BaitRoller")
	if old then
		old:Destroy()
	end
	gui = new("ScreenGui", {
		Name = "BaitRoller",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
end

-- Tall left column. Its own background only — it does NOT cover the whole screen.
local panel = new("Frame", {
	Name = "Panel",
	BackgroundColor3 = WHITE,   -- the UIGradient below owns the colour; both = colour squared
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	Position = UDim2.new(0, -4, 0.5, 0), -- tucked just past the left edge, flush
	AnchorPoint = Vector2.new(0, 0.5),
}, gui)
-- No rounded corners: it's a plain rectangle so its left side sits flush to the edge.
outline(panel, 5)
new("UIGradient", { Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM), Rotation = 90 }, panel)

local panelScale = new("UIScale", { Scale = 1 }, panel)
-- The layout mode, decided and published by fit() - see FIT, further down, below the buttons it
-- lays out. Declared up here because makeCell() and the pity/BAITS labels read it as well.
local hudMode = "desktop"

----------------------------------------------------------------------
-- REEL
----------------------------------------------------------------------

local reelLeft = (PANEL_W - REEL_W) / 2

local reel = new("Frame", {
	Name = "Reel",
	BackgroundColor3 = WHITE,   -- ditto: gradient(reel, REEL_BG, REEL_BG2) owns the colour
	Size = UDim2.fromOffset(REEL_W, REEL_H),
	Position = UDim2.fromOffset(reelLeft, REEL_TOP),
	ClipsDescendants = true,
	ZIndex = 3,
}, panel)
corner(reel, UDim.new(0, 14))
outline(reel, 5)
gradient(reel, REEL_BG, REEL_BG2)
-- 1 everywhere but a phone, where fit() shrinks the whole reel into the height the buttons leave
local reelScale = new("UIScale", { Scale = 1 }, reel)

local strip = new("Frame", {
	Name = "Strip",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 0),
	ZIndex = 3,
}, reel)

-- Cell furniture in fractions of CELL_H, not pixels: these numbers were hand-tuned against
-- the original 210px cell, so scaling them keeps the proportions the design was signed off on
-- while letting CELL_H move. At 188 the stack ends at 165 of 188, so it still has its margin.
local function cs(v) return math.floor(v * CELL_H / 210 + 0.5) end

-- Where the icon and the two labels sit in a cell. On a PHONE the reel renders at ~0.30-0.36 of
-- design (rail scale x the reel's own fit), where cs()'s boxes put the bait name at ~11px and the
-- odds at 8.9 - so the phone stack trades some icon for taller text boxes, still centred on the
-- cell (20..166 of 188). fit() re-runs this on every cell on the strip when the mode flips.
local function layoutCell(cell)
	local icon, name, odds = cell:FindFirstChild("Icon"), cell:FindFirstChild("BaitName"), cell:FindFirstChild("Odds")
	if not (icon and name and odds) then
		return
	end
	if hudMode == "phone" then
		icon.Size = UDim2.fromOffset(62, 62)
		icon.Position = UDim2.new(0.5, 0, 0, 20)
		name.Size = UDim2.new(1, -16, 0, 44)
		name.Position = UDim2.new(0.5, 0, 0, 86)
		odds.Size = UDim2.new(1, -16, 0, 34)
		odds.Position = UDim2.new(0.5, 0, 0, 132)
	else
		icon.Size = UDim2.fromOffset(cs(78), cs(78))
		icon.Position = UDim2.new(0.5, 0, 0, cs(26))
		name.Size = UDim2.new(1, -24, 0, cs(40))
		name.Position = UDim2.new(0.5, 0, 0, cs(112))
		odds.Size = UDim2.new(1, -24, 0, cs(28))
		odds.Position = UDim2.new(0.5, 0, 0, cs(156))
	end
end

local function makeCell(def, index)
	local cell = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CELL_H),
		Position = UDim2.fromOffset(0, index * CELL_H),
		ZIndex = 3,
	}, strip)

	txt(cell, {
		Name = "Icon",
		Text = def.icon,
		AnchorPoint = Vector2.new(0.5, 0),
		TextScaled = true,
		ZIndex = 4,
	}, 0)

	txt(cell, {
		Name = "BaitName",
		Text = def.name,
		AnchorPoint = Vector2.new(0.5, 0),
		TextScaled = true,
		TextColor3 = def.color,
		ZIndex = 4,
	}, 3.5)

	txt(cell, {
		Name = "Odds",
		Text = "1 / " .. fmtOdds(def.odds),
		AnchorPoint = Vector2.new(0.5, 0),
		TextScaled = true,
		TextColor3 = DIM,
		ZIndex = 4,
	}, 2)

	layoutCell(cell)
	return cell
end

-- top/bottom fades so cells slide out of view rather than clip hard
for _, edge in ipairs({ 0, 1 }) do
	local fade = new("Frame", {
		BackgroundColor3 = edge == 0 and REEL_BG or REEL_BG2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 130),
		Position = UDim2.new(0, 0, edge, 0),
		AnchorPoint = Vector2.new(0, edge),
		ZIndex = 5,
	}, reel)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, edge == 0 and 0.1 or 1),
			NumberSequenceKeypoint.new(1, edge == 0 and 1 or 0.1),
		}),
		Rotation = 90,
	}, fade)
end

-- selector row (the centre band the reel lands in)
for _, y in ipairs({ 0.5 - (CELL_H / 2) / REEL_H, 0.5 + (CELL_H / 2) / REEL_H }) do
	local line = new("Frame", {
		BackgroundColor3 = CYAN,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.fromScale(0, y),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 6,
	}, reel)
	corner(line, UDim.new(1, 0))
end

local flash = new("Frame", {
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 7,
}, reel)
corner(flash, UDim.new(0, 14))

----------------------------------------------------------------------
-- MARQUEE — gold bulbs around the reel's border
----------------------------------------------------------------------

local bulbs = {}
local bulbUV = {}   -- [bulb] = where it sits on the marquee rect, 0..1 each way
local function addBulb(u, v)
	local b = new("Frame", {
		BackgroundColor3 = GOLD,
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 8,
	}, panel)
	corner(b, UDim.new(1, 0))
	table.insert(bulbs, b)
	bulbUV[b] = Vector2.new(u, v)
end

-- Lay the bulbs around a reel drawn at (rx, ry, rw, rh) in panel px, where k is the reel's own
-- scale (1 except on a phone). The marquee rect is the reel grown by 15k each way, as it always was.
local function placeBulbs(rx, ry, rw, rh, k)
	local inset = 15 * k
	local x0, y0 = rx - inset, ry - inset
	local x1, y1 = rx + rw + inset, ry + rh + inset
	for _, b in ipairs(bulbs) do
		local uv = bulbUV[b]
		b.Position = UDim2.fromOffset(x0 + (x1 - x0) * uv.X, y0 + (y1 - y0) * uv.Y)
		b.Size = UDim2.fromOffset(12 * k, 12 * k)
	end
end

do
	local inset = 15
	local x0, y0 = reelLeft - inset, REEL_TOP - inset
	local x1, y1 = reelLeft + REEL_W + inset, REEL_TOP + REEL_H + inset
	local step = 28
	local cols = math.max(2, math.floor((x1 - x0) / step))
	for i = 0, cols do
		addBulb(i / cols, 0)
		addBulb(i / cols, 1)
	end
	local rows = math.max(2, math.floor((y1 - y0) / step))
	for i = 1, rows - 1 do
		addBulb(0, i / rows)
		addBulb(1, i / rows)
	end
end
placeBulbs(reelLeft, REEL_TOP, REEL_W, REEL_H, 1)

----------------------------------------------------------------------
-- PITY CHIPS
----------------------------------------------------------------------

local pityCount = { 0, 0, 0 }
-- SAVED PITY (SaveServer writes BaitPity1..3 before this script starts; bumpPity keeps them current for the save)
for i = 1, 3 do pityCount[i] = math.max(0, math.floor(tonumber(player:GetAttribute("BaitPity" .. i)) or 0)) end
local pityLabels = {}
local pityChips = {}

local counterRow = new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(PANEL_W - 24, 44),
	Position = UDim2.new(0.5, 0, 0, REEL_TOP + REEL_H + 26),
	AnchorPoint = Vector2.new(0.5, 0),
	ZIndex = 6,
}, panel)
local pityList = new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, counterRow)

local PITY_TINT = { RARITY.Uncommon.color, RARITY.Rare.color, RARITY.Epic.color }

-- A phone's pity chips are 27-39px wide, where "999/1,000" cannot sit at a readable size, so the
-- phone reads "1K" (PITY[i].short). Every writer of these labels goes through here.
local function pityText(i)
	local p = PITY[i]
	return commas(pityCount[i]) .. "/" .. ((hudMode == "phone" and p.short) or p.label)
end

for i, p in ipairs(PITY) do
	local chip = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 84, 152),
		Size = UDim2.fromOffset(104, 40),
		LayoutOrder = i,
		ZIndex = 6,
	}, counterRow)
	corner(chip, UDim.new(0, 10))
	outline(chip, 3, PITY_TINT[i])
	pityChips[i] = chip

	pityLabels[i] = txt(chip, {
		Text = pityText(i),
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextScaled = true,
		TextColor3 = PITY_TINT[i],
		ZIndex = 7,
	}, 2)
end

----------------------------------------------------------------------
-- BUTTONS
----------------------------------------------------------------------

local BTN_W = PANEL_W - 40
local autoOn = false

local autoBtn = new("TextButton", {
	BackgroundColor3 = WHITE,   -- autoGrad owns the colour
	Size = UDim2.fromOffset(BTN_W, 52),
	Position = UDim2.new(0.5, 0, 0, REEL_TOP + REEL_H + 82),
	AnchorPoint = Vector2.new(0.5, 0),
	Text = "",
	AutoButtonColor = false,
	ZIndex = 6,
}, panel)
corner(autoBtn, UDim.new(0, 12))
outline(autoBtn, 4)
local autoGrad = new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(120, 180, 230), Color3.fromRGB(48, 104, 166)),
	Rotation = 90,
}, autoBtn)
local autoLbl = txt(autoBtn, {
	Text = "AUTO ROLL: OFF",
	Size = UDim2.new(1, -16, 1, -12),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	TextScaled = true,
	ZIndex = 7,
}, 3)

local rollBtn = new("TextButton", {
	BackgroundColor3 = WHITE,   -- rollGrad owns the colour
	Size = UDim2.fromOffset(BTN_W, 70),
	Position = UDim2.new(0.5, 0, 0, REEL_TOP + REEL_H + 144),
	AnchorPoint = Vector2.new(0.5, 0),
	Text = "",
	AutoButtonColor = false,
	ZIndex = 6,
}, panel)
corner(rollBtn, UDim.new(0, 12))
outline(rollBtn, 4)
local rollGrad = new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(126, 240, 120), Color3.fromRGB(36, 168, 62)),
	Rotation = 90,
}, rollBtn)
local rollLbl = txt(rollBtn, {
	Text = "ROLL",
	Size = UDim2.new(1, -16, 1, -16),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	TextScaled = true,
	ZIndex = 7,
}, 4)

-- BAITS. Baits used to be a tab inside the Inventory, which meant crossing the whole screen
-- to look at something this panel had just handed you. Purple rather than the green ROLL or
-- the blue AUTO, and 66 tall rather than 70, so it reads as the secondary action on a column
-- whose primary one is still ROLL.
local baitsBtn = new("TextButton", {
	BackgroundColor3 = WHITE,   -- the gradient owns the colour
	Size = UDim2.fromOffset(BTN_W, 66),
	Position = UDim2.new(0.5, 0, 0, REEL_TOP + REEL_H + 224),
	AnchorPoint = Vector2.new(0.5, 0),
	Text = "",
	AutoButtonColor = false,
	ZIndex = 6,
}, panel)
corner(baitsBtn, UDim.new(0, 12))
outline(baitsBtn, 4)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(190, 152, 252), Color3.fromRGB(112, 66, 198)),
	Rotation = 90,
}, baitsBtn)
local baitsLbl = txt(baitsBtn, {
	Text = "\240\159\144\155 BAITS",
	Size = UDim2.new(1, -16, 1, -16),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	TextScaled = true,
	ZIndex = 7,
}, 4)

-- What is actually on the hook, read straight off the attributes publishBaitStats() already
-- writes - so this needs no copy of the bait table and no knowledge of which one is equipped.
-- ⚠️ THE WORD "BAITS" STAYS WHATEVER IS EQUIPPED. The first version swapped the whole label
-- for the bait icon and its count, which reads well once you know the panel and not at all
-- before: a purple button showing "🦐 x7" does not tell a new player it OPENS anything. The
-- equipped bait is a bonus on the button, never its name.
-- The glyph is MIRRORED on both ends, so the word sits centred on a full-width button instead
-- of being pushed off-centre by a single leading icon. The COUNT is not mirrored - it rides
-- with the word, because two of it would read as two different numbers.
local function refreshBaitsBtn()
	local icon = player:GetAttribute("BaitIcon")
	local left = player:GetAttribute("BaitLeft") or 0
	-- a phone's BAITS button is ~120px wide: single spaces keep a 4-digit count at >= 13px there
	local sp = hudMode == "phone" and " " or "  "
	if icon and icon ~= "" and left > 0 then
		baitsLbl.Text = icon .. sp .. "BAITS x" .. commas(left) .. sp .. icon
	else
		baitsLbl.Text = "\240\159\144\155" .. sp .. "BAITS" .. sp .. "\240\159\144\155"
	end
end
refreshBaitsBtn()
player:GetAttributeChangedSignal("BaitIcon"):Connect(refreshBaitsBtn)
player:GetAttributeChangedSignal("BaitLeft"):Connect(refreshBaitsBtn)

----------------------------------------------------------------------
-- FIT - the HUD mode, the rail scale and the per-mode column (HUD_CONTRACT §1, L1, L2)
----------------------------------------------------------------------
-- THIS script decides the HUD mode and PUBLISHES it on the gui (HudMode, RailScale), so the rest
-- of the HUD reads one answer instead of re-deriving it:
--   phone    short side < 500. Each rail is 20% of W and this column runs the FULL height, laid
--            out BOTTOM-UP IN SCREEN PX: BAITS 36, ROLL 42, AUTO ROLL 30, pity 18, and the reel +
--            marquee scale into whatever is left (iPhone 7 ~218px, Galaxy A06 ~182px).
--   tablet   the rail is capped at 22.85% of W and the desktop column is bottom-anchored, which
--            leaves the corner above it for the Daily/Wheel dock (RewardsHUD).
--   desktop  today's formula and layout, pixel for pixel. 0.2285 sits just above both the laptop
--            and the HD 1080 scale, so neither ever falls into tablet.
-- ⚠️ W,H ARE THE GUI'S, NOT THE CAMERA'S. On a notched phone the camera is the whole screen while
-- this gui is the safe area (iPhone 14: 750x369 of 844x390).
-- ⚠️ THE BUTTONS KEEP THEIR AUTHORED OFFSETS 320 x 52/70/66 - TutorialController finds them by
-- those numbers - and it breathes their OWN UIScale (resetting it to 1 after), so a phone height
-- comes from Size.Y.SCALE, never from a new offset or a UIScale of ours.
-- ⚠️ EVERY BRANCH SETS EVERYTHING. The mode flips both ways mid-session (a rotate, the simulator),
-- so no branch may lean on another having left a property alone.
-- AUTO ROLL is 31 (not 30) with a 4px gap (not 5): the engine lands a 30px target at 29.99, which
-- reads as under the 30px chip floor; the column total is unchanged.
local PHONE_PX = { margin = 5, baits = 36, roll = 42, auto = 31, pity = 18,
	gapBtn = 4, gapAuto = 4, gapReel = 7, top = 2, reelMin = 150, reelW = 288 }
-- phone pity chip widths, in proportion to each chip's widest label at 11px ("9/10", "99/100", "999/1K")
local PITY_W = { 27, 39, 39 }

local function guiSize()
	local a = gui.AbsoluteSize
	if gui.Enabled and a.X > 1 and a.Y > 1 then
		return a.X, a.Y
	end
	local mm = playerGui:FindFirstChild("MainMenu")
	if mm and mm.AbsoluteSize.X > 1 and mm.AbsoluteSize.Y > 1 then
		return mm.AbsoluteSize.X, mm.AbsoluteSize.Y
	end
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.Y > 1 then
		return cam.ViewportSize.X, cam.ViewportSize.Y
	end
	return nil, nil
end

local function fit()
	local W, H = guiSize()
	if not W then
		return
	end
	local topbar = GuiService:GetGuiInset().Y
	local sH, sW = (H - 4) / PANEL_H, 0.2285 * W / PANEL_W
	local mode, s
	if math.min(W, H) < 500 then
		mode, s = "phone", 0.20 * W / PANEL_W
	elseif sW < sH and ((H - 2 - PANEL_H * sW) - (topbar + 6) - 8) >= 76 then
		mode, s = "tablet", sW
	else
		-- The 0.4 floor keeps the column wide enough to read, but it must never make the panel
		-- TALLER than the screen: PANEL_H is 884, so 0.4 is a 354px panel and any viewport
		-- shorter than that had the reel clipped off at both ends. Below that height the floor
		-- gives way - a short column beats a cropped one.
		local floor = math.min(0.4, (H - 4) / PANEL_H)
		mode, s = "desktop", math.clamp(math.min((H - 4) / PANEL_H, (W * 0.46) / PANEL_W), floor, 1.7)
	end
	local changed = mode ~= hudMode
	hudMode = mode
	panelScale.Scale = s
	gui:SetAttribute("HudMode", mode)
	gui:SetAttribute("RailScale", s)
	-- keep the right-side MainMenu bar the same width as this roller (the ONLY writer of its Size)
	local menu = playerGui:FindFirstChild("MainMenu")
	local bar = menu and menu:FindFirstChild("MenuBar")
	if bar then
		bar.Size = UDim2.new(0, math.floor(PANEL_W * s + 0.5), 1, 0)
	end

	if mode == "phone" then
		local P = PHONE_PX
		local Hd = (H - 4) / s                   -- the panel's full height, in design px
		local function d(px) return px / s end   -- screen px -> design px
		panel.Size = UDim2.fromOffset(PANEL_W, Hd)
		panel.AnchorPoint = Vector2.new(0, 0.5)
		panel.Position = UDim2.new(0, -4, 0.5, 0)
		local y = Hd - d(P.margin)
		local function stack(btn, px, offset, gapAfter)
			y -= d(px)
			btn.Size = UDim2.new(0, BTN_W, (d(px) - offset) / Hd, offset)
			btn.Position = UDim2.new(0.5, 0, 0, y)
			y -= d(gapAfter)
		end
		stack(baitsBtn, P.baits, 66, P.gapBtn)
		stack(rollBtn, P.roll, 70, P.gapBtn)
		stack(autoBtn, P.auto, 52, P.gapAuto)
		-- Priority is buttons, then reel, then pity: a screen too short to leave the reel 150px
		-- with the chips in gives the chips' room to the reel instead.
		local blockTop = d(P.top)
		local showPity = (y - d(P.pity + P.gapReel) - blockTop) * s >= P.reelMin
		counterRow.Visible = showPity
		if showPity then
			y -= d(P.pity)
			counterRow.Size = UDim2.fromOffset(PANEL_W - d(20), d(P.pity))
			counterRow.Position = UDim2.new(0.5, 0, 0, y)
		end
		y -= d(P.gapReel)
		-- The reel + its marquee (bulbs reach 21 past the reel at k = 1) scale uniformly into what
		-- is left. The reel keeps a fixed RENDERED width (reelW, never wider than today's 300) by
		-- widening its own box by 1/k; REEL_H stays 3 cells, so the selector maths is untouched.
		local blockH = y - blockTop
		local k = math.clamp(blockH / (REEL_H + 42), 0.2, 1)
		local rw = P.reelW
		local top = blockTop + (blockH - (REEL_H + 42) * k) / 2 + 21 * k
		reelScale.Scale = k
		reel.Size = UDim2.fromOffset(rw / k, REEL_H)
		reel.Position = UDim2.fromOffset((PANEL_W - rw) / 2, top)
		placeBulbs((PANEL_W - rw) / 2, top, rw, REEL_H * k, k)
		-- pity chips: 18px tall, each as wide as its widest label needs
		local gap = d(3)
		local avail = PANEL_W - d(20) - 2 * gap
		local total = PITY_W[1] + PITY_W[2] + PITY_W[3]
		pityList.Padding = UDim.new(0, gap)
		for i, chip in ipairs(pityChips) do
			chip.Size = UDim2.fromOffset(avail * PITY_W[i] / total, d(P.pity))
			pityLabels[i].Size = UDim2.new(1, -d(4), 1, -d(2))
		end
	else
		panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
		if mode == "tablet" then
			panel.AnchorPoint = Vector2.new(0, 1)
			panel.Position = UDim2.new(0, -4, 1, -2)
		else
			panel.AnchorPoint = Vector2.new(0, 0.5)
			panel.Position = UDim2.new(0, -4, 0.5, 0)
		end
		local base = REEL_TOP + REEL_H
		autoBtn.Size = UDim2.fromOffset(BTN_W, 52)
		autoBtn.Position = UDim2.new(0.5, 0, 0, base + 82)
		rollBtn.Size = UDim2.fromOffset(BTN_W, 70)
		rollBtn.Position = UDim2.new(0.5, 0, 0, base + 144)
		baitsBtn.Size = UDim2.fromOffset(BTN_W, 66)
		baitsBtn.Position = UDim2.new(0.5, 0, 0, base + 224)
		counterRow.Visible = true
		counterRow.Size = UDim2.fromOffset(PANEL_W - 24, 44)
		counterRow.Position = UDim2.new(0.5, 0, 0, base + 26)
		pityList.Padding = UDim.new(0, 8)
		for i, chip in ipairs(pityChips) do
			chip.Size = UDim2.fromOffset(104, 40)
			pityLabels[i].Size = UDim2.new(1, -10, 1, -10)
		end
		reelScale.Scale = 1
		reel.Size = UDim2.fromOffset(REEL_W, REEL_H)
		reel.Position = UDim2.fromOffset(reelLeft, REEL_TOP)
		placeBulbs(reelLeft, REEL_TOP, REEL_W, REEL_H, 1)
	end
	if changed then
		-- the cells already on the strip, and the two mode-worded labels
		for _, c in ipairs(strip:GetChildren()) do
			layoutCell(c)
		end
		refreshBaitsBtn()
		for i in ipairs(PITY) do
			pityLabels[i].Text = pityText(i)
		end
	end
end
fit()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
-- the MainMenu bar may clone in after this script runs; re-apply once it exists
task.spawn(function()
	for _ = 1, 25 do
		if playerGui:FindFirstChild("MainMenu") then
			fit()
			break
		end
		task.wait(0.1)
	end
end)

----------------------------------------------------------------------
-- MARQUEE CHASE
----------------------------------------------------------------------

local clock = 0
local marqueeParked = false
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then
		return
	end
	-- Settings > Menu Animations. Park the bulbs evenly lit on the way out so the
	-- marquee doesn't freeze mid-wave looking half broken.
	if player:GetAttribute("Set_MenuFX") == false then
		if not marqueeParked then
			marqueeParked = true
			for _, b in ipairs(bulbs) do
				b.BackgroundTransparency = 0.12
			end
		end
		return
	end
	marqueeParked = false
	clock += dt
	for i, b in ipairs(bulbs) do
		local wave = math.sin(clock * 11 - i * 0.5)
		b.BackgroundTransparency = 0.12 + 0.6 * (1 - (wave * 0.5 + 0.5))
	end
end)

----------------------------------------------------------------------
-- ROLLING
----------------------------------------------------------------------

local baitRemote
local remotes = ReplicatedStorage:FindFirstChild("BaitRemotes")
if remotes then
	baitRemote = remotes:FindFirstChild("Rolled")
end

local inventory = {}
local spinning = false
local lastResult = BAITS[1]
local tickCell = nil   -- last cell index the reel showed, for the ratchet below

local function centreOffsetFor(index)
	return (REEL_H / 2) - (index * CELL_H + CELL_H / 2)
end

local function buildStrip(finalBait)
	strip:ClearAllChildren()
	for i = 0, STRIP_LEN - 1 do
		local def
		if i == START_INDEX then
			def = lastResult
		elseif i == END_INDEX then
			def = finalBait
		else
			def = pickBait() -- filler is weighted too, so the reel looks honest
		end
		makeCell(def, i)
	end
	strip.Position = UDim2.fromOffset(0, centreOffsetFor(START_INDEX))
end

local function bumpPity(result)
	for i, p in ipairs(PITY) do
		if result.rank >= p.rank then
			pityCount[i] = 0
		else
			pityCount[i] += 1
		end
		pityLabels[i].Text = pityText(i)
		player:SetAttribute("BaitPity" .. i, pityCount[i])
	end
end

local function forcedRank()
	local best = nil
	for i, p in ipairs(PITY) do
		if pityCount[i] + 1 >= p.every then
			if not best or p.rank > best then
				best = p.rank
			end
		end
	end
	return best
end

local function announce(result)
	if result.rank >= 3 then
		flash.BackgroundColor3 = result.color
		flash.BackgroundTransparency = 0.45
		TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	end
	-- The sting is Legendary+ only. Rare/Epic land often enough that giving them the
	-- fanfare would leave nothing left to mark a Leviathan Bait with.
	if result.rank >= 5 then
		Audio.play("Fanfare")
	elseif result.rank >= 3 then
		Audio.play("Coin", { pitch = 1.1 })
	end
	inventory[result.name] = (inventory[result.name] or 0) + 1
	-- Mirror onto the player so the Inventory menu (and any future server) can read
	-- the haul. Attribute is the source of truth; the local table is just the HUD's.
	-- attribute names allow only [A-Za-z0-9_], and several baits have spaces
	-- ("Golden Roe", "Leviathan Bait"); InventoryController strips them the same way
	local bk = "Bait_" .. (string.gsub(result.name, "[^%w]", ""))
	player:SetAttribute(bk, (player:GetAttribute(bk) or 0) + 1)
	gui:SetAttribute("LastRoll", result.name) -- for testing / other scripts
	if baitRemote and baitRemote:IsA("RemoteEvent") then
		baitRemote:FireServer(result.name)
	end
end

local function rollOnce()
	spinning = true
	rollLbl.Text = "ROLLING..."
	rollGrad.Color = ColorSequence.new(Color3.fromRGB(150, 154, 162), Color3.fromRGB(96, 100, 110))

	local result = pickBait(forcedRank())
	buildStrip(result)

	-- one 3s ease-out: Quint/Out starts at full speed and decelerates the whole way
	local tween = TweenService:Create(
		strip,
		TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, centreOffsetFor(END_INDEX)) }
	)
	-- Ticks are driven off the STRIP'S OWN POSITION, one per cell crossing the window,
	-- rather than off a timer - so the ratchet decelerates exactly in step with the
	-- ease-out instead of drifting away from what you can see.
	local ticker = RunService.RenderStepped:Connect(function()
		local cell = math.floor(-strip.Position.Y.Offset / CELL_H)
		if tickCell and cell ~= tickCell then
			Audio.play("Tick", { pitch = 1.15 + math.random() * 0.15, volume = 0.32 })
		end
		tickCell = cell
	end)

	tween:Play()
	tween.Completed:Wait()
	ticker:Disconnect()
	tickCell = nil

	bumpPity(result)
	announce(result)
	lastResult = result

	rollLbl.Text = "ROLL"
	rollGrad.Color = ColorSequence.new(Color3.fromRGB(126, 240, 120), Color3.fromRGB(36, 168, 62))
	spinning = false
end

local function startRolling()
	if spinning then
		return
	end
	task.spawn(function()
		repeat
			rollOnce()
			if autoOn then
				task.wait(0.35)
			end
		until not autoOn
	end)
end

local TouchKit = require(game:GetService("ReplicatedStorage"):WaitForChild("TouchKit"))
-- ROLL is the primary action of this panel and renders 134x29 on an 812x375 phone, well
-- under the 44px touch floor; AUTO ROLL is 134x22. Both get a hit pad on touch devices.
TouchKit.press(rollBtn, startRolling)

-- InventoryController builds BaitsMenu at runtime and may not have got there yet on a cold
-- join, so this resolves the window at PRESS time rather than at build time.
TouchKit.press(baitsBtn, function()
	local menu = playerGui:FindFirstChild("BaitsMenu")
	if not menu then return end
	local open = menu:FindFirstChild("Open")
	if open and open:IsA("BindableEvent") then open:Fire() else menu.Enabled = true end
end)

TouchKit.press(autoBtn, function()
	autoOn = not autoOn
	autoLbl.Text = autoOn and "AUTO ROLL: ON" or "AUTO ROLL: OFF"
	autoGrad.Color = autoOn
			and ColorSequence.new(Color3.fromRGB(126, 240, 120), Color3.fromRGB(36, 168, 62))
		or ColorSequence.new(Color3.fromRGB(120, 180, 230), Color3.fromRGB(48, 104, 166))
	if autoOn then
		startRolling()
	end
end)

-- Dev hook: BaitRoller.DevRoll:Fire() rolls without a click (scripted clicks aren't
-- possible from the Studio MCP thread).
local devRoll = new("BindableEvent", { Name = "DevRoll" }, gui)
devRoll.Event:Connect(startRolling)

buildStrip(BAITS[1])

print(string.format(
	"[BaitRoller] online - %d baits, 1/2 to 1/%s, %.1fs spin",
	#BAITS,
	commas(BAITS[#BAITS].odds),
	SPIN_TIME
))
