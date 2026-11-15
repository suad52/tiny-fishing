--[==[
	BoatsController - buy and sail the 8 boats in BoatData.

	A sibling of ZonesController: same card states (active / owned / buy / locked), same
	strictly-linear gate, same economy plumbing onto the shared leaderstats.Money balance.
	If you change one, look at the other.

	WHAT IT OWNS: `Boat_<id>` ownership and `CurrentBoat`. That is ALL it writes.
	BoatClient watches CurrentBoat and does the rest - stats, and swapping the hull in the
	world. This menu never touches Workspace, which is why buying a boat cannot leave the
	stage in a broken state if something in here throws.

	PREVIEWS ARE REAL 3D BOATS, not painted Frames like the Zones cards: a boat is a shape,
	and a flat mini-diorama of one would be a worse lie the bigger the hull got. They are
	built through BoatBuilder's `simple` mode (~70 parts instead of ~250) and only for cards
	that have actually been scrolled into view - eight full-detail hulls live in eight
	ViewportFrames would be ~2000 parts rendering every frame behind the menu.

	2026-10-10 - THE LOOK MOVED ONTO ReplicatedStorage.ShopKit (the owner: "rework the uis of all
	the buttons based on this theme that we have going"). The old reef recipe - DEEP_TOP/MID/BOT
	panels, thin Gotham body copy, a hand-drawn X - no longer matched the Shop, Daily and Gifts
	windows beside it. Now: UI.window (lagoon body, BLUE header with a wave crest, gold title, the
	sailboat breaking out of the top-left corner, the red key X - a TextButton named "TextButton",
	which is how TutorialController's closeButtonOf finds it); the Shop's gold cash pill; each boat
	a candy card in its own UI.CANDY colour (warm timber -> the abyss; a locked card is grey) with
	the real 3D hull kept in its painted sea well; ONE candyKey per card coloured by STATE - gold
	SAILING, green SAIL, green price you can afford, grey price you can't (in red), grey LOCKED;
	bubbles and light rays in the ocean layer. The star on NEXT (U+2605, which never drew in
	FredokaOne) and the tick on SAILING (U+2713, the same text-presentation family) became a
	ShopKit sticker and the kit's check image. Behaviour is untouched: the attributes, the spend,
	DevBoat, the MenuBar badge, TouchKit.press, MenuFit (MIN_H 440) and the phone reflow.
	COMPACT_ROW 350 -> 360: a candy card carries a hard drop, so a compact row is the 90 px header
	band + a 256 cell + 12. Pre-restyle source: ServerStorage.MenuBackup_PreCandy_2026-10-10.

	Test hook: `BoatsMenu.DevBoat` BindableEvent.
	  :Fire("__ALL__")  grant every boat (does not sail one)
	  :Fire(n)          grant boat n and sail it
	  :Fire("__RESET__")back to the rowboat, everything else revoked
]==]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- The look: the Shop's kit - window, candy cards, keys, chips and labels. Shared by every menu:
-- never edit it from here; anything Boats needs that it lacks is built locally below.
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))

local plr = Players.LocalPlayer
local gui = script.Parent

local BoatData    = require(ReplicatedStorage:WaitForChild("BoatData"))
local BoatBuilder = require(ReplicatedStorage:WaitForChild("BoatBuilder"))

local rgb, V2 = Color3.fromRGB, Vector2.new
local make = UI.new

----------------------------------------------------------------------
-- look
----------------------------------------------------------------------
local LOOK = {
	-- one UI.CANDY colour per boat (the colour is the ITEM; the key carries the STATE), warm
	-- timber at the bottom of the ladder up to the abyss at the top
	colour = { "orange", "coral", "teal", "cyan", "blue", "royal", "purple", "cosmic" },
	locked = { rgb(208, 216, 230), rgb(116, 130, 156) },     -- a locked card is grey, whatever the boat
	lockVeil = { rgb(156, 170, 198), rgb(86, 100, 132) },    -- the slate veil over a locked hull
	-- The preview well: sunny sky over the sea as ONE gradient with a hard stop at 64% - the line
	-- framePreview lands the waterline on. One fill keeps the well's rounded corners rounded (a
	-- separate sea Frame pokes its square corners out of them: ClipsDescendants clips to the box).
	skySea = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(214, 248, 255)), ColorSequenceKeypoint.new(0.638, rgb(146, 218, 250)),
		ColorSequenceKeypoint.new(0.642, rgb(66, 192, 234)), ColorSequenceKeypoint.new(1, rgb(16, 98, 186)),
	}),
}
-- Card geometry, desktop and phone (compact). A card is its grid cell minus 4 px each side and 14 at
-- the bottom (its outline and the +6 hard drop live in that margin), so cellH - 14 is the card. The
-- vertical budget is FULL in both - a TextLabel does not clip, so anything taller draws under the key:
--   desk    (card 263): well 10..120 · name 123..149 · stats 149..183 · blurb 183..206 · key 209..251 (+drop 261)
--   compact (card 242): well 10..86  · name 89..115  · stats 115..151 · blurb 151..175 · key 178..228 (+drop 238)
-- The blurb is two TextScaled lines (max 12 / 13): one truncated line showed half a sentence.
-- 2026-10-10: the blurb is HIDDEN and the stats take its band too (statH 34 -> 57 / 36 -> 60). In a playtest a
-- 12 px two-line sentence in 23 px rendered ~8 px - unreadable - while the stat line, the reason to buy, was
-- the crowded one. The blurb label stays (refresh still writes it) so it can come back as a tooltip.
local CARD = {
	desk = { cellH = 277, prevH = 110, nameY = 123, nameH = 26, statY = 149, statH = 57, blurbY = 183, blurbH = 23,
		blurbS = 12, keyY = 209, keyH = 42, keyS = 24, iconS = 32 },
	compact = { cellH = 256, prevH = 76, nameY = 89, nameH = 26, statY = 115, statH = 60, blurbY = 151, blurbH = 24,
		blurbS = 13, keyY = 178, keyH = 50, keyS = 26, iconS = 38 },
}

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------
local BOATS = BoatData.TIERS
local BY_ID = {}
for _, b in ipairs(BOATS) do BY_ID[b.id] = b end

local function isOwned(id) return id == 1 or plr:GetAttribute("Boat_" .. id) == true end
local function getCurrent() return math.clamp(tonumber(plr:GetAttribute("CurrentBoat")) or 1, 1, BoatData.MAX_TIER) end
local function boatState(id)
	if isOwned(id) then return (getCurrent() == id) and "active" or "owned" end
	if isOwned(id - 1) then return "buy" end
	return "locked"
end
if plr:GetAttribute("CurrentBoat") == nil then plr:SetAttribute("CurrentBoat", 1) end
plr:SetAttribute("Boat_1", true)

local DEMO_BALANCE = 0   -- fallback only; the real balance is the shared leaderstats.Money
local cash = DEMO_BALANCE
local cashSource = nil
local refresh, updateNotif
local function bindCash()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then
		cashSource = m; cash = m.Value
		-- updateNotif runs whether or not the menu is open - that badge exists precisely to
		-- be seen while it is CLOSED, so it cannot be gated on gui.Enabled like refresh().
		m.Changed:Connect(function(v) cash = v; updateNotif(); if gui.Enabled then refresh() end end)
	end
end

----------------------------------------------------------------------
-- window chrome (ShopKit's window: lagoon body, blue header + wave crest, the sailboat breakout, red key X)
----------------------------------------------------------------------
local DESIGN_W, DESIGN_H = 1100, 680
local HEAD_H = 84          -- desktop header: the gold title over a "Sailing:" line (compact: 70, see applyLayout)

local backdrop = make("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1,1), BackgroundColor3 = rgb(2,10,26), BackgroundTransparency = 0.4, AutoButtonColor = false, Selectable = false, Text = "", ZIndex = 1 }, gui)
local win = UI.window(gui, "BOATS", {
	Name = "Window", w = DESIGN_W, h = DESIGN_H, headerH = HEAD_H, emoji = "\u{26F5}", headColour = "blue", ZIndex = 5,
})
local root = win.root
local uiscale = make("UIScale", { Scale = 1 }, root)
-- Shared with every other pop-up window in the game. On a small screen it makes the window
-- SHORTER rather than smaller, so the WIDTH drives the scale (+30-38%% text on a phone) and
-- centres it below the Roblox top bar instead of underneath it. MIN_H is the shortest design
-- height this layout survives - found by binary search, checking that nothing outside a
-- ScrollingFrame pokes out of the window. Desktop and iPad are deliberately unchanged.
-- (2026-10-10: outside the card list there is only the 84 px header + its 13 px crest, so 440
-- still holds - the list just shows less.)
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
local MIN_H = 440
-- PHONES (short side < 500) get a reflow instead of the shrunken desktop window. At 1100 wide a
-- 667px phone landed at 0.58: blurb 6px, stats 7px, CTAs 24px tall, close X 30px. So on a phone
-- the design WIDTH is chosen to land the window at COMPACT_S and the grid reflows to 2 columns
-- of bigger-text cards (applyLayout, below). COMPACT_ROW is the design height one full card row
-- needs under the compact header: on a very short phone (Galaxy A06, 269px usable) the scale
-- drops just enough for that row to fit. Re-run on every open and viewport change.
-- ZonesController carries the SAME COMPACT_S so the two menus match - keep them in step.
local COMPACT_S, COMPACT_ROW = 0.8, 360
local isCompact = false
local applyLayout -- assigned once the cards exist
local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return end
	isCompact = math.min(vp.X, vp.Y) < 500
	if isCompact then
		local availH = vp.Y - game:GetService("GuiService"):GetGuiInset().Y - 12
		local s = math.min(COMPACT_S, availH / COMPACT_ROW)
		local w = math.clamp(math.floor(vp.X / s) - 50, 640, DESIGN_W)
		if applyLayout then applyLayout(true, w) end
		MenuFit.apply(root, uiscale, w, DESIGN_H, 0.4, 1.1, 300)
		-- 2026-10-11, the owner: "make the button uis centered to the phone screen". The sailboat is tucked inside the
		-- header on a phone (applyLayout), so nothing reaches above the window's top-left: up 0, the hard drop 9.
		MenuFit.centre(root, uiscale, 0, 9)
	else
		if applyLayout then applyLayout(false, DESIGN_W) end
		MenuFit.apply(root, uiscale, DESIGN_W, DESIGN_H, 0.4, 1.1, MIN_H)
		MenuFit.centre(root, uiscale, 46, 9)   -- centred on the screen, the sailboat clear of the top bar
	end
end

-- The window catches its own taps (ShopController's pattern): an Active Frame does NOT stop the
-- Backdrop under it, so transparent ClickGuard buttons with no handler sit over the body + its drop
-- (ZIndex 3: over Shadow / Body, under the title, the pill, the list and the X) and over the big
-- sailboat. Silent: SndHooked is set before they are parented, so AudioController leaves them alone.
local function clickGuard(parent, size, z)
	local b = make("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, ZIndex = z,
	})
	b:SetAttribute("SndHooked", true)
	b.Parent = parent
	return b
end
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, 9), 3), 24)
if win.icon then clickGuard(win.icon, UDim2.new(1, 0, 1, 5), 20) end

-- header furniture: the "Sailing:" line under the title, and the Shop's gold cash pill left of the X
local HD = { waves = {}, pillIcon = 40, pillText = 28, broke = 0, toastToken = 0 }
for _, d in ipairs(win.crest:GetChildren()) do
	if d:IsA("Frame") then table.insert(HD.waves, d) end
end
HD.sub = UI.label(root, "", {
	Name = "Sub", size = 19, minSize = 10, align = "left", drop = 2, RichText = true, ZIndex = 8,
	Position = UDim2.fromOffset(114, 56), Size = UDim2.fromOffset(680, 24),
})
HD.pill = UI.candyKey(root, "gold", {
	Name = "CashPill", static = true, Size = UDim2.fromOffset(196, 48), AnchorPoint = V2(1, 0),
	Position = UDim2.new(1, -96, 0, 18), ZIndex = 7,
})
function HD.setCash(v)
	local s = UI.cash(v)
	if HD.cashShown == s then return end
	HD.cashShown = s
	HD.pill.setParts(nil, {
		{ icon = "coins", size = HD.pillIcon, drop = 0 }, { text = s, size = HD.pillText, o = 4, drop = 2 },
	}, { gap = 6 })
end
-- can't afford it: the pill flushes red for a beat (it used to be the cash label's colour)
function HD.flashBroke()
	HD.broke += 1
	local my = HD.broke
	HD.pill.recolour("red")
	UI.punch(HD.pill.scale, 1.12, 0.3)
	task.delay(0.6, function() if HD.broke == my then HD.pill.recolour("gold") end end)
end
-- a scaled label's max size, on the label AND its hard-drop copy (UI.dropShadow clones the constraint)
local function setMax(l, n)
	for _, t in ipairs({ l, l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop") }) do
		local c = t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then c.MaxTextSize = n end
	end
end

local closeBtn = win.close.button

-- the card list: ShopController's gold thumb over a faint INK track (the track only while it scrolls)
local LIST_TOP = HEAD_H + 20
local track = make("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	AnchorPoint = V2(1, 0), Position = UDim2.new(1, -18, 0, LIST_TOP), Size = UDim2.new(0, 10, 1, -(LIST_TOP + 12)),
	ZIndex = 5, Visible = false,
}, root)
UI.corner(track, 5)
local scroller = make("ScrollingFrame", {
	Name = "Cards", Position = UDim2.new(0, 18, 0, LIST_TOP), Size = UDim2.new(1, -36, 1, -(LIST_TOP + 12)),
	BackgroundTransparency = 1, ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb, ScrollBarImageTransparency = 0,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, VerticalScrollBarInset = Enum.ScrollBarInset.None, ZIndex = 6,
}, root)
-- Cells carry their card's outline + drop inside them, so the list needs no top/bottom padding:
-- two desktop rows are 2*277 + 8 = 562 of the 564-tall list (no scrollbar at the design size).
-- Right padding 14 keeps the cards clear of the 10 px bar. Change cellH and check that again.
local scrollPad = make("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0) }, scroller)
local GRID_COLS = 4
local grid = make("UIGridLayout", { CellSize = UDim2.fromOffset(256, CARD.desk.cellH), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, scroller)
local function syncTrack()
	track.Visible = scroller.AbsoluteCanvasSize.Y > scroller.AbsoluteSize.Y + 1
end
scroller:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(syncTrack)
scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncTrack)

----------------------------------------------------------------------
-- toast: a ShopKit chip that pops on the header seam (gold = bought, sea = sailing, red = can't)
----------------------------------------------------------------------
HD.toast = UI.chip(root, "navy", {
	Name = "Toast", height = 50, textSize = 24, pad = 26, minWidth = 240, AnchorPoint = V2(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, HEAD_H), ZIndex = 40,
})
HD.toast.block.root.Visible = false
HD.toastScale = make("UIScale", {}, HD.toast.block.root)
local function showToast(text, colour)
	HD.toastToken += 1
	local my = HD.toastToken
	HD.toast.set(text, colour or "gold")
	HD.toast.block.root.Visible = true
	UI.punch(HD.toastScale, 0.6, 0.28)
	task.delay(2.4, function()
		if HD.toastToken == my then HD.toast.block.root.Visible = false end
	end)
end

----------------------------------------------------------------------
-- the sea behind the cards: light rays and rising bubbles in the window's Ocean layer (only the
-- gaps between cards show them). Driven by the one RenderStepped loop below, idle while closed
-- or with Menu Animations off (Set_MenuFX = false).
----------------------------------------------------------------------
local FX = { rays = {}, bubbles = {} }
do
	local ocean = win.ocean
	for i, x in ipairs({ 0.08, 0.3, 0.52, 0.74, 0.94 }) do
		local ray = make("Frame", {
			Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 60 + (i % 2) * 40, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, ocean)
		make("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(FX.rays, { f = ray, phase = i * 1.3 })
	end
	for i = 1, 26 do
		local s = 6 + (i * 7) % 13
		local b = make("Frame", {
			Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = V2(0.5, 0.5),
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, ocean)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		make("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		local e = { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i }
		b.Position = UDim2.new(e.x, 0, e.y, 0)
		table.insert(FX.bubbles, e)
	end
end

----------------------------------------------------------------------
-- 3D preview
----------------------------------------------------------------------
-- One ViewportFrame per card. The model is built lazily the first time the card is
-- actually on screen (see cullPreviews) and never rebuilt.
-- MOVE THE CAMERA, NEVER THE BOAT. The first version bobbed each hull with Model:PivotTo
-- and re-read Model:GetBoundingBox() every frame, for all eight cards: ~700 part CFrame
-- writes plus eight full descendant walks per frame, which measured 60 fps -> 39 fps with
-- the menu open. The bbox is cached at build time (the hull never changes shape) and the
-- bob is folded into the camera, so a frame is now eight CFrame writes.
local function framePreview(entry, spin, bob)
	local vp = entry.vp
	local cam = vp.CurrentCamera
	if not cam or not entry.bbox then return end
	if vp.AbsoluteSize.Y < 2 then return end        -- not laid out yet; the reframe below covers it
	local cf, size = entry.bbox.cf, entry.bbox.size
	local aspect = vp.AbsoluteSize.X / vp.AbsoluteSize.Y
	local tanH = math.tan(math.rad(cam.FieldOfView * 0.5))
	-- Fit the two axes SEPARATELY and take whichever binds. A Camera's FieldOfView is
	-- vertical, and these wells are wide, so for a long flat hull the width binds.
	-- Sizing off the bounding sphere instead over-pads enormously: the first pass put the
	-- camera 35 studs from a 14-stud rowboat and it filled a third of the card.
	-- halfW uses the X-Z diagonal so the hull never clips as it turns under the cursor.
	local halfW = 0.5 * math.sqrt(size.X * size.X + size.Z * size.Z)
	-- The margin is NOT decoration. The fit above is an orthographic one; in perspective
	-- the near side of a hull 6-9 studs deep projects ~10-15% larger than the centre, and
	-- at a 1.12 margin every boat overflowed its card. Push back by half the depth as well
	-- so the extra magnification is paid for rather than estimated.
	local dist = math.max((size.Y * 0.5) / tanH, halfW / (tanH * aspect)) * 1.30 + size.Z * 0.5
	-- Aim ABOVE the waterline, by exactly enough to land y=0 on the painted sea line at
	-- 64% down the well (LOOK.skySea's hard stop), so the hull sits in the water.
	local look = Vector3.new(cf.X, 0.28 * dist * tanH - (bob or 0), 0)
	local dir = CFrame.Angles(0, spin, 0) * CFrame.Angles(math.rad(-13), 0, 0)
	cam.CFrame = CFrame.lookAt(look + dir:VectorToWorldSpace(Vector3.new(0, 0, dist)), look)
end

local function buildPreview(entry)
	if entry.previewBuilt then return end
	entry.previewBuilt = true
	local t = entry.boat
	if not t.hull then return end
	local ok, m = pcall(BoatBuilder.build, t, true)
	if not ok or not m then
		warn("[Boats] preview build failed for tier " .. t.id .. ": " .. tostring(m))
		return
	end
	m:PivotTo(CFrame.new())
	m.Parent = entry.vp
	entry.model = m
	local bcf, bsize = m:GetBoundingBox()
	entry.bbox = { cf = bcf, size = bsize }     -- read ONCE; the hull is static from here
	framePreview(entry, entry.spin or 0, 0)
	-- On the very first open the card may not have been laid out yet, so AbsoluteSize is
	-- still 0 and the framing above bails. Re-frame the moment it gets a real size.
	local conn
	conn = entry.vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if entry.vp.AbsoluteSize.Y >= 2 then
			framePreview(entry, entry.spin or 0, 0)
			conn:Disconnect()
		end
	end)
end

----------------------------------------------------------------------
-- cards
----------------------------------------------------------------------
-- A candy card (ShopKit's row recipe stood on end): a gradient face in the boat's colour, INK
-- outline, +6 hard drop, gloss cap; the painted well with the 3D hull, its tier number (a navy
-- keycap), its headline perk (a green chip) and, when it is the next one to buy, a gold NEXT!
-- sticker; the name, the stat line (lime: gains), the blurb; ONE key in the STATE's colour.
-- The sailing card wears the gold owned band (UI.RING) just inside its outline.
local cards, cardsById = {}, {}
-- BoatData joins the stats with U+2022; FredokaOne's middle dot (U+00B7, the Shop's DOT) is the safe one.
-- Broken into two balanced lines here (3 + 2 terms) so a wrap never leaves a dot dangling at a line end.
local function statsOf(b)
	local terms = string.split(BoatData.benefits(b), "  \u{2022}  ")
	if #terms <= 2 then return table.concat(terms, "  \u{00B7}  ") end
	local half = math.ceil(#terms / 2)
	return table.concat(terms, "  \u{00B7}  ", 1, half) .. "\n" .. table.concat(terms, "  \u{00B7}  ", half + 1, #terms)
end
local function makeCard(b)
	local P = CARD.desk
	local cell = make("Frame", { Name = "Boat" .. b.id, BackgroundTransparency = 1, LayoutOrder = b.id, ZIndex = 2 }, scroller)
	local cellScale = make("UIScale", { Scale = 1 }, cell)
	local holder = make("Frame", { Name = "Card", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -14), ZIndex = 2 }, cell)
	UI.hardShadow(holder, 18, 4, 6, 1)
	local face = make("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, holder)
	UI.corner(face, 18)
	UI.stroke(face, 4)
	local colour = LOOK.colour[b.id] or "blue"
	UI.vgrad(face, UI.CANDY[colour] or UI.CANDY.blue)
	UI.gloss(face, { frac = 0.3, alpha = 0.5, inset = 4, radius = 14 })

	-- preview well: a painted sea/sky behind a real 3D boat
	local prev = make("Frame", { Name = "Preview", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, P.prevH), BackgroundColor3 = UI.WHITE, ClipsDescendants = true, ZIndex = 3 }, face)
	UI.corner(prev, 12)
	UI.stroke(prev, 3)
	UI.vgrad(prev, LOOK.skySea)
	make("Frame", { Name = "Surf", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.45, Position = UDim2.new(0, 0, 0.64, -1), Size = UDim2.new(1, 0, 0, 3), ZIndex = 4 }, prev)
	local vp = make("ViewportFrame", { Name = "Hull", Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, ZIndex = 6,
		LightDirection = Vector3.new(-0.4, -1, -0.5), Ambient = rgb(168,188,208),
		LightColor = rgb(255,252,240) }, prev)
	-- A narrow FOV keeps these closer to the flat, product-shot look of the 2.5D stage
	-- itself (which runs at FOV 20) and cuts the near-side perspective blow-up.
	local vcam = make("Camera", { FieldOfView = 20 }, vp)
	vp.CurrentCamera = vcam

	local num = UI.block(prev, "navy", {
		Name = "Num", Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(6, 6), radius = 15, lip = 4,
		outline = 2.5, highlight = false, ZIndex = 12,
	})
	UI.label(num.face, tostring(b.id), { Name = "N", size = 17, outline = 0.12 })

	local perk = UI.chip(prev, "green", {
		Name = "Perk", height = 26, textSize = 15, pad = 10, lip = 4, radius = 12, minWidth = 30,
		AnchorPoint = V2(0, 1), Position = UDim2.new(0, 7, 1, -7), ZIndex = 10,
	})
	perk.block.root:FindFirstChildWhichIsA("UIStroke").Thickness = 3
	perk.set(BoatData.headline(b))

	local lockOverlay = make("Frame", { Name = "Locked", Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.WHITE, ZIndex = 11, Visible = false }, prev)
	UI.corner(lockOverlay, 12)
	UI.vgrad(lockOverlay, LOOK.lockVeil)
	local lockIcon = UI.icon(lockOverlay, "lock", 54, {
		Name = "LockIcon", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = -6, ZIndex = 13,
	})
	UI.iconDrop(lockIcon, 4, 0.5)

	local nextTag = UI.sticker(face, "gold", "NEXT!", {
		Name = "Next", height = 30, textSize = 16, pad = 10, Position = UDim2.new(1, -46, 0, 24), Rotation = 8, ZIndex = 20,
	})
	nextTag.block.root.Visible = false

	local ring = make("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 9, Visible = false }, face)
	UI.corner(ring, 14)
	UI.stroke(ring, 4, UI.RING)

	-- The full five-stat line gets its own wrapped two-line slot. It is the reason to buy
	-- the boat, so it must be legible; the flavour blurb below it is the part that shrinks.
	local nameLbl = UI.label(face, b.name, {
		Name = "BoatName", size = 22, minSize = 11, drop = 2, ZIndex = 6,
		Position = UDim2.fromOffset(12, P.nameY), Size = UDim2.new(1, -24, 0, P.nameH),
	})
	local statLbl = UI.label(face, statsOf(b), {
		Name = "Stats", size = 18, minSize = 10, color = UI.TEXT.lime, drop = 2, TextWrapped = true, ZIndex = 6,
		Position = UDim2.fromOffset(12, P.statY), Size = UDim2.new(1, -24, 0, P.statH),
	})
	local tagLbl = UI.label(face, b.blurb, {
		Name = "Blurb", size = P.blurbS, minSize = 8, color = UI.TEXT.soft, outline = 0.1, TextWrapped = true, ZIndex = 6,
		Visible = false,   -- (see CARD: the stats took its band)
		Position = UDim2.fromOffset(12, P.blurbY), Size = UDim2.new(1, -24, 0, P.blurbH),
	})

	-- the one key (its colour and contents are the STATE: setKey). Named "Action": never "TextButton".
	local key = UI.candyKey(face, "grey", {
		Name = "Action", Size = UDim2.fromOffset(224, P.keyH), Position = UDim2.fromOffset(12, P.keyY), ZIndex = 10,
	})

	local entry = { boat = b, cell = cell, cellScale = cellScale, face = face, colour = colour,
		prev = prev, vp = vp, num = num, perk = perk, nextTag = nextTag, lockOverlay = lockOverlay, ring = ring,
		nameLbl = nameLbl, statLbl = statLbl, tagLbl = tagLbl, key = key, spin = -0.36,
		hover = false, clickable = false }
	cards[#cards+1] = entry; cardsById[b.id] = entry

	TouchKit.press(key.button, function() if entry.onClick then entry.onClick() end end)
	face.MouseEnter:Connect(function() entry.hover = true end)
	face.MouseLeave:Connect(function() entry.hover = false end)
	return entry
end
for _, b in ipairs(BOATS) do makeCard(b) end

-- Phone reflow (see fit()). With compact == false every value below is the desktop layout.
-- Compact: a 70 header (title 38, "Sailing:" line 16, a 60 px sailboat tucked in its corner, a 170 x 42 pill), 2 or 3
-- columns of 256-tall cells (CARD.compact) with a 50 px key. UI.window drew the header and its wave
-- crest for the 1100 design width, so the crest is re-centred and trimmed to the width here.
applyLayout = function(compact, w)
	local P = compact and CARD.compact or CARD.desk
	local hh = compact and 70 or HEAD_H
	local top = hh + 20
	win.header.Size = UDim2.new(1, 0, 0, hh)
	win.ocean.Position = UDim2.fromOffset(0, hh)
	win.ocean.Size = UDim2.new(1, 0, 1, -hh)
	win.crest.Position = UDim2.fromOffset(0, hh)
	local n = math.ceil((w - 10) / 26)
	local x0 = (w - n * 26) / 2
	for i, d in ipairs(HD.waves) do
		d.Visible = i <= n
		d.Position = UDim2.fromOffset(x0 + (i - 1) * 26, -1)
	end
	if win.icon then
		-- 2026-10-11 ("centered to the phone screen"): on a phone the sailboat sits INSIDE the 70 header instead of
		-- breaking out above it, so the centred window need not shrink for it. Its -8 deg tilt still clears the box
		-- (about 4..72 x 1..69) and the title at x 88.
		local s = compact and 60 or 124
		win.icon.Size = UDim2.fromOffset(s, s)
		win.icon.Position = compact and UDim2.fromOffset(8, 5) or UDim2.fromOffset(-36, -44)
	end
	local pillW, pillH, pillR = compact and 170 or 196, compact and 42 or 48, compact and 88 or 96
	HD.pill.button.Size = UDim2.fromOffset(pillW, pillH)
	HD.pill.button.Position = UDim2.new(1, -pillR, 0, math.floor((hh - pillH) / 2))
	HD.pillIcon, HD.pillText = compact and 34 or 40, compact and 24 or 28
	HD.cashShown = nil
	win.title.Position = UDim2.fromOffset(compact and 88 or 112, compact and 0 or 2)
	win.title.Size = UDim2.fromOffset(compact and 260 or 320, compact and 46 or 54)
	setMax(win.title, compact and 38 or 46)
	local subX = compact and 90 or 114
	HD.sub.Position = UDim2.fromOffset(subX, compact and 44 or 56)
	HD.sub.Size = UDim2.fromOffset(math.max(120, w - subX - (pillW + pillR + 14)), compact and 20 or 24)
	setMax(HD.sub, compact and 16 or 19)
	HD.toast.block.root.Position = UDim2.new(0.5, 0, 0, hh)
	scroller.Position = UDim2.new(0, 18, 0, top)
	scroller.Size = UDim2.new(1, -36, 1, -(top + 12))
	track.Position = UDim2.new(1, -18, 0, top)
	track.Size = UDim2.new(0, 10, 1, -(top + 12))
	scrollPad.PaddingBottom = UDim.new(0, compact and 6 or 0)
	local cols = compact and (w >= 1000 and 3 or 2) or GRID_COLS
	local cellW = math.floor(((w - 36) - 16 - (cols - 1) * 8) / cols)
	grid.CellSize = UDim2.fromOffset(cellW, P.cellH)
	local cardW = cellW - 8
	for _, e in ipairs(cards) do
		e.prev.Size = UDim2.new(1, -20, 0, P.prevH)
		e.nameLbl.Position = UDim2.fromOffset(12, P.nameY)
		e.nameLbl.Size = UDim2.new(1, -24, 0, P.nameH)
		e.statLbl.Position = UDim2.fromOffset(12, P.statY)
		e.statLbl.Size = UDim2.new(1, -24, 0, P.statH)
		e.tagLbl.Position = UDim2.fromOffset(12, P.blurbY)
		e.tagLbl.Size = UDim2.new(1, -24, 0, P.blurbH)
		setMax(e.tagLbl, P.blurbS)
		e.key.button.Size = UDim2.fromOffset(cardW - 24, P.keyH)
		e.key.button.Position = UDim2.fromOffset(12, P.keyY)
		e.keySig = nil     -- the key's pieces are laid out in px: lay them out again on the next refresh
	end
end

local function pop(id)
	local e = cardsById[id]; if not e then return end
	UI.punch(e.cellScale, 1.06, 0.3)
end

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------
local function sailTo(id)
	local b = BY_ID[id]; if not b then return end
	if not isOwned(id) then return end
	-- The ONLY world-facing write. BoatClient owns the swap and the stat publish.
	plr:SetAttribute("CurrentBoat", id)
	refresh(); pop(id)
	showToast("\u{26F5}  Now sailing the " .. b.short, "sea")
end

local function buy(id)
	local b = BY_ID[id]; if not b or isOwned(id) then return end
	if not isOwned(id - 1) then return end
	if cash < b.cost then
		showToast("Not enough coins!", "red")
		HD.flashBroke()
		return
	end
	cash = cash - b.cost
	if cashSource then pcall(function() cashSource.Value = cash end) end
	plr:SetAttribute("Boat_" .. id, true)
	sailTo(id)
	showToast("\u{1F513} Bought the " .. b.name .. "!", "gold")
end

for _, entry in ipairs(cards) do
	local b = entry.boat
	entry.onClick = function()
		local st = boatState(b.id)
		if st == "buy" then buy(b.id) elseif st == "owned" then sailTo(b.id) end
	end
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
-- a card's key: gold SAILING (the check) / green SAIL / the price - green when you can afford it,
-- grey with the price in red when you can't / grey LOCKED. Re-laid only when what it shows changes.
local function setKey(e, st, afford)
	local P = isCompact and CARD.compact or CARD.desk
	local k = e.key
	local sig = st .. (st == "buy" and (afford and "+" or "-") or "") .. "|" .. k.button.Size.X.Offset .. "|" .. P.keyS
	if e.keySig == sig then return end
	e.keySig = sig
	if st == "active" then
		k.recolour("gold")
		k.setParts(nil, { { icon = "check", size = P.iconS }, { text = "SAILING", size = P.keyS } }, { gap = 8 })
	elseif st == "owned" then
		k.recolour("green")
		-- (the anchor is an emoji: no outline and no hard drop, or its colour glyph would draw twice)
		k.setParts(nil, { { text = "\u{2693}", size = P.keyS, o = 0, drop = 0 }, { text = "SAIL", size = P.keyS } }, { gap = 8 })
	elseif st == "buy" then
		k.recolour(afford and "green" or "grey")
		k.setParts(nil, {
			{ icon = "coins", size = P.iconS + 4, drop = 0 },
			{ text = UI.cash(e.boat.cost), size = P.keyS, color = afford and UI.TEXT.gold or UI.TEXT.red },
		}, { gap = 6 })
	else
		k.recolour("grey")
		k.setParts(nil, { { icon = "lock", size = P.iconS - 2 }, { text = "LOCKED", size = P.keyS } }, { gap = 8 })
	end
end

function refresh()
	HD.setCash(cash)
	local cur = BY_ID[getCurrent()] or BOATS[1]
	HD.sub.Text = "Sailing: <font color=\"#FFDE50\">" .. cur.name .. "</font>" .. (isCompact and "" or "   \u{00B7}   a bigger boat lands more, and lands it deeper")
	for _, e in ipairs(cards) do
		local b = e.boat
		local st = boatState(b.id)
		local locked = (st == "locked")
		e.lockOverlay.Visible = locked
		e.perk.block.root.Visible = not locked
		e.nextTag.block.root.Visible = (st == "buy")
		e.ring.Visible = (st == "active")
		e.clickable = (st == "buy" or st == "owned")
		local faceKey = locked and "locked" or e.colour
		if e.faceKey ~= faceKey then
			e.faceKey = faceKey
			UI.vgrad(e.face, locked and LOOK.locked or (UI.CANDY[e.colour] or UI.CANDY.blue))
		end
		if locked then
			-- the hint takes the stat slot (centred under the name), so a locked card has no hole in it
			e.nameLbl.Text = "? ? ?"
			e.statLbl.Text = "Buy the previous boat first"
			e.statLbl.TextColor3 = UI.TEXT.soft
			e.tagLbl.Text = ""
		else
			e.nameLbl.Text = b.name
			e.statLbl.Text = statsOf(b)
			e.statLbl.TextColor3 = UI.TEXT.lime
			e.tagLbl.Text = b.blurb
		end
		setKey(e, st, cash >= b.cost)
	end
	updateNotif()
end

-- The `!` badge on the MainMenu's Boats button. The bar's other three badges (Upgrades,
-- Zones, Rebirth) are hardcoded Visible=true and nothing ever writes them - permanently
-- lit decoration. This one is driven, so it means "you can afford the next boat" instead
-- of nothing at all.
local notif = nil
function updateNotif()
	if not notif or not notif.Parent then return end
	local show = false
	for _, b in ipairs(BOATS) do
		if boatState(b.id) == "buy" and cash >= b.cost then show = true break end
	end
	notif.Visible = show
end

task.spawn(function()
	local pg = plr:WaitForChild("PlayerGui")
	local mm = pg:WaitForChild("MainMenu", 20); if not mm then return end
	local bar = mm:WaitForChild("MenuBar", 10); if not bar then return end
	local lst = bar:WaitForChild("List", 10); if not lst then return end
	local btn = lst:WaitForChild("Boats", 10); if not btn then return end
	notif = btn:FindFirstChild("Notif")
	if notif then notif.Visible = false end
	updateNotif()
end)

plr.AttributeChanged:Connect(function(a)
	if a == "CurrentBoat" or a:sub(1, 5) == "Boat_" then updateNotif() end
end)

-- Build a card's 3D boat only once it has actually been scrolled into view. Locked cards
-- still build: the hull is hidden behind the lock veil, but skipping it would make the
-- reveal pop a frame late the moment you buy one.
local function cullPreviews()
	local top = scroller.CanvasPosition.Y
	local bot = top + scroller.AbsoluteSize.Y
	for _, e in ipairs(cards) do
		local y = e.cell.AbsolutePosition.Y - scroller.AbsolutePosition.Y + top
		if y + e.cell.AbsoluteSize.Y > top - 120 and y < bot + 120 then
			buildPreview(e)
		end
	end
end
scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(cullPreviews)

----------------------------------------------------------------------
-- animation
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	if plr:GetAttribute("Set_MenuFX") == false then return end
	local t = os.clock()
	for _, bd in ipairs(FX.bubbles) do
		bd.y -= bd.speed * dt
		if bd.y < -0.05 then
			bd.y = 1.05
			bd.x = (bd.x + 0.37) % 1
		end
		bd.f.Position = UDim2.new(bd.x, math.sin(t * bd.wob + bd.phase) * 6, bd.y, 0)
	end
	for _, r in ipairs(FX.rays) do
		r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
	end
	-- Boats ride the swell, and turn to show themselves off while you hover a card.
	for _, e in ipairs(cards) do
		if e.model then
			if e.hover then e.spin = e.spin + dt * 0.9 end
			framePreview(e, e.spin, math.sin(t * 1.5 + e.boat.id) * 0.16)
		end
	end
end)

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
local function close() gui.Enabled = false end
TouchKit.press(closeBtn, close)
TouchKit.press(backdrop, close)
plr:GetAttributeChangedSignal("CurrentBoat"):Connect(function() if gui.Enabled then refresh() end end)

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
		fit(); refresh(); setInventoryHidden(true)
		task.defer(cullPreviews)
		local targetScale = uiscale.Scale
		uiscale.Scale = targetScale * 0.9
		TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetScale }):Play()
	else
		HD.toast.block.root.Visible = false
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

----------------------------------------------------------------------
-- dev hook
----------------------------------------------------------------------
local devHook = gui:FindFirstChild("DevBoat") or make("BindableEvent", { Name = "DevBoat" }, gui)
devHook.Event:Connect(function(arg)
	if arg == "__ALL__" then
		for _, b in ipairs(BOATS) do if b.id ~= 1 then plr:SetAttribute("Boat_" .. b.id, true) end end
		refresh()
	elseif arg == "__RESET__" then
		for _, b in ipairs(BOATS) do if b.id ~= 1 then plr:SetAttribute("Boat_" .. b.id, nil) end end
		plr:SetAttribute("CurrentBoat", 1)
		refresh()
	elseif typeof(arg) == "number" and BY_ID[arg] then
		plr:SetAttribute("Boat_" .. arg, true)
		sailTo(arg)
	end
end)

----------------------------------------------------------------------
-- boot
----------------------------------------------------------------------
bindCash()
plr.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then task.wait(0.2); bindCash(); if gui.Enabled then refresh() end end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit(); refresh(); task.defer(cullPreviews) end end)
end

fit()
refresh()
syncTrack()
print(string.format("[Boats] built - %d tiers, %s -> %s (ShopKit look)", #BOATS, BOATS[1].short, BOATS[#BOATS].short))
