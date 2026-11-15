--[==[
	UpgradesController - the Upgrades skill tree (StarterGui.UpgradesMenu). A FULL-SCREEN pannable / zoomable canvas,
	not a MenuFit window: START in the middle, eight branches folding outward in lockstep, one node per tier.

	2026-10-10 RESTYLE (owner: "rework the uis of all the buttons based on this theme that we have going ... nothing
	drastic has to change in terms of functionality, i just want it to look better"). The look moved off the
	2026-09-03 "cartoon reef" recipe (DEEP_TOP/MID/BOT water, white cards wearing a coloured ring) onto
	ReplicatedStorage.ShopKit, the Shop's sea-candy kit, so the tree belongs next to the Shop:
	  * a green header with a gloss cap and the Shop window's wave crest, the menu's emoji beside the gold gradient
	    title, your cash in a gold pill (the Shop's), and the red key X;
	  * the canvas is the sunny lagoon with the Shop's light rays and rising bubbles, over a sandy seabed;
	  * every node is a candy KEYCAP whose fill is its STATE - gold = owned, green = you can buy it now, grey = save up
	    (or locked) - with its branch's own candy colour on the icon disc, a check sticker once owned and a star sticker
	    on every 4th (milestone) tier; affordable nodes glow and breathe;
	  * branches are candy ropes with a hard drop, gold once the node they lead to is owned;
	  * the tooltip is a candy card (branch icon, name, tier, effect, blurb) with one state key: gold OWNED, green price,
	    grey price in red; zoom +/- are sea keys with DRAWN glyphs (never typed: see the X note in the 09-02 memory).
	Nothing the tree DOES changed: same nodes, names, geometry, prices, attributes, touch rules, hooks.
(Playtest verify, same day: desktop, the three tooltip states, click-to-buy, pan / zoom, the X, header taps and the
tutorial's SPEND ring on luck1 then its ring on the X all checked live. One fix: the legend's colour key says
"Gold: owned", not "Gold = owned" - at the phone legend's small size the INK outline filled the "=" into a block.)

	THE CONTRACT (what the rest of the place relies on - unchanged by the restyle):
	  * PlayerGui.UpgradesMenu stays the SAME instance and Enabled is the open/close signal (MenuLogic opens it,
	    MenuBlurManager blurs behind it, AudioController swishes on it, TutorialController and DailyController read it).
	  * Nodes are TextButtons named <branch><tier> ("luck1" ...) directly inside Container.Canvas, each with ONE UIScale
	    (TutorialController's nextLuckNode() rings the next luck node and breathes that UIScale every frame). The
	    default view fits the first ring, so luck1 is on screen the instant the window opens - layoutChrome() applies
	    that view while the menu is CLOSED too, because the tutorial measures the node on the first open frame.
	  * TutorialFreeUpg = "<branch><tier>" prices that one node at $0 (TutorialController's SPEND step); buy() clears it.
	  * The close X is the ONLY TextButton named "TextButton" here (Text "", 46-60 square, Frame children):
	    TutorialController's closeButtonOf() finds it by that shape.
	  * Upg_<key> attributes are the saved tiers; publish() writes the derived attributes the game reads (MaxDepth,
	    HookCapacity, UpgValueMult, UpgReelMult, UpgCatchRadius, UpgLuck, UpgIdleRate -> IdleClient / IdleServer,
	    UpgAuto). Money is leaderstats.Money (CurrencyClient) or the Coins attribute.
	  * DevUpgrade:Fire("__MAX__" | "__RESET__" | key, tier); ReplicatedStorage.RebirthRemotes.OnRebirth wipes the tree.
	  * Decor (bubbles, rays, glows) idles while the menu is shut or Set_MenuFX is false.
]==]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local plr = Players.LocalPlayer
local gui = script.Parent

-- ShopKit's builder: sets BorderSizePixel 0 on GuiObjects, then the props
local make = UI.new

local function roman(n)
	local vals = {{10,"X"},{9,"IX"},{5,"V"},{4,"IV"},{1,"I"}}
	local r = ""
	for _,v in ipairs(vals) do while n >= v[1] do r = r..v[2]; n = n - v[1] end end
	return r
end

local rgb = Color3.fromRGB
local V2 = Vector2.new
local INK = UI.INK

-- The look's own values, on ONE table: this chunk sits close to Luau's 200-locals-per-function register cap.
local K = {
	DOT = "  \u{00B7}  ",
	SAND = { rgb(255, 240, 184), rgb(234, 200, 124) },
	SAND_LIP = rgb(255, 248, 214),
	ROPE_OFF = { rgb(246, 252, 255), rgb(170, 214, 242) },   -- a rope leading to a node you do not own yet
	LOCKED = { rgb(188, 198, 216), rgb(116, 128, 154) },      -- (unreachable in play: see the 09-03 note on stateOf)
	GLOW_GOLD = rgb(255, 214, 60),
	GLOW_GREEN = rgb(150, 255, 110),
	HEAD = UI.HEAD.green,                                     -- the menu's header colour (spec table: green)
	EMOJI = "\u{2B06}\u{FE0F}",                               -- the MenuBar button's own emoji
	crestD = 26,
	compact = false,
}

-- Same in a TextScaled label AND its hard-drop twin (ShopKit's dropShadow clones the label, constraint and all, and
-- does not follow a later cap change - a phone title would otherwise draw its drop bigger than itself).
function K.setCap(lbl, v)
	for _, l in ipairs({ lbl, lbl.Parent and lbl.Parent:FindFirstChild(lbl.Name .. "Drop") }) do
		local c = l and l:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MinTextSize = 1
			c.MaxTextSize = v
		end
	end
end

-- 2026-07-19: every ladder was lengthened (*"add more levels to each upgrade, at least
-- 20 for some"*). 54 nodes -> 133. Two rules made the numbers, not taste:
--   1. PER-TIER STEPS SHRANK as counts grew, so the tree gained a lot of levels and
--      only about 2x end-game power rather than 2.5x per branch.
--   2. GROWTH HAD TO COME DOWN HARD. The old rates were tuned for 6-9 tiers; at 20
--      tiers growth 2.6 puts the last node at 2700 * 2.6^19 = ~$120 BILLION, against
--      a maxed income of ~$89M/hr. Long branches need growth ~1.5-1.6.
-- ⚠️ DEPTH IS CAPPED BY GEOMETRY, NOT BALANCE. GameClient adds the equipped rod's
-- RodDepth (+300 at rod 10) to this, the Mythic band bottoms out at -620 and the
-- painted column floor is -660. So the branch may contribute AT MOST 200:
-- 120 base + 200 + 300 = 620. 20 tiers x 10 studs lands exactly on it. If you add
-- tiers here you must also move BANDS and DepthStrata's column.
-- (2026-10-10: `candy` is the branch's ShopKit colour - its icon disc on every node and in the tooltip; `icon3d`
-- names the ReplicatedStorage.ShopIcons model the tooltip shows instead of the emoji, where one fits.)
local BRANCHES = {
	{ key="depth", name="Line Depth", short="Depth", angle=90, icon="⚓", candy="blue", base=2200, growth=1.56, count=20,
	  tip="Cast deeper to reach rarer, bigger fish.",
	  effect=function(t) return "+"..(10*t).." max depth" end },
	{ key="luck", name="Luck", short="Luck", angle=45, icon="🍀", candy="emerald", icon3d="clover", base=1500, growth=1.50, count=20,
	  tip="Improves your odds of hooking rare species.",
	  effect=function(t) return "+"..(3*t).."% rare chance" end },
	{ key="value", name="Fish Value", short="Value", angle=0, icon="💰", candy="orange", icon3d="moneybag", base=1400, growth=1.52, count=20,
	  tip="Every fish you sell is worth more cash.",
	  effect=function(t) return "+"..(7*t).."% sell value" end },
	-- ONE node, not six. The other five only shaved 12% off the pause between casts, which
	-- is not worth a node each - you buy auto-fishing once and you have it. growth is unused
	-- at count=1, so `base` IS the price and this is the only place it is set.
	-- PRICE 2026-09-03: $400K -> $120K. The note this replaces claimed $400K landed "around
	-- rod 4-5", but measured against ShopProducts.ROD_CASH - rod 4 $65K, rod 5 $140K, rod 6
	-- $450K - $400K was really a rod SIX purchase, two rungs later than intended, and it fell
	-- in the dead gap between zone 3 ($120K) and zone 4 ($900K). $120K puts the node where
	-- that note always said it should be: just under rod 5 and level with unlocking zone 3,
	-- one recognisable mid-game beat instead of a late one. It stays a real save-up at 17x
	-- rod 2 and 55x the first upgrade node - nothing like the discredited $7,500 tier-1,
	-- which was under two minutes of fishing at starting income.
	-- PRICE 2026-10-10: $120K -> $85K (the owner's call): between rod 4 ($65K) and zone 3 ($120K).
	{ key="auto", name="Auto Fishing", short="Auto", angle=-45, icon="🤖", candy="purple", base=85000, growth=1, count=1,
	  tip="Casts and reels for you, even while idle. Switch it on and off with the button on screen.",
	  effect=function(t) return "Unlock auto-cast" end },
	-- cap stays the SHORTEST ladder on purpose: every tier is a whole extra fish per
	-- cast, so it multiplies income more directly than anything else here. 14 tiers
	-- (capacity 17) is already 1.55x the old 8 (capacity 11); 20 would be too much.
	{ key="cap", name="Hook Capacity", short="Hooks", angle=-90, icon="🐟", candy="coral", icon3d="twofish", base=3000, growth=1.72, count=14,
	  tip="Hold more fish on a single cast.",
	  effect=function(t) return "+"..t.." fish per cast" end },
	{ key="magnet", name="Magnet", short="Magnet", angle=-135, icon="🧲", candy="red", base=1600, growth=1.52, count=18,
	  tip="Pulls nearby fish toward your hook.",
	  effect=function(t) return string.format("+%g catch radius", 1.5*t) end },
	{ key="reel", name="Reel Speed", short="Reel", angle=180, icon="🎣", candy="cyan", icon3d="reel", base=1300, growth=1.50, count=20,
	  tip="Reel your line back in faster.",
	  effect=function(t) return "+"..(5*t).."% reel speed" end },
	-- Replaced Rod Power ("+9% line strength"), whose only effect was shaving reel drag - it
	-- overlapped Reel Speed and had almost no bite left once the full-hook bolt capped drag.
	-- Deep Pockets banks cash while you are away instead: see IdleServer / IdleClient.
	{ key="pockets", name="Deep Pockets", short="Pockets", angle=135, icon="🏦", candy="rose", base=1500, growth=1.53, count=20,
	  tip="Your crew keeps fishing while you are offline.",
	  effect=function(t) return "$"..(20*t).."/min while away" end },
}

-- Currency: the ONE shared balance (leaderstats.Money if present, else the Coins
-- attribute) — the SAME money GameClient earns from fishing and the other menus spend,
-- so what you catch is spendable here. leaderstats.Money is created by CurrencyClient.
local function coinObject()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then return m end
	return nil
end
local function getBalance()
	local m = coinObject()
	if m then return m.Value end
	return plr:GetAttribute("Coins") or 0
end
local function spend(n)
	local m = coinObject()
	if m then pcall(function() m.Value = m.Value - n end)
	else plr:SetAttribute("Coins", (plr:GetAttribute("Coins") or 0) - n) end
end
local balance = getBalance()

-- ============ HEADER ============
-- The Shop window's header, run full width: the menu's green with a gloss cap, a wave crest of outlined scallops
-- hanging off its bottom edge, the menu's emoji + the gold gradient title on the left, the gold cash pill and the
-- red key X on the right. 76 tall on a desktop (the window kit's is 74); on a phone it IS the top-bar band
-- (layoutChrome).
local HEADER_H = 76
local header = make("Frame", { Name="Header", Size=UDim2.new(1,0,0,HEADER_H), BackgroundColor3=UI.WHITE, ZIndex=10 }, gui)
UI.vgrad(header, ColorSequence.new({
	ColorSequenceKeypoint.new(0, K.HEAD[1]), ColorSequenceKeypoint.new(0.7, K.HEAD[2]), ColorSequenceKeypoint.new(1, K.HEAD[2]),
}))
-- The bar catches its own taps: a silent transparent button under everything on it, so a tap on the header never
-- reaches the MenuBar rows (MainMenu, DisplayOrder 20) that sit beneath its right end. SndHooked is set before it is
-- parented, so AudioController leaves it alone; it is not "TextButton", so closeButtonOf ignores it.
do
	local guard = make("TextButton", { Name="ClickGuard", Text="", AutoButtonColor=false, BackgroundTransparency=1,
		Selectable=false, Size=UDim2.fromScale(1,1), ZIndex=1 })
	guard:SetAttribute("SndHooked", true)
	guard.Parent = header
end
UI.gloss(header, { frac=0.46, alpha=0.5, inset=5, radius=12, ZIndex=2 })

-- The wave crest: discs of the header's bottom colour, each INK-outlined, centred on the seam so only their lower
-- halves show (the header draws over the tops). They touch at a point (step = diameter), so no outline crosses a
-- scallop. Built off the LIVE width and rebuilt when it changes: this header is full-screen, so the count cannot be
-- a constant the way it is in the pop-up windows.
local crestHolder = make("Frame", { Name="Crest", BackgroundTransparency=1, Position=UDim2.fromOffset(0, HEADER_H),
	Size=UDim2.new(1,0,0,0), ZIndex=9 }, gui)
local function layCrest()
	for _, c in ipairs(crestHolder:GetChildren()) do c:Destroy() end
	local w = crestHolder.AbsoluteSize.X
	K.crestW, K.crestBuiltD = w, K.crestD
	if w < 40 then return end
	local D = K.crestD
	local n = math.ceil(w / D) + 1
	local x0 = math.floor((w - n * D) / 2)
	for i = 0, n - 1 do
		local disc = make("Frame", { Name="Wave", BackgroundColor3=K.HEAD[2], AnchorPoint=V2(0, 0.5),
			Position=UDim2.fromOffset(x0 + i * D, -1), Size=UDim2.fromOffset(D, D), ZIndex=9 }, crestHolder)
		make("UICorner", { CornerRadius=UDim.new(0.5, 0) }, disc)
		UI.stroke(disc, D >= 24 and 3.5 or 3)
	end
end
crestHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if crestHolder.AbsoluteSize.X ~= K.crestW then layCrest() end
end)
task.defer(layCrest)

-- the menu's emoji, big and tilted like the window kit's breakout icon (GothamBold: the face the MenuBar draws it in)
K.emoji = make("TextLabel", { Name="Icon", BackgroundTransparency=1, AnchorPoint=V2(0, 0.5), Position=UDim2.new(0,26,0.5,-3),
	Size=UDim2.fromOffset(66,66), Rotation=-8, Font=Enum.Font.GothamBold, Text=K.EMOJI, TextScaled=true, ZIndex=6 }, header)
local titleLbl = UI.label(header, "UPGRADES", { Name="Title", size=46, align="left", drop=4, outline=4.5/46,
	outlineColor=UI.TITLE.outline, AnchorPoint=V2(0, 0.5), Position=UDim2.new(0,100,0.5,-3), Size=UDim2.fromOffset(400,56), ZIndex=6 })
UI.vgrad(titleLbl, UI.TITLE.keys)

-- your cash, in the Shop's gold pill (a key that is not pressable)
K.pill = UI.candyKey(header, "gold", { Name="CashPill", static=true, Size=UDim2.fromOffset(196,48), AnchorPoint=V2(1, 0.5),
	Position=UDim2.new(1,-90,0.5,-3), ZIndex=7 })
function K.setCash(v, force)
	local s = UI.cash(v)
	if K.cashShown == s and not force then return end
	K.cashShown = s
	local c = K.compact
	K.pill.setParts(nil, { { icon="coins", size=c and 32 or 40, drop=0 }, { text=s, size=c and 22 or 28, o=c and 3 or 4, drop=2 } }, { gap=6 })
end
K.setCash(balance)

-- THE X: the kit's red key with a typed ASCII "X" (FredokaOne has that glyph; it is the ✕ U+2715 it lacks, which
-- once left this button a blank red square - never put that one back). It stays a TextButton named "TextButton":
-- TutorialController's closeButtonOf() finds every window's X by that shape (blank Text, 40-60 square, Frame kids).
K.close = UI.candyKey(header, "red", { Name="TextButton", Size=UDim2.fromOffset(60,60), AnchorPoint=V2(1, 0.5),
	Position=UDim2.new(1,-16,0.5,-3), ZIndex=8 })
K.close.set(nil, "X", 34)
local closeBtn = K.close.button

-- ============ CONTAINER + CANVAS ============
-- The Shop window's lagoon (UI.LAGOON: bright at the surface, deeper blue at the bottom) across the whole screen.
local container = make("Frame", { Name="Container", Position=UDim2.new(0,0,0,HEADER_H), Size=UDim2.new(1,0,1,-HEADER_H),
	BackgroundColor3=UI.WHITE, ClipsDescendants=true, Active=true, ZIndex=1 }, gui)
UI.vgrad(container, UI.LAGOON)

-- ============ OCEAN DECOR ============
-- ⚠️ LIVES IN THE CONTAINER, NOT THE CANVAS. The canvas is the thing that pans and zooms;
-- decor parented to it would slide off with the tree and scale with it, so light rays would
-- drift away and bubbles would grow to the size of nodes. The container is fixed and is the
-- thing that clips, so the water stays put behind a tree that moves over it - which is also
-- what sells the depth. ZIndex 0 keeps every piece behind the canvas (ZIndex 1) regardless
-- of child order. (2026-10-10: the Shop's rays and bubbles, the same recipe as its window's Ocean layer.)
local rays, bubbles = {}, {}
for i, x in ipairs({ 0.07, 0.24, 0.42, 0.6, 0.77, 0.94 }) do
	local r = make("Frame", { Name="Ray", BackgroundColor3=UI.WHITE, AnchorPoint=V2(0.5, 0), Position=UDim2.new(x,0,0,-60),
		Size=UDim2.new(0, 64 + (i % 2) * 44, 1.4, 0), Rotation=18, BackgroundTransparency=0.82, ZIndex=0 }, container)
	make("UIGradient", { Rotation=90, Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) }) }, r)
	rays[i] = { f = r, phase = i * 1.3 }
end
for i = 1, 26 do
	local s = 6 + (i * 7) % 13
	local b = make("Frame", { Name="Bubble", BackgroundColor3=UI.WHITE, BackgroundTransparency=0.78, AnchorPoint=V2(0.5, 0.5),
		Size=UDim2.fromOffset(s, s), ZIndex=0 }, container)
	make("UICorner", { CornerRadius=UDim.new(0.5, 0) }, b)
	make("UIStroke", { Color=UI.WHITE, Thickness=1.5, Transparency=0.35 }, b)
	bubbles[i] = { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, sp = 0.04 + (i % 5) * 0.012, wob = (i % 3) + 1, ph = i }
	b.Position = UDim2.fromScale(bubbles[i].x, bubbles[i].y)
end
-- A SANDY seabed, not a dark one: it reads as the floor of the lagoon rather than a letterbox bar, and the legend
-- sign sits on it. A pale rounded lip along the top makes the sand meet the water as a dune, not a ruled line.
local seabed = make("Frame", { Name="Seabed", BackgroundColor3=UI.WHITE, Size=UDim2.new(1,0,0,58), Position=UDim2.new(0,0,1,-58), ZIndex=0 }, container)
UI.vgrad(seabed, K.SAND)
local sandLip = make("Frame", { Name="SandLip", BackgroundColor3=K.SAND_LIP, Size=UDim2.new(1,0,0,8), Position=UDim2.new(0,0,1,-60), ZIndex=0 }, container)
UI.corner(sandLip, 4)

local canvas = make("Frame", { Name="Canvas", AnchorPoint=V2(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Active=true, ZIndex=1 }, container)
local zoom = make("UIScale", { Scale=0.9 }, canvas)

-- ⚠️ THE HEADER LIVES IN THE TOP-BAR BAND; IT IS NOT PUSHED UNDER IT. The old fix for
-- Roblox's top bar covering the title shoved the whole header down by the inset on short
-- screens. On a 375-tall phone that cost 58 + 76 = 134px (36% of the screen) before a single
-- node, and left a 58px strip ABOVE the header where the fishing HUD showed through. What the
-- bar really occupies is only its LEFT end - GuiService.TopbarInset is the free part of the
-- band (measured x 208..right on every simulated device, laptop included). So the header now
-- starts at y=0 on every screen, the title starts where Roblox's buttons end (it sat right
-- under them at x=26, desktop too), and on a phone the header IS the band. layoutChrome()
-- (with the zoom controls, further down) owns all of it and re-runs on any viewport change.
local headerBottom = HEADER_H   -- gui-local y where the header ends; the tooltip clamps read it
local defaultZoom               -- forward: defined with the zoom controls; START and open use it
local autoZoom = true           -- still at the fitted default (no manual zoom since opening)

local function P(dx,dy) return UDim2.new(0.5, dx, 0.5, dy) end

-- A candy keycap face inside `holder` (a transparent button or frame): the INK hard drop, a white rim with the INK
-- outline, the state-coloured fill with a gloss cap. Returns the fill (recolour it with UI.vgrad).
function K.keycap(holder, radius, colours, dropPx)
	UI.hardShadow(holder, radius, 4, dropPx or 6, 1)
	local rim = make("Frame", { Name="Rim", BackgroundColor3=UI.WHITE, Size=UDim2.fromScale(1,1), ZIndex=2 }, holder)
	UI.corner(rim, radius)
	UI.stroke(rim, 4)
	local fill = make("Frame", { Name="Fill", BackgroundColor3=UI.WHITE, Position=UDim2.fromOffset(3,3), Size=UDim2.new(1,-6,1,-6), ZIndex=1 }, rim)
	UI.corner(fill, math.max(radius - 3, 2))
	UI.vgrad(fill, colours)
	UI.gloss(fill, { frac=0.46, alpha=0.5, inset=2, radius=math.max(radius - 5, 2), ZIndex=2 })
	return fill, rim
end

-- A round icon disc in a branch's candy colour: white rim, INK outline, the emoji on it. Returns disc, fill, emoji.
function K.disc(parent, size, candy, emoji, props)
	local disc = make("Frame", { Name="Disc", BackgroundColor3=UI.WHITE, Size=UDim2.fromOffset(size, size), ZIndex=3 }, parent)
	for k, v in pairs(props or {}) do disc[k] = v end
	make("UICorner", { CornerRadius=UDim.new(0.5, 0) }, disc)
	UI.stroke(disc, 3)
	local fill = make("Frame", { Name="Fill", BackgroundColor3=UI.WHITE, AnchorPoint=V2(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
		Size=UDim2.new(1,-6,1,-6), ZIndex=1 }, disc)
	make("UICorner", { CornerRadius=UDim.new(0.5, 0) }, fill)
	UI.vgrad(fill, UI.CANDY[candy] or UI.CANDY.blue)
	local e = make("TextLabel", { Name="Emoji", BackgroundTransparency=1, AnchorPoint=V2(0.5,0.5), Position=UDim2.fromScale(0.5,0.53),
		Size=UDim2.fromScale(0.62,0.62), Font=Enum.Font.GothamBold, Text=emoji or "", TextScaled=true, ZIndex=2 }, disc)
	return disc, fill, e
end

-- ============ START NODE ============
-- The hub the eight branches radiate from, so it gets to be the loudest thing on the
-- canvas: a gold glow that breathes (driven in the RenderStepped loop) behind a big GOLD keycap.
-- Everything else on the tree is deliberately quieter than this.
local startHalo = make("ImageLabel", { Name="Halo", AnchorPoint=V2(0.5,0.5), Position=P(0,0), Size=UDim2.fromOffset(196,196),
	BackgroundTransparency=1, Image=UI.ICONS.glow or "", ImageColor3=K.GLOW_GOLD, ImageTransparency=0.35, ZIndex=5 }, canvas)
local startNode = make("TextButton", { Name="START", AnchorPoint=V2(0.5,0.5), Position=P(0,0), Size=UDim2.fromOffset(96,96),
	BackgroundTransparency=1, AutoButtonColor=false, Text="", ZIndex=6 }, canvas)
UI.pressFeel(startNode, make("UIScale", { Scale=1 }, startNode))
K.keycap(startNode, 24, UI.BRICK.gold, 7)
make("TextLabel", { Name="Emoji", Size=UDim2.fromOffset(44,44), AnchorPoint=V2(0.5,0), Position=UDim2.new(0.5,0,0,10),
	BackgroundTransparency=1, Font=Enum.Font.GothamBold, Text="\240\159\142\163", TextScaled=true, ZIndex=4 }, startNode)
local startTxt = UI.label(startNode, "START", { Name="StartLabel", size=18, drop=2, AnchorPoint=V2(0.5,1),
	Position=UDim2.new(0.5,0,1,-11), Size=UDim2.new(1,-16,0,24), ZIndex=5 })
K.setCap(startTxt, 18)

-- ============ GENERATE BRANCHES (twisty paths) ============
local records = {}
-- Tiers PERSIST on the player as Upg_<key> attributes, and every purchase re-publishes
-- the derived gameplay attributes below. Those derived attributes are the entire
-- contract with the rest of the game: GameClient and InventoryController read them and
-- never look at this menu. Same "attribute is the seam" convention as ZoneCoinMult and
-- the Set_<key> settings.
local stateByKey = {}
-- ⚠️ CLAMP ON THE WAY IN. A tier above b.count is not a cosmetic lie: publish()
-- multiplies it straight into MaxDepth, and a depth tier of 400 sends the hook to
-- -4120 - far below the painted column floor of -660 - leaving the player in an
-- empty black void with fish swimming in nothing. Also coerces junk (nil / NaN /
-- a string) rather than trusting whatever is sitting on the attribute.
local function saneTier(v, count)
	local n = tonumber(v) or 0
	if n ~= n then n = 0 end                -- NaN
	return math.clamp(math.floor(n), 0, count)
end
for _,b in ipairs(BRANCHES) do
	stateByKey[b.key] = saneTier(plr:GetAttribute("Upg_"..b.key), b.count)
end

local BASE_DEPTH, BASE_CAP = 120, 3
local function publish()
	local t = stateByKey
	-- 8/tier when the rarity ladder bottomed out at -240; the ladder now runs to -620, so
	-- +72 across the whole branch would have been rounding error next to the rods. GameClient
	-- ADDS the equipped rod's RodDepth to this.
	-- ⚠️ These coefficients MUST match the effect() strings in BRANCHES above - they
	-- are what the player was promised. Both were rescaled together on 2026-07-19.
	plr:SetAttribute("MaxDepth",       BASE_DEPTH + 10 * t.depth) -- "+10 max depth"  (20 tiers -> 320, +rod 300 = 620)
	plr:SetAttribute("HookCapacity",   BASE_CAP + t.cap)          -- "+1 fish per cast" (14 tiers -> 17)
	plr:SetAttribute("UpgValueMult",   1 + 0.07 * t.value)        -- "+7% sell value"   (20 tiers -> +140%)
	plr:SetAttribute("UpgReelMult",    1 + 0.05 * t.reel)         -- "+5% reel speed"   (20 tiers -> +100%)
	plr:SetAttribute("UpgCatchRadius", 1.5 * t.magnet)            -- "+1.5 catch radius" (18 tiers -> 27)
	plr:SetAttribute("UpgLuck",        0.03 * t.luck)             -- "+3% rare chance"  (20 tiers -> +60%)
	-- cash per SECOND banked while offline; IdleClient reports it to IdleServer, which is
	-- what actually persists it and pays it out on your next join
	plr:SetAttribute("UpgIdleRate",    (20 / 60) * t.pockets)     -- "$20/min while away" (20 tiers -> $400/min)
	plr:SetAttribute("UpgAuto",        t.auto)                    -- 0 = off, 1+ = auto-cast
	for _,b in ipairs(BRANCHES) do plr:SetAttribute("Upg_"..b.key, t[b.key]) end
end

-- A branch link is a candy ROPE: a 12px pill with the INK outline and a cylinder shade across it (the gradient
-- turns with the frame), over its own INK hard drop 4px lower. Gold once the node it leads to is owned.
-- Returns the rope and its drop - they show and hide together (setLine).
local function addLine(dx1,dy1,dx2,dy2)
	local mx,my = (dx1+dx2)/2, (dy1+dy2)/2
	local ddx,ddy = dx2-dx1, dy2-dy1
	local len = math.sqrt(ddx*ddx+ddy*ddy)
	local ang = math.deg(math.atan2(ddy,ddx))
	local drop = make("Frame", { Name="RopeDrop", AnchorPoint=V2(0.5,0.5), Position=P(mx,my+4), Size=UDim2.fromOffset(len+8,12),
		Rotation=ang, BackgroundColor3=INK, ZIndex=1, Visible=false }, canvas)
	UI.corner(drop, 6); UI.stroke(drop, 3)
	local line = make("Frame", { Name="Rope", AnchorPoint=V2(0.5,0.5), Position=P(mx,my), Size=UDim2.fromOffset(len+8,12),
		Rotation=ang, BackgroundColor3=UI.WHITE, ZIndex=2, Visible=false }, canvas)
	UI.corner(line, 6); UI.stroke(line, 3)
	UI.vgrad(line, K.ROPE_OFF)
	return line, drop
end
local function setLine(rec, v)
	if rec.line then rec.line.Visible = v end
	if rec.lineDrop then rec.lineDrop.Visible = v end
end

-- ⚠️ BRANCHES SWITCH BACK NOW, THEY DO NOT RUN STRAIGHT OUT. stepLen had already been
-- pulled 150 -> 128 to shorten the run, but a straight 20-node ladder still put the last
-- node 2616px from the hub: one and a half screens of dragging to reach the end of a
-- branch, which is unpleasant even with the pan working properly. Folding each branch
-- inside its own lane puts the outermost node at 1258px - same node count, same spacing,
-- half the travel.
--
-- ⚠️ THE LANE IS CAPPED IN PIXELS, NOT DEGREES. A wedge keeps widening with radius, so
-- a weave inside one has to take ever longer strides to cross it - measured, an angular
-- weave stretched the stride from 128 to 329 studs at the far end while the near end
-- stayed tight. A pixel lane folds at a constant width, so the stride stays constant.
-- Near the hub the wedge is narrower than the cap, so the first tiers run straight out
-- and the folding only begins once there is room for it.
--
-- ⚠️ ALL EIGHT BRANCHES FOLD IN LOCKSTEP. That is what holds them exactly 45 deg apart
-- at every radius, and it is the whole reason nothing collides - do NOT give them
-- per-branch phases. (A true equal-arc spiral was tried and is strictly worse: curl it
-- enough to be compact and neighbouring arms' nodes at DIFFERENT radii run into each
-- other - 53px min gap at maxR 1039, i.e. nodes overlapping outright.)
--
-- ⚠️ THE LANE IS INSET BY A NODE HALF-WIDTH, and that is not a detail. Tapering the
-- lane as a plain FRACTION of the wedge looks right and is not: near the hub the wedge
-- is only a couple of hundred px across, so two NEIGHBOURING branches both leaning to
-- the same side closed to 10px of each other at tier 2-3 while every angular measure
-- still said they were a clean 45 deg apart. Subtracting the node's own half-width from
-- the lane makes the clearance a property of the geometry instead of a guess.
--
-- ⚠️ MEASURE CLEARANCE BETWEEN THE NODE RECTANGLES, NOT BETWEEN THEIR CENTRES. Centre
-- distance lies badly here: two boxes 119px apart centre-to-centre can be 1px apart edge
-- to edge, because a 45-degree branch splits its 128px stride into dx=dy=90 against a
-- combined half-width of 89. Judged on centres this layout looked fine at 119 vs 128;
-- judged on boxes it was touching.
--
-- The two numbers that matter, over all 133 nodes, as clear air between rectangles:
--   consecutive nodes on one branch   4px   (straight layout: 2px - it always did this,
--                                            diagonal branches nearly touch by design)
--   nodes with no connection at all  39px   (straight layout: 40px)
-- So the fold is fractionally CLEANER than the straight tree while cutting the distance
-- to the outermost node from 2616px to 1379px.
-- (2026-10-10: the keycaps are drawn INSIDE those same 84x90 / 94x100 boxes, so every number above still holds;
-- only their INK outline and hard drop reach past the box, as every candy piece's do.)
local startGap, stepLen = 184, 128
local LANE_MAX, LAT_STEP, MIN_DR, LANE_INSET = 220, 124, 26, 60
local WEDGE = math.sin(math.rad(22.5))          -- half-angle of one branch's own wedge
for bi,b in ipairs(BRANCHES) do
	local baseRad = math.rad(b.angle)
	local r, lat, dir = startGap, 0, 1
	local px,py = 0,0
	local prevx,prevy = 0,0
	for t=1,b.count do
		local th = baseRad + lat / r
		px = math.cos(th) * r
		py = -math.sin(th) * r
		local line, lineDrop = addLine(prevx,prevy,px,py)
		local milestone = (t % 4 == 0)
		local W = milestone and 94 or 84
		local H = milestone and 100 or 90
		-- ⚠️ THE GLOW IS A SIBLING OF THE NODE, NOT A CHILD. Under ZIndexBehavior.Sibling a
		-- child ALWAYS draws above its parent whatever its ZIndex, so a glow parented to the
		-- node would cover the very key it is meant to sit behind. As a sibling at ZIndex 3 it
		-- lands under the node (4) and over the ropes (2), which is exactly the stack we want.
		-- (A soft ShopKit glow image tinted by state, not a rounded box.)
		local glow = make("ImageLabel", { Name="Glow_"..b.key..t, AnchorPoint=V2(0.5,0.5), Position=P(px,py),
			Size=UDim2.fromOffset(W+56,H+56), BackgroundTransparency=1, Image=UI.ICONS.glow or "", ImageTransparency=1,
			ZIndex=3, Visible=false }, canvas)
		-- The node: a transparent TextButton named <branch><tier> holding a candy keycap. Its ONE UIScale is the
		-- tutorial's (it breathes it) and the reveal / buy pop's; hover and press squash it too (ShopKit's feel).
		local node = make("TextButton", { Name=b.key..t, AnchorPoint=V2(0.5,0.5), Position=P(px,py), Size=UDim2.fromOffset(W,H),
			BackgroundTransparency=1, AutoButtonColor=false, Text="", ZIndex=4, Visible=false }, canvas)
		local nodeScale = make("UIScale", { Scale=1 }, node)
		local fill = K.keycap(node, 18, UI.BRICK.grey, 6)
		local disc = K.disc(node, milestone and 48 or 44, b.candy, b.icon, { AnchorPoint=V2(0.5,0), Position=UDim2.new(0.5,0,0,9) })
		local nameLbl = UI.label(node, b.short.." "..t, { Name="Name", size=15, AnchorPoint=V2(0.5,1), Position=UDim2.new(0.5,0,1,-8),
			Size=UDim2.new(1,-10,0,22), ZIndex=4 })
		local nameMax = nameLbl:FindFirstChildOfClass("UITextSizeConstraint")
		nameMax.MinTextSize = 1
		-- owned: the green check sticker on the top-right corner (ShopKit's check badge, small)
		local badge = make("Frame", { Name="Owned", AnchorPoint=V2(1,0), Position=UDim2.new(1,-3,0,3), Size=UDim2.fromOffset(24,24),
			BackgroundColor3=UI.WHITE, ZIndex=5, Visible=false }, node)
		make("UICorner", { CornerRadius=UDim.new(0.5,0) }, badge)
		UI.stroke(badge, 2.5)
		UI.vgrad(badge, { rgb(150,250,100), rgb(40,190,40) })
		UI.icon(badge, "check", UDim2.fromScale(0.74,0.74), { Name="Tick", AnchorPoint=V2(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), ZIndex=2, flat=true })
		-- Every 4th node is a milestone and used to be marked ONLY by being 10px bigger, which
		-- nobody notices. It wears ShopKit's glossy star sticker on its top-left corner (an image,
		-- so no glyph question at all - ★ U+2605 is the one FredokaOne cannot draw).
		if milestone then
			UI.icon(node, "star", 26, { Name="Star", Position=UDim2.fromOffset(1,1), Rotation=-12, ZIndex=5, flat=true })
		end
		UI.pressFeel(node, nodeScale)
		local cost = math.floor(b.base * (b.growth ^ (t-1)))
		table.insert(records, { inst=node, scale=nodeScale, glow=glow, fill=fill, disc=disc, name=nameLbl, nameMax=nameMax, badge=badge,
			line=line, lineDrop=lineDrop, branch=b, tier=t, cost=cost, milestone=milestone, wasVisible=false })
		prevx,prevy = px,py
		-- advance: spend up to LAT_STEP of this step sideways and the rest outward, so
		-- the node-to-node distance stays stepLen however hard the branch is folding.
		-- MIN_DR is what stops a fold that is running fully sideways from stalling at one
		-- radius and laying the next pass on top of the last.
		local lane = math.min(LANE_MAX, math.max(r * WEDGE - LANE_INSET, 0))
		local target = dir * lane
		local dlat = math.clamp(target - lat, -LAT_STEP, LAT_STEP)
		lat = lat + dlat
		if math.abs(lat - target) < 1e-9 then dir = -dir end
		r = r + math.max(math.sqrt(math.max(stepLen*stepLen - dlat*dlat, 0)), MIN_DR)
	end
end

-- ============ CURSOR TOOLTIP ============
-- A candy card (the Shop's row recipe, in the sea-blue "reef" candy for every branch so its white / lime / red
-- text always reads): the branch's icon over a soft glow (its 3D ShopIcons model where one fits, else its emoji
-- on a disc in the branch colour), the name and tier, the effect in lime (a gain), the blurb, and ONE state key -
-- gold OWNED, green price (you can buy it), grey price in red (not yet). Sized by hand from the measured text
-- (TIP.layout), never by AutomaticSize + UIListLayout: see the 09-03 note about gloss() growing that combination.
local TIP = { W = 256, PAD = 14, ICON = 52 }
local tip = make("Frame", { Name="Tip", BackgroundTransparency=1, Size=UDim2.fromOffset(TIP.W, 220), Visible=false, ZIndex=70 }, gui)
UI.hardShadow(tip, 18, 4, 6, 1)
TIP.face = make("Frame", { Name="Face", BackgroundColor3=UI.WHITE, Size=UDim2.fromScale(1,1), ZIndex=2 }, tip)
UI.corner(TIP.face, 18); UI.stroke(TIP.face, 4); UI.vgrad(TIP.face, UI.CANDY.reef)
UI.gloss(TIP.face, { frac=0.24, alpha=0.4, inset=4, radius=14, ZIndex=1 })
TIP.glow = make("ImageLabel", { Name="Glow", BackgroundTransparency=1, Image=UI.ICONS.glow or "", AnchorPoint=V2(0.5,0.5),
	Position=UDim2.fromOffset(TIP.PAD + TIP.ICON/2, TIP.PAD + TIP.ICON/2), Size=UDim2.fromOffset(96,96), ImageTransparency=0.2, ZIndex=3 }, tip)
TIP.disc, TIP.discFill, TIP.emoji = K.disc(tip, TIP.ICON, "blue", "", { Position=UDim2.fromOffset(TIP.PAD, TIP.PAD), ZIndex=4 })
TIP.icon3d = UI.icon(tip, "none", 66, { Name="Icon", Position=UDim2.fromOffset(TIP.PAD - 7, TIP.PAD - 9), ZIndex=5, Visible=false })
do
	local x1 = TIP.PAD + TIP.ICON + 10
	local inner = TIP.W - 2 * TIP.PAD
	TIP.name = UI.label(tip, "", { Name="TipName", size=24, align="left", drop=2, Position=UDim2.fromOffset(x1, TIP.PAD - 1),
		Size=UDim2.fromOffset(TIP.W - x1 - TIP.PAD, 30), ZIndex=6 })
	TIP.tier = UI.label(tip, "", { Name="TipTier", size=16, align="left", color=UI.TEXT.soft, Position=UDim2.fromOffset(x1, TIP.PAD + 30),
		Size=UDim2.fromOffset(TIP.W - x1 - TIP.PAD, 22), ZIndex=6 })
	TIP.effect = UI.label(tip, "", { Name="TipEffect", size=21, align="left", color=UI.TEXT.lime, drop=2,
		Position=UDim2.fromOffset(TIP.PAD, TIP.PAD + TIP.ICON + 8), Size=UDim2.fromOffset(inner, 28), ZIndex=6 })
	TIP.desc = UI.label(tip, "", { Name="TipDesc", size=15, scaled=false, align="left", color=UI.TEXT.soft, TextWrapped=true,
		TextYAlignment=Enum.TextYAlignment.Top, Size=UDim2.fromOffset(inner, 20), ZIndex=6 })
	TIP.key = UI.candyKey(tip, "green", { Name="PriceKey", static=true, Size=UDim2.fromOffset(inner, 46), ZIndex=6 })
	TIP.hint = UI.label(tip, "", { Name="TipHint", size=16, Size=UDim2.fromOffset(inner, 22), ZIndex=6 })
	TIP.inner = inner
end
-- the branch's look on the card: its 3D model if ShopIcons has one (and it has replicated), else its emoji disc
function TIP.setBranch(b)
	if TIP.branch == b then return end
	TIP.branch = b
	UI.vgrad(TIP.discFill, UI.CANDY[b.candy] or UI.CANDY.blue)
	TIP.emoji.Text = b.icon
	local models = ReplicatedStorage:FindFirstChild("ShopIcons")
	local model = b.icon3d and models and models:FindFirstChild(b.icon3d)
	local has = model ~= nil and model:IsA("Model")
	TIP.disc.Visible = not has
	TIP.icon3d.Visible = has
	if has and TIP.icon3dName ~= b.icon3d then
		TIP.icon3dName = b.icon3d
		UI.setIcon(TIP.icon3d, b.icon3d)
	end
end
-- stack the lines under the icon row and size the card to them (the blurb wraps: measured, not guessed)
function TIP.layout()
	local y = TIP.PAD + TIP.ICON + 8 + 28 + 2
	local th = TextService:GetTextSize(TIP.desc.Text, 15, Enum.Font.FredokaOne, V2(TIP.inner, 1000)).Y
	TIP.desc.Position = UDim2.fromOffset(TIP.PAD, y)
	TIP.desc.Size = UDim2.fromOffset(TIP.inner, th + 2)
	y += th + 12
	TIP.key.button.Position = UDim2.fromOffset(TIP.PAD, y)
	y += 46 + 6
	if TIP.hint.Visible then
		TIP.hint.Position = UDim2.fromOffset(TIP.PAD, y + 4)
		y += 4 + 22
	end
	tip.Size = UDim2.fromOffset(TIP.W, y + TIP.PAD)
end

-- ============ LEGEND ============
-- A sea-blue candy sign on the seabed: how to move around, and what the three key colours mean. On a phone it is a
-- small sign in the bottom-left corner instead of a line across the seabed (the long strip ran under the zoom
-- buttons and sat on top of cap1). layoutChrome() writes its text and size.
K.legend = UI.block(container, "sea", { Name="LegendCard", Size=UDim2.fromOffset(600,42), AnchorPoint=V2(0.5,1),
	Position=UDim2.new(0.5,0,1,-10), ZIndex=15, lip=6, radius=14, highlight={ top=3, inset=12, height=4 } })
K.legendLbl = UI.label(K.legend.face, "", { Name="Legend", size=16, RichText=true, Size=UDim2.new(1,-28,1,0),
	Position=UDim2.fromOffset(14,0), ZIndex=2 })
K.KEYWORDS = '<font color="#FFDE50">Gold</font>: owned' .. K.DOT .. '<font color="#AAFF64">Green</font>: buy now'
local LEGEND_DESKTOP = "Drag to pan" .. K.DOT .. "Scroll to zoom" .. K.DOT .. "Hover for info" .. K.DOT .. K.KEYWORDS
	.. K.DOT .. '<font color="#D8DEE8">Grey</font>: save up'

-- ============ LOGIC ============
local hoveredRec = nil

local function stateOf(rec)
	local s = stateByKey[rec.branch.key]
	if rec.tier <= s then return "owned"
	elseif rec.tier == s+1 then return "avail"
	else return "locked" end
end

-- The ONE tutorial freebie. TutorialController names the node its SPEND step points at
-- ("luck1") in TutorialFreeUpg for as long as that step is live, and that node alone prices
-- at $0 - so "Buy a Luck upgrade." can always be done, whatever the first haul paid. buy()
-- clears it the moment it is taken, so it is ONE upgrade, never the whole ladder. Every
-- price read goes through here; rec.cost stays the real price.
local function costOf(rec)
	if plr:GetAttribute("TutorialFreeUpg") == rec.branch.key .. rec.tier then return 0 end
	return rec.cost
end

-- The keycap's FILL is the state, the house grammar for every key (ShopKit's BRICK colours):
--   OWNED  gold key, check sticker, gold rope in, a soft gold glow
--   AVAIL  green key when you can afford it (its glow BREATHES - the RenderStepped loop below),
--          grey key when you cannot yet ("save up"), with a faint white glow so the frontier still reads
--   LOCKED a darker grey key (unreachable in play: a locked node is never visible, see the memory note)
-- The branch keeps its identity on the icon disc, which never changes colour.
local function styleNode(rec)
	local st = stateOf(rec)
	local afford = st == "avail" and balance >= costOf(rec)
	rec.afford = afford
	local look = st == "owned" and "owned" or (st == "avail" and (afford and "buy" or "save")) or "locked"
	if rec.look == look then return end
	rec.look = look
	UI.vgrad(rec.fill, look == "owned" and UI.BRICK.gold or look == "buy" and UI.BRICK.green or look == "save" and UI.BRICK.grey or K.LOCKED)
	rec.badge.Visible = look == "owned"
	rec.name.TextTransparency = look == "locked" and 0.3 or 0
	rec.glow.ImageColor3 = look == "owned" and K.GLOW_GOLD or look == "buy" and K.GLOW_GREEN or UI.WHITE
	rec.glowRest = look == "owned" and 0.55 or look == "buy" and 0.3 or look == "save" and 0.7 or 1
	if look ~= "buy" then rec.glow.ImageTransparency = rec.glowRest end   -- (a "buy" glow is driven by the pulse)
	if rec.line then UI.vgrad(rec.line, look == "owned" and UI.BRICK.gold or K.ROPE_OFF) end
end

local function reveal(rec)
	rec.inst.Visible = true
	rec.glow.Visible = true
	setLine(rec, true)
	local s = rec.inst:FindFirstChildOfClass("UIScale")
	if s then s.Scale = 0.35; TweenService:Create(s, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
	-- the glow has no UIScale of its own (it would double the instance count for 0.3s of
	-- polish), so it fades up instead of popping - which reads fine behind a node that pops
	rec.glow.ImageTransparency = 1
	TweenService:Create(rec.glow, TweenInfo.new(0.4), { ImageTransparency = rec.glowRest or 0.6 }):Play()
end

local showTip   -- forward: refresh() re-draws a tip that is already up
local tipFor    -- the record the visible tip describes
local availList = {}
local function refresh()
	balance = getBalance()
	availList = {}
	for _,rec in ipairs(records) do
		styleNode(rec)
		local vis = rec.tier <= stateByKey[rec.branch.key] + 1
		if vis and not rec.wasVisible then
			reveal(rec)
		elseif not vis then
			rec.inst.Visible = false
			rec.glow.Visible = false
			setLine(rec, false)
		end
		rec.wasVisible = vis
		if vis and stateOf(rec) == "avail" then table.insert(availList, rec) end
	end
	K.setCash(balance)
	-- the card follows the money too: a node that just became affordable turns green on the card as well
	if tip.Visible and tipFor and tipFor.inst.Visible then showTip(tipFor) end
end

showTip = function(rec)
	local b, st = rec.branch, stateOf(rec)
	tipFor = rec
	TIP.setBranch(b)
	TIP.name.Text = b.name
	TIP.tier.Text = "Tier " .. roman(rec.tier) .. K.DOT .. rec.tier .. "/" .. b.count
	TIP.effect.Text = b.effect(rec.tier)
	TIP.desc.Text = b.tip
	local key = TIP.key
	local hint, hintColour = nil, UI.TEXT.soft
	-- Always the same two pieces (an icon, then a word), so the key re-uses its slots instead of rebuilding them.
	if st == "owned" then
		key.recolour("gold")
		key.setParts(nil, { { icon="check", size=32 }, { text="OWNED", size=26 } }, { gap=8 })
	elseif st == "avail" then
		local cost = costOf(rec)
		local afford = balance >= cost
		key.recolour(afford and "green" or "grey")
		key.setParts(nil, { { icon="coins", size=34 },
			{ text=cost == 0 and "FREE!" or UI.cash(cost), size=cost == 0 and 28 or 26, color=(not afford) and UI.TEXT.red or nil } }, { gap=6 })
		-- On touch the first tap opened this card and a SECOND one commits, so say so.
		if afford then
			hint, hintColour = TouchKit.wanted() and "Tap again to buy" or "Click to buy", UI.TEXT.lime
		else
			hint, hintColour = "Not enough cash", UI.TEXT.red
		end
	else
		key.recolour("grey")
		key.setParts(nil, { { icon="lock", size=30 }, { text=UI.cash(rec.cost), size=24 } }, { gap=6 })
		hint = "Locked - buy the tier before it first"
	end
	TIP.hint.Visible = hint ~= nil
	TIP.hint.Text = hint or ""
	TIP.hint.TextColor3 = hintColour
	TIP.layout()
	tip.Visible = true
end

-- can't afford it: the cash pill flashes red and jumps
local function flashMoney()
	local l = K.pill.label
	if l then
		l.TextColor3 = UI.TEXT.red
		TweenService:Create(l, TweenInfo.new(0.5), { TextColor3 = UI.WHITE }):Play()
	end
	UI.punch(K.pill.scale, 1.12, 0.3)
end

local function buy(rec)
	if not rec or stateOf(rec) ~= "avail" then return end
	local cost = costOf(rec)
	if getBalance() < cost then flashMoney(); return end
	spend(cost)
	-- The freebie is spent: cleared here, with the spend, so it can never pay for a second node.
	if cost ~= rec.cost then plr:SetAttribute("TutorialFreeUpg", nil) end
	stateByKey[rec.branch.key] = rec.tier
	publish()
	refresh()
	local s = rec.inst:FindFirstChildOfClass("UIScale")
	if s then s.Scale = 1.3; TweenService:Create(s, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
end

-- TOUCH: a phone has no hover, so on touch this whole tree used to be unreadable AND
-- dangerous - the tooltip (name, effect, cost, "Click to buy") is only ever shown from
-- MouseEnter, while MouseButton1Click bought the node outright. One tap on a phone spent
-- your money on an upgrade whose effect and price you had never been shown.
--
-- So on touch the first tap SELECTS (pins the tip beside the node) and only a second tap
-- on the SAME node buys. Desktop keeps hover-to-inspect, click-to-buy, untouched.
local TOUCH = TouchKit.wanted()
local pinnedRec = nil

-- Park the tip beside the node rather than under a finger that has already lifted.
-- ⚠️ AbsolutePosition is measured from the BOTTOM of the top bar, but the tip is a child of
-- an IgnoreGuiInset ScreenGui whose Position is measured from the SCREEN top - feeding one
-- into the other (as this used to) parked the tip 58px above its node on a phone. Taking
-- away the ScreenGui's own AbsolutePosition converts exactly, notch insets included.
-- Re-run every frame while pinned, so the card follows its node through a pan or a pinch;
-- returns false when the node has been panned out of the tree's frame.
local function placePinned(rec)
	local origin, area = gui.AbsolutePosition, gui.AbsoluteSize
	local np, ns = rec.inst.AbsolutePosition - origin, rec.inst.AbsoluteSize
	local cp, cs = container.AbsolutePosition - origin, container.AbsoluteSize
	local cx, cy = np.X + ns.X / 2, np.Y + ns.Y / 2
	if cx < cp.X or cx > cp.X + cs.X or cy < cp.Y or cy > cp.Y + cs.Y then return false end
	local sx, sy = tip.AbsoluteSize.X, tip.AbsoluteSize.Y
	local px = np.X + ns.X + 12
	if px + sx > area.X - 6 then px = np.X - sx - 12 end
	if px < 6 then px = 6 end
	local py = np.Y + ns.Y / 2 - sy / 2
	local top = headerBottom + math.floor(K.crestD / 2) + 6   -- clear the header and its crest
	py = math.clamp(py, top, math.max(top, area.Y - sy - 12))
	tip.Position = UDim2.fromOffset(math.floor(px), math.floor(py))
	return true
end

local function pinTip(rec)
	pinnedRec = rec
	hoveredRec = rec
	showTip(rec)
	placePinned(rec)
end

for _,rec in ipairs(records) do
	rec.inst.MouseEnter:Connect(function()
		if TOUCH then return end
		if not rec.inst.Visible then return end
		hoveredRec = rec
		showTip(rec)
	end)
	rec.inst.MouseLeave:Connect(function()
		if TOUCH then return end
		if hoveredRec == rec then hoveredRec = nil; tip.Visible = false end
	end)
	TouchKit.press(rec.inst, function()
		if TOUCH then
			if pinnedRec ~= rec then
				pinTip(rec)          -- first tap: show me what this is
				return
			end
			if stateOf(rec) == "avail" then buy(rec) end
			pinTip(rec)              -- keep it up so the new state is visible
			return
		end
		if stateOf(rec) == "avail" then
			buy(rec)
			if hoveredRec == rec then showTip(rec) end
		end
	end)
end

startNode.MouseButton1Click:Connect(function()
	autoZoom = true
	TweenService:Create(canvas, TweenInfo.new(0.3), { Position = UDim2.new(0.5,0,0.5,0) }):Play()
	TweenService:Create(zoom, TweenInfo.new(0.3), { Scale = defaultZoom() }):Play()
end)

-- ============ PAN + ZOOM ============
-- ⚠️ THE DRAG STARTS ON THE CONTAINER, NOT THE CANVAS. The canvas is the thing that
-- MOVES: a GuiObject only gets InputBegan for presses inside its own rect, and that
-- rect walks out from under the pointer as you pan. Past roughly a screen's worth of
-- travel there was nothing left under the cursor to grab, so the tree became
-- unpannable in exactly the direction you had been going and the far half of a branch
-- was unreachable - you could still SEE the nodes, because the canvas does not clip,
-- which is what made it look like the drag had broken rather than moved. It is worse
-- than it sounds even at rest: UIScale 0.9 leaves the canvas 80px inside the container
-- on every side before you pan at all, and at the 0.20 zoom floor it covers a fifth of
-- it. The container is fixed, is the thing that clips, and (verified) still receives
-- InputBegan from every descendant, so nothing that used to start a drag stopped.
-- Fixing it here rather than by enlarging the canvas because the pan is unclamped:
-- no finite canvas is big enough, but the container always is.
local zoomBox     -- built further down, with the zoom controls
local dragging, dragStart, canvasStart = false, Vector2.new(), Vector2.new()
-- The zoom buttons are the one thing in the container that must NOT also grab the
-- canvas - they used to be immune for the wrong reason (they are siblings of the
-- canvas, not children), and a press that both zooms and starts a drag slides the
-- tree by whatever jitter is in the click. A rect test rather than ordering games
-- between the two InputBegan handlers: io.Position and AbsolutePosition are the same
-- screen space here (measured), and this only runs on a press.
local function overZoom(io)
	if not zoomBox then return false end
	local p, s = zoomBox.AbsolutePosition, zoomBox.AbsoluteSize
	local x, y = io.Position.X, io.Position.Y
	return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end
-- TOUCH: a tap on open water (not a drag, not a node) puts the pinned tip away - on a phone
-- it otherwise sat over the tree until you tapped another node. Every GuiButton on the canvas
-- but START counts as a node, TouchKit's pads included, because a pad tap PINS its node.
local pressOnNode = false
local function overNode(io)
	local x, y = io.Position.X, io.Position.Y
	for _, c in ipairs(canvas:GetChildren()) do
		if c:IsA("GuiButton") and c.Visible and c ~= startNode then
			local p, s = c.AbsolutePosition, c.AbsoluteSize
			if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then return true end
		end
	end
	return false
end
container.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
		if overZoom(io) then return end
		dragging = true
		dragStart = Vector2.new(io.Position.X, io.Position.Y)
		canvasStart = Vector2.new(canvas.Position.X.Offset, canvas.Position.Y.Offset)
		pressOnNode = TOUCH and overNode(io) or false
	end
end)
-- ⚠️ THE PAN IS CLAMPED TO THE TREE. Unclamped, the canvas can be dragged until every
-- node is off-frame and the panel is a blank rectangle - nothing to aim at, and the
-- START node that re-centres the view has gone with it, so the only way back is to
-- guess a direction and drag until something appears. The bound lets the OUTERMOST
-- node be pushed PAN_SLACK past the middle of the container and no further: every
-- node stays reachable, an empty screen stops being reachable.
--
-- ⚠️⚠️ THIS IS A 2D CONDITION AND CANNOT BE DONE AS TWO 1D CLAMPS. The obvious
-- version - clamp x to the node extent, clamp y to the node extent - is wrong here,
-- because the tree is EIGHT THIN BRANCHES radiating from the middle, not a filled
-- rectangle, and a bounding box round a star is mostly empty corners. Measured on a
-- maxed tree: axis clamps happily allowed pan (-2396, 2405), the bottom-left corner
-- of the box, with ZERO of the 134 nodes on screen - the rightmost node was centred
-- horizontally and far off vertically, the lowest node the other way about. The
-- condition that actually matters is "is any node still on screen", so test that.
--
-- ⚠️ VISIBLE nodes only. The tree reveals one tier past what you own, so early on 9
-- of 133 nodes are drawn and the other 124 sit out along branches up to 2540px long;
-- bounding by all of them clamps to a frontier that has not been drawn yet.
--
-- ⚠️ The two live in DIFFERENT units: a node's offset is canvas-local and therefore
-- scaled by the UIScale, while the pan offset moves the canvas inside the container
-- and is NOT. A node sits at `pan + offset*zoom.Scale` from the container centre.
--
-- Out of bounds does not REFUSE the drag - it projects the requested pan back onto
-- the circle of radius `limit` around the nearest node, so the view slides along the
-- boundary and rubber-bands to the branch instead of stopping dead. Being a pure
-- function of (x, y) is also what lets the zoom hook below re-apply it: zooming out
-- shrinks every offset, and a pan that was legal at 1.7 has to be pulled back in at
-- 0.20 without a drag ever happening.
local function setPan(x, y)
	local s = zoom.Scale
	-- a node this close to the middle is always inside the panel; the panel is far
	-- wider than tall, so the height is what binds
	local limit = math.max(math.min(container.AbsoluteSize.X, container.AbsoluteSize.Y) * 0.5 - 60, 140)
	local bestD, bestX, bestY = math.huge, 0, 0
	for _, rec in ipairs(records) do
		if rec.inst.Visible then
			local nx = rec.inst.Position.X.Offset * s
			local ny = rec.inst.Position.Y.Offset * s
			local dx, dy = x + nx, y + ny
			local d = dx * dx + dy * dy
			if d < bestD then bestD, bestX, bestY = d, nx, ny end
		end
	end
	if bestD > limit * limit and bestD < math.huge then
		local k = limit / math.sqrt(bestD)
		x = (x + bestX) * k - bestX
		y = (y + bestY) * k - bestY
	end
	canvas.Position = UDim2.new(0.5, x, 0.5, y)
end

-- Zooming OUT shrinks the bound, so a pan that was legal at 1.7 is off the end at
-- 0.20 and the tree would drift out of frame without a drag ever happening. Hooking
-- the property rather than each caller catches the wheel, the +/- buttons (which
-- TWEEN the scale, so one re-clamp after the call would use the old value) and the
-- pinch, in one place.
zoom:GetPropertyChangedSignal("Scale"):Connect(function()
	setPan(canvas.Position.X.Offset, canvas.Position.Y.Offset)
end)

UIS.InputChanged:Connect(function(io)
	if not gui.Enabled then return end
	if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
		local d = Vector2.new(io.Position.X, io.Position.Y) - dragStart
		setPan(canvasStart.X + d.X, canvasStart.Y + d.Y)
	elseif io.UserInputType == Enum.UserInputType.MouseWheel then
		-- floor pulled down for the longer ladders: at 20 tiers a branch runs ~2540px,
		-- so 0.4 could not show even one whole branch. 0.20 fits the horizontal ones
		-- entirely and most of the vertical ones; the rest is what panning is for.
		autoZoom = false
		zoom.Scale = math.clamp(zoom.Scale + io.Position.Z * 0.1, 0.20, 1.7)
	end
end)
UIS.InputEnded:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
		if dragging and TOUCH and pinnedRec and not pressOnNode and gui.Enabled
			and (Vector2.new(io.Position.X, io.Position.Y) - dragStart).Magnitude < 10 then
			pinnedRec = nil; hoveredRec = nil; tip.Visible = false
		end
		dragging = false
	end
end)

-- ZOOM CONTROLS. Zoom used to be MouseWheel ONLY, so on a phone the tree could be panned
-- but never zoomed: you were stuck at the 0.9 opening scale, and the longer ladders run
-- ~2540px, so most of a branch was simply unreachable. Two buttons work everywhere, and
-- pinch is wired underneath them for the devices that have it.
-- (2026-10-10: sea candy keys. Their + and - are DRAWN - two pill bars over an INK copy a little bigger - so they
-- never depend on a glyph, and the minus is exactly the plus's crossbar. The box is a plain fixed Frame laid out by
-- hand, no UIListLayout: TouchKit's pad rule.)
local function setZoom(v)
	autoZoom = false
	local target = math.clamp(v, 0.20, 1.7)
	TweenService:Create(zoom, TweenInfo.new(0.12), { Scale = target }):Play()
end
zoomBox = make("Frame", { Name="ZoomControls", AnchorPoint=V2(1,1), Position=UDim2.new(1,-16,1,-16),
	Size=UDim2.fromOffset(56,126), BackgroundTransparency=1, ZIndex=40 }, container)
local function zoomBtn(name, plus, delta)
	local k = UI.candyKey(zoomBox, "sea", { Name=name, Size=UDim2.fromOffset(56,56), ZIndex=40 })
	local glyph = make("Frame", { Name="Glyph", BackgroundTransparency=1, Size=UDim2.fromScale(1,1), ZIndex=4 }, k.text)
	for _, layer in ipairs({ { INK, 6, 1 }, { UI.WHITE, 0, 2 } }) do
		for _, rot in ipairs(plus and { 0, 90 } or { 0 }) do
			local bar = make("Frame", { Name="Bar", BackgroundColor3=layer[1], AnchorPoint=V2(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
				Size=UDim2.new(0.46,layer[2],0.13,layer[2]), Rotation=rot, ZIndex=layer[3] }, glyph)
			make("UICorner", { CornerRadius=UDim.new(0.5,0) }, bar)
		end
	end
	TouchKit.press(k.button, function() setZoom(zoom.Scale + delta) end)
	return k.button
end
local zoomInBtn = zoomBtn("ZoomIn", true, 0.18)
local zoomOutBtn = zoomBtn("ZoomOut", false, -0.18)

local pinchBase = nil
UIS.TouchPinch:Connect(function(_, pinchScale, _, state)
	if not gui.Enabled then return end
	if state == Enum.UserInputState.Begin then
		pinchBase = zoom.Scale
	elseif state == Enum.UserInputState.Change and pinchBase then
		autoZoom = false
		zoom.Scale = math.clamp(pinchBase * pinchScale, 0.20, 1.7)
	else
		pinchBase = nil
	end
end)

-- ============ SCREEN FIT (phone / tablet / desktop) ============
-- The tree is a full-screen canvas, not a MenuFit window, so it never got the phone pass the
-- pop-up menus did: it was sized for a laptop and simply cropped on a phone. Measured on an
-- iPhone 7 (667x375): header 134px of 375, the tree opened at 0.9 with luck1 half under the
-- header and magnet1 / auto1 / cap1 off the bottom, the legend line ran under the zoom
-- buttons, and it said "Scroll to zoom / Hover for info" on a touch screen.
-- "Compact" = a PHONE (short side < 500), read from the live viewport and re-read on every
-- change. The desktop branch is today's look, bar the title moving out from under Roblox's
-- top-left buttons.
-- The first ring - START plus the eight tier-1 nodes, +-229 canvas px tall - plus the keycaps' outline and hard
-- drop (+10) and room for the header's crest scallops (+14 a side). The default view fits exactly this, so every
-- branch's first node is on screen when the menu opens: luck1 included, which the tutorial rings WITHOUT panning.
local RING_SPAN = 2 * (184 + 45 + 10) + 2 * 14

defaultZoom = function()
	local area = gui.AbsoluteSize
	if area.X < 2 or area.Y < 2 then
		local cam = workspace.CurrentCamera
		area = cam and cam.ViewportSize or Vector2.new(1366, 768)
	end
	local h, w = area.Y - headerBottom, area.X
	return math.clamp(math.min((h - 16) / RING_SPAN, (w - 16) / RING_SPAN, 0.9), 0.45, 0.9)
end

-- ⚠️ A TextScaled caption's UITextSizeConstraint caps the RENDERED size - it applies AFTER
-- the canvas UIScale, not before (measured: cap 20 -> 19px bounds and cap 17 -> 16px at zoom
-- 0.646; cap 15 -> 15px at 0.9). So on a phone a fixed cap did two wrong things at once: the
-- short names ("Luck 1") sat at the full cap while the long ones ("Pockets 1") were squeezed
-- by their box, and the ring read as two font sizes (19 vs 12px bounds on an iPhone 7).
-- Tying the cap to the zoom makes every caption scale with the node it is on; 20 x zoom is
-- what the widest tier-1 name fills in its 80px box, so they all land on one size. Desktop
-- keeps its fixed 15 / 18.
local compactNow, captionCap = false, nil
local function fitCaptions()
	local cap = compactNow and math.max(8, math.floor(20 * zoom.Scale + 0.5)) or 15
	if cap == captionCap then return end
	captionCap = cap
	for _, rec in ipairs(records) do rec.nameMax.MaxTextSize = cap end
	K.setCap(startTxt, compactNow and math.max(8, math.floor(24 * zoom.Scale + 0.5)) or 18)
end
zoom:GetPropertyChangedSignal("Scale"):Connect(fitCaptions)

local function layoutChrome()
	local cam = workspace.CurrentCamera
	local area = gui.AbsoluteSize
	if (area.X < 2 or area.Y < 2) and cam then area = cam.ViewportSize end
	if area.X < 2 or area.Y < 2 then return end
	local vp = cam and cam.ViewportSize or area
	local compact = math.min(vp.X, vp.Y) < 500
	local wasTouch = TOUCH
	TOUCH = TouchKit.wanted()
	-- a pinned (touch) tip must not turn into a hover tip stuck to the mouse, or vice versa
	if TOUCH ~= wasTouch then pinnedRec = nil; hoveredRec = nil; tip.Visible = false end
	local inset = GuiService:GetGuiInset().Y
	local tb = GuiService.TopbarInset
	local robloxRight = (tb.Height > 0 and tb.Max.X > tb.Min.X) and tb.Min.X or 0
	local wasCompact = K.compact
	K.compact = compact

	-- HEADER: always from y=0. On a phone it is exactly the top-bar band (58px).
	local hh = compact and math.max(inset, 52) or HEADER_H
	local midY = compact and 0 or -3
	headerBottom = hh
	header.Position = UDim2.new(0, 0, 0, 0)
	header.Size = UDim2.new(1, 0, 0, hh)
	container.Position = UDim2.new(0, 0, 0, hh)
	container.Size = UDim2.new(1, 0, 1, -hh)
	-- the crest: smaller scallops on the phone's shorter band
	K.crestD = compact and 20 or 26
	crestHolder.Position = UDim2.fromOffset(0, hh)
	if K.crestBuiltD ~= K.crestD then layCrest() end
	-- the X (46 on a phone: the band is 58 and its drop must stay inside it) and the cash pill left of it
	local closeR = compact and 10 or 16
	local xs = compact and 46 or 60
	closeBtn.Size = UDim2.fromOffset(xs, xs)
	closeBtn.Position = UDim2.new(1, -closeR, 0.5, midY)
	if K.closeShown ~= xs then
		K.closeShown = xs
		K.close.set(nil, "X", compact and 27 or 34)
	end
	local chipW, chipH = compact and 150 or 196, compact and 38 or 48
	local chipR = closeR + xs + (compact and 10 or 14)
	K.pill.button.Position = UDim2.new(1, -chipR, 0.5, midY)
	K.pill.button.Size = UDim2.fromOffset(chipW, chipH)
	if wasCompact ~= compact or not K.cashShown then K.setCash(balance, true) end
	-- the emoji and the title start where Roblox's own top-bar buttons end
	local left = (inset > 0 and robloxRight > 0) and math.max(26, robloxRight + 12) or 26
	local em = compact and 44 or 66
	K.emoji.Position = UDim2.new(0, left, 0.5, midY)
	K.emoji.Size = UDim2.fromOffset(em, em)
	local tx = left + em + (compact and 6 or 8)
	titleLbl.Position = UDim2.new(0, tx, 0.5, midY)
	titleLbl.Size = UDim2.fromOffset(math.clamp(area.X - chipR - chipW - 12 - tx, 80, 420), compact and 40 or 56)
	K.setCap(titleLbl, compact and 30 or 46)

	-- LEGEND + SEABED
	if compact then
		seabed.Size = UDim2.new(1, 0, 0, 34); seabed.Position = UDim2.new(0, 0, 1, -34)
		sandLip.Position = UDim2.new(0, 0, 1, -36)
		local l1 = TOUCH and "Drag to pan" .. K.DOT .. "Pinch to zoom" or "Drag to pan" .. K.DOT .. "Scroll to zoom"
		local l2 = TOUCH and "Tap a node, tap again to buy" or "Hover for info, click to buy"
		local l3 = K.KEYWORDS
		local l4 = '<font color="#D8DEE8">Grey</font>: save up'
		-- 14px with a slightly thinner outline and a little leading: at 13px the INK outline filled the gap in "=" so
		-- "Gold = owned" drew as "Gold [block] owned" (hence the colons). The widest line at 14 is 175px - the same card
		-- width the 13px "=" text had, so it still clears magnet1 on a 667-wide phone.
		local w = 0
		for _, l in ipairs({ l1, l2, l3, l4 }) do w = math.max(w, UI.textWidth(l, 14)) end
		local lbl = K.legendLbl
		lbl.Text = l1 .. "\n" .. l2 .. "\n" .. l3 .. "\n" .. l4
		lbl.TextScaled = false
		lbl.TextSize = 14
		lbl.LineHeight = 1.05
		lbl.Outline.Thickness = 0.1
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Size = UDim2.new(1, -24, 1, 0)
		lbl.Position = UDim2.fromOffset(12, 0)
		local root = K.legend.root
		root.AnchorPoint = V2(0, 1)
		root.Position = UDim2.new(0, 10, 1, -8)
		root.Size = UDim2.fromOffset(math.ceil(w) + 30, math.ceil(4 * 14 * 1.05) + 14 + 6)
	else
		seabed.Size = UDim2.new(1, 0, 0, 58); seabed.Position = UDim2.new(0, 0, 1, -58)
		sandLip.Position = UDim2.new(0, 0, 1, -60)
		local text = TOUCH and ("Drag to pan" .. K.DOT .. "Pinch to zoom" .. K.DOT .. "Tap a node for info, tap again to buy"
			.. K.DOT .. K.KEYWORDS .. K.DOT .. '<font color="#D8DEE8">Grey</font>: save up') or LEGEND_DESKTOP
		local lbl = K.legendLbl
		lbl.Text = text
		lbl.TextScaled = true
		lbl.LineHeight = 1
		lbl.Outline.Thickness = 0.13
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.Size = UDim2.new(1, -28, 1, 0)
		lbl.Position = UDim2.fromOffset(14, 0)
		local root = K.legend.root
		root.AnchorPoint = V2(0.5, 1)
		root.Position = UDim2.new(0.5, 0, 1, -10)
		-- as wide as the line wants at 16px, but never under the zoom buttons (56 + 16 margin + 14 air, both sides)
		local want = math.ceil(UI.textWidth(text, 16)) + 40
		root.Size = UDim2.fromOffset(math.max(math.min(want, area.X - 2 * (56 + 16 + 14)), 200), 42)
	end

	-- ZOOM BUTTONS: 56px + 8 on a 317px-tall phone tree was 38% of its height
	local zb, zg, zm = compact and 46 or 56, compact and 6 or 8, compact and 10 or 16
	zoomBox.Position = UDim2.new(1, -zm, 1, -zm)
	zoomBox.Size = UDim2.fromOffset(zb, zb * 2 + zg + 6)   -- (+6: the lower key's hard drop)
	zoomInBtn.Size = UDim2.fromOffset(zb, zb); zoomInBtn.Position = UDim2.fromOffset(0, 0)
	zoomOutBtn.Size = UDim2.fromOffset(zb, zb); zoomOutBtn.Position = UDim2.fromOffset(0, zb + zg)

	-- NODE CAPTIONS: a slightly smaller disc buys a taller, wider caption box on a phone (sizes:
	-- fitCaptions). Node size and the fold geometry are untouched - the clearances noted above
	-- assume 84x90.
	for _, rec in ipairs(records) do
		rec.name.Size = compact and UDim2.new(1, -6, 0, 26) or UDim2.new(1, -10, 0, 22)
		rec.name.Position = compact and UDim2.new(0.5, 0, 1, -6) or UDim2.new(0.5, 0, 1, -8)
		local ds = rec.milestone and (compact and 42 or 48) or (compact and 38 or 44)
		rec.disc.Size = UDim2.fromOffset(ds, ds)
		rec.disc.Position = compact and UDim2.new(0.5, 0, 0, 7) or UDim2.new(0.5, 0, 0, 9)
	end
	compactNow = compact
	captionCap = nil
	fitCaptions()

	-- Applied while CLOSED too, so the tree already sits at its opening view when the menu is
	-- enabled: the tutorial measures luck1 the instant the window opens, and a node still at
	-- the previous zoom was measured where it no longer was.
	if autoZoom then zoom.Scale = defaultZoom() end
end
layoutChrome()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutChrome)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutChrome)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutChrome)

-- breathe the affordable nodes' glows + the decor + follow the cursor with the tooltip
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then tip.Visible = false; return end
	local t = os.clock()
	local a = 0.5 + 0.5 * math.sin(t * 4)
	-- The affordable nodes BREATHE: their green glow swells and fades. (A node's UIScale is NOT touched here: the
	-- tutorial writes that one every frame while it rings luck1, and two per-frame writers would fight.)
	for _,rec in ipairs(availList) do
		if rec.afford then rec.glow.ImageTransparency = 0.55 - 0.37 * a end
	end
	-- the hub's glow breathes on a slower, offset beat so the two do not throb in lockstep
	startHalo.ImageTransparency = 0.42 - 0.24 * (0.5 + 0.5 * math.sin(t * 2.2))
	-- ocean decor. Gated on Settings > Menu Animations exactly like every other menu's decor.
	if plr:GetAttribute("Set_MenuFX") ~= false then
		for _, bd in ipairs(bubbles) do
			bd.y -= bd.sp * math.min(dt, 0.1)
			if bd.y < -0.06 then
				bd.y = 1.06
				bd.x = (bd.x + 0.37) % 1
			end
			bd.f.Position = UDim2.new(bd.x, math.sin(t * bd.wob + bd.ph) * 6, bd.y, 0)
		end
		for _, r in ipairs(rays) do r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase) end
	end
	-- on touch the tip is PINNED beside the node it belongs to (see pinTip); it must not be
	-- dragged around by GetMouseLocation, which on a phone is just wherever you last tapped
	if TOUCH then
		if pinnedRec and pinnedRec.inst.Visible then
			tip.Visible = placePinned(pinnedRec)
		else
			pinnedRec = nil; hoveredRec = nil; tip.Visible = false
		end
		return
	end
	if hoveredRec and hoveredRec.inst.Visible then
		local m = UIS:GetMouseLocation()
		local vp = workspace.CurrentCamera.ViewportSize
		local sx, sy = tip.AbsoluteSize.X, tip.AbsoluteSize.Y
		local px, py = m.X + 18, m.Y + 16
		if px + sx > vp.X - 6 then px = m.X - sx - 14 end
		if py + sy > vp.Y - 12 then py = m.Y - sy - 18 end
		if px < 6 then px = 6 end
		local top = headerBottom + math.floor(K.crestD / 2) + 4
		if py < top then py = top end
		tip.Position = UDim2.fromOffset(px, py)
	else
		if hoveredRec then hoveredRec = nil end
		tip.Visible = false
	end
end)

-- ============ OPEN / CLOSE ============
TouchKit.press(closeBtn, function() gui.Enabled = false end)
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		autoZoom = true
		layoutChrome()   -- the screen (and touch vs mouse) may have changed since it last ran
		canvas.Position = UDim2.new(0.5,0,0.5,0)
		zoom.Scale = defaultZoom()
		hoveredRec = nil
		pinnedRec = nil
		tip.Visible = false
		refresh()   -- pick up any money earned while the menu was closed
	else
		-- back to the opening view while closed (see layoutChrome): nothing moves on the next open
		autoZoom = true
		canvas.Position = UDim2.new(0.5,0,0.5,0)
		zoom.Scale = defaultZoom()
	end
end)

-- keep the header + affordability live with the shared balance while the tree is open
local function bindMoney()
	local m = coinObject()
	if m then m.Changed:Connect(function() if gui.Enabled then refresh() end end) end
end
bindMoney()
plr.ChildAdded:Connect(function(c)
	if c.Name == "leaderstats" then task.wait(0.2); bindMoney(); if gui.Enabled then refresh() end end
end)
plr:GetAttributeChangedSignal("Coins"):Connect(function() if gui.Enabled then refresh() end end)
-- The tutorial's freebie arriving or being taken re-colours its node (grey -> green) and
-- re-prices a tooltip that is already up over it.
plr:GetAttributeChangedSignal("TutorialFreeUpg"):Connect(function()
	if not gui.Enabled then return end
	refresh()
	if hoveredRec then showTip(hoveredRec) end
end)

-- Dev hook, same convention as DevRoll / DevZone / DevDiscover / DevCast.
--   DevUpgrade:Fire("__MAX__")      -> every branch maxed
--   DevUpgrade:Fire("depth", 5)     -> set one branch to a tier
--   DevUpgrade:Fire("__RESET__")    -> back to zero
local devUp = Instance.new("BindableEvent")
devUp.Name = "DevUpgrade"
devUp.Parent = gui
devUp.Event:Connect(function(key, tier)
	if key == "__MAX__" then
		for _,b in ipairs(BRANCHES) do stateByKey[b.key] = b.count end
	elseif key == "__RESET__" then
		for _,b in ipairs(BRANCHES) do stateByKey[b.key] = 0 end
	elseif stateByKey[key] ~= nil then
		-- clamped to the branch length for the same reason as the loader above
		local branch
		for _,b in ipairs(BRANCHES) do if b.key == key then branch = b end end
		stateByKey[key] = saneTier(tier or 1, branch and branch.count or 0)
	end
	publish()
	refresh()
end)

-- ============ REBIRTH WIPE ============
-- Rebirthing washes the whole tree back to tier 0. This is what the rebirth
-- confirm dialog has always promised ("your upgrades ... wash away with the
-- tide") but nothing actually did: doRebirth only reset cash, so a maxed tree
-- survived every rebirth and each new Tide Current multiplier stacked on top
-- of it instead of replacing it.
--
-- The wipe lives HERE, not in RebirthController, because publish() owns the
-- derived-attribute formulas (MaxDepth, HookCapacity, UpgValueMult, UpgAuto...).
-- A second copy of them in the rebirth menu would drift silently the first time
-- a coefficient is retuned. RebirthController only announces the event; this
-- script decides what resetting an upgrade means. For the same reason the reset
-- must republish, not just zero Upg_*: stored tiers are the save, the derived
-- attributes are what the game reads, and clearing only the former leaves the
-- player at +140% sell value on 620m of line with an empty tree.
--
-- Visuals need no extra work. refresh() drops every node above tier 1 out of
-- `vis` and hides it, clearing wasVisible so reveal() tweens it back on the
-- re-buy; a pinned or hovered tooltip aimed at a node that just vanished is
-- dropped by the RenderStepped loop above, which already tests inst.Visible.
--
-- AutoCastOn is deliberately left alone. UpgAuto drops to 0, which is what
-- GameClient's autoOn() gates on, so auto-cast stops and its button hides --
-- while the player's own on/off preference survives for when they re-buy it.
-- WaitForChild (with a timeout, so a missing folder warns nothing) because this
-- LocalScript can win the race against ReplicatedStorage replicating on join.
task.spawn(function()
	local rr = game:GetService("ReplicatedStorage"):WaitForChild("RebirthRemotes", 10)
	local ev = rr and rr:WaitForChild("OnRebirth", 10)
	if not (ev and ev:IsA("BindableEvent")) then return end
	ev.Event:Connect(function()
		for _,b in ipairs(BRANCHES) do stateByKey[b.key] = 0 end
		publish()
		refresh()
	end)
end)

publish()   -- apply saved tiers to the game on join, before anything reads them
refresh()
