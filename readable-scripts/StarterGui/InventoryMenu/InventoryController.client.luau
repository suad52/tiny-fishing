--[==[
	InventoryController — fishing-game "Inventory" (+ the Baits window), on the Shop's sea-candy kit

	Everything the player owns, in tabs:
	    🎣 Rods    — all 10 tiers, live 3D ViewportFrame of the real Tool, EQUIP
	    🧪 Boosts  — the shop's potions + jackpot casts, USE one

	BAITS ARE NO LONGER A TAB. 2026-09-03 they moved to their own window, opened by a
	BAITS button on the bait roller's left column - the place the player already is when
	a bait drops. That window is still built BY THIS SCRIPT (see "the baits window"),
	because the catalogue, publishBaitStats(), equipBait/unequipBait and the two-currency
	buy row all live here: a separate controller would have meant a THIRD hand-copy of the
	12-bait table (RollerController holds the second) and two scripts both publishing
	BaitLuck / BaitValueMult / BaitHaste. One owner, two windows.

	STATE (player attributes, matching Set_<key> / Zone_<id> / QP_<id>):
	    Rod_<tier>      owned            EquippedRod   tier
	    Bait_<name>     count            EquippedBait  bait name
	    Inv_<key>       potion count     (shared with ShopController)
	    Fish_<name>     count in bucket

	Shared, not siloed: bait counts are written by RollerController on every roll,
	and potion counts are mirrored both ways with ShopController — using a potion
	here updates the Shop's "Use (N)" button and vice-versa.

	The bucket is DEMO-SEEDED (deterministic, by fish id) because this place has no
	fishing loop yet. Real catches should call:
	    InventoryMenu.AddCatch:Fire(fishName, count)

	Test hook: InventoryMenu.DevInv:Fire("__OPEN__") / :Fire("__CLEAR__")
	           / :Fire("__GIVE__") / :Fire(fishName, count)

	2026-10-10 — THE LOOK MOVED ONTO ReplicatedStorage.ShopKit (the Shop's "sea candy" kit), at the owner's
	request to re-theme every MenuBar menu after the Shop ("i just want it to look better"). Both windows are
	UI.window shells now: a lagoon body with rising bubbles, a purple header with a wave crest, the gold title,
	🎒 / 🐛 breaking out of the top-left corner and the red key X (a TextButton named "TextButton" - the
	tutorial's closeButtonOf() finds it by that). Every item is a candy CARD in its own colour (rods by tier,
	baits by rarity, potions as the Shop paints them) with its art on a soft glow, and every button is a candy
	KEY in its STATE's colour: green = do it / affordable, grey = not yet / can't, gold = equipped, pink = a
	Robux price, red = the unequip X. Tabs are gold (on) / sea (off) keys, money and pearls are gold / sea
	pills, the scroll bars are the Shop's. The old reef recipe (DEEP_TOP/MID/BOT body, aquarium tanks, dark
	stat panels, thin Gotham copy) is gone. NOTHING ELSE CHANGED: the same attributes, remotes, dev hooks,
	TouchKit pads, MenuFit fits, phone (landscape) cards, the reflow-rebound guard, the toast that follows
	whichever window is up, and the BaitsMenu contract the tutorial rings:
	    PlayerGui.BaitsMenu.Window.Content.<ScrollingFrame>.Bait_<akey>.Action   (+ BaitsMenu.Open)
	One new rule: the breakout emoji reaches 44 design px ABOVE the window, so after MenuFit places a window
	LAY.clearTop() keeps that emoji under Roblox's top bar - shorter first (MenuFit's own rule), smaller only
	if it must (the Shop holds its cart the same way). On a phone the emoji sits INSIDE a 60 px header instead
	(a breakout would cost a fifth of a 375 px screen), and since 2026-10-11 LAY.centre centres it there too.
	Verified in Edit through a harness (fake LocalPlayer / camera, the real source): no overlaps, no spilled or
	unscaled text, one X per window, the tutorial's Action path, equip / rebound / unequip / cash buy / toast.
	Then PLAY-verified the same day, which changed four things: a rod lies DIAGONALLY across its art tile (frameModel's
	camera roll, fitted to what the lens sees) instead of standing as a thin upright stick; the kit's glow is 0.5 here, not 0.2 (it read as a hard
	white plate behind every emoji) and is hidden on a card you have none of; a boost card is rod-height (330), so the
	Boosts tab is no longer two-thirds empty lagoon; and clearTop keeps the window's SIDES 6 px clear too.
	Pre-restyle source: ServerStorage.MenuBackup_PreCandy_2026-10-10.
]==]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")
local gui = script.Parent

local FishData = require(ReplicatedStorage:WaitForChild("FishData"))
-- Every price on every buy button, in both currencies, plus the Developer Product ids.
-- Shared with ServerScriptService.ProductServer so a Robux receipt grants exactly what
-- the button promised.
local ShopProducts = require(ReplicatedStorage:WaitForChild("ShopProducts"))
local MarketplaceService = game:GetService("MarketplaceService")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(game:GetService("ReplicatedStorage"):WaitForChild("TouchKit"))
-- The Shop's kit (windows, candy cards / keys, labels, 3D icons). Shared with the Shop and every other
-- menu: never edited from here - anything this window needs on top of it lives in K below.
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))

----------------------------------------------------------------------
-- palette + helpers
----------------------------------------------------------------------
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local function lighten(c,t) return c:Lerp(Color3.new(1,1,1), t) end
local function darken(c,t)  return c:Lerp(Color3.new(0,0,0), t) end

local INK  = UI.INK
local GOLD = rgb(255,224,104)   -- a toast's "good news" colour (it picks the gold key)
local C = {
	bad = rgb(240,84,96),    -- a toast's failure colour (the red key)
	off = rgb(168,184,204),  -- a toast's neutral colour (the grey key)
}

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- K: this window's small additions to the kit, ONE local (the 200-register cap, see LAY below).
local K = {}
-- a TEXT size of a key, as a share of the key's height, so one paint works at every key size
K.REL = { word = 0.56, small = 0.44, icon = 0.8, flat = 0.64 }
-- a candy key (the kit's) with a name and a ZIndex; painted later with K.paint
function K.key(parent, colour, name, z, static)
	return UI.candyKey(parent, colour, { Name = name, Size = UDim2.fromOffset(100, 36), ZIndex = z or 8, static = static })
end
-- Paint a key: its STATE colour and its line of pieces. parts = { { text = s, rel, color } | { icon = name, rel,
-- flat } | { text = emoji, emoji = true } }, each sized as a share of the key's height (K.REL), so LAY.place can
-- resize a key and K.apply just lays the same line out again. minW = drop this piece on a key narrower than that.
function K.paint(k, colour, lead, parts)
	if k.colour ~= colour then k.recolour(colour) end
	local sig = tostring(lead)
	for _, p in ipairs(parts) do
		sig ..= "|" .. tostring(p.text or p.icon) .. ":" .. tostring(p.rel) .. ":" .. tostring(p.color) .. ":" .. tostring(p.minW)
	end
	k.spec = { lead = lead, parts = parts }
	if k.sig ~= sig then k.sig, k.laid = sig, nil end
	K.apply(k)
end
function K.apply(k)
	local sp = k.spec
	if not sp then return end
	local w, h = k.button.Size.X.Offset, k.button.Size.Y.Offset
	if w <= 0 or h <= 0 then return end
	local at = w .. "x" .. h
	if k.laid == at then return end
	k.laid = at
	local out = {}
	for _, p in ipairs(sp.parts) do
		if not (p.minW and w < p.minW) then
			local s = math.max(9, math.floor(h * (p.rel or K.REL.word)))
			if p.icon then
				-- a flat icon gets a 2 px drop and a 3D one none (it brings its own): the kit only rebuilds a slot
				-- when its drop changes, so this also stops a flat slot being re-pointed at a 3D icon (blank)
				out[#out + 1] = { icon = p.icon, size = s, flat = p.flat, drop = p.flat and 2 or 0, gap = p.gap }
			elseif p.emoji then
				out[#out + 1] = { text = p.text, size = s, o = 0, drop = 0, gap = p.gap }
			else
				out[#out + 1] = { text = p.text, size = s, o = math.max(2, math.floor(s * 0.16 + 0.5)),
					drop = s >= 18 and 2 or 1, color = p.color, gap = p.gap }
			end
		end
	end
	local o = { gap = math.max(4, math.floor(h * 0.14)) }
	if sp.lead == "check" then o.leadSize = math.floor(h * 0.92); o.pad = math.floor(o.leadSize * 0.55) end
	k.setParts(sp.lead, out, o)
end
-- the cash price of a buy key: white when you can afford it, red when you can't (the key itself goes grey)
function K.cash(k, cash, pack, afford)
	local parts = {
		{ icon = "coins", rel = K.REL.icon, minW = 110 },
		{ text = UI.cash(cash), color = (not afford) and UI.TEXT.red or nil },
	}
	-- the pack size is only worth printing when it is not 1
	if pack and pack > 1 then parts[#parts + 1] = { text = "x" .. pack, rel = K.REL.small, gap = 4 } end
	K.paint(k, afford and "green" or "grey", nil, parts)
end
-- the Robux price key: pink while the product exists (and the item can be bought now), grey otherwise
function K.robux(k, price, kind, key, enabled)
	local live = ShopProducts.productId(kind, key) > 0
	K.paint(k, (live and enabled ~= false) and "pink" or "grey", nil,
		{ { icon = "robux", flat = true, rel = K.REL.flat }, { text = UI.num(price) } })
end
-- a label's text cap (a kit label is TextScaled under a UITextSizeConstraint; its drop copy has its own)
function K.setMax(l, size)
	for _, t in ipairs({ l, l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop") }) do
		local c = t and t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MinTextSize = math.min(9, size)
			c.MaxTextSize = size
		end
	end
end
-- an emoji drawn as art: a scaled TextLabel, no outline (an outline would ring the glyph's box)
function K.emoji(parent, glyph, props)
	local l = UI.new("TextLabel", {
		Name = "Icon", BackgroundTransparency = 1, Text = glyph, TextScaled = true, FontFace = UI.FONT, TextColor3 = UI.WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(60, 60),
	}, nil)
	for k, v in pairs(props or {}) do l[k] = v end
	l.Parent = parent
	return l
end
-- the window swallows its own taps: a transparent, silent button with no handler (the Shop's ClickGuard). A plain
-- Active Frame does NOT stop the close-on-tap Backdrop under it.
function K.guard(parent, size, z, pos)
	local b = UI.new("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, Position = pos or UDim2.new(), ZIndex = z,
	}, nil)
	b:SetAttribute("SndHooked", true)   -- AudioController leaves it silent
	b.Parent = parent
	return b
end
-- a small count / tier pill in a card's top-right corner (sized to its text, no AutomaticSize: TouchKit rule 2)
function K.badge(parent, z)
	local b = {}
	b.root = UI.new("Frame", {
		Name = "Badge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(60, 26),
		BackgroundColor3 = UI.WHITE, ZIndex = z,
	}, parent)
	UI.corner(b.root, 13)
	UI.stroke(b.root, 3)
	b.label = UI.label(b.root, "", {
		Name = "Text", size = 16, scaled = false, Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), ZIndex = 2,
	})
	return b
end
K.PILL = { navy = { rgb(60, 112, 180), rgb(18, 52, 104) }, grey = UI.BRICK.grey, gold = UI.BRICK.gold }
function K.badgeSet(b, text, colour, textColour)
	if b.text ~= text then
		b.text = text
		b.label.Text = text
		b.root.Size = UDim2.fromOffset(math.ceil(UI.textWidth(text, 16)) + 20, 26)
	end
	b.label.TextColor3 = textColour or UI.WHITE
	if b.colour ~= colour then
		b.colour = colour
		UI.vgrad(b.root, K.PILL[colour] or UI.BRICK[colour] or colour)
	end
end
-- a toast's key colour from the Color3 the callers have always passed (rarity / accent colours keep their hue)
function K.tone(c)
	if c == nil or c == INK then return "navy" end
	if c == C.bad then return "red" end
	if c == GOLD then return "gold" end
	if c == C.off then return "grey" end
	return { hi = lighten(c, 0.35), base = c, lip = darken(c, 0.45) }
end
-- the Shop's scroll track: a faint INK lane behind the gold thumb, shown only while the list can scroll
function K.track(page, parent)
	local tr = UI.new("Frame", {
		Name = "Track", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 10, 1, 0), ZIndex = 1, Visible = false,
	}, parent)
	UI.corner(tr, 5)
	local function sync()
		tr.Visible = page.Visible and page.AbsoluteCanvasSize.Y > page.AbsoluteWindowSize.Y + 1
	end
	page:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(sync)
	page:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(sync)
	page:GetPropertyChangedSignal("Visible"):Connect(sync)
	sync()
	return tr
end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIX[tier + 1])
end
local function money(n) return "$" .. abbrev(n) end
local function commas(n)
	local s = tostring(math.floor(n))
	local o = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (o:gsub("^,", ""))
end

----------------------------------------------------------------------
-- catalogues
----------------------------------------------------------------------
-- Rods: `tool` matches the Tool name in StarterPack / ServerStorage.FishingRods.
local RODS = {
	{ tier=1,  tool="01 · Oakwood Rod",       name="Oakwood",       accent=rgb(168,120,72),  blurb="Plain and honest." },
	{ tier=2,  tool="02 · Fiberglass Rod",    name="Fiberglass",    accent=rgb(120,178,208), blurb="Light and springy." },
	{ tier=3,  tool="03 · Carbon Rod",        name="Carbon",        accent=rgb(92,100,116),  blurb="Stiff, fast tip." },
	{ tier=4,  tool="04 · Bronze Angler",     name="Bronze Angler", accent=rgb(198,126,60),  blurb="Clockwork reel." },
	{ tier=5,  tool="05 · Silver Tide",       name="Silver Tide",   accent=rgb(198,210,226), blurb="Fishtail counterweight." },
	{ tier=6,  tool="06 · Golden Lure",       name="Golden Lure",   accent=rgb(240,202,84),  blurb="Crowned and charmed." },
	{ tier=7,  tool="07 · Emerald Rod",       name="Emerald",       accent=rgb(70,204,140),  blurb="Vines and orbiting orbs." },
	{ tier=8,  tool="08 · Frost Crystal Rod", name="Frost Crystal", accent=rgb(150,220,246), blurb="Jagged ice shards." },
	{ tier=9,  tool="09 · Inferno Rod",       name="Inferno",       accent=rgb(240,90,50),   blurb="Molten core, lit tip." },
	{ tier=10, tool="10 · Cosmic Rod",        name="Cosmic",        accent=rgb(158,116,244), blurb="Its own little galaxy." },
}

-- Baits: mirrors RollerController's BAITS table (icons are byte escapes there; the
-- literals are fine here). Rarity colours match the roller's RARITY map.
local BRC = {
	Common    = rgb(198,206,220), Uncommon = rgb(88,220,110), Rare = rgb(74,158,250),
	Epic      = rgb(186,108,250), Legendary = rgb(250,190,52), Mythic = rgb(252,74,110),
	Divine    = rgb(120,246,246),
}
local BAITS = {
	{ name="Breadcrumbs",    icon="🍞", odds=2,         rarity="Common",    buff="+2% Luck" },
	{ name="Grub",           icon="🐛", odds=5,         rarity="Common",    buff="+5% Hook Speed" },
	{ name="Minnow",         icon="🐟", odds=20,        rarity="Uncommon",  buff="+10% Value" },
	{ name="Shrimp",         icon="🦐", odds=60,        rarity="Uncommon",  buff="+15% Luck" },
	{ name="Squid",          icon="🦑", odds=250,       rarity="Rare",      buff="+25% Hook Speed" },
	{ name="Octopus Ink",    icon="🐙", odds=1200,      rarity="Rare",      buff="+40% Value" },
	{ name="Glowworm",       icon="✨", odds=6000,      rarity="Epic",      buff="+60% Luck" },
	{ name="Golden Roe",     icon="🥚", odds=30000,     rarity="Epic",      buff="+80% Value" },
	{ name="Black Pearl",    icon="💎", odds=200000,    rarity="Legendary", buff="+150% Luck" },
	{ name="Siren Song",     icon="🎵", odds=1500000,   rarity="Legendary", buff="+200% Hook Speed" },
	{ name="Abyssal Chum",   icon="🌊", odds=12000000,  rarity="Mythic",    buff="+300% Value" },
	{ name="Leviathan Bait", icon="🐋", odds=435000000, rarity="Divine",    buff="+1000% Luck" },
}

-- Boosts: keys match ShopController's `inventory` table so counts stay in sync.
local BOOSTS = {
	{ key="potion_luck",  icon="🍀", name="Luck Potion",  accent=rgb(92,220,96),   blurb="Rarer fish for 10 minutes." },
	{ key="potion_cast",  icon="⚡", name="Cast Speed",   accent=rgb(255,190,58),  blurb="Cast faster for 10 minutes." },
	{ key="potion_bite",  icon="⏱", name="Hook Speed",   accent=rgb(252,92,100),  blurb="Hook moves faster for 10 minutes." },
	{ key="potion_money", icon="💰", name="Money Potion", accent=rgb(240,202,84),  blurb="More coins for 10 minutes." },
	{ key="jackpot",      icon="🌟", name="Jackpot Cast", accent=rgb(120,150,250), blurb="1000x luck on your next cast." },
}

-- MUST stay in step with GameClient's copy - a fish is worth the same whichever way it
-- leaves the bucket. Rebalanced 2026-07-18 (bases ~9x down, length /40 -> /70) and now
-- also carries the Fish Value upgrade branch, which is literally "+% sell value".
-- 2026-07-18 (2) RE-FLATTENED alongside the depth restretch. Rarity is now gated by
-- DEPTH, so the old 1:1900 Common-to-Mythic spread turned the depth ladder into an income
-- CLIFF: measured across the rod tiers it ran $0.007M/hr -> $250M/hr, which made the early
-- game a 40-minute grind for the second rod and the endgame trivial. Note the length term
-- already multiplies a 4000cm Kraken by 58x on its own, so the BASE table does not have to
-- be steep to produce a dramatic ladder. Bases are now 120 * 1.5^rank, which restores both
-- ends of the previously tuned economy (~$0.27M/hr fresh, ~$72M/hr fully maxed) while the
-- depth gating - not poverty - does the pacing. Average values a player actually sees:
-- Common $150 / Uncommon $289 / Rare $596 / Epic $2.6K / Legendary $9.4K / Mythic $53K.
-- ⚠️ IN STEP WITH GameClient's COPY. Raised alongside the depth-band change that made the top
-- tiers 2-4x rarer: a fish is worth the same whichever way it leaves the bucket, so if one table
-- moves and the other does not, the Inventory quotes a different price than the sale pays.
local RARITY_BASE = { Common=120, Uncommon=180, Rare=330, Epic=700, Legendary=1150, Mythic=2400 }
local function fishValue(f)
	return math.floor((RARITY_BASE[f.rarity] or 120) * (1 + f.lengthCm / 70)
		* (plr:GetAttribute("UpgValueMult") or 1))
end
local FISH_BY_NAME = {}
for _, f in ipairs(FishData.fish) do FISH_BY_NAME[f.name] = f end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------
-- Roblox attribute names only allow [A-Za-z0-9_], and plenty of fish and bait
-- names have spaces ("Blue Tang", "Golden Roe"), so the key is the stripped name.
-- RollerController writes Bait_<akey> the same way — keep the two in step.
local function akey(s) return (string.gsub(s, "[^%w]", "")) end

local function baitCount(n)  return plr:GetAttribute("Bait_" .. akey(n)) or 0 end
local function boostCount(k) return plr:GetAttribute("Inv_" .. k) or 0 end
local function fishCount(n)  return plr:GetAttribute("Fish_" .. akey(n)) or 0 end
local function rodOwned(t)   return plr:GetAttribute("Rod_" .. t) == true end

-- Rods unlock IN ORDER with cash, the same shape as Zones: you can only buy the tier
-- straight after the best one you own.
--
-- Re-scaled 2026-07-18 against the simulated income at each tier (0.27 / 0.42 / 0.76 /
-- 1.16 / 2.69 / 4.07 / 9.29 / 14.98 / 44.62 $M per hour on rods 1-9). Each price is set so
-- the next rod is roughly 1.5, 3, 5, 7, 10, 13, 16, 20, 24 minutes of fishing at the rate
-- of the rod you are on - about 3 hours to reach Cosmic once the upgrade tree and the
-- zones are taking their share too. The OLD ladder topped out at $120M, which was 2.7
-- hours for the last rod alone: priced for the pre-restretch economy, where a fresh player
-- was pulling Epics out of their very first cast.
-- Moved into ReplicatedStorage.ShopProducts so the cash ladder, the Robux ladder and the
-- server's receipt handler all read one table.
local ROD_COST = ShopProducts.ROD_CASH
-- WHAT A ROD ACTUALLY DOES. Every tier is a straight upgrade on five axes, and the
-- table below is the ONLY place they are defined: publishRodStats() copies the equipped
-- row onto player attributes, and GameClient reads nothing but those attributes. Same
-- "the attribute is the seam" contract as the Upgrades tree's publish() and ZoneCoinMult.
--
--   depth  +studs of max depth  - the big one. Rarity is gated by DEPTH (see GameClient's
--                                BANDS), so a better rod is what physically reaches
--                                better fish. This is the main progression axis.
--   cap    +fish per cast
--   reel   reel-speed multiplier - and you need it: the deep column a late rod opens up
--                                is a long way to wind back at the base 26 studs/sec.
--   power  line strength: divides the drag a heavy haul puts on the reel
--   luck   adds to the rare-species tilt (stacks with the Luck branch)
--
-- Deliberately NO value multiplier. Cash-per-fish is the Fish Value branch's job, and a
-- rod that ALREADY unlocks richer fish would be compounding income twice over.
-- 2026-10-10 (the owner): rods give DEPTH and LUCK only - "remove everything except the luck and depth features".
-- cap / reel / power stay in every row at their NEUTRAL values (0 / 1.00 / 0.00), so publishRodStats still writes
-- RodCap / RodReelMult / RodPower and every reader (GameClient, StatsHUD) sees "no bonus". Old values:
-- ServerStorage.ShopBackup_2026-10-10.InventoryController_PreRodStats.
local ROD_STATS = {
	[1]  = { depth = 0,   cap = 0, reel = 1.00, power = 0.00, luck = 0.00 },
	[2]  = { depth = 14,  cap = 0, reel = 1.00, power = 0.00, luck = 0.02 },
	[3]  = { depth = 32,  cap = 0, reel = 1.00, power = 0.00, luck = 0.05 },
	[4]  = { depth = 54,  cap = 0, reel = 1.00, power = 0.00, luck = 0.09 },
	[5]  = { depth = 82,  cap = 0, reel = 1.00, power = 0.00, luck = 0.14 },
	[6]  = { depth = 116, cap = 0, reel = 1.00, power = 0.00, luck = 0.20 },
	[7]  = { depth = 156, cap = 0, reel = 1.00, power = 0.00, luck = 0.27 },
	[8]  = { depth = 202, cap = 0, reel = 1.00, power = 0.00, luck = 0.35 },
	[9]  = { depth = 252, cap = 0, reel = 1.00, power = 0.00, luck = 0.44 },
	[10] = { depth = 300, cap = 0, reel = 1.00, power = 0.00, luck = 0.55 },
}
local function rodStats(tier) return ROD_STATS[math.clamp(tier or 1, 1, #RODS)] end

-- WHAT A BAIT ACTUALLY DOES. Those buff strings up in BAITS were pure flavour text:
-- EquippedBait was written by the EQUIP button and read by absolutely NOTHING, so an
-- equipped bait had no effect and was never spent. They are parsed once here onto the same
-- attribute seam the rods use, and GameClient reads only those attributes - it never sees
-- this table, so the icon and the rarity tint ride along as attributes too.
--
-- "Hook Speed" is the third buff axis. It was called "Bite Speed" until 2026-09-03, which
-- described a bite-and-wait mechanic this loop does not have - you sink, steer and reel,
-- and nothing ever bites. It publishes HASTE, and GameClient multiplies that into BOTH
-- underwater legs: the plunge (SINK_SPEED) and the wind back up (reelSpeed). It does NOT
-- touch the cast arc or the haul, so what it buys is THROUGHPUT - more casts per minute -
-- rather than a better or a more frequent catch. Hence "hook": it is the hook itself that
-- moves faster, in both directions.
--
-- PARSE TRAP: haste is the ELSE branch below, not a match on "Hook Speed". Any buff string
-- containing neither "Luck" nor "Value" lands here, so a new buff category would silently
-- become haste instead of erroring. The percentage comes from match("(%d+)%%"), so a buff
-- needs a literal integer followed by % - "+2.5x Hook Speed" would parse as 0 and go dead.
local BAIT_BY_NAME = {}
for _, b in ipairs(BAITS) do BAIT_BY_NAME[b.name] = b end
local function publishBaitStats()
	local b = BAIT_BY_NAME[plr:GetAttribute("EquippedBait") or ""]
	if b and baitCount(b.name) <= 0 then b = nil end   -- one you ran out of is not one you are fishing with
	local luck, value, haste = 0, 1, 1
	if b then
		local pct = tonumber(b.buff:match("(%d+)%%")) or 0
		if b.buff:find("Luck") then luck = pct / 100
		elseif b.buff:find("Value") then value = 1 + pct / 100
		else haste = 1 + pct / 100 end
	end
	plr:SetAttribute("BaitLuck",      luck)
	plr:SetAttribute("BaitValueMult", value)
	plr:SetAttribute("BaitHaste",     haste)
	plr:SetAttribute("BaitIcon",      b and b.icon or "")
	-- how many are left, published so the HUD readouts do not each need their own copy of
	-- the akey strip just to look up Bait_<key>
	plr:SetAttribute("BaitLeft",      b and baitCount(b.name) or 0)
	plr:SetAttribute("BaitTint",      b and BRC[b.rarity] or Color3.fromRGB(255, 255, 255))
end
local function publishRodStats()
	local st = rodStats(plr:GetAttribute("EquippedRod") or 1)
	plr:SetAttribute("RodDepth",    st.depth)
	plr:SetAttribute("RodCap",      st.cap)
	plr:SetAttribute("RodReelMult", st.reel)
	plr:SetAttribute("RodPower",    st.power)
	plr:SetAttribute("RodLuck",     st.luck)
end
-- rodGrant is assigned by the bootstrap block further down, once backpackTool exists
local rodGrant

local function coinSource()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then return m end
	return nil
end
local function getCoins()
	local m = coinSource()
	if m then return m.Value end
	return plr:GetAttribute("Coins") or 0
end
local function addCoins(n)
	local m = coinSource()
	if m then pcall(function() m.Value = m.Value + n end)
	else plr:SetAttribute("Coins", getCoins() + n) end
end
local function getPearls() return plr:GetAttribute("Pearls") or 0 end

-- Rod ownership seeds from what's ACTUALLY in the Backpack. StarterPack hands out
-- all 10 today, so this reports the truth rather than inventing a lock state that
-- contradicts the player's own hotbar; a future shop just sets Rod_<tier>.
local function backpackTool(name)
	local bp = plr:FindFirstChildOfClass("Backpack")
	local t = bp and bp:FindFirstChild(name)
	if t then return t end
	local ch = plr.Character
	return ch and ch:FindFirstChild(name) or nil
end
local function seedRods()
	publishRodStats()
	publishBaitStats()
	for _, r in ipairs(RODS) do
		if plr:GetAttribute("Rod_" .. r.tier) == nil then
			plr:SetAttribute("Rod_" .. r.tier, backpackTool(r.tool) ~= nil)
		end
	end
	if plr:GetAttribute("EquippedRod") == nil then plr:SetAttribute("EquippedRod", 1) end
end

-- Rod bootstrap. This MUST live below backpackTool(): a local declared after a function
-- body is not an upvalue of it, so placing this higher made backpackTool resolve to a
-- nil global and reissue() died with "attempt to call a nil value".
task.spawn(function()
	local rs = game:GetService("ReplicatedStorage"):WaitForChild("RodRemotes", 30)
	rodGrant = rs and rs:WaitForChild("Grant", 10) or nil
	-- Respawning empties the Backpack, so re-issue everything already owned AND put the
	-- player's chosen rod back in hand. That second half matters: FishingServer used to do
	-- the equipping by grabbing the first Tool in the pack, which is arbitrary once you own
	-- more than one - you would respawn holding a rod the menu did not think was equipped.
	local function reissue()
		if not rodGrant then return end
		for _, r in ipairs(RODS) do
			if r.tier > 1 and rodOwned(r.tier) then rodGrant:FireServer(r.tier) end
		end
		-- The grants above are RemoteEvent round-trips, so the wanted rod is NOT in the pack
		-- yet. A fixed wait silently fails whenever the reply is slow (measured: the rod
		-- arrived after 0.7s and nothing got equipped at all), so poll for it, then fall
		-- back to Oakwood if it never shows.
		local want = RODS[math.clamp(plr:GetAttribute("EquippedRod") or 1, 1, #RODS)]
		local tool
		for _ = 1, 24 do
			tool = want and backpackTool(want.tool)
			if tool then break end
			task.wait(0.25)
		end
		tool = tool or backpackTool(RODS[1].tool)
		local ch = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and tool and tool.Parent ~= ch then
			pcall(function() hum:EquipTool(tool) end)
		end
	end
	plr.CharacterAdded:Connect(function() task.wait(1.5); reissue() end)
	task.wait(1)
	reissue()
end)



----------------------------------------------------------------------
-- window
----------------------------------------------------------------------
local WIN_W, WIN_H = 1180, 700
-- PHONE LAYOUT (2026-09-25 mobile pass). ONE table rather than a dozen new locals: this chunk
-- already sits ~120 locals deep and the 200-register cap kills the whole script when crossed.
--   compact  min(viewport side) < 500, i.e. a landscape phone. Re-decided on EVERY fit - the
--            viewport can change under an open window - never once at build time.
--   W        the design width handed to MenuFit. On a phone it is NARROWER than 1180, so the
--            window scale lands near 0.84 instead of 0.54 (authored 12-16pt copy was rendering
--            at 6-8px), and both grids reflow to 2 columns of landscape cards to fit it.
--   H        the phone card heights (LAY.card / LAY.inv / LAY.baits share them). 2026-10-10: bait 158 -> 166
--            and boost 172 -> 184, the room a candy key's drop and outline take between the two key rows.
--   V        the portrait (desktop / iPad) card's stack, design px from its top: the art tile's height, the
--            name line, the sub line and the rod's stat well. The keys are placed from the BOTTOM (LAY.place).
--   GAP_Y / PAD_T / PAD_B  the grid's row gap and top / bottom padding: a card's hard drop (+6) and its 4 px
--            outline need 18 between rows, the first row's outline 6 above it inside the ScrollingFrame's clip,
--            and the last row's drop 12 under it.
--   UP / UP_C  how far a window's art reaches ABOVE its top-left, for LAY.clearTop and MenuFit.centre: the breakout
--            emoji's 44 on a desktop; on a phone the emoji sits INSIDE the header (a breakout cost a fifth of a 375px
--            screen), so 0 - the red X's 18 at the top-RIGHT may rise into the top bar's free region (MenuFit's rule).
--            It was 18 until phones were centred too (2026-10-11).
-- Desktop and iPad stay on the authored layout (W = 1180); LAY.cap only nudges the small
-- captions up where the scale would render them under 12px (iPad: 0.96).
local LAY = { compact = false, W = WIN_W, seen = {}, UX = 36, UXG = 10,
	H = { rod = 180, bait = 166, boost = 184 },
	V = { rod = { tile = 116, name = 126, sub = 150, stats = 176 },
		bait = { tile = 78, name = 86, sub = 110 }, boost = { tile = 150, name = 160, sub = 186, subH = 46 } },
	GAP_Y = 18, PAD_T = 6, PAD_B = 12, UP = 44, UP_C = 0 }
function LAY.decide()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return end   -- not-yet-a-screen (see MenuFit)
	LAY.compact = math.min(vp.X, vp.Y) < 500
	LAY.W = LAY.compact and math.clamp(math.floor(vp.X / 0.84) - 50, 700, 1000) or WIN_W
end
-- MenuFit places a window as if nothing stuck out of it, but this kit's windows wear their emoji 44 design px
-- ABOVE the top edge (on a phone none: UP_C) and a 9 px drop BELOW. Off the desktop's roomy screens that put the emoji
-- under Roblox's top bar, over the platform's own buttons. So: if the window as placed is legal, leave it exactly
-- where MenuFit put it (big screens are untouched); else make it SHORTER first, never below the menu's minH
-- (MenuFit's own rule: the scroll viewport gives, not the type), then smaller only if it still cannot fit, and
-- set it in the band between the top bar and the bottom edge. Returns the scale.
function LAY.clearTop(win, sc, s, minH, up)
	local cam = workspace.CurrentCamera
	local vh = cam and cam.ViewportSize.Y or 0
	if vh < 100 or not s or s <= 0 then return s end
	-- The SIDES first (2026-10-10, play-verified): the breakout emoji's art reaches ~30 design px left of the window
	-- (inside the header on a phone) and the X 18 right of it, and MenuFit's 25 px margin left the 🎒 touching the
	-- left edge of a 1190 px screen. A window whose width binds gets just small enough to keep 6 px clear.
	local sw = (cam.ViewportSize.X / 2 - 6) / (win.Size.X.Offset / 2 + ((up == LAY.UP) and 30 or 18))
	if s > sw then s = sw; sc.Scale = s end
	local top0 = GuiService:GetGuiInset().Y + 4   -- these guis ignore the inset: their y IS the screen's
	local bot0 = vh - 6
	local down = 9
	local W, h = win.Size.X.Offset, win.Size.Y.Offset
	local cy = win.Position.Y.Scale * vh + win.Position.Y.Offset
	if cy - (h / 2 + up) * s >= top0 and cy + (h / 2 + down) * s <= bot0 then return s end
	local band = bot0 - top0
	if (h + up + down) * s > band then
		local h2 = math.max(minH, math.floor(band / s - up - down))
		if h2 < h then
			h = h2
			win.Size = UDim2.fromOffset(W, h)
		end
		if (h + up + down) * s > band then s = math.max(0.1, band / (h + up + down)) end
	end
	local lo = top0 + (up + h / 2) * s
	local hi = bot0 - (down + h / 2) * s
	cy = math.clamp(cy, lo, math.max(lo, hi))
	win.Position = UDim2.new(0.5, 0, 0, math.floor(cy + 0.5))
	sc.Scale = s
	return s
end

local backdrop = make("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1,1), BackgroundColor3 = rgb(2,10,26), BackgroundTransparency = 0.4, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 1 }, gui)

-- THE WINDOW: the kit's shell (UI.window) - a lagoon body with an Ocean decor layer, the purple header with
-- its gloss and wave crest, the gold title, the 🎒 breaking out of the top-left corner and the red key X
-- (win.close.button: a TextButton named "TextButton", 60 x 60 - the tutorial's closeButtonOf() contract).
-- Its parts (and every other Inventory-window piece) live on INV: one local, the register cap.
local INV = {}
INV.win = UI.window(gui, "INVENTORY", { Name = "Window", w = WIN_W, h = WIN_H, emoji = "🎒", headColour = "purple", ZIndex = 5 })
local root = INV.win.root
local uiscale = make("UIScale", { Scale = 1 }, root)
-- the window swallows its own taps (body + drop, and the breakout emoji), so only the Backdrop closes it
UI.corner(K.guard(root, UDim2.new(1, 0, 1, 9), 3), 24)
if INV.win.icon then K.guard(INV.win.icon, UDim2.new(1, 0, 1, 5), 20) end
-- Shared with every other pop-up window in the game. On a small screen it makes the window
-- SHORTER rather than smaller, so the WIDTH drives the scale (+30-38%% text on a phone) and
-- centres it below the Roblox top bar instead of underneath it. MIN_H is the shortest design
-- height this layout survives - found by binary search, checking that nothing outside a
-- ScrollingFrame pokes out of the window. Desktop and iPad are deliberately unchanged.
local MenuFit = require(game:GetService("ReplicatedStorage"):WaitForChild("MenuFit"))
local MIN_H = 460
-- CENTRED ON THE PHONE SCREEN TOO (2026-10-11, the owner: "make the button uis centered to the phone screen"). Both
-- windows end their fit here. Off a phone: the plain MenuFit.centre call, unchanged. On one the emoji is tucked
-- (UP_C = 0) and centring gives the top bar's height up again at the bottom, so a window taller than that band gives
-- back HEIGHT first at the same scale (never below minH: shorter first, as above), and only then gets smaller.
function LAY.centre(win, sc, minH)
	if not LAY.compact then return MenuFit.centre(win, sc, LAY.UP, 9) end
	local s0 = sc.Scale
	local s = MenuFit.centre(win, sc, LAY.UP_C, 9)
	if s < s0 then
		-- the height MenuFit's band holds at s0 (r = s / s0): h*r - 2*up*(1-r) under its top limit, h*r - 2*9*(1-r) over its bottom
		local r = s / s0
		win.Size = UDim2.fromOffset(win.Size.X.Offset, math.max(minH, math.floor(win.Size.Y.Offset * r - 2 * math.max(LAY.UP_C, 9) * (1 - r))))
		sc.Scale = s0
		s = MenuFit.centre(win, sc, LAY.UP_C, 9)
	end
	return s
end
local function fit()
	LAY.decide()
	-- phone minH 280 = header + tab row + a slice of the card list; below that the scale gives, not the layout
	local minH = LAY.compact and 280 or MIN_H
	local s = MenuFit.apply(root, uiscale, LAY.W, WIN_H, 0.4, 1.1, minH)
	s = LAY.clearTop(root, uiscale, s, minH, LAY.compact and LAY.UP_C or LAY.UP)
	s = LAY.centre(root, uiscale, minH)   -- centred on the screen, phones too
	if LAY.inv then LAY.inv(s) end   -- nil on the build-time call; defined after the cards
end
fit()

-- the wallet: your cash in a gold pill and your pearls in a sea one, left of the X (keys that are not pressable)
INV.cash = K.key(root, "gold", "CashPill", 7, true)
INV.pearl = K.key(root, "sea", "PearlPill", 7, true)
INV.cash.button.AnchorPoint, INV.pearl.button.AnchorPoint = Vector2.new(1, 0), Vector2.new(1, 0)
function INV.setPills()
	K.paint(INV.cash, "gold", nil, { { icon = "coins", rel = 0.83 }, { text = UI.cash(getCoins()), rel = 0.58 } })
	K.paint(INV.pearl, "sea", nil, { { text = "🦪", emoji = true, rel = 0.62 }, { text = UI.num(getPearls()), rel = 0.58 } })
end

----------------------------------------------------------------------
-- toast
----------------------------------------------------------------------
-- a candy chip at the top centre of the screen, in a key colour picked from the colour the caller passes
-- (K.tone: gold = good news, red = can't, grey = neutral, a rarity / accent colour keeps its hue)
INV.toast = UI.chip(gui, "navy", {
	Name = "Toast", height = 50, textSize = 22, pad = 24, minWidth = 220, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 74), ZIndex = 40,
})
INV.toast.block.root.Visible = false
INV.toastScale = make("UIScale", { Scale = 1 }, INV.toast.block.root)
local toastToken = 0
-- The baits window is a SECOND ScreenGui, so a toast parented to this one would fire
-- invisibly whenever a bait is equipped from over there. One toast, reparented to whichever
-- window is actually up. BW is forward-declared here for that check and filled in below;
-- it is also ONE local instead of a dozen, because this script is already dense with
-- file-scope locals and Lua's 200-register cap fails at RUN time, not at edit time.
-- (No fade tweens any more: a fade still running from the last toast used to blank the next one.)
local BW = {}
local function showToast(text, color)
	toastToken += 1; local my = toastToken
	local t = INV.toast
	local r = t.block.root
	r.Parent = (BW.gui and BW.gui.Enabled) and BW.gui or gui
	t.set(text, K.tone(color))
	r.Visible = true
	r.Position = UDim2.new(0.5, 0, 0, 62)
	TweenService:Create(r, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 74) }):Play()
	UI.punch(INV.toastScale, 0.7, 0.28)
	task.delay(2.3, function() if my == toastToken then r.Visible = false end end)
end

----------------------------------------------------------------------
-- tabs + pages
----------------------------------------------------------------------
local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 160), Size = UDim2.new(1, -36, 1, -176), ZIndex = 6 }, root)
local USABLE = WIN_W - 36 - 6 - 16
-- a card grid in a ScrollingFrame with the Shop's gold thumb (its INK track is K.track, beside it)
local function makePage(cols, cellH)
	local p = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1,1), Visible = false,
		ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb, ScrollBarImageTransparency = 0,
		VerticalScrollBarInset = Enum.ScrollBarInset.None, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 2,
	}, content)
	local cellW = math.floor((USABLE - (cols-1)*12) / cols)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cellW, cellH), CellPadding = UDim2.fromOffset(12, LAY.GAP_Y), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }, p)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, LAY.PAD_T), PaddingBottom = UDim.new(0, LAY.PAD_B) }, p)
	return p, cellW
end
-- (the 330 / 330 / 228 cell heights carry the two-currency buy row under the main action key. 2026-10-10: a boost
-- card is as tall as a rod card now - at 236 the tab's one row of five filled the top third of the window and left
-- the rest empty lagoon; the extra height is a 120 px potion and a two-line blurb. A bait card stays 228 so the
-- baits window's two rows fit a 1313 x 751 screen without scrolling)
local pageRods,   RODW  = makePage(5, 330)
local pageBaits,  BAITW = makePage(6, 228)
local pageBoosts, BSTW  = makePage(5, 330)
pageRods.Name, pageBaits.Name, pageBoosts.Name = "Rods", "Baits", "Boosts"
K.track(pageRods, content)
K.track(pageBoosts, content)
-- pageBaits is deliberately NOT in here: it is reparented into its own window below, and a
-- page listed here would be switched Visible=false by selectTab the first time a tab changes.
local pages = { rods = pageRods, boosts = pageBoosts }

-- the tabs are candy keys under the header (the Shop's): gold is the tab you're on, the other sea blue
local TAB_DEFS = {
	{ name = "rods",   word = "RODS",   icon = "rod" },
	{ name = "boosts", word = "BOOSTS", icon = "potionluck" },
}
-- the line beside the tabs (counts, what is equipped, the rods' stat legend)
INV.sub = UI.label(root, "", { Name = "Sub", size = 20, align = "left", RichText = true, ZIndex = 7,
	Position = UDim2.fromOffset(450, 95), Size = UDim2.fromOffset(WIN_W - 470, 52) })

----------------------------------------------------------------------
-- the baits window  (its own ScreenGui, opened from the roller's BAITS button)
----------------------------------------------------------------------
-- Only the chrome below is new. Every behaviour - equip, unequip, the buy row, the rebound
-- guard, publishBaitStats - is the same code the tab used, and pageBaits is the same grid;
-- it is simply re-parented out of `content` and into this window.
-- THE CONTRACT (TutorialController.baitEquipButton): BaitsMenu.Window is the window, its child Content holds
-- the grid as its ONLY ScrollingFrame, the cards in it are named Bait_<akey> and each card's main key is a
-- direct child named "Action" (with its own UIScale, which the tutorial breathes). BaitsMenu.Open opens it.
local BWIN_H = 640
do
	local old = pg:FindFirstChild("BaitsMenu")
	if old then old:Destroy() end
end
BW.gui = make("ScreenGui", { Name = "BaitsMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = gui.DisplayOrder, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, pg)

BW.backdrop = make("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1,1), BackgroundColor3 = rgb(2,10,26), BackgroundTransparency = 0.4, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 1 }, BW.gui)
BW.win = UI.window(BW.gui, "BAITS", { Name = "Window", w = WIN_W, h = BWIN_H, emoji = "🐛", headColour = "purple", ZIndex = 5 })
BW.root = BW.win.root
BW.scale = make("UIScale", { Scale = 1 }, BW.root)
UI.corner(K.guard(BW.root, UDim2.new(1, 0, 1, 9), 3), 24)
if BW.win.icon then K.guard(BW.win.icon, UDim2.new(1, 0, 1, 5), 20) end
-- Same shared fit as every other window. MIN_H can be low here because the ONLY things
-- outside the ScrollingFrame are the header and the subtitle - there is no tab bar and no footer.
BW.fit = function()
	LAY.decide()
	local minH = LAY.compact and 240 or 360
	local s = MenuFit.apply(BW.root, BW.scale, LAY.W, BWIN_H, 0.4, 1.1, minH)
	-- Off a phone the top-bar rule may make this window shorter only down to 626 - where both rows of baits
	-- still show whole (grid top 120 + 6 + 2 x 228 + 18 + 12 + 14) - and smaller below that: a 12-card catalogue
	-- that fits on one screen should not scroll by 40 px. A phone always scrolls, so it keeps the menu's minH.
	s = LAY.clearTop(BW.root, BW.scale, s, LAY.compact and minH or 626, LAY.compact and LAY.UP_C or LAY.UP)
	s = LAY.centre(BW.root, BW.scale, minH)   -- centred on the screen, phones too
	if LAY.baits then LAY.baits(s) end
end
BW.fit()

-- the coin pill (the window's own: a key belongs to one parent)
BW.cash = K.key(BW.root, "gold", "CashPill", 7, true)
BW.cash.button.AnchorPoint = Vector2.new(1, 0)
function BW.setCash()
	K.paint(BW.cash, "gold", nil, { { icon = "coins", rel = 0.83 }, { text = UI.cash(getCoins()), rel = 0.58 } })
end
-- no tab bar, so a one-line subtitle sits under the header and the grid starts under it
BW.sub = UI.label(BW.root, "", { Name = "Sub", size = 20, align = "left", RichText = true, ZIndex = 7,
	Position = UDim2.fromOffset(24, 92), Size = UDim2.fromOffset(WIN_W - 48, 24) })
local bContent = make("Frame", { Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 120), Size = UDim2.new(1, -36, 1, -134), ZIndex = 6 }, BW.root)
pageBaits.Parent  = bContent
pageBaits.Visible = true      -- nothing toggles it any more; it is the whole window
K.track(pageBaits, bContent)
local currentTab = TAB_DEFS[1].name
local refreshAll

-- counts you have in lime, what is equipped in gold (RichText; FredokaOne has no bold, so colour does it)
local function subtitleFor(tab)
	local LIME, GOLDT, SOFT = "#AAFF64", "#FFDE50", "#D6EEFF"
	if tab == "rods" then
		local owned = 0
		for _, r in ipairs(RODS) do if rodOwned(r.tier) then owned += 1 end end
		local eq = plr:GetAttribute("EquippedRod") or 1
		local name = RODS[math.clamp(eq,1,#RODS)].name
		-- the icon legend gets its own line (it decodes the stat wells on the cards)
		return string.format("<font color=\"%s\">%d / %d</font> rods owned  ·  equipped: <font color=\"%s\">%s</font>\n<font color=\"%s\">rods add ⚓ depth and 🍀 luck</font>",
			LIME, owned, #RODS, GOLDT, name, SOFT)
	elseif tab == "baits" then
		local total, kinds = 0, 0
		for _, b in ipairs(BAITS) do local c = baitCount(b.name); if c > 0 then kinds += 1; total += c end end
		local eq = plr:GetAttribute("EquippedBait")
		return string.format("<font color=\"%s\">%s</font> baits across <font color=\"%s\">%d</font> kinds  ·  equipped: <font color=\"%s\">%s</font>",
			LIME, commas(total), LIME, kinds, GOLDT, eq or "none")
	elseif tab == "boosts" then
		local total = 0
		for _, b in ipairs(BOOSTS) do total += boostCount(b.key) end
		return string.format("<font color=\"%s\">%d</font> boosts ready  ·  shared with the Shop's Use buttons", LIME, total)
	end
	return ""
end

local function selectTab(name)
	currentTab = name
	for _, def in ipairs(TAB_DEFS) do
		local on = (def.name == name)
		if def.lit ~= on then
			def.lit = on
			def.key.recolour(on and "gold" or "sea")
		end
		pages[def.name].Visible = on
	end
	INV.sub.Text = subtitleFor(name)
end
for _, def in ipairs(TAB_DEFS) do
	local k = K.key(root, "sea", def.word:sub(1, 1) .. def.word:sub(2):lower() .. "Tab", 7)
	k.button.AnchorPoint = Vector2.new(0, 0.5)
	k.button.Size = UDim2.fromOffset(200, 52)
	K.paint(k, "sea", nil, { { icon = def.icon, rel = 0.72 }, { text = def.word, rel = 0.5, gap = 8 } })
	def.key = k
	TouchKit.press(k.button, function() selectTab(def.name) end)
end

----------------------------------------------------------------------
-- generic item card  (a candy card: the item's colour, its art on a glow, keys in the STATE's colour)
----------------------------------------------------------------------
-- One candy colour per ITEM (UI.CANDY names or { top, bottom }): rods by tier, from their accent's hue; baits by
-- rarity (the Index's rarity hues); potions exactly as the Shop paints them, with the Shop's 3D icons.
local LOOK = {
	rod = { { rgb(240, 196, 128), rgb(176, 106, 46) }, "teal", { rgb(150, 166, 196), rgb(52, 64, 92) }, "coral", "blue",
		"orange", "emerald", "cyan", "fire", "cosmic" },
	rarity = { Common = { rgb(176, 194, 222), rgb(84, 104, 140) }, Uncommon = "emerald", Rare = "blue", Epic = "purple",
		Legendary = "orange", Mythic = "rose", Divine = "aurora" },
	boost = {
		potion_luck = { colour = "emerald", icon = "potionluck" }, potion_cast = { colour = "blue", icon = "potioncast" },
		potion_bite = { colour = "red", icon = "potionhook" }, potion_money = { colour = "orange", icon = "potionmoney" },
		jackpot = { colour = "cosmic", icon = "jackpot" },
	},
	DIM = rgb(8, 10, 30),   -- over a card you have none of / cannot reach yet (the Gifts menu's claimed-card dim)
}
-- Children of a card, bottom to top (ZIndexBehavior.Sibling): Shadow 1, Face 2 (+ its gloss), Dim 3, Art 4 (glow,
-- the 3D rod / icon / emoji), Stats 5, Ring 6 (the gold "equipped" band), the name / sub labels 7, the keys 8
-- (TouchKit puts their pads at 7, so no pad can cover a neighbouring key), the count badge 9, a sticker 10.
local function itemCard(page, order, cellW, cellH, kind)
	local rec = { kind = kind, cellH = cellH, cw = cellW, ch = cellH, mode = "both" }
	local card = make("Frame", { Name = "Card", BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 2 }, page)
	rec.card = card
	UI.hardShadow(card, 16, 4, 6, 1)
	rec.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, card)
	UI.corner(rec.face, 16)
	UI.stroke(rec.face, 4)
	UI.gloss(rec.face, { frac = 0.36, alpha = 0.55, inset = 4, radius = 12 })
	rec.dim = UI.new("Frame", { Name = "Dim", BackgroundColor3 = LOOK.DIM, BackgroundTransparency = 0.7, Size = UDim2.fromScale(1, 1),
		ZIndex = 3, Visible = false }, card)
	UI.corner(rec.dim, 16)
	-- the art tile ("tank" since the aquarium days): no frame of its own any more, just the glow and the art
	rec.tank = UI.new("Frame", { Name = "Art", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(cellW - 12, 100), ZIndex = 4 }, card)
	rec.glow = UI.new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow, ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(100, 100),
		ImageTransparency = 0.5, ZIndex = 1 }, rec.tank)
	rec.ring = UI.new("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8),
		ZIndex = 6, Visible = false }, card)
	UI.corner(rec.ring, 12)
	UI.stroke(rec.ring, 4, UI.RING)
	rec.nameLbl = UI.label(card, "", { Name = "ItemName", size = 22, drop = 2, ZIndex = 7 })
	rec.subLbl = UI.label(card, "", { Name = "Sub", size = 16, ZIndex = 7 })
	rec.badge = K.badge(card, 9)

	-- THE KEYS: the main action, and under it THE BUY ROW - cash on the left, Robux on the right.
	-- Every purchasable item carries both, so which currencies an item takes is never a
	-- per-item surprise. setBuyRow() hides the row and drops the main key onto the
	-- bottom edge for items with nothing left to sell you (an owned rod), so a card is
	-- never left with a dead gap where the row used to be.
	rec.btnK = K.key(card, "green", "Action", 8)
	rec.cashK = K.key(card, "green", "BuyCash", 8)
	rec.robuxK = K.key(card, "pink", "BuyRobux", 8)
	rec.btn, rec.cashBtn, rec.robuxBtn = rec.btnK.button, rec.cashK.button, rec.robuxK.button

	function rec.setColour(c)
		UI.vgrad(rec.face, UI.CANDY[c] or c)
	end
	-- Three layouts, because the currencies do not always both belong in the row:
	--   "none"  nothing left to buy (an owned rod) - main action sits on the bottom edge
	--   "both"  a consumable - EQUIP/USE on top, cash and Robux side by side under it
	--   "robux" an unowned rod - its main key IS the cash buy, so only Robux goes in
	--           the row, full width. Painting the price twice was the first version's bug.
	function rec.setBuyRow(mode)
		rec.mode = mode
		rec.cashBtn.Visible, rec.robuxBtn.Visible = mode == "both", mode ~= "none"
		LAY.place(rec)   -- the geometry of all three modes, desktop and phone, lives there
	end
	rec.setBuyRow("both")
	return rec
end

----------------------------------------------------------------------
-- RODS — live ViewportFrame of the actual Tool
----------------------------------------------------------------------
local CAM_DIR = Vector3.new(0.6, 0.28, 1).Unit
-- A Tool has no GetBoundingBox, so reparent its BaseParts into a Model to get one.
local function rodModelFrom(tool)
	local clone = tool:Clone()
	local m = Instance.new("Model")
	m.Name = tool.Name
	for _, d in ipairs(clone:GetChildren()) do
		if d:IsA("BasePart") then d.Anchored = true; d.Parent = m end
	end
	clone:Destroy()
	m.PrimaryPart = m:FindFirstChild("Handle") or m:FindFirstChildWhichIsA("BasePart")
	-- Stand it up (2026-10-10, play-verified). A HELD rod is cloned in the hand's pose - measured mid-session with its
	-- Handle's up axis at (0.75, 0.63, 0.20), so frameModel's roll on top of that laid it flat - and a rod in the pack
	-- sits wherever it was last dropped. Every preview is turned into its own Handle's frame first: the rod runs up it.
	if m.PrimaryPart then m:PivotTo(CFrame.new(m.PrimaryPart.Position)) end
	return m
end
-- 2026-10-10 (play-verified): the rod lies on a DIAGONAL across the desktop card's wide art tile - handle low-left,
-- tip high-right, the way an item icon shows a rod - instead of standing as a thin upright stick that filled half of
-- the tile's height and a quarter of its width. That is a camera ROLL of 50 degrees on a wide tile (a phone's tall tile
-- keeps the rod upright). The fit is MEASURED: every part's corners are projected through the rolled lens, the camera
-- re-centres on what it actually sees (a rod's reel and perspective make the bounding box's centre a poor aim) and
-- moves in until the larger half-span sits at 1 / 1.08 of the tile - four passes converge it. The focus and the roll
-- are returned for the hover spin, which orbits about world Y and has to keep both.
local function frameModel(vpf, model, aspect)
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera"); cam.FieldOfView = 45; cam.Parent = vpf; vpf.CurrentCamera = cam
	local tanV = math.tan(math.rad(22.5))
	local tanH = tanV * aspect
	local roll = (aspect >= 1.2) and math.rad(50) or 0
	local pts = {}
	for _, bp in ipairs(model:GetDescendants()) do
		if bp:IsA("BasePart") and bp.Transparency < 1 then
			local h = bp.Size / 2
			for i = 0, 7 do
				pts[#pts + 1] = bp.CFrame:PointToWorldSpace(Vector3.new(h.X * (i % 2 == 0 and -1 or 1),
					h.Y * (i % 4 < 2 and -1 or 1), h.Z * (i < 4 and -1 or 1)))
			end
		end
	end
	local focus, dist = cf.Position, math.max(size.Magnitude * 2, 6)
	if #pts > 0 then
		for _ = 1, 4 do
			local view = CFrame.lookAt(focus + CAM_DIR * dist, focus) * CFrame.Angles(0, 0, roll)
			local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
			for _, w in ipairs(pts) do
				local lp = view:PointToObjectSpace(w)
				local d = math.max(-lp.Z, 0.05)
				local x, y = lp.X / (d * tanH), lp.Y / (d * tanV)
				x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
			end
			focus = focus + view.RightVector * ((x0 + x1) / 2 * tanH * dist) + view.UpVector * ((y0 + y1) / 2 * tanV * dist)
			dist = math.max(dist * math.max((x1 - x0) / 2, (y1 - y0) / 2) * 1.08, 3)
		end
	end
	cam.CFrame = CFrame.lookAt(focus + CAM_DIR * dist, focus) * CFrame.Angles(0, 0, roll)
	return cam, focus, dist, roll
end

local rodRecs = {}
local spinning = nil   -- one hovered item orbits at a time; rods and fish share it
-- Owned rods are previewed from the real Tool in the pack; the next one up is previewed
-- from ReplicatedStorage.RodPreviews, which RodServer publishes for exactly this.
local function rodSource(name)
	local t = backpackTool(name)
	if t then return t end
	local pv = game:GetService("ReplicatedStorage"):FindFirstChild("RodPreviews")
	return pv and pv:FindFirstChild(name) or nil
end

local function buildRodViewport(rec)
	if rec.built then return end
	local tool = rodSource(rec.def.tool)
	if not tool then return end
	rec.built = true
	-- straight onto the card's colour, over the art tile's glow (the tile itself is see-through)
	local vpf = make("ViewportFrame", { Name = "Rod3D", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1,-6,1,-6), Position = UDim2.fromOffset(3,3), ZIndex = 2 }, rec.tank)
	vpf.Ambient = rgb(206,224,238); vpf.LightColor = Color3.new(1,1,1); vpf.LightDirection = Vector3.new(-0.4,-1,-0.5)
	pcall(function()
		local m = rodModelFrom(tool)
		m.Parent = vpf
		-- rec.aspect: the DESIGN tile shape LAY.card set (AbsoluteSize can still be the last layout's)
		local a = rec.aspect or ((rec.tank.AbsoluteSize.Y > 0) and (rec.tank.AbsoluteSize.X / rec.tank.AbsoluteSize.Y) or 1)
		local cam, centre, dist, roll = frameModel(vpf, m, a)
		rec.cam, rec.centre, rec.dist, rec.roll, rec.model = cam, centre, dist, roll, m
	end)
	rec.vpf = vpf
end

-- THE STAT BLOCK on each rod card. A fixed 2-column grid rather than a UIListLayout, so
-- the same stat always sits in the same spot on every card - you compare two tiers by
-- reading DOWN a column. The icons are decoded by the legend in the tab subtitle.
-- THE STATS on each rod card: what a rod changes - DEPTH and LUCK - as two labelled candy pills side by side
-- (2026-10-10, the owner: "make the stats for the fishing rods look better"). Each pill: its icon, a small word, the
-- value big. The starter rod's pills are grey and read BASE (a "+0" reads as broken, not as the baseline).
local STAT_ROWS = {
	{ key = "depth", icon = "⚓", word = "DEPTH", candy = { rgb(126, 224, 255), rgb(22, 118, 212) },
		fmt = function(v) return "+" .. v .. "m" end },
	{ key = "luck", icon = "🍀", word = "LUCK", candy = { rgb(156, 248, 132), rgb(30, 168, 62) },
		fmt = function(v) return "+" .. math.floor(v * 100 + 0.5) .. "%" end },
}
local STAT_BASE = { depth = 0, luck = 0 }
local STAT_GREY = { rgb(200, 210, 226), rgb(118, 132, 158) }
local function statPanel(card)
	local p = UI.new("Frame", { Name = "Stats", BackgroundTransparency = 1, ZIndex = 5 }, card)
	local pills = {}
	for _, sr in ipairs(STAT_ROWS) do
		local q = {}
		q.root = UI.new("Frame", { Name = "Stat_" .. sr.key, BackgroundTransparency = 1, ZIndex = 5 }, p)
		UI.hardShadow(q.root, 12, 3, 4, 5)
		q.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 6 }, q.root)
		UI.corner(q.face, 12)
		UI.stroke(q.face, 3)
		UI.vgrad(q.face, sr.candy)
		UI.gloss(q.face, { frac = 0.5, alpha = 0.5, inset = 3, radius = 9 })
		local icon, iconStroke = UI.label(q.root, sr.icon, { Name = "Icon", size = 24, scaled = false, AnchorPoint = Vector2.new(0, 0.5), ZIndex = 8 })
		iconStroke.Enabled = false
		q.icon = icon
		q.word = UI.label(q.root, sr.word, { Name = "Word", size = 12, scaled = false, align = "left", outline = 0.22, ZIndex = 8 })
		q.value = UI.label(q.root, "", { Name = "Value", size = 21, scaled = false, align = "left", drop = 2, outline = 0.17, ZIndex = 8 })
		q.sr = sr
		pills[sr.key] = q
	end
	return p, pills
end

----------------------------------------------------------------------
-- ONE CARD, TWO SHAPES. Desktop/iPad: the authored portrait card. Phone (LAY.compact): a
-- LANDSCAPE card - art on the left, copy and keys in a column on the right - because a
-- 375px-tall screen showed ~1.3 rows of 5-6 microscopic portrait cards. LAY.card sets the
-- static parts and the text caps; LAY.place the keys, which ALSO move with the buy-row
-- mode and the bait's unequip X - so setBuyRow() and setUnequip() both route through it.
-- rec.rx is set only while a card is laid out as a phone card; place() trusts it rather than
-- LAY.compact, so a card is always placed consistently with its OWN last layout.
-- Every key is placed in design OFFSETS from the card's known size (rec.cw x rec.ch): a candy key lays its
-- text out from its own pixel width, so a scale-sized key would measure nothing. After placing, K.apply lays
-- each key's line out again for its new size.
----------------------------------------------------------------------
function LAY.place(rec)
	local btn, cash, rbx, ux = rec.btn, rec.cashBtn, rec.robuxBtn, rec.unequipBtn
	local m, cw, ch = rec.mode, rec.cw, rec.ch
	local function put(b, x, y, w, h)
		b.AnchorPoint = Vector2.zero
		b.Position, b.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
	end
	if rec.rx then
		local rx, rw = rec.rx, rec.rw
		if m == "both" then
			-- EQUIP/USE (+ the unequip X) over a cash | Robux row. 48 design = 40px at the ~0.84 phone scale: the
			-- spec's floor for a primary key; the row under it starts below the key's drop and outline.
			local hw = math.floor((rw - 8) / 2)
			put(cash, rx, ch - 46, hw, 38)
			put(rbx, rx + hw + 8, ch - 46, rw - hw - 8, 38)
			put(btn, rx, ch - 108, rec.uxOn and (rw - 56) or rw, 48)
			if ux then put(ux, rx + rw - 48, ch - 108, 48, 48) end
		else
			-- one row: the main key, and for an unowned rod its Robux price beside it
			local bw = (m == "robux") and math.floor((rw - 8) * 0.6) or rw
			put(btn, rx, ch - 56, bw, 48)
			put(rbx, rx + bw + 8, ch - 56, rw - bw - 8, 48)
			if ux then put(ux, rx + rw - 48, ch - 56, 48, 48) end
		end
	else
		-- the portrait card: the buy row 30 tall on the bottom edge (10 up), the main key 36 tall over it, its
		-- bottom 52 up (12 when there is no row) - so the key's +6 drop and both outlines never touch the row
		local w = cw - 16
		local shift = rec.uxOn and (LAY.UX + LAY.UXG) or 0
		put(btn, 8, ch - (m == "none" and 12 or 52) - 36, w - shift, 36)
		local hw = math.floor((w - 8) / 2)
		put(cash, 8, ch - 40, hw, 30)
		if m == "robux" then put(rbx, 8, ch - 40, w, 30) else put(rbx, 8 + hw + 8, ch - 40, w - hw - 8, 30) end
		if ux then put(ux, 8 + w - LAY.UX, ch - 52 - 36, LAY.UX, 36) end
	end
	-- A HIDDEN control keeps a live TouchKit pad wherever it last was (layoutPad never checks
	-- Visible), and the phone card moves everything: an owned rod's hidden Robux key would
	-- leave an invisible tap target that prompts a purchase. Zero size = no pad.
	if not cash.Visible then cash.Size = UDim2.new() end
	if not rbx.Visible then rbx.Size = UDim2.new() end
	if ux and not rec.uxOn then ux.Size = UDim2.new() end
	K.apply(rec.btnK); K.apply(rec.cashK); K.apply(rec.robuxK)
	if rec.uxK then K.apply(rec.uxK) end
end

function LAY.card(rec, c, cw, cap)
	local kind, tank, nm, sb = rec.kind, rec.tank, rec.nameLbl, rec.subLbl
	local ch = c and LAY.H[kind] or rec.cellH
	rec.cw, rec.ch = cw, ch
	local tw, th
	if c then
		tw, th = (kind == "rod") and 118 or 100, ch - 12
		rec.rx, rec.rw = tw + 16, cw - tw - 26
		nm.Position, nm.Size = UDim2.fromOffset(rec.rx, 8), UDim2.fromOffset(rec.rw - 84, 24)   -- room for the badge
		-- 2 lines where the copy can wrap (a boost blurb). A rod's blurb and its locked hint are one line,
		-- so the rod's stat well starts right under it (at 56).
		sb.Position, sb.Size = UDim2.fromOffset(rec.rx, 32), UDim2.fromOffset(rec.rw, (kind == "boost") and 36 or ((kind == "rod") and 22 or 20))
	else
		local V = LAY.V[kind]
		tw, th = cw - 12, V.tile
		rec.rx, rec.rw = nil, nil
		nm.Position, nm.Size = UDim2.fromOffset(8, V.name), UDim2.fromOffset(cw - 16, 24)
		sb.Position, sb.Size = UDim2.fromOffset(8, V.sub), UDim2.fromOffset(cw - 16, V.subH or 20)
	end
	tank.Position, tank.Size = UDim2.fromOffset(6, 6), UDim2.fromOffset(tw, th)
	rec.aspect = (tw - 6) / math.max(th - 6, 1)   -- the rod viewport's shape (the tile less its 3 px inset)
	-- the glow is a soft halo a little wider than the art (behind a rod, most of the tile's height). At the kit's 0.2
	-- it read as a hard white plate behind every emoji and every thin rod, so it is 0.5 here (set in itemCard).
	local a = math.floor(math.min(tw, th) * ((kind == "rod") and 0.5 or 0.8))
	local g = (kind == "rod") and math.floor(math.min(tw * 1.15, th * 1.25)) or math.floor(math.min(tw * 1.15, th * 1.25, a * 1.7))
	rec.glow.Size = UDim2.fromOffset(g, g)
	if rec.art then rec.art.Size = UDim2.fromOffset(a, a) end
	-- the count / tier pill: the art tile's top-right corner on a portrait card; on a phone card the CARD's top-right
	-- corner, the name line shortened for it (at a 118 px tile's corner it ran into the rod's NEXT sticker)
	rec.badge.root.Position = c and UDim2.fromOffset(cw - 8, 6) or UDim2.fromOffset(6 + tw - 4, 10)
	nm.TextXAlignment = c and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
	-- the name's hard drop is a copy that follows its text / size / position but NOT its alignment: keep it in step
	local nmDrop = nm.Parent and nm.Parent:FindFirstChild(nm.Name .. "Drop")
	if nmDrop then nmDrop.TextXAlignment = nm.TextXAlignment end
	sb.TextXAlignment = nm.TextXAlignment
	sb.TextYAlignment = c and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	-- (never write TextWrapped on these: a kit label is TextScaled, which wraps anyway, and TextWrapped = false
	-- switches TextScaled OFF - it left the desktop blurbs at an 8 px TextSize)
	K.setMax(sb, c and 15 or math.max(16, (cap or 12) + 4))
	if rec.statPanel then
		local w = c and rec.rw or (cw - 16)
		local h = c and 50 or 52
		rec.statPanel.Position = UDim2.fromOffset(c and rec.rx or 8, c and 58 or LAY.V.rod.stats + 2)
		rec.statPanel.Size = UDim2.fromOffset(w, h)
		local gap = 8
		local pw = math.floor((w - gap) / 2)
		for i, sr in ipairs(STAT_ROWS) do
			local q = rec.statLbls[sr.key]
			q.root.Position = UDim2.fromOffset((i - 1) * (pw + gap), 0)
			q.root.Size = UDim2.fromOffset(pw, h - 4)
			q.icon.Position = UDim2.new(0, 6, 0.5, -2)
			q.icon.Size = UDim2.fromOffset(28, 28)
			q.word.Position = UDim2.fromOffset(36, 4)
			q.word.Size = UDim2.fromOffset(pw - 40, 14)
			q.value.Position = UDim2.fromOffset(36, 17)
			q.value.Size = UDim2.fromOffset(pw - 40, 24)
		end
	end
	-- a rod already on camera is re-framed for the new tile shape (portrait on a phone)
	if rec.cam and rec.model and rec.vpf then
		rec.cam:Destroy()
		rec.cam, rec.centre, rec.dist, rec.roll = frameModel(rec.vpf, rec.model, rec.aspect)
	end
	LAY.place(rec)
end

----------------------------------------------------------------------
-- BUYING - cash and Robux, on every tab
----------------------------------------------------------------------
-- Both currencies end in the SAME grantItem() call. A cash buy calls it directly; a Robux
-- buy is granted by ServerScriptService.ProductServer inside ProcessReceipt, which fires
-- ShopRemotes.Granted back here. One grant path, so the two routes cannot deliver
-- different things for the same item.
local BAIT_BY_AKEY = {}
for _, b in ipairs(BAITS) do BAIT_BY_AKEY[akey(b.name)] = b end

local function grantItem(kind, key, qty)
	if kind == "rod" then
		local tier = tonumber(key)
		if not tier then return end
		plr:SetAttribute("Rod_" .. tier, true)
		if rodGrant then rodGrant:FireServer(tier) end
	elseif kind == "bait" then
		local b = BAIT_BY_AKEY[key]
		-- qty 0 means "you work it out": the server does not carry the rarity table, so a
		-- Robux bait purchase resolves its pack size here instead.
		local n = (qty and qty > 0) and qty or ShopProducts.packFor("bait", key, b and b.rarity)
		plr:SetAttribute("Bait_" .. key, (plr:GetAttribute("Bait_" .. key) or 0) + n)
	elseif kind == "boost" then
		local n = (qty and qty > 0) and qty or ShopProducts.packFor("boost", key)
		plr:SetAttribute("Inv_" .. key, (plr:GetAttribute("Inv_" .. key) or 0) + n)
	else
		return
	end
	if refreshAll then refreshAll() end
end

do
	local rem = ReplicatedStorage:FindFirstChild("ShopRemotes")
	local ev = rem and rem:FindFirstChild("Granted")
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(function(kind, key, qty, _restore, receiptId)
			grantItem(kind, key, qty)
			-- applied: tell SaveClient, so the purchase completes once this is saved (SaveServer "ROBUX")
			do
				local sr = ReplicatedStorage:FindFirstChild("SaveRemotes"); local ack = sr and sr:FindFirstChild("Ack")
				if ack and type(receiptId) == "string" then ack:Fire(receiptId) end
			end
			showToast("\u{1F48E}  Purchase delivered!", GOLD)
		end)
	end
end

-- An id left at 0 means the Developer Product has not been created yet, so the button says
-- so rather than prompting. PromptProductPurchase on an unset id is a dead end that reads
-- to the player as a broken game - and nothing here can ever take Robux for nothing.
local function buyRobux(kind, key, label)
	local id = ShopProducts.productId(kind, key)
	if id <= 0 then
		showToast(label .. " \u{2014} no Robux product set up yet", GOLD)
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(plr, id)
	end)
	if not ok then
		warn("[Inventory] PromptProductPurchase failed:", err)
		showToast("Couldn't open the purchase prompt.", C.bad)
	end
end

local function buyBaitCash(b)
	local price = ShopProducts.BAIT_BY_RARITY[b.rarity]
	if not price then return end
	if getCoins() < price.cash then
		showToast("You need " .. money(price.cash) .. " for " .. b.name .. ".", C.bad); return
	end
	addCoins(-price.cash)
	grantItem("bait", akey(b.name), price.pack)
	showToast("\u{1F41B}  +" .. price.pack .. "  " .. b.name, BRC[b.rarity])
end

local function buyBoostCash(b)
	local price = ShopProducts.BOOST[b.key]
	if not price then return end
	if getCoins() < price.cash then
		showToast("You need " .. money(price.cash) .. " for a " .. b.name .. ".", C.bad); return
	end
	addCoins(-price.cash)
	grantItem("boost", b.key, price.pack)
	showToast("\u{1F9EA}  +" .. price.pack .. "  " .. b.name, b.accent)
end

-- (2026-10-10: paintBuy / paintRobux are gone - every buy key is a candy key now, painted by K.cash / K.robux:
-- green or grey by whether you can afford it, pink while the Robux product exists. A key you cannot afford still
-- takes the tap, so the toast can say what is missing - a dead button explains nothing.)

local function buyRod(def)
	if rodOwned(def.tier) then return end
	if def.tier > 1 and not rodOwned(def.tier - 1) then
		showToast("Unlock the " .. RODS[def.tier - 1].name .. " Rod first.", C.bad); return
	end
	local cost = ROD_COST[def.tier] or 0
	if getCoins() < cost then
		showToast("You need " .. money(cost) .. " for the " .. def.name .. " Rod.", C.bad); return
	end
	addCoins(-cost)
	plr:SetAttribute("Rod_" .. def.tier, true)
	if rodGrant then rodGrant:FireServer(def.tier) end   -- server puts the Tool in the pack
	showToast("🎣  Unlocked the " .. def.name .. " Rod!", GOLD)
	refreshAll()
end

local function equipRod(def)
	if not rodOwned(def.tier) then showToast("You don't own the " .. def.name .. " yet.", C.bad); return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local tool = backpackTool(def.tool)
	if not (hum and tool) then showToast("Couldn't find that rod in your pack.", C.bad); return end
	pcall(function() hum:EquipTool(tool) end)
	plr:SetAttribute("EquippedRod", def.tier)
	publishRodStats()
	showToast("🎣  Equipped the " .. def.name .. " Rod", def.accent)
	refreshAll()
end

for i, def in ipairs(RODS) do
	local rec = itemCard(pageRods, i, RODW, 330, "rod")
	rec.def = def
	rec.card.Name = "Rod_" .. def.tier
	rec.setColour(LOOK.rod[def.tier] or "blue")
	rec.statPanel, rec.statLbls = statPanel(rec.card)
	-- what a rod you cannot reach yet shows instead of its model
	rec.art = UI.icon(rec.tank, "lock", 56, { Name = "Lock", flat = true, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3, Visible = false })
	-- the rod you can buy next wears a gold NEXT sticker (Boats and Zones flag theirs the same way)
	rec.sticker = UI.sticker(rec.card, "gold", "NEXT", { Name = "Next", Position = UDim2.fromOffset(36, 18), Rotation = -8,
		textSize = 15, height = 28, ZIndex = 10 })
	rec.sticker.block.root.Visible = false
	rodRecs[#rodRecs+1] = rec
	TouchKit.press(rec.btn, function()
		if rodOwned(def.tier) then equipRod(def) else buyRod(def) end
	end)
	TouchKit.press(rec.cashBtn, function() buyRod(def) end)
	TouchKit.press(rec.robuxBtn, function()
		if def.tier > 1 and not rodOwned(def.tier - 1) then
			showToast("Unlock the " .. RODS[def.tier - 1].name .. " Rod first.", C.bad); return
		end
		buyRobux("rod", def.tier, def.name .. " Rod")
	end)
	rec.card.MouseEnter:Connect(function() if rec.cam then spinning = rec end end)
	rec.card.MouseLeave:Connect(function() if spinning == rec then spinning = nil end end)
end

local function refreshRods()
	local eq = plr:GetAttribute("EquippedRod") or 1
	local coins = getCoins()
	for _, rec in ipairs(rodRecs) do
		local d = rec.def
		local owned = rodOwned(d.tier)
		local nextUp = (d.tier == 1) or rodOwned(d.tier - 1)
		buildRodViewport(rec)
		-- EVERY rod shows its model, name, blurb, stats and price (the owner, 2026-10-10: "make it to where u can
		-- see all the fishing rods"). The numbers ARE the sales pitch, and a ladder you can see the top of is
		-- something to aim at; past the next rod it used to be "? ? ?" behind a padlock. Buying is still in
		-- order - buyRod and the Robux key both refuse a rod whose previous tier you do not own, with a toast.
		local st = rodStats(d.tier)
		rec.statPanel.Visible = true
		for _, sr in ipairs(STAT_ROWS) do
			local v = st[sr.key]
			local q = rec.statLbls[sr.key]
			local base = v == STAT_BASE[sr.key]
			q.value.Text = base and "BASE" or sr.fmt(v)
			if q.base ~= base then
				q.base = base
				UI.vgrad(q.face, base and STAT_GREY or sr.candy)
			end
		end
		rec.nameLbl.Text = d.name
		rec.subLbl.Text = d.blurb
		K.badgeSet(rec.badge, "TIER " .. d.tier, "navy")
		-- An owned rod has nothing left to sell you; an unowned one already carries its cash
		-- price on the main key, so only the Robux option goes in the row.
		rec.setBuyRow(owned and "none" or "robux")
		if not owned then
			K.robux(rec.robuxK, ShopProducts.ROD_ROBUX[d.tier] or 0, "rod", d.tier, nextUp)
		end
		if rec.vpf then rec.vpf.Visible = true end
		rec.art.Visible = false
		rec.dim.Visible = false
		rec.sticker.block.root.Visible = (not owned) and nextUp
		rec.ring.Visible = owned and d.tier == eq
		if not owned then
			-- every unowned rod is priced; only the NEXT one can go green (a rod further up is grey until its
			-- turn - tapping it says which rod to unlock first)
			local cost = ROD_COST[d.tier] or 0
			K.cash(rec.btnK, cost, nil, nextUp and coins >= cost)
		elseif d.tier == eq then
			K.paint(rec.btnK, "gold", nil, { { icon = "check", flat = true, rel = K.REL.flat }, { text = "EQUIPPED", rel = 0.5 } })
		else
			K.paint(rec.btnK, "green", nil, { { text = "EQUIP" } })
		end
	end
end

----------------------------------------------------------------------
-- BAITS
----------------------------------------------------------------------
local baitRecs = {}
local function equipBait(b)
	if baitCount(b.name) <= 0 then showToast("You have no " .. b.name .. ".", C.bad); return end
	plr:SetAttribute("EquippedBait", b.name)
	publishBaitStats()
	showToast("🐛  Equipped " .. b.name .. "  ·  " .. b.buff, BRC[b.rarity])
	refreshAll()
end

-- Taking a bait OFF. There is no systems work here: nil is already the canonical "no bait"
-- and GameClient's consumeBait writes exactly this line every time you spend your last one,
-- so publishBaitStats republishes luck 0 / value 1 / haste 1 and the HUD chip, the bobber
-- tag and the subtitle's "equipped: none" all follow on their own.
local function unequipBait(b)
	-- The guard is load-bearing, not decorative. A tap can land a frame after consumeBait
	-- already cleared this, and TouchKit's hit pad for a HIDDEN button stays live (layoutPad
	-- never checks btn.Visible), so a stray tap in a card's bottom margin can reach here on a
	-- card that is not the equipped one. Both cases no-op silently rather than toasting.
	if plr:GetAttribute("EquippedBait") ~= b.name then return end
	plr:SetAttribute("EquippedBait", nil)
	publishBaitStats()
	-- NOT C.good: green + ✓ + a gold 4.5 stroke is this game's reserved "this is the current
	-- one" grammar (rods and boats too). NOT C.bad either - red is the failure toast.
	showToast("🐛  Unequipped " .. b.name .. "  ·  no bait buff", C.off)
	refreshAll()
end

-- The unequip X shares the action row with the EQUIP key: while it is up the key gives back
-- exactly its width plus the gap (LAY.UX + LAY.UXG = 36 + 10 on the portrait card, 48 + 8 on
-- a phone card). 2026-10-10: every key is placed in whole design offsets now, so the old
-- keep-it-even rule for a centre-anchored button no longer applies.
-- ⚠️ setBuyRow() and this both go through LAY.place() now, which owns the action row's
-- geometry (the phone card lays it out differently), so the two can no longer disagree.
local UX_SZ, UX_GAP = LAY.UX, LAY.UXG   -- the numbers live in LAY: LAY.place runs before this line
-- ⚠️ THE ACTION ROW RE-FLOWS ACROSS THE FINGER THAT JUST PRESSED IT. Equipping makes the
-- button shrink and the ✕ appear over its old right end; unequipping makes the button grow
-- back over where the ✕ was. Either way the SECOND tap of a double-tap lands on the other
-- control and instantly undoes the first - measured: two taps on ✕ left the bait equipped,
-- with an "Unequipped" toast followed by an "Equipped" one. So a card that has just changed
-- shape ignores presses for a moment. Per card, so switching to a DIFFERENT bait is instant.
local REBOUND = 0.35
local function rebounding(rec) return os.clock() - (rec.reflowAt or 0) < REBOUND end
local function setUnequip(rec, on)
	if rec.unequipBtn.Visible ~= on then rec.reflowAt = os.clock() end
	if on then
		rec.uxOn = true; LAY.place(rec)   -- narrows the button (either card shape)
		-- shown LAST: TouchKit measures the ✕'s hit pad on this transition, and by now the
		-- button is already narrow, so neighbourLimits clamps the pad to the real gap
		rec.unequipBtn.Visible = true
	else
		-- hidden FIRST, so TouchKit drops that pad before the button expands underneath it
		rec.unequipBtn.Visible = false
		rec.uxOn = false; LAY.place(rec)
	end
end

for i, b in ipairs(BAITS) do
	local rec = itemCard(pageBaits, i, BAITW, 228, "bait")
	rec.bait = b
	-- Named so the TUTORIAL can ring the EQUIP key of the bait you have just rolled. The
	-- card's name is EXACTLY the attribute RollerController bumps on a roll ("Bait_" .. akey,
	-- the same non-alphanumeric strip), so the tutorial gets the right card straight from the
	-- attribute that changed - no name matching against a label, no index arithmetic.
	-- Safe to rename: this grid sorts on LayoutOrder, not Name, and nothing finds these cards
	-- by name (refreshBaits walks baitRecs). The main key is itemCard's "Action" - a direct child
	-- of the card, carrying the UIScale the tutorial breathes.
	rec.card.Name = "Bait_" .. akey(b.name)
	rec.btn.Name  = "Action"
	rec.setColour(LOOK.rarity[b.rarity] or "blue")
	rec.iconLbl = K.emoji(rec.tank, b.icon, { ZIndex = 3 })
	rec.art = rec.iconLbl
	baitRecs[#baitRecs+1] = rec
	TouchKit.press(rec.btn, function() if rebounding(rec) then return end; equipBait(b) end)
	-- Built HERE and not in itemCard, which rods and boosts share: neither should get an
	-- unequip, and it only has a slot beside the main key in "both" buy-row mode - a rod card
	-- sits in "none" mode with its key on the bottom edge. Same precedent as rec.bait / rec.iconLbl
	-- above: bait-only members bolted on after the ctor.
	-- ⚠️ Same ZIndex (8) as the EQUIP key beside it. TouchKit parents a control's hit pad to the
	-- card at ZIndex-1, so both pads sit at 7 and neither can cover the other's control, whatever
	-- order they lay out in (a window close's ZIndex here would put its pad ABOVE the EQUIP key).
	-- A red candy key with a typed X (FredokaOne has the letter; it is the ✕ glyph that draws blank).
	local ux = K.key(rec.card, "red", "Unequip", 8)
	ux.button.Visible = false
	ux.button.Size = UDim2.new()   -- hidden = zero-sized, so it carries no live TouchKit pad (LAY.place keeps it so)
	rec.uxK = ux
	rec.unequipBtn = ux.button
	K.paint(ux, "red", nil, { { text = "X", rel = 0.62 } })
	TouchKit.press(ux.button, function() if rebounding(rec) then return end; unequipBait(b) end)
	TouchKit.press(rec.cashBtn, function() buyBaitCash(b) end)
	TouchKit.press(rec.robuxBtn, function() buyRobux("bait", akey(b.name), b.name) end)
end
local function fmtOdds(n)
	for _, u in ipairs({ {1e9,"B"}, {1e6,"M"}, {1e3,"K"} }) do
		if n >= u[1] then return string.format("%.2f%s", n/u[1], u[2]) end
	end
	return string.format("%d", n)
end
local function refreshBaits()
	local eq = plr:GetAttribute("EquippedBait")
	local coins = getCoins()
	for _, rec in ipairs(baitRecs) do
		local b = rec.bait
		local n = baitCount(b.name)
		rec.nameLbl.Text = b.name
		rec.subLbl.Text = b.buff
		-- how many you have: lime on navy, a grey x0 when you have none
		K.badgeSet(rec.badge, "x" .. commas(n), n > 0 and "navy" or "grey", n > 0 and UI.TEXT.lime or nil)
		rec.iconLbl.TextTransparency = n > 0 and 0 or 0.35
		rec.glow.Visible = n > 0   -- none yet: no halo (through a faded emoji it showed as a white ghost disc)
		-- Bait is a consumable, so the buy row is ALWAYS live: the whole point is topping up.
		do
			local price = ShopProducts.BAIT_BY_RARITY[b.rarity]
			if price then
				K.cash(rec.cashK, price.cash, price.pack, coins >= price.cash)
				K.robux(rec.robuxK, price.robux, "bait", akey(b.name), true)
			end
		end
		-- Hoisted above the three paint branches on purpose: one call site none of them can
		-- forget, and it ties the X to the DATA (is this the equipped bait) rather than to the
		-- paint state. That also leaves it live on an equipped-but-exhausted card, which is
		-- the only UI way back out of a stale equip.
		setUnequip(rec, eq == b.name)
		rec.ring.Visible = (eq == b.name)
		rec.dim.Visible = n <= 0
		if n <= 0 then
			rec.subLbl.Text = "1 / " .. fmtOdds(b.odds) .. " — none yet"
			K.paint(rec.btnK, "grey", nil, { { text = "NONE" } })
		elseif eq == b.name then
			K.paint(rec.btnK, "gold", nil, { { icon = "check", flat = true, rel = K.REL.flat }, { text = "EQUIPPED", rel = 0.5 } })
		else
			K.paint(rec.btnK, "green", nil, { { text = "EQUIP" } })
		end
	end
end

----------------------------------------------------------------------
-- BOOSTS  (counts shared with ShopController via Inv_<key>)
----------------------------------------------------------------------
local boostRecs = {}
local shopRemotes = ReplicatedStorage:FindFirstChild("ShopRemotes")
local function useBoost(b)
	local n = boostCount(b.key)
	if n <= 0 then showToast("You have no " .. b.name .. " to use.", C.bad); return end
	plr:SetAttribute("Inv_" .. b.key, n - 1)
	local rem = shopRemotes and shopRemotes:FindFirstChild("UseItem")
	if rem and rem:IsA("RemoteEvent") then pcall(function() rem:FireServer(b.key) end) end
	-- ⚠️ THIS is what makes a potion do anything. UseItem has no server listener - for a long
	-- time using a boost decremented the count, fired into the void and toasted "activated!",
	-- which is why a Jackpot or a Luck won off the wheel appeared to do nothing at all.
	-- BoostClient owns the durations and publishes the Boost* attributes GameClient reads.
	local boosts = ReplicatedStorage:FindFirstChild("BoostRemotes")
	local act = boosts and boosts:FindFirstChild("Activate")
	if act then act:Fire(b.key) end
	showToast("🧪  " .. b.name .. " activated!", b.accent)
	refreshAll()
end
for i, b in ipairs(BOOSTS) do
	local rec = itemCard(pageBoosts, i, BSTW, 330, "boost")
	rec.boost = b
	rec.card.Name = "Boost_" .. b.key
	local look = LOOK.boost[b.key] or { colour = "blue", icon = "potionluck" }
	rec.setColour(look.colour)
	-- the Shop's 3D potion (ReplicatedStorage.ShopIcons), rocking gently on its glow
	rec.iconImg = UI.icon(rec.tank, look.icon, 80, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3 })
	rec.art = rec.iconImg
	boostRecs[#boostRecs+1] = rec
	TouchKit.press(rec.btn, function() useBoost(b) end)
	TouchKit.press(rec.cashBtn, function() buyBoostCash(b) end)
	TouchKit.press(rec.robuxBtn, function() buyRobux("boost", b.key, b.name) end)
end
local function refreshBoosts()
	local coins = getCoins()
	for _, rec in ipairs(boostRecs) do
		local b = rec.boost
		local n = boostCount(b.key)
		rec.nameLbl.Text = b.name
		rec.subLbl.Text = b.blurb
		K.badgeSet(rec.badge, "x" .. n, n > 0 and "navy" or "grey", n > 0 and UI.TEXT.lime or nil)
		rec.iconImg.ImageTransparency = n > 0 and 0 or 0.45
		rec.glow.Visible = n > 0   -- none left: no halo behind the faded potion
		do
			local price = ShopProducts.BOOST[b.key]
			if price then
				K.cash(rec.cashK, price.cash, nil, coins >= price.cash)
				K.robux(rec.robuxK, price.robux, "boost", b.key, true)
			end
		end
		rec.dim.Visible = n <= 0
		if n > 0 then
			K.paint(rec.btnK, "green", nil, { { text = "USE (" .. n .. ")" } })
		else
			K.paint(rec.btnK, "grey", nil, { { text = "NONE" } })
		end
	end
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
----------------------------------------------------------------------
-- window-level phone layout (see LAY at the top). Each runs from its window's fit(), which
-- runs on open AND on every viewport change while open. The else-values are the authored ones.
----------------------------------------------------------------------
function LAY.cap(s) return (s and s > 0 and s * 12 < 11.95) and math.ceil(12 / s) or 12 end
-- The kit's header for this width: its height (74, 60 on a phone), the wave crest re-spaced (the scallops
-- were laid for WIN_W; a narrower phone window hides the spares - they would hang past its right edge), the
-- emoji (breaking out of the corner on a desktop, tucked inside the header on a phone, where 44 px above the
-- window is a fifth of the screen) and the title's box between it and `used` px of furniture. Returns hh.
function LAY.head(win, c, W, used)
	local hh = c and 60 or 74
	win.header.Size = UDim2.new(1, 0, 0, hh)
	win.ocean.Position, win.ocean.Size = UDim2.fromOffset(0, hh), UDim2.new(1, 0, 1, -hh)
	win.crest.Position = UDim2.fromOffset(0, hh)
	local D = 26
	local n = math.ceil((W - 10) / D)
	local x0 = (W - n * D) / 2
	local i = 0
	for _, d in ipairs(win.crest:GetChildren()) do
		if d:IsA("Frame") then
			d.Visible = i < n
			d.Position = UDim2.fromOffset(x0 + i * D, -1)
			i += 1
		end
	end
	if win.icon then
		win.icon.Size = c and UDim2.fromOffset(50, 50) or UDim2.fromOffset(124, 124)
		win.icon.Position = c and UDim2.fromOffset(12, 5) or UDim2.fromOffset(-36, -LAY.UP)
	end
	local tx = c and 70 or 112
	win.title.Position = UDim2.fromOffset(tx, 0)
	win.title.Size = UDim2.fromOffset(math.max(W - tx - used, 80), hh)
	K.setMax(win.title, c and 38 or 46)
	return hh
end
-- a header pill: right edge `right` px in from the window's right, centred in a header hh tall
function LAY.pill(k, right, w, h, hh)
	k.button.Position = UDim2.new(1, -right, 0, math.floor((hh - h) / 2))
	k.button.Size = UDim2.fromOffset(w, h)
	K.apply(k)
end
function LAY.inv(s)
	local c, W = LAY.compact, LAY.W
	local cap, cw = LAY.cap(s), math.floor((W - 70) / 2)
	local cashW, pearlW, pillH = c and 156 or 196, c and 118 or 150, c and 40 or 48
	local hh = LAY.head(INV.win, c, W, 96 + cashW + 10 + pearlW + 12)
	LAY.pill(INV.cash, 96, cashW, pillH, hh)
	LAY.pill(INV.pearl, 96 + cashW + 10, pearlW, pillH, hh)
	-- the tab keys under the crest, the subtitle beside them (two lines: the counts, then the rods' legend)
	local tw, th = c and 160 or 200, c and 40 or 52
	local ty = hh + (c and 40 or 47)   -- the keys' centre line (desktop 121: 95..147, clear of the crest's outlined tips at ~90)
	for i, def in ipairs(TAB_DEFS) do
		def.key.button.Position = UDim2.fromOffset(18 + (i - 1) * (tw + 12), ty)
		def.key.button.Size = UDim2.fromOffset(tw, th)
		K.apply(def.key)
	end
	local sx = 18 + #TAB_DEFS * (tw + 12) + 6
	INV.sub.Position = UDim2.fromOffset(sx, ty - (c and 20 or 26))
	INV.sub.Size = UDim2.fromOffset(W - sx - 20, c and 40 or 52)
	K.setMax(INV.sub, c and 16 or 20)
	local top = ty + th / 2 + (c and 8 or 13)   -- desktop 160, phone 128
	content.Position = UDim2.fromOffset(18, top)
	content.Size = UDim2.new(1, -36, 1, -(top + (c and 10 or 16)))
	pageRods:FindFirstChildOfClass("UIGridLayout").CellSize = c and UDim2.fromOffset(cw, LAY.H.rod) or UDim2.fromOffset(RODW, 330)
	pageBoosts:FindFirstChildOfClass("UIGridLayout").CellSize = c and UDim2.fromOffset(cw, LAY.H.boost) or UDim2.fromOffset(BSTW, 330)
	for _, r in ipairs(rodRecs) do LAY.card(r, c, c and cw or RODW, cap) end
	for _, r in ipairs(boostRecs) do LAY.card(r, c, c and cw or BSTW, cap) end
	INV.sub.Text = subtitleFor(currentTab)
end
function LAY.baits(s)
	local c, W = LAY.compact, LAY.W
	local cap, cw = LAY.cap(s), math.floor((W - 70) / 2)
	local cashW, pillH = c and 156 or 196, c and 40 or 48
	local hh = LAY.head(BW.win, c, W, 96 + cashW + 12)
	LAY.pill(BW.cash, 96, cashW, pillH, hh)
	-- no tab row to share, so the subtitle gets a thin row of its own under the crest
	local sy = hh + (c and 16 or 18)
	BW.sub.Position = UDim2.fromOffset(24, sy)
	BW.sub.Size = UDim2.fromOffset(W - 48, c and 22 or 24)
	K.setMax(BW.sub, c and 16 or 20)
	local top = sy + (c and 22 or 24) + (c and 6 or 4)   -- desktop 120, phone 104
	BW.inset = top + (c and 10 or 14)                      -- what the grid's viewport loses (LAY.reveal)
	bContent.Position = UDim2.fromOffset(18, top)
	bContent.Size = UDim2.new(1, -36, 1, -BW.inset)
	pageBaits:FindFirstChildOfClass("UIGridLayout").CellSize = c and UDim2.fromOffset(cw, LAY.H.bait) or UDim2.fromOffset(BAITW, 228)
	for _, r in ipairs(baitRecs) do LAY.card(r, c, c and cw or BAITW, cap) end
end
-- Scroll the baits grid so one card is wholly in view. Two columns put most of the catalogue
-- below the fold on a phone, and the tutorial rings the rolled bait's EQUIP without scrolling.
-- Worked in DESIGN units from the grid maths (no AbsolutePosition, which lags a CellSize change),
-- then written in REAL pixels: CanvasPosition is NOT in design units (measured: its max is
-- AbsoluteCanvasSize - AbsoluteSize), so it has to be multiplied by the window's scale.
function LAY.reveal(name)
	local card = pageBaits:FindFirstChild(name)
	local g = pageBaits:FindFirstChildOfClass("UIGridLayout")
	local k = BW.scale.Scale
	if not (card and g) or k <= 0 then return end
	local cellH = g.CellSize.Y.Offset
	local top = LAY.PAD_T + math.floor((card.LayoutOrder - 1) / (LAY.compact and 2 or 6)) * (cellH + LAY.GAP_Y)
	local viewH = BW.root.Size.Y.Offset - (BW.inset or 134)
	local y = pageBaits.CanvasPosition.Y / k
	if top + cellH > y + viewH then y = top + cellH - viewH + 10
	elseif top < y then y = top - LAY.PAD_T
	else return end
	y = math.max(0, y)
	pageBaits.CanvasPosition = Vector2.new(0, y * k)
	-- and again once the open pop (scale 0.9 -> 1 over 0.24s) has settled: a pixel canvas that
	-- is still growing, or was just re-flowed, can clamp the first write short
	task.delay(0.3, function()
		if BW.gui.Enabled and BW.scale.Scale > 0 then
			pageBaits.CanvasPosition = Vector2.new(0, y * BW.scale.Scale)
		end
	end)
end

function refreshAll()
	INV.setPills()
	refreshRods(); refreshBaits(); refreshBoosts()
	INV.sub.Text = subtitleFor(currentTab)
	-- the baits window has its own header to keep in step
	BW.setCash()
	BW.sub.Text = subtitleFor("baits")
end

-- react to anything changing our attributes from outside (roller rolls, shop uses)
plr.AttributeChanged:Connect(function(a)
	-- EquippedRod is the one that carries GAMEPLAY, so its stats are republished whatever
	-- changed it - not just the equip button. Anything that restores a saved loadout, or a
	-- future server hand-off, would otherwise leave GameClient reading a stale rod.
	if a == "EquippedRod" then publishRodStats() end
	-- remember the bait that just went UP (a roll, a buy): opening the window scrolls to it
	if a:match("^Bait_") then
		local v = plr:GetAttribute(a) or 0
		if v > (LAY.seen[a] or 0) then LAY.lastBait = a end
		LAY.seen[a] = v
	end
	-- GameClient spends a bait on every cast and clears EquippedBait on the last one, so
	-- the buffs have to be recomputed from out here too, not just from the EQUIP button.
	if a == "EquippedBait" or a:match("^Bait_") then publishBaitStats() end
	if a:match("^Bait_") or a:match("^Inv_") or a:match("^Fish_") or a:match("^Rod_")
		or a == "Coins" or a == "Pearls" or a == "EquippedBait" or a == "EquippedRod" then
		if gui.Enabled or BW.gui.Enabled then refreshAll() end
	end
end)

----------------------------------------------------------------------
-- decor + rod spin (obey Settings > Menu Animations)
----------------------------------------------------------------------
-- The Shop's sea behind the cards: soft light rays and rising bubbles in each window's Ocean layer (only the gaps
-- between cards show them). One loop for both windows, each piece idle while its own window is shut.
local FX = { bubbles = {}, rays = {} }
local function oceanFX(win, owner, count)
	for i, x in ipairs({ 0.12, 0.34, 0.58, 0.83 }) do
		local ray = UI.new("Frame", {
			Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, win.ocean)
		UI.new("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(FX.rays, { f = ray, g = owner, phase = i * 1.3 })
	end
	for i = 1, count do
		local s = 6 + (i * 7) % 13
		local b = UI.new("Frame", {
			Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, win.ocean)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		UI.new("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		local rec = { f = b, g = owner, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i }
		b.Position = UDim2.new(rec.x, 0, rec.y, 0)
		table.insert(FX.bubbles, rec)
	end
end
oceanFX(INV.win, gui, 22)
oceanFX(BW.win, BW.gui, 18)
RunService.RenderStepped:Connect(function(dt)
	if not (gui.Enabled or BW.gui.Enabled) then return end
	local t = os.clock()
	-- the hovered rod spin is content, the bubbles/rays are decor
	if spinning and spinning.cam then
		local off = CFrame.Angles(0, t * 0.9, 0) * (CAM_DIR * spinning.dist)
		spinning.cam.CFrame = CFrame.lookAt(spinning.centre + off, spinning.centre) * CFrame.Angles(0, 0, spinning.roll or 0)
	end
	if plr:GetAttribute("Set_MenuFX") == false then return end
	for _, b in ipairs(FX.bubbles) do
		if b.g.Enabled then
			b.y -= b.speed * dt
			if b.y < -0.05 then
				b.y = 1.05
				b.x = (b.x + 0.37) % 1
			end
			b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
		end
	end
	for _, r in ipairs(FX.rays) do
		if r.g.Enabled then r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase) end
	end
end)

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
local function close() gui.Enabled = false end
TouchKit.press(INV.win.close.button, close)
TouchKit.press(backdrop, close)

local function closeBaits() BW.gui.Enabled = false end
TouchKit.press(BW.win.close.button, closeBaits)
TouchKit.press(BW.backdrop, closeBaits)
-- RollerController's BAITS button fires this; it does not need to know how the window works.
make("BindableEvent", { Name = "Open" }, BW.gui).Event:Connect(function() BW.gui.Enabled = true end)
BW.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not BW.gui.Enabled then return end
	BW.fit(); refreshAll()
	-- synchronously, so it lands before the tutorial's own Enabled handler rings that card's EQUIP
	if LAY.lastBait then LAY.reveal(LAY.lastBait); LAY.lastBait = nil end
	local target = BW.scale.Scale
	BW.scale.Scale = target * 0.9
	TweenService:Create(BW.scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if BW.gui.Enabled then BW.fit() end
	end)
end

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
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		fit(); seedRods(); refreshAll(); selectTab(currentTab); setInventoryHidden(true)
		local target = uiscale.Scale
		uiscale.Scale = target * 0.9
		TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	else
		spinning = nil
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit() end end)
end
plr.CharacterAdded:Connect(function() task.wait(1); seedRods(); if gui.Enabled then refreshAll() end end)

----------------------------------------------------------------------
-- open hook
----------------------------------------------------------------------
-- Open the window, optionally on a NAMED TAB. Same shape as the BaitsMenu "Open" event
-- above, so outside widgets have one idiom to reach for.
--
-- Why a tab argument is needed at all: the Enabled handler re-applies selectTab(currentTab),
-- i.e. whichever tab you were on LAST - not the default. So a plain `gui.Enabled = true` from
-- the ProgressHUD's "next rod" chip would land on Boosts for anyone who had visited it, which
-- is not where that chip promised to take them. selectTab BEFORE enabling: it sets currentTab,
-- which the Enabled handler then re-applies, and it also works when the window is already open
-- (writing Enabled = true again fires no signal).
local openHook = gui:FindFirstChild("Open") or make("BindableEvent", { Name = "Open" }, gui)
openHook.Event:Connect(function(tab)
	if tab and pages[tab] then selectTab(tab) end
	gui.Enabled = true
end)

----------------------------------------------------------------------
-- dev hook
----------------------------------------------------------------------
local devHook = gui:FindFirstChild("DevInv") or make("BindableEvent", { Name = "DevInv" }, gui)
devHook.Event:Connect(function(a, b)
	if a == "__OPEN__" then
		gui.Enabled = true
	elseif a == "__CLEAR__" then
		refreshAll()
	elseif a == "__GIVE__" then
		for _, bt in ipairs(BAITS) do plr:SetAttribute("Bait_" .. akey(bt.name), (b or 5)) end
		for _, bs in ipairs(BOOSTS) do plr:SetAttribute("Inv_" .. bs.key, (b or 5)) end
		refreshAll()
	end
end)

----------------------------------------------------------------------
-- first paint
----------------------------------------------------------------------
seedRods()
-- lay both windows out once now (their build-time fits ran before the cards existed), so no card is painted unsized
LAY.inv(uiscale.Scale); LAY.baits(BW.scale.Scale)
selectTab(TAB_DEFS[1].name)
refreshAll()

print(string.format("[Inventory] built — %d rods, %d boosts, %d fish species  ·  [Baits] own window, %d baits", #RODS, #BOOSTS, #FishData.fish, #BAITS))
