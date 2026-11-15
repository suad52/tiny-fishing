--[==[
	RebirthController  -  "The Deep Current"  (StarterGui.RebirthMenu)

	Reach a cash threshold -> release your catch to the tide for Pearls (the prestige currency) and a permanent
	"Tide Current" money multiplier. Ranks are ocean depth zones; the Pearl Reef sells permanent perks for pearls.
	Three tabs:
	    REBIRTH       the rank card, the next-tide progress bar, the big REBIRTH key (-> the confirm pop-up)
	    DEPTH LADDER  the twelve depth ranks and the Tide Current each one pays
	    PEARL REEF    the six permanent perks bought with pearls

	2026-10-10  RE-SKINNED ONTO ReplicatedStorage.ShopKit, the Shop's "sea candy" kit (the owner: make every MenuBar
	menu look like it belongs next to the Shop). The window is UI.window: a lagoon body with rising bubbles and light
	rays, a pink header with a wave crest, the gold title, the recycle emoji breaking out of the top-left corner and
	the red key X. Ranks and perks are candy rows in one colour each - the depth ladder runs from sunlit cyan down to
	the Kraken's fire - and every button is a candy key in its STATE's colour (green = you can, grey = not yet,
	gold = owned / the tab you're on, sea = the other tabs and NOT YET). Cash and pearls sit in pills, the lists
	scroll with the Shop's gold thumb. The dark DEEP_TOP/MID/BOT reef panels, the Gotham body copy and the drawn-X
	helper are gone. Three emoji that never rendered (U+1FA9C ladder, U+1FABC jellyfish, U+1FAA3 bucket - not in
	Roblox's emoji font; they measure as the 13 px notdef box) were swapped for ones that do.
	Nothing the menu DOES changed: the same model, attributes, remotes, publishProgression and TouchKit.press wiring.
	Geometry: the design size went 1100x680 -> 800x580 (the Shop's), so MIN_H was re-derived (desk 556 - the Rebirth
	page's stack; phone 316 - its two-column form), and off a phone the scale is held so the corner emoji stays
	under Roblox's top bar, as the Shop does. On a phone the window keeps its width and reflows only the Rebirth page
	(two columns) and the header (shorter, emoji and X tucked inside it). Pre-restyle source:
	ServerStorage.MenuBackup_PreCandy_2026-10-10.RebirthController (a StringValue).

	THE CONTRACT (what the rest of the place relies on)
	  * PlayerGui.RebirthMenu stays the same ScreenGui; Enabled is the only open/close signal (MenuLogic opens it,
	    MenuBlurManager blurs behind it, AudioController swishes on it, TutorialController and DailyController check it).
	  * The window X is the ONLY TextButton named "TextButton" in this gui (TutorialController's closeButtonOf). The
	    confirm pop-up has no X of its own; its NOT YET key closes it.
	  * State is LocalPlayer attributes: Rebirths, Pearls, Perk_<key>. This file publishes RebirthMult and
	    PerkValueMult (GameClient.valueOf and StatsHUD read them). A rebirth fires ReplicatedStorage.RebirthRemotes
	    .Rebirth (RemoteEvent, FireServer(gain)) and .OnRebirth (BindableEvent, Fire(rebirths, starterCash) -
	    UpgradesController wipes the tree on it); ZonesController resets off the Rebirths attribute.
	  * The confirm pop-up (Confirm > ConfirmWindow) is NOT under the window's UIScale: it stays 1:1 and readable.
	  * No click / open sounds of our own: AudioController hooks every button (the silent ClickGuards and the confirm
	    veil carry SndHooked so it leaves them alone).
	Studio lever: PlayerGui.RebirthMenu.DevRebirth:Fire("open", "Rebirth" | "Ranks" | "Reef") / ("tab", t) /
	("confirm") / ("preview" - the confirm pop-up even without the cash; RELEASE still re-checks) / ("close").
]==]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- Shared with every other pop-up window in the game (see fitToViewport).
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
-- The Shop's look: the window, candy rows, candy keys, pills and labels.
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))

local plr = Players.LocalPlayer
local gui = script.Parent

local rgb = Color3.fromRGB
local V2 = Vector2.new
local CENTRE = V2(0.5, 0.5)
local DOT = "  \u{00B7}  "

----------------------------------------------------------------------
-- number formatting
----------------------------------------------------------------------
local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.floor(math.log(n, 1000))
	tier = math.clamp(tier, 1, #SUFFIX - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIX[tier + 1])
end
local function money(n) return "$" .. abbrev(n) end
local function pearls(n) return abbrev(n) end

----------------------------------------------------------------------
-- rebirth model  (unchanged; Twilight Diver's icon was the jellyfish, which does not render)
----------------------------------------------------------------------
local RANKS = {
	{ title = "Tide Pool Novice",   zone = "Tide Pool",       icon = "🐚", accent = rgb(96,196,246)  },
	{ title = "Shallows Angler",    zone = "The Shallows",    icon = "🐠", accent = rgb(64,186,236)  },
	{ title = "Reef Diver",         zone = "Coral Reef",      icon = "🐡", accent = rgb(70,204,180)  },
	{ title = "Kelp Ranger",        zone = "Kelp Forest",     icon = "🌿", accent = rgb(76,200,120)  },
	{ title = "Open Water Sailor",  zone = "Open Water",      icon = "⛵", accent = rgb(74,170,240)  },
	{ title = "Deep Sea Hunter",    zone = "Deep Sea",        icon = "🦈", accent = rgb(72,122,220)  },
	{ title = "Twilight Diver",     zone = "Twilight Zone",   icon = "🤿", accent = rgb(132,110,240) },
	{ title = "Midnight Master",    zone = "Midnight Zone",   icon = "🦑", accent = rgb(112,80,214)  },
	{ title = "Abyssal Legend",     zone = "The Abyss",       icon = "🐙", accent = rgb(168,86,224)  },
	{ title = "Trench Sovereign",   zone = "The Trench",      icon = "🦞", accent = rgb(224,96,168)  },
	{ title = "Leviathan Lord",     zone = "Leviathan's Maw", icon = "🐋", accent = rgb(255,124,124) },
	{ title = "Kraken Ascendant",   zone = "Kraken's Realm",  icon = "🦑", accent = rgb(255,104,150) },
}
local function rankFor(n) return RANKS[math.clamp(n + 1, 1, #RANKS)] end
-- one candy colour per rank (UI.CANDY), running down the water column: sunlit cyan at the Tide Pool, through the
-- reef and the kelp, blues and violets in the deep, the abyss's aurora, then the trench's rose and the Kraken's fire
local RANK_CANDY = { "cyan", "reef", "teal", "emerald", "blue", "royal", "purple", "cosmic", "aurora", "rose", "coral", "fire" }

-- ⚠️ REQ_GROWTH was 6, against a reward that grows +0.25 ADDITIVELY per rank. Cost x6 versus
-- reward +0.25 diverges 5.3x every rank, so the ladder outran the game: rank 11 wanted
-- $3,023,308,800,000 - about 2.3 YEARS of continuous play - and the RANKS table advertises 12.
-- Six of the twelve ranks were fiction. At 2.5 the ladder reads 50k / 125k / 313k / 781k /
-- 1.95M / 4.88M / 12.2M / 30.5M / 76.3M / 191M / 477M, which finishes inside a long session
-- and stays under the compressed boat ladder's 150M top rung.
local REQ_BASE, REQ_GROWTH = 50000, 2.5
local function req(n) return math.floor(REQ_BASE * (REQ_GROWTH ^ n)) end
local function currentMult(n) return 1 + 0.25 * n end
local function pearlsFor(cash, n)
	local ratio = cash / req(n)
	if ratio < 1 then return 0 end
	return math.max(1, math.floor(4 * (n + 1) * math.sqrt(ratio)))
end

local PERKS = {
	{ key = "fortune",  name = "Tide Fortune",    icon = "💰", accent = rgb(240,202,84),  base = 2, growth = 1.6, max = 25, per = 8,  unit = "% fish value",  desc = "Every fish you sell is worth more." },
	{ key = "luck",     name = "Pearl Luck",      icon = "🍀", accent = rgb(96,214,128),  base = 3, growth = 1.7, max = 20, per = 6,  unit = "% rare chance", desc = "Hook rarer species far more often." },
	{ key = "reach",    name = "Deep Reach",      icon = "⚓", accent = rgb(96,172,242),  base = 3, growth = 1.7, max = 15, per = 10, unit = " max depth",    desc = "Cast into deeper, richer water." },
	{ key = "reel",     name = "Swift Reel",      icon = "🎣", accent = rgb(92,204,224),  base = 2, growth = 1.6, max = 20, per = 7,  unit = "% reel speed",  desc = "Reel every catch in faster." },
	{ key = "nets",     name = "Bountiful Nets",  icon = "🪣", accent = rgb(242,152,90),  base = 4, growth = 1.8, max = 12, per = 1,  unit = " fish / cast",  desc = "Haul more fish on a single cast." },
	{ key = "blessing", name = "Ocean's Blessing",icon = "✨", accent = rgb(182,142,244), base = 5, growth = 1.9, max = 10, per = 50, unit = "% starter cash",desc = "Begin every rebirth far wealthier." },
}
local function perkCost(perk, tier) return math.floor(perk.base * (perk.growth ^ tier)) end
-- how each perk's row looks: its candy colour and its icon - a 3D ShopIcons model where one fits, else the emoji
-- (Bountiful Nets' bucket emoji does not render; the two-fish model says "more fish a cast" anyway)
local PERK_LOOK = {
	fortune  = { colour = "orange",  icon = "coinpile" },
	luck     = { colour = "emerald", icon = "clover" },
	reach    = { colour = "blue",    emoji = "⚓" },
	reel     = { colour = "cyan",    icon = "reel" },
	nets     = { colour = "coral",   icon = "twofish" },
	blessing = { colour = "purple",  icon = "treasure" },
}

----------------------------------------------------------------------
-- state  (attributes on the player, unchanged)
----------------------------------------------------------------------
local function getRebirths() return plr:GetAttribute("Rebirths") or 0 end
local function getPearls()   return plr:GetAttribute("Pearls") or 0 end
local function getPerk(key)  return plr:GetAttribute("Perk_" .. key) or 0 end
if plr:GetAttribute("Rebirths") == nil then plr:SetAttribute("Rebirths", 0) end
if plr:GetAttribute("Pearls") == nil then plr:SetAttribute("Pearls", 0) end
for _, p in ipairs(PERKS) do
	if plr:GetAttribute("Perk_" .. p.key) == nil then plr:SetAttribute("Perk_" .. p.key, 0) end
end

----------------------------------------------------------------------
-- publish: the seam the fishing loop actually reads
----------------------------------------------------------------------
-- ⚠️ EVERYTHING ABOVE THIS POINT USED TO BE DISPLAY ONLY. Until 2026-09-03 nothing in the
-- game read Rebirths or Perk_*, so the "Tide Current" on the rank card, the x1.00 -> x3.75
-- column running down the whole Depth Ladder, and the "+25% Current" promised in the
-- confirm dialog all multiplied NOTHING: a rebirth took your cash, your entire upgrade tree
-- and every zone past Lighthouse Cove, and paid back a number that did not exist anywhere.
-- StatsHUD had already found the gap and left the instruction in its own docstring -
-- "Wire those into GameClient first, then add them here." This is that wiring.
--
-- Same "attribute is the seam" contract as UpgradesController's publish(), BoatClient's
-- BoatCoinMult and InventoryController's publishBaitStats: this menu owns the formula and
-- GameClient reads only the published result, never this file.
--   RebirthMult    the Tide Current, 1 + 0.25 per rebirth  -> multiplies fish value
--   PerkValueMult  the Tide Fortune pearl perk, +8% / tier  -> multiplies fish value
--
-- The other four perks are still unwired ON PURPOSE, and one of them is a trap:
--   • Deep Reach (+10 max depth / tier, 15 tiers) CANNOT be wired as written. Depth is
--     capped by GEOMETRY, not balance - see the warning above BRANCHES in
--     UpgradesController: the Mythic band bottoms out at -620 and the painted column floor
--     is -660, and 120 base + 200 from the upgrade branch + 300 from rod 10 already lands
--     on 620 exactly. A further +150 would drop the hook through the floor into unpainted
--     black water. Move the bands and DepthStrata's column first.
--   • Pearl Luck, Swift Reel and Bountiful Nets are safe to add (they would join the same
--     sums GameClient already builds for luck, reel speed and hook capacity) but they are
--     not money, so they are out of scope for this pass.
local FORTUNE
for _, p in ipairs(PERKS) do if p.key == "fortune" then FORTUNE = p end end
local function publishProgression()
	plr:SetAttribute("RebirthMult",   currentMult(getRebirths()))
	plr:SetAttribute("PerkValueMult", 1 + (FORTUNE.per / 100) * getPerk(FORTUNE.key))
end
-- Driven off the ATTRIBUTES rather than off the rebirth/buy buttons, so a dev hook, a
-- future server hand-off or a restored save all republish too - the same reasoning
-- InventoryController gives for republishing EquippedRod "whatever changed it". Ungated by
-- gui.Enabled: the fishing loop needs these whether or not this menu is open.
plr:GetAttributeChangedSignal("Rebirths"):Connect(publishProgression)
plr:GetAttributeChangedSignal("Perk_" .. FORTUNE.key):Connect(publishProgression)
publishProgression()

local DEMO_BALANCE = 0 -- fallback only; the real balance is the shared leaderstats.Money
local cash = DEMO_BALANCE
local cashSource = nil
local refreshAll  -- forward decl
local function bindCash()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then
		cashSource = m
		cash = m.Value
		m.Changed:Connect(function(v) cash = v; if gui.Enabled then refreshAll() end end)
	end
end

----------------------------------------------------------------------
-- layout (design px: the window scales with a UIScale)
----------------------------------------------------------------------
-- 800 x 580 is the Shop's design size, so the two windows sit at the same scale side by side. MIN_H is the shortest
-- design height at which nothing outside a ScrollingFrame pokes out of the window (MenuFit's contract):
--   desk  556 = Content top 160 + the Rebirth page's one-column stack (374 + its 6 px key drop) + 16 under it
--   phone 316 = Content top 130 + the two-column stack (168 + 6 + 2) + 10 under it
-- The Ladder and Reef pages are ScrollingFrames, so they go as short as the window does.
local L = {
	W = 800, H = 580, MIN_H = 556, MIN_H_PHONE = 316, MAX_S = 1.1, MAX_S_PHONE = 1,
	REACH = 46,                      -- the corner emoji's reach above the window top (44 px up + its tilt)
	TAB_X = { 140, 400, 660 }, TAB_W = 244,
}
-- the window chrome per form. Arrays are { x, y, w, h }; pills add their icon / text sizes.
-- phone: a 60 px header with the emoji INSIDE it (breaking out, it would sit under Roblox's top-bar buttons) and the
-- X moved in off the screen edge (the window spans ~94% of a phone's width, so a corner X overhanging by 30 px
-- would be clipped).
local MODE = {
	desk = {
		headerH = 74, titleX = 112, titleW = 244, titleMax = 46, icon = { -36, -44, 124 },
		close = { pos = UDim2.new(1, -12, 0, 12), size = 60, text = 34 },
		pearl = { 368, 14, 140, 46, icon = 30, text = 26 }, cash = { 520, 14, 184, 46, icon = 38, text = 26 },
		tabY = 95, tabH = 54, tabIcon = 30, tabText = 28, contentY = 160, contentB = 16,
	},
	phone = {
		headerH = 60, titleX = 72, titleW = 338, titleMax = 36, icon = { 6, 0, 58 },
		close = { pos = UDim2.new(1, -34, 0, 30), size = 52, text = 30 },
		pearl = { 420, 9, 130, 42, icon = 28, text = 24 }, cash = { 560, 9, 170, 42, icon = 34, text = 24 },
		tabY = 76, tabH = 44, tabIcon = 28, tabText = 26, contentY = 130, contentB = 10,
	},
}
-- the Rebirth page per form, inside its stack (744 wide, centred in Content). Text entries are { x, y, w, h, max }.
-- desk: rank card / progress card / REBIRTH key in one column. phone: the rank card on the left, progress + key on
-- the right, so the key never scrolls away.
local P1L = {
	desk = {
		stackH = 374, rank = { 0, 0, 744, 136 }, prog = { 0, 156, 744, 112 }, key = { 0, 288, 744, 86 },
		rankIcon = { 18, 20, 96 }, rankGlow = 124,
		rankTag = { 128, 12, 324, 28, 22 }, rankTitle = { 128, 40, 324, 52, 42 }, rankZone = { 128, 94, 324, 30, 24 },
		tiles = { { 464, 14, 128, 108 }, { 602, 14, 128, 108 } },
		tileLabel = { 6, 8, 116, 26, 17 }, tileValue = { 6, 36, 116, 56, 44 },
		progHead = { 20, 6, 704, 32, 28 }, bar = { 20, 42, 704, 36, 24 }, reward = { 20, 82, 704, 26, 22 },
		keyTop = { 6, 44, 38 }, keySub = { 52, 24, 20 },
	},
	phone = {
		stackH = 168, rank = { 0, 0, 364, 168 }, prog = { 380, 0, 364, 96 }, key = { 380, 108, 364, 60 },
		rankIcon = { 14, 12, 72 }, rankGlow = 96,
		rankTag = { 92, 8, 262, 22, 17 }, rankTitle = { 92, 30, 262, 38, 30 }, rankZone = { 92, 68, 262, 22, 18 },
		tiles = { { 12, 94, 166, 64 }, { 186, 94, 166, 64 } },
		tileLabel = { 6, 3, 154, 20, 15 }, tileValue = { 6, 22, 154, 32, 28 },
		progHead = { 12, 4, 340, 24, 20 }, bar = { 12, 30, 340, 32, 20 }, reward = { 12, 66, 340, 24, 17 },
		keyTop = { 4, 32, 28 }, keySub = { 36, 18, 15 },
	},
}
local lay = { compact = false, modeName = "desk" }

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
-- a line in the house face (UI.label: FredokaOne, an INK outline that scales with the letters, a hard drop).
-- o: x / y / w / h, o (outline px), drop, color, align, rich, wrap, ZIndex, Name
local function label(parent, str, size, o)
	o = o or {}
	return (UI.label(parent, str, {
		Name = o.Name or "Text", size = size, color = o.color, drop = o.drop, align = o.align,
		outline = (o.o and o.o > 0) and o.o / size or nil,
		Size = UDim2.fromOffset(o.w or 100, o.h or math.ceil(size * 1.3)), Position = UDim2.fromOffset(o.x or 0, o.y or 0),
		ZIndex = o.ZIndex or 3, RichText = o.rich or nil, TextWrapped = o.wrap or nil,
	}))
end
-- a scaled label's max text size, on it and on its drop
local function setMax(l, n)
	for _, t in ipairs({ l, l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop") }) do
		local c = t and t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MaxTextSize = n
			c.MinTextSize = math.min(c.MinTextSize, n)
		end
	end
end
-- place a box by its top-left corner whatever its AnchorPoint: s = { x, y, w, h }
local function rect(o, s)
	local ap = o.AnchorPoint
	o.Position = UDim2.fromOffset(s[1] + s[3] * ap.X, s[2] + s[4] * ap.Y)
	o.Size = UDim2.fromOffset(s[3], s[4])
end
-- a label: rect + its max text size (s[5])
local function place(l, s)
	rect(l, s)
	if s[5] then setMax(l, s[5]) end
end
-- a transparent button with no handler: it swallows taps so they never reach the Backdrop under the window.
-- Silent (SndHooked before it is parented, so AudioController leaves it alone).
local function clickGuard(parent, size, z)
	local b = UI.new("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, ZIndex = z,
	})
	b:SetAttribute("SndHooked", true)
	b.Parent = parent
	return b
end
-- an emoji icon on a soft glow (the rows' icon slot, for icons this game draws as emoji)
local function emojiIcon(parent, emoji, z)
	z = z or 4
	local g = UI.new("ImageLabel", {
		Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow or "", ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = CENTRE, ImageTransparency = 0.15, ZIndex = z,
	}, parent)
	local e = UI.new("TextLabel", {
		Name = "Icon", BackgroundTransparency = 1, Text = emoji, TextScaled = true, FontFace = UI.FONT,
		TextColor3 = UI.WHITE, Rotation = -6, ZIndex = z + 2,
	}, parent)
	return g, e
end
local function placeEmoji(g, e, x, y, size, glow)
	e.Position, e.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(size, size)
	g.Position, g.Size = UDim2.fromOffset(x + size / 2, y + size / 2), UDim2.fromOffset(glow, glow)
end
-- a candy slab (UI.candyRow's anatomy without its fixed geometry): INK outline, hard drop, gloss cap, a gradient face
-- in a UI.CANDY colour. Centre-anchored so a punch grows it evenly. Content goes on .root at ZIndex 4+.
local function slab(parent, name, colour, z)
	local s = {}
	s.root = UI.new("Frame", { Name = name, BackgroundTransparency = 1, AnchorPoint = CENTRE, ZIndex = z or 2 }, parent)
	s.scale = UI.new("UIScale", {}, s.root)
	UI.hardShadow(s.root, 16, 4, 6, 1)
	s.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, s.root)
	UI.corner(s.face, 16)
	UI.stroke(s.face, 4)
	UI.gloss(s.face, { frac = 0.42, alpha = 0.62, inset = 4, radius = 12 })
	function s.setColour(c)
		if s.colour == c then return end
		s.colour = c
		UI.vgrad(s.face, UI.CANDY[c] or c)
	end
	s.setColour(colour)
	return s
end
-- a scroll list in the Shop's style: 772 wide (rows 744 at x 8), its gold thumb over a faint INK track in a 10 px
-- lane on the right. CanvasPosition is in SCREEN px, so a UIScale change (the open pop, a refit) would slide the rows
-- under the view: the list keeps its place in design px (.y) and puts it back.
local function makeList(parent, name)
	local o = { y = 0 }
	o.track = UI.new("Frame", {
		Name = name .. "Track", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
		Position = UDim2.fromOffset(762, 0), Size = UDim2.new(0, 10, 1, 0), ZIndex = 5,
	}, parent)
	UI.corner(o.track, 5)
	o.frame = UI.new("ScrollingFrame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(0, 772, 1, 0), ZIndex = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, VerticalScrollBarInset = Enum.ScrollBarInset.None,
		CanvasSize = UDim2.fromOffset(0, 400),
	}, parent)
	local function k()
		local c, a = o.frame.CanvasSize.Y.Offset, o.frame.AbsoluteCanvasSize.Y
		if c <= 0 or a <= 0 then return nil end
		return a / c
	end
	function o.scrollTo(y)
		local kk = k()
		if not kk then return end
		local view = o.frame.AbsoluteWindowSize.Y / kk
		o.y = math.clamp(y, 0, math.max(o.frame.CanvasSize.Y.Offset - view, 0))
		o.frame.CanvasPosition = V2(0, o.y * kk)
	end
	o.frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local kk = k()
		if kk then o.y = o.frame.CanvasPosition.Y / kk end
	end)
	return o
end

----------------------------------------------------------------------
-- backdrop + window
----------------------------------------------------------------------
-- the scrim: a dark full-screen BUTTON under the window - a tap anywhere outside the window closes the menu
local backdrop = UI.new("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.45, AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(4, 4),
	ZIndex = 1,
}, gui)

local WIN = UI.window(gui, "REBIRTH", { Name = "Window", w = L.W, h = L.H, emoji = "♻️", headColour = "pink", ZIndex = 5 })
local root = WIN.root
local uiscale = UI.new("UIScale", { Scale = 1 }, root)
-- the window catches its own taps (a plain Active Frame does NOT stop the Backdrop under it): handler-less guards over
-- the body + its drop (ZIndex 3: over Shadow / Body, under everything else) and over the corner emoji
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, 9), 3), 24)
if WIN.icon then clickGuard(WIN.icon, UDim2.new(1, 0, 1, 5), 20) end

-- the counters: your pearls and your cash, in pills left of the X (static keys: not pressable)
local HUD = {}
HUD.pearl = UI.candyKey(root, "sea", { Name = "PearlPill", static = true, ZIndex = 7 })
HUD.cash = UI.candyKey(root, "gold", { Name = "CashPill", static = true, ZIndex = 7 })
function HUD.setPearls(force)
	local s = pearls(getPearls())
	if HUD.pearlShown == s and not force then return end
	HUD.pearlShown = s
	local m = MODE[lay.modeName]
	HUD.pearl.setParts(nil, { { text = "🦪", size = m.pearl.icon, drop = 0, o = 0 }, { text = s, size = m.pearl.text, o = 4, drop = 2 } }, { gap = 6 })
end
function HUD.setCash(force)
	local s = money(cash)
	if HUD.cashShown == s and not force then return end
	HUD.cashShown = s
	local m = MODE[lay.modeName]
	HUD.cash.setParts(nil, { { icon = "coins", size = m.cash.icon, drop = 0 }, { text = s, size = m.cash.text, o = 4, drop = 2 } }, { gap = 6 })
end
-- "not enough pearls": the pearl pill blinks red
function HUD.flashPearls()
	HUD.flashToken = (HUD.flashToken or 0) + 1
	local my = HUD.flashToken
	HUD.pearl.recolour("red")
	task.delay(0.5, function() if HUD.flashToken == my then HUD.pearl.recolour("sea") end end)
end

----------------------------------------------------------------------
-- content area, pages, tabs
----------------------------------------------------------------------
local CONTENT = UI.new("Frame", { Name = "Content", BackgroundTransparency = 1, ZIndex = 6 }, root)
local PAGES = {}
for _, n in ipairs({ "Rebirth", "Ranks", "Reef" }) do
	PAGES[n] = UI.new("Frame", { Name = n, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = n == "Rebirth", ZIndex = 2 }, CONTENT)
end
local currentTab = "Rebirth"
local selectTab -- forward decl
-- the tabs: keys under the header - gold is the tab you're on, the others sea blue (the Shop's)
local TABS = {
	{ name = "Rebirth", word = "REBIRTH",      emoji = "🌊" },
	{ name = "Ranks",   word = "DEPTH LADDER", emoji = "🔱" },
	{ name = "Reef",    word = "PEARL REEF",   emoji = "🦪" },
}
for _, t in ipairs(TABS) do
	t.key = UI.candyKey(root, "sea", { Name = t.name .. "Tab", AnchorPoint = CENTRE, ZIndex = 7 })
	TouchKit.press(t.key.button, function() selectTab(t.name) end)
end

--==================================================================
-- PAGE 1 : REBIRTH  (rank card, next-tide progress, the REBIRTH key)
--==================================================================
local P1 = {}
P1.stack = UI.new("Frame", {
	Name = "Stack", BackgroundTransparency = 1, AnchorPoint = CENTRE, Position = UDim2.new(0.5, 0, 0.5, -3), ZIndex = 2,
}, PAGES.Rebirth)

-- the rank card: your rank's emoji on a glow, CURRENT RANK / the title / the zone, and two counter tiles
P1.rank = slab(P1.stack, "RankCard", RANK_CANDY[1], 2)
P1.rankGlow, P1.rankIcon = emojiIcon(P1.rank.root, RANKS[1].icon, 4)
P1.rankTag = label(P1.rank.root, "CURRENT RANK", 22, { Name = "RankTag", o = 3, drop = 2, ZIndex = 7 })
P1.rankTitle = label(P1.rank.root, RANKS[1].title, 42, { Name = "RankTitle", o = 5, drop = 3, ZIndex = 7 })
P1.rankZone = label(P1.rank.root, "", 24, { Name = "RankZone", o = 3.5, drop = 2, ZIndex = 7, color = UI.TEXT.soft })
P1.tiles = {}
for i, def in ipairs({ { "RebirthsTile", "REBIRTHS", UI.TEXT.gold }, { "CurrentTile", "TIDE CURRENT", UI.TEXT.lime } }) do
	local b = UI.block(P1.rank.root, "navy", { Name = def[1], ZIndex = 8, lip = 7, radius = 14 })
	P1.tiles[i] = {
		block = b,
		label = label(b.face, def[2], 17, { Name = "Label", o = 2.5, drop = 2, ZIndex = 3 }),
		value = label(b.face, "-", 44, { Name = "Value", o = 5, drop = 3, color = def[3], ZIndex = 3 }),
	}
end

-- the next tide: a progress bar (gold while it fills, green once you can rebirth) and the reward
P1.prog = slab(P1.stack, "NextTide", "royal", 2)
P1.progHead = label(P1.prog.root, "NEXT TIDE", 28, { Name = "Head", o = 4, drop = 3, ZIndex = 7 })
P1.bar = UI.new("Frame", { Name = "Bar", BackgroundColor3 = UI.INK, BackgroundTransparency = 0.45, ZIndex = 7 }, P1.prog.root)
UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, P1.bar)
UI.stroke(P1.bar, 3)
P1.fill = UI.new("Frame", { Name = "Fill", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(0, 1), Visible = false, ZIndex = 2 }, P1.bar)
UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, P1.fill)
UI.gloss(P1.fill, { frac = 0.5, alpha = 0.5, inset = 3, radius = 10 })
P1.barText = label(P1.bar, "", 24, { Name = "Amount", o = 3.5, drop = 2, ZIndex = 4 })
P1.barText.Size = UDim2.fromScale(1, 1)
P1.reward = label(P1.prog.root, "", 22, { Name = "Reward", o = 3, drop = 2, ZIndex = 7, rich = true })
function P1.setFill(pct, can)
	-- never narrower than the bar is tall (a sliver would draw as a squashed blob, not a pill)
	local h = P1.bar.Size.Y.Offset
	P1.fill.Visible = pct > 0
	TweenService:Create(P1.fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		Size = UDim2.new(pct, math.floor(h * (1 - pct)), 1, 0),
	}):Play()
	local c = can and "green" or "gold"
	if P1.fillColour ~= c then
		P1.fillColour = c
		UI.vgrad(P1.fill, UI.BRICK[c])
	end
end

-- the REBIRTH key (green when you can, grey with a lock when you can't), with a breathing gold ring when ready
P1.halo = UI.new("Frame", { Name = "ReadyGlow", BackgroundTransparency = 1, Visible = false, ZIndex = 1 }, P1.stack)
UI.corner(P1.halo, 20)
P1.haloStroke = UI.stroke(P1.halo, 4, UI.RING)
P1.key = UI.candyKey(P1.stack, "grey", { Name = "RebirthKey", AnchorPoint = CENTRE, ZIndex = 3 })
P1.glyphL = UI.new("TextLabel", {
	Name = "GlyphL", BackgroundTransparency = 1, Text = "🌊", TextScaled = true, FontFace = UI.FONT,
	TextColor3 = UI.WHITE, AnchorPoint = V2(0, 0.5), ZIndex = 2,
}, P1.key.text)
P1.glyphR = P1.glyphL:Clone()
P1.glyphR.Name = "GlyphR"
P1.glyphR.Parent = P1.key.text
P1.lockImg = UI.icon(P1.key.text, "lock", 38, { Name = "Lock", AnchorPoint = V2(0, 0.5), ZIndex = 2, flat = true, Visible = false })
P1.keyWord = label(P1.key.text, "REBIRTH", 38, { Name = "Word", o = 4.5, drop = 3, ZIndex = 2 })
P1.keySub = label(P1.key.text, "", 20, { Name = "Sub", o = 3, drop = 2, ZIndex = 2 })
-- the key's top line: [wave] REBIRTH [wave], or [lock] NOT ENOUGH, centred on the key
function P1.layKey(can)
	local p = P1L[lay.modeName]
	local keyW = p.key[3]
	local y, h, size = p.keyTop[1], p.keyTop[2], p.keyTop[3]
	local word = can and "REBIRTH" or "NOT ENOUGH"
	P1.keyWord.Text = word
	local ww = math.ceil(UI.textWidth(word, size)) + 6 + math.ceil(size * 0.3) -- (+ the outline: no slack and TextScaled shrinks)
	local gw = can and size or math.floor(size * 0.9)
	local gap = math.floor(size * 0.3)
	local total = can and (gw * 2 + gap * 2 + ww) or (gw + gap + ww)
	local x = math.floor((keyW - total) / 2 + 0.5)
	local cy = math.floor(y + h / 2 + 0.5)
	P1.glyphL.Visible, P1.glyphR.Visible, P1.lockImg.Visible = can, can, not can
	local lead = can and P1.glyphL or P1.lockImg
	lead.Position, lead.Size = UDim2.fromOffset(x, cy), UDim2.fromOffset(gw, gw)
	P1.keyWord.AnchorPoint = V2(0, 0.5)
	P1.keyWord.Position, P1.keyWord.Size = UDim2.fromOffset(x + gw + gap, cy), UDim2.fromOffset(ww, h)
	setMax(P1.keyWord, size)
	if can then
		P1.glyphR.Position, P1.glyphR.Size = UDim2.fromOffset(x + gw + gap + ww + gap, cy), UDim2.fromOffset(gw, gw)
	end
	P1.keySub.Position, P1.keySub.Size = UDim2.fromOffset(10, p.keySub[1]), UDim2.fromOffset(keyW - 20, p.keySub[2])
	setMax(P1.keySub, p.keySub[3])
end

--==================================================================
-- PAGE 2 : DEPTH LADDER  (one candy row per rank, in its depth colour)
--==================================================================
local LAD = { rows = {}, ROW_H = 84, STEP = 102 }
LAD.list = makeList(PAGES.Ranks, "Ladder")
function LAD.rowY(i) return 10 + (i - 1) * LAD.STEP end
for i, rk in ipairs(RANKS) do
	local r = UI.candyRow(LAD.list.frame, {
		kind = "card", Name = "Rank" .. i, colour = RANK_CANDY[i], h = LAD.ROW_H, key = false, mid = { x = 96, w = 470 },
		Position = UDim2.fromOffset(8, LAD.rowY(i)),
	})
	r.l1.Position, r.l1.Size = UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 40)
	r.l2.Position, r.l2.Size = UDim2.fromOffset(0, 48), UDim2.new(1, 0, 0, 28)
	local g, e = emojiIcon(r.button, rk.icon, 4)
	placeEmoji(g, e, 18, 12, 60, 92)
	label(r.l1, rk.title, 32, { Name = "Title", w = 470, h = 40, o = 4.5, drop = 3 })
	label(r.l2, string.upper(rk.zone), 22, { Name = "Zone", w = 470, h = 28, o = 3, drop = 2, color = UI.TEXT.soft })
	-- the Tide Current this rank pays, on a static key: green + check = passed, gold = you, grey + lock = ahead
	local mult = UI.candyKey(r.button, "grey", {
		Name = "Mult", static = true, Size = UDim2.fromOffset(156, 56), Position = UDim2.fromOffset(574, 14), ZIndex = 10,
	})
	local here = UI.sticker(r.button, "gold", "YOU ARE HERE", {
		Name = "Here", Position = UDim2.fromOffset(600, 8), Rotation = 6, textSize = 14, height = 28, ZIndex = 12,
	})
	here.block.root.Visible = false
	LAD.rows[i] = { row = r, mult = mult, here = here, text = string.format("x%.2f", currentMult(i - 1)) }
end
LAD.list.frame.CanvasSize = UDim2.fromOffset(0, LAD.rowY(#RANKS) + LAD.ROW_H + 6 + 10)
-- opening the ladder shows your own rank (with the one above it for context), not always the Tide Pool
function LAD.showCurrent()
	local idx = math.clamp(getRebirths() + 1, 1, #RANKS)
	LAD.list.scrollTo(LAD.rowY(idx) - 10 - LAD.STEP)
end

--==================================================================
-- PAGE 3 : PEARL REEF  (the perks: one tall candy row each, a pearl-price key)
--==================================================================
local REEF = { rows = {}, STEP = 148 }
REEF.list = makeList(PAGES.Reef, "Perks")
do
	local note = UI.candyRow(REEF.list.frame, { kind = "strip", Name = "ReefNote", colour = "royal", Position = UDim2.fromOffset(8, 10) })
	label(note.l1, "Spend pearls on permanent power - they survive every rebirth!", 22, { Name = "Note", w = 744, h = 50, o = 3, drop = 2 })
end
for i, perk in ipairs(PERKS) do
	local look = PERK_LOOK[perk.key] or { colour = "blue", emoji = perk.icon }
	local r = UI.candyRow(REEF.list.frame, {
		kind = "tall744", Name = "Perk_" .. perk.key, colour = look.colour, icon = look.icon,
		Position = UDim2.fromOffset(8, 80 + (i - 1) * REEF.STEP),
	})
	if look.emoji then
		local g, e = emojiIcon(r.button, look.emoji, 4)
		placeEmoji(g, e, 14, 16, 96, 132)
	end
	local pc = { perk = perk, row = r }
	pc.name = label(r.l1, perk.name, 34, { Name = "Title", w = 404, h = 46, o = 5, drop = 3 })
	pc.eff = label(r.l2, "", 25, { Name = "Effect", w = 404, h = 32, o = 3.5, drop = 2, rich = true })
	pc.desc = label(r.l3, perk.desc, 22, { Name = "Desc", w = 404, h = 28, o = 3, drop = 2, color = UI.TEXT.soft })
	REEF.rows[i] = pc
end
REEF.list.frame.CanvasSize = UDim2.fromOffset(0, 80 + (#PERKS - 1) * REEF.STEP + 128 + 6 + 10)

----------------------------------------------------------------------
-- confirmation pop-up  (NOT under the window's UIScale: it stays 1:1 and readable)
----------------------------------------------------------------------
local CF = { W = 520, H = 298, fit = 1 }
-- the veil is a BUTTON with no handler: taps on it must not reach the window's keys under it
CF.veil = UI.new("TextButton", {
	Name = "Confirm", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(4, 12, 30),
	BackgroundTransparency = 0.42, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30,
})
CF.veil:SetAttribute("SndHooked", true)
CF.veil.Parent = gui
CF.win = UI.window(CF.veil, "TURN THE TIDE?", {
	Name = "ConfirmWindow", w = CF.W, h = CF.H, headerH = 64, titleSize = 36, emoji = "🌊", iconSize = 58,
	iconPos = V2(12, 3), headColour = "pink", ZIndex = 31,
})
-- one X per gui (TutorialController's closeButtonOf would otherwise have two to choose from): NOT YET closes this one
CF.win.close.button:Destroy()
CF.win.close = nil
CF.win.title.Position, CF.win.title.Size = UDim2.fromOffset(80, 0), UDim2.fromOffset(CF.W - 80 - 18, 64)
CF.scale = UI.new("UIScale", { Scale = 1 }, CF.win.root)
CF.body = label(CF.win.root, "", 20, {
	Name = "Body", x = 22, y = 80, w = CF.W - 44, h = 132, o = 3, drop = 2, rich = true, wrap = true, ZIndex = 7,
})
CF.cancel = UI.candyKey(CF.win.root, "sea", { Name = "NotYet", Size = UDim2.fromOffset(224, 58), Position = UDim2.fromOffset(24, 222), ZIndex = 7 })
CF.cancel.set(nil, "NOT YET", 28)
CF.ok = UI.candyKey(CF.win.root, "green", { Name = "Release", Size = UDim2.fromOffset(224, 58), Position = UDim2.fromOffset(272, 222), ZIndex = 7 })
CF.ok.setParts(nil, { { text = "RELEASE!", size = 28 }, { text = "🌊", size = 30, drop = 0, o = 0 } })

----------------------------------------------------------------------
-- toast (in the window, the Shop's: a navy / green / gold / red chip that pops in over the bottom edge)
----------------------------------------------------------------------
local TOAST = {}
TOAST.chip = UI.chip(root, "navy", {
	Name = "Toast", height = 50, textSize = 24, pad = 26, minWidth = 240, AnchorPoint = V2(0.5, 1), ZIndex = 40,
	Position = UDim2.new(0.5, 0, 1, -18),
})
TOAST.chip.block.root.Visible = false
TOAST.scale = UI.new("UIScale", {}, TOAST.chip.block.root)
-- kind: "good" (green), "info" (gold), "bad" (red), else navy
local function showToast(msg, kind)
	local colour = ({ good = "green", info = "gold", bad = "red" })[kind or ""] or "navy"
	TOAST.chip.set(msg, colour)
	local r = TOAST.chip.block.root
	r.Visible = true
	UI.punch(TOAST.scale, 0.6, 0.28)
	TOAST.token = (TOAST.token or 0) + 1
	local my = TOAST.token
	task.delay(2.4, function()
		if TOAST.token == my then r.Visible = false end
	end)
end

----------------------------------------------------------------------
-- the sea behind it all: light rays and rising bubbles in the window's Ocean layer (and a few in the pop-up's)
----------------------------------------------------------------------
local FX = { bubbles = {}, rays = {} }
for i, x in ipairs({ 0.12, 0.34, 0.58, 0.83 }) do
	local ray = UI.new("Frame", {
		Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
		Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
	}, WIN.ocean)
	UI.new("UIGradient", {
		Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
		}),
	}, ray)
	table.insert(FX.rays, { f = ray, phase = i * 1.3 })
end
function FX.addBubbles(ocean, n)
	for i = 1, n do
		local s = 6 + (i * 7) % 13
		local b = UI.new("Frame", {
			Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = CENTRE,
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, ocean)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		UI.new("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		local rec = { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i }
		b.Position = UDim2.new(rec.x, 0, rec.y, 0)
		table.insert(FX.bubbles, rec)
	end
end
FX.addBubbles(WIN.ocean, 22)
FX.addBubbles(CF.win.ocean, 8)

----------------------------------------------------------------------
-- phone / desk layout: every geometry the form decides, set in one place (re-run when the form changes)
----------------------------------------------------------------------
function lay.apply()
	local name = lay.compact and "phone" or "desk"
	lay.modeName = name
	local m, p = MODE[name], P1L[name]
	-- the header (UI.window built it at 74; a phone's is 60)
	local hh = m.headerH
	WIN.header.Size = UDim2.new(1, 0, 0, hh)
	WIN.ocean.Position, WIN.ocean.Size = UDim2.fromOffset(0, hh), UDim2.new(1, 0, 1, -hh)
	WIN.crest.Position = UDim2.fromOffset(0, hh)
	place(WIN.title, { m.titleX, 0, m.titleW, hh, m.titleMax })
	if WIN.icon then rect(WIN.icon, { m.icon[1], m.icon[2], m.icon[3], m.icon[3] }) end
	WIN.close.button.Position = m.close.pos
	WIN.close.button.Size = UDim2.fromOffset(m.close.size, m.close.size)
	WIN.close.set(nil, "X", m.close.text)
	rect(HUD.pearl.button, m.pearl)
	rect(HUD.cash.button, m.cash)
	HUD.setPearls(true)
	HUD.setCash(true)
	for i, t in ipairs(TABS) do
		t.key.button.Position = UDim2.fromOffset(L.TAB_X[i], m.tabY + m.tabH / 2)
		t.key.button.Size = UDim2.fromOffset(L.TAB_W, m.tabH)
		t.key.setParts(nil, { { text = t.emoji, size = m.tabIcon, drop = 0, o = 0 }, { text = t.word, size = m.tabText, gap = 8 } })
	end
	CONTENT.Position = UDim2.fromOffset(10, m.contentY)
	CONTENT.Size = UDim2.new(1, -20, 1, -(m.contentY + m.contentB))
	-- the Rebirth page
	P1.stack.Size = UDim2.fromOffset(744, p.stackH)
	rect(P1.rank.root, p.rank)
	rect(P1.prog.root, p.prog)
	rect(P1.key.button, p.key)
	rect(P1.halo, { p.key[1] - 7, p.key[2] - 7, p.key[3] + 14, p.key[4] + 20 })
	placeEmoji(P1.rankGlow, P1.rankIcon, p.rankIcon[1], p.rankIcon[2], p.rankIcon[3], p.rankGlow)
	place(P1.rankTag, p.rankTag)
	place(P1.rankTitle, p.rankTitle)
	place(P1.rankZone, p.rankZone)
	for i, t in ipairs(P1.tiles) do
		rect(t.block.root, p.tiles[i])
		place(t.label, p.tileLabel)
		place(t.value, p.tileValue)
	end
	place(P1.progHead, p.progHead)
	rect(P1.bar, p.bar)
	setMax(P1.barText, p.bar[5])
	place(P1.reward, p.reward)
	P1.keyMode = nil -- the key's line is re-laid by the next refresh
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
function refreshAll()
	local rb = getRebirths()
	local pr = getPearls()
	local rk = rankFor(rb)
	local need = req(rb)
	local gain = pearlsFor(cash, rb)
	local canRebirth = cash >= need

	HUD.setPearls()
	HUD.setCash()

	-- the rank card
	local curIdx = math.clamp(rb + 1, 1, #RANKS)
	P1.rank.setColour(RANK_CANDY[curIdx])
	P1.rankIcon.Text = rk.icon
	P1.rankZone.Text = string.upper(rk.zone)
	P1.rankTitle.Text = rk.title
	P1.tiles[1].value.Text = tostring(rb)
	P1.tiles[2].value.Text = string.format("x%.2f", currentMult(rb))

	-- the next tide
	P1.setFill(math.clamp(cash / need, 0, 1), canRebirth)
	P1.barText.Text = string.format("%s / %s", money(math.min(cash, need)), money(need))
	P1.reward.Text = string.format(
		'Reward: <font color="#AAFF64">+%s pearls</font>%s<font color="#96EEFF">+25%% Current</font>', pearls(gain), DOT)

	-- the key
	local state = canRebirth and "ready" or "locked"
	if P1.keyState ~= state or P1.keyMode ~= lay.modeName then
		P1.keyState, P1.keyMode = state, lay.modeName
		P1.key.recolour(canRebirth and "green" or "grey")
		P1.layKey(canRebirth)
	end
	P1.keySub.Text = canRebirth and "Release your catch to the tide" or ("Earn " .. money(need - cash) .. " more to turn the tide")
	P1.halo.Visible = canRebirth

	-- the ladder
	for i, lr in ipairs(LAD.rows) do
		local st = i < curIdx and "done" or (i == curIdx and "now" or "ahead")
		if lr.state ~= st then
			lr.state = st
			if st == "done" then
				lr.mult.recolour("green")
				lr.mult.setParts("check", { { text = lr.text, size = 28 } }, { leadSize = 44 })
			elseif st == "now" then
				lr.mult.recolour("gold")
				lr.mult.setParts(nil, { { text = lr.text, size = 30 } })
			else
				lr.mult.recolour("grey")
				lr.mult.setParts(nil, { { icon = "lock", size = 30, drop = 0, flat = true }, { text = lr.text, size = 28 } })
			end
			lr.row.setOwned(st == "now")
			lr.here.block.root.Visible = st == "now"
		end
	end

	-- the perks
	for _, pc in ipairs(REEF.rows) do
		local perk = pc.perk
		local tier = getPerk(perk.key)
		local maxed = tier >= perk.max
		local tierText = maxed and ("Tier " .. tier .. " \u{00B7} MAX") or ("Tier " .. tier .. " / " .. perk.max)
		pc.eff.Text = '<font color="#AAFF64">+' .. (perk.per * tier) .. perk.unit .. "</font>" .. DOT .. tierText
		local cost = maxed and 0 or perkCost(perk, tier)
		local afford = (not maxed) and pr >= cost
		local sig = maxed and "max" or ((afford and "y" or "n") .. cost)
		if pc.sig ~= sig then
			pc.sig = sig
			local k = pc.row.key
			if maxed then
				k.recolour("gold")
				k.setParts("check", { { text = "MAXED", size = 30 } })
			else
				k.recolour(afford and "green" or "grey")
				k.setParts(nil, {
					{ text = "🦪", size = 34, drop = 0, o = 0 },
					{ text = pearls(cost), size = 34, color = afford and UI.WHITE or UI.TEXT.red },
				})
			end
			pc.row.setOwned(maxed)
		end
	end
end

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("RebirthRemotes")

local function doRebirth()
	local rb = getRebirths()
	local need = req(rb)
	if cash < need then showToast("Not enough cash yet!", "bad"); return end
	local gain = pearlsFor(cash, rb)

	plr:SetAttribute("Pearls", getPearls() + gain)
	plr:SetAttribute("Rebirths", rb + 1)

	local blessing = getPerk("blessing")
	local starter = math.floor(1000 * (1 + 0.5 * blessing))
	cash = starter
	if cashSource then pcall(function() cashSource.Value = starter end) end

	if remotesFolder then
		local re = remotesFolder:FindFirstChild("Rebirth")
		if re and re:IsA("RemoteEvent") then pcall(function() re:FireServer(gain) end) end
		local be = remotesFolder:FindFirstChild("OnRebirth")
		if be and be:IsA("BindableEvent") then pcall(function() be:Fire(rb + 1, starter) end) end
	end

	refreshAll()
	showToast("Reborn!  +" .. pearls(gain) .. " pearls", "good")
	UI.punch(P1.rank.scale, 1.08, 0.4)
end

-- force (the Studio lever's "preview" only): show the pop-up without the cash - RELEASE still re-checks in doRebirth
local function openConfirm(force)
	local rb = getRebirths()
	if cash < req(rb) and force ~= true then
		showToast("Not enough cash yet!", "bad")
		return
	end
	local gain = pearlsFor(cash, rb)
	local nextRank = rankFor(rb + 1)
	CF.body.Text = string.format(
		'Your <font color="#FFDE50">%s</font>, your upgrades and every zone past Lighthouse Cove wash away with the tide.\n\nIn return: <font color="#AAFF64">%s pearls</font>, a <font color="#AAFF64">x%.2f</font> Tide Current, and the rank of <font color="#96EEFF">%s</font>.',
		money(cash), pearls(gain), currentMult(rb + 1), nextRank.title)
	CF.veil.Visible = true
	CF.scale.Scale = 0.9 * CF.fit
	TweenService:Create(CF.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = CF.fit }):Play()
end

local function buyPerk(pc)
	local perk = pc.perk
	local tier = getPerk(perk.key)
	if tier >= perk.max then return end
	local cost = perkCost(perk, tier)
	if getPearls() < cost then
		showToast("Not enough pearls!", "bad")
		HUD.flashPearls()
		return
	end
	plr:SetAttribute("Pearls", getPearls() - cost)
	plr:SetAttribute("Perk_" .. perk.key, tier + 1)
	refreshAll()
	UI.punch(pc.row.scale, 1.03, 0.25)
	showToast(perk.name .. ": Tier " .. (tier + 1) .. "!", "good")
end

function selectTab(name)
	if not PAGES[name] then name = "Rebirth" end
	currentTab = name
	for _, t in ipairs(TABS) do
		local on = t.name == name
		PAGES[t.name].Visible = on
		if t.lit ~= on then
			t.lit = on
			t.key.recolour(on and "gold" or "sea")
		end
	end
	if name == "Ranks" then task.defer(LAD.showCurrent) end
end

----------------------------------------------------------------------
-- wiring
----------------------------------------------------------------------
TouchKit.press(P1.key.button, function() openConfirm() end)
TouchKit.press(CF.cancel.button, function() CF.veil.Visible = false end)
TouchKit.press(CF.ok.button, function() CF.veil.Visible = false; doRebirth() end)
for _, pc in ipairs(REEF.rows) do
	TouchKit.press(pc.row.key.button, function() buyPerk(pc) end)
end

local function close() gui.Enabled = false end
TouchKit.press(WIN.close.button, close)
TouchKit.press(backdrop, close)

plr:GetAttributeChangedSignal("Pearls"):Connect(function() if gui.Enabled then refreshAll() end end)
plr:GetAttributeChangedSignal("Rebirths"):Connect(function() if gui.Enabled then refreshAll() end end)

-- the lists keep their place (in design px) through a scale change
uiscale:GetPropertyChangedSignal("Scale"):Connect(function()
	if PAGES.Ranks.Visible then LAD.list.scrollTo(LAD.list.y) end
	if PAGES.Reef.Visible then REEF.list.scrollTo(REEF.list.y) end
end)

----------------------------------------------------------------------
-- ambient bubbles + rays + the ready pulse
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	local t = os.clock()
	-- Settings > Menu Animations gates the decor only; the "ready" pulse below is
	-- a gameplay cue, so it keeps running either way.
	if plr:GetAttribute("Set_MenuFX") ~= false then
		for _, b in ipairs(FX.bubbles) do
			b.y -= b.speed * dt
			if b.y < -0.05 then
				b.y = 1.05
				b.x = (b.x + 0.37) % 1
			end
			b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
		end
		for _, r in ipairs(FX.rays) do
			r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
		end
	end
	if P1.halo.Visible and currentTab == "Rebirth" then
		local a = 0.5 + 0.5 * math.sin(t * 4)
		P1.haloStroke.Thickness = 3 + 3 * a
		P1.haloStroke.Transparency = 0.1 + 0.45 * (1 - a)
	end
end)

----------------------------------------------------------------------
-- hide the player's rod hotbar (Roblox Backpack) while this menu is open
----------------------------------------------------------------------
local prevBackpack = true
local function setInventoryHidden(hidden)
	pcall(function()
		if hidden then
			prevBackpack = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		else
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, prevBackpack)
		end
	end)
end

----------------------------------------------------------------------
-- fit (MenuFit) + placement
----------------------------------------------------------------------
-- Off a phone the corner emoji reaches 44 px above the window and the X 18 px: hold the scale so that reach stays
-- under Roblox's top bar and the drop stays on screen (the Shop's rule - without it a 580-tall window at 1.1 put
-- the emoji over the top-bar buttons at 1313 x 751). MenuFit still decides the size and the position.
local function holdReach(vp)
	local s = uiscale.Scale
	if s <= 0 then return end
	local h = root.Size.Y.Offset
	local cy = root.Position.Y.Scale * vp.Y + root.Position.Y.Offset
	local bar = GuiService.TopbarInset.Max.Y
	local top = (bar > 0 and bar or GuiService:GetGuiInset().Y) + 4
	local cap = math.min((cy - top) / (h / 2 + L.REACH), (vp.Y - 8 - cy) / (h / 2 + 9))
	if cap > 0.1 and cap < s then uiscale.Scale = cap end
end
local function fitToViewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.zero
	local compact = vp.X >= 100 and vp.Y >= 100 and math.min(vp.X, vp.Y) < 500
	local changed = compact ~= lay.compact or not lay.applied
	if changed then
		lay.compact, lay.applied = compact, true
		lay.apply()
	end
	if compact then
		MenuFit.apply(root, uiscale, L.W, L.H, 0.4, L.MAX_S_PHONE, L.MIN_H_PHONE)
		-- CENTRED ON THE PHONE SCREEN (2026-10-11, the owner: "make the button uis centered to the phone screen"), not in
		-- the band under the top bar: MODE.phone tucks the emoji inside the 60 px header, so nothing reaches above the
		-- box - only the 9 px drop below it. MenuFit.centre shrinks the scale just enough for the top to clear the bar.
		MenuFit.centre(root, uiscale, 0, 9)
	else
		MenuFit.apply(root, uiscale, L.W, L.H, 0.4, L.MAX_S, L.MIN_H)
		if vp.X >= 100 and vp.Y >= 100 then holdReach(vp) end
	end
	-- the confirm pop-up: screen-centred, on a phone too (2026-10-11, "centered to the phone screen" - it used to sit in
	-- the band below the Roblox top bar), with its own scale, not the window's. Off a phone it fits the screen's height;
	-- on a phone MenuFit.centre sizes it so its top clears the top bar (its 🌊 is tucked in the header and it has no X,
	-- so nothing reaches above the box). A stand-in table carries the scale: openConfirm pops CF.scale to CF.fit.
	CF.win.root.Position = UDim2.fromScale(0.5, 0.5)
	if vp.Y >= 100 then
		CF.fit = compact and math.clamp(MenuFit.centre(CF.win.root, { Scale = 1 }, 0, 9), 0.4, 1)
			or math.clamp((vp.Y - 16) / (CF.H + 9), 0.4, 1)
		if CF.veil.Visible then CF.scale.Scale = CF.fit end
	end
	if changed and gui.Enabled then refreshAll() end
end

----------------------------------------------------------------------
-- open / close pop-in
----------------------------------------------------------------------
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		fitToViewport()
		TOAST.chip.block.root.Visible = false
		refreshAll()
		selectTab(currentTab)
		setInventoryHidden(true)
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		local targetScale = uiscale.Scale
		uiscale.Scale = targetScale * 0.9
		TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetScale }):Play()
	else
		CF.veil.Visible = false
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

bindCash()
plr.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then task.wait(0.2); bindCash(); if gui.Enabled then refreshAll() end end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if gui.Enabled then fitToViewport() end
	end)
end
-- the safe area can settle after the camera does (notch phones): refit on it too
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if gui.Enabled then fitToViewport() end
end)

-- Studio lever (the house Dev* convention)
if RunService:IsStudio() then
	local function tabOf(s)
		s = type(s) == "string" and s:lower() or ""
		if s == "rebirth" then return "Rebirth" end
		if s == "ranks" or s == "ladder" or s == "depth" then return "Ranks" end
		if s == "reef" or s == "perks" or s == "pearls" then return "Reef" end
		return nil
	end
	local lever = UI.new("BindableEvent", { Name = "DevRebirth" }, gui)
	lever.Event:Connect(function(verb, arg)
		if verb == "open" then
			currentTab = tabOf(arg) or currentTab
			if gui.Enabled then selectTab(currentTab) else gui.Enabled = true end
		elseif verb == "tab" and tabOf(arg) then
			selectTab(tabOf(arg))
		elseif verb == "confirm" or verb == "preview" then
			if not gui.Enabled then gui.Enabled = true end
			openConfirm(verb == "preview")
		elseif verb == "close" then
			close()
		end
	end)
end

fitToViewport()
selectTab("Rebirth")
refreshAll()
print("[Rebirth] sea candy edition built — " .. #RANKS .. " ranks, " .. #PERKS .. " pearl perks, 3 tabs")
