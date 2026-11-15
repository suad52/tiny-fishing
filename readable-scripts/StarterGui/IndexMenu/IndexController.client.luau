--[==[
	IndexController - LocalScript for StarterGui.IndexMenu (the Fish Index / Fishopedia).
	Dual-mode: if script.Parent is a ScreenGui, build into it; else make PlayerGui.IndexMenu.
	Reads ReplicatedStorage.FishData + ReplicatedStorage.FishModels.
	Discovered tracking (client demo) + hooks:
	  ReplicatedStorage.IndexRemotes.Discover (RemoteEvent, server->client, arg=fishName)
	  <ScreenGui>.Discover (BindableEvent): GameClient fires it with every hauled species
	  <ScreenGui>.DevDiscover (BindableEvent): name / "__ALL__" / "__RESET__" / "__DETAIL__:<name>"

	2026-10-10 - THE SEA-CANDY PASS. The owner asked for the nine MenuBar menus to "look better" in the theme the
	Shop was rebuilt in that day (the +1 snowball's Candy Brick look, ported as ReplicatedStorage.ShopKit). This
	window was still on the older "cartoon reef" recipe (DEEP_TOP/MID/BOT navy panels, thin GothamMedium body copy,
	a drawn makeClose X), so the LOOK moved onto ShopKit: the UI.window shell (lagoon body, teal header with a wave
	crest, gold title, the book breaking out of the top-left corner, the red key X), FredokaOne labels with INK
	outlines everywhere, every species a candy card in its RARITY's colour (Common slate, Uncommon emerald, Rare
	blue, Epic purple, Legendary orange, Mythic rose - FishData.rarityColor's hues in the Shop's palette), the
	rarity filters as candy keys (gold = the one you're on, sea = the rest, each with its rarity gem), progress as a
	green meter and REWARDS as a candy key in the header, the fish detail as a window of its own whose header takes
	the fish's rarity colour, the rewards ladder as candy rows with CLAIM / LOCKED / CLAIMED keys, the Shop's scroll
	bars, bubbles and light rays, and the NEW SPECIES toast as a candy pill. What it DOES did not change: the same
	bounties, ladder, IX_ claims, attributes, hooks, phone layout and MenuFit call. Two click fixes came with the
	shell: the window now has the Backdrop every other menu has (it was the only one without, so a tap went through
	it to the MenuBar underneath), and ClickGuards so a tap on a window's body never reaches a backdrop.
	The window's chrome reaches past its box (the book 44 above, the X 18, the drop 9 below), so MenuFit is handed
	the whole FOOTPRINT and the box is set back inside it (LAY.fitRoot) - it never runs off the top of the screen.

	THE CONTRACT (what other scripts rely on - keep it):
	  * PlayerGui.IndexMenu stays the same ScreenGui; Enabled is open/close (MenuLogic opens it; MenuBlurManager,
	    AudioController, TutorialController and DailyController read it).
	  * Attributes on the gui: Discovered / Total (QuestsController counts "discover" off Discovered),
	    RewardsClaimable.
	  * gui.Discover BindableEvent (GameClient fires it per hauled fish) and gui.DevDiscover (the Studio verbs above).
	  * Claims are IX_<id> player attributes; coins go to leaderstats.Money (else the Coins attribute); Pearls.
	  * The window's close X is the ONLY TextButton named "TextButton" in this gui (TutorialController's
	    closeButtonOf finds it by name and shape); the detail and rewards windows' X are DetailClose / RewardsClose.
	  * Named for instance_path clicks: Window, RewardsButton, RewardsOverlay, RewardsWindow, RewardList, one row per
	    reward named after its id with a "Claim" key, Grid (cards named after their fish), Detail, DetailWindow.
	  * The NEW SPECIES / reward toast is PlayerGui.IndexToast (its own always-on ScreenGui, DisplayOrder 60), placed
	    in AfkHUD's notice slot, and silent while the TutorialActive attribute is set.
	  * MainMenu.MenuBar.List.Index gets a Notif badge (cloned from Upgrades') while a reward is claimable.
	  * Every control goes through TouchKit.press; no layout or AutomaticSize parent hosts a key (TouchKit's rules).
]==]

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local RS            = game:GetService("ReplicatedStorage")
local StarterGui    = game:GetService("StarterGui")
local GuiService    = game:GetService("GuiService")
local UIS           = game:GetService("UserInputService")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(RS:WaitForChild("TouchKit"))
-- The look: the Shop's kit (window, candy rows and keys, labels, icons, palettes).
local UI = require(RS:WaitForChild("ShopKit"))
-- Shared with every other pop-up window in the game (see LAY.fitRoot).
local MenuFit = require(RS:WaitForChild("MenuFit"))

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

local FishData   = require(RS:WaitForChild("FishData"))
local FishModels = RS:WaitForChild("FishModels")

-- ===== palette / helpers =====
local function C(r,g,b) return Color3.fromRGB(r,g,b) end
local function lighten(c,t) return c:Lerp(Color3.new(1,1,1), t) end
local function darken(c,t)  return c:Lerp(Color3.new(0,0,0), t) end
local V2 = Vector2.new
local INK, WHITE = UI.INK, Color3.new(1, 1, 1)
local SAND = C(240,222,150)
local RCOLOR = FishData.rarityColor
local RORDER = FishData.rarityOrder
local DOT = "  \u{00B7}  "

-- One candy per RARITY: ShopKit's own families, picked to match FishData.rarityColor's hues (a rarity the table
-- does not know falls back to a gradient made from its rarityColor). Headers use the matching UI.HEAD colours.
local PAL = {
	card = { Common = { C(226,234,246), C(134,150,178) }, Uncommon = "emerald", Rare = "blue", Epic = "purple",
		Legendary = "orange", Mythic = "rose" },
	head = { Common = { C(212,222,238), C(110,128,160) }, Uncommon = "green", Rare = "blue", Epic = "purple",
		Legendary = "orange", Mythic = "pink" },
	unknown = { C(178,198,224), C(88,110,148) },       -- a species not caught yet
	unknownChip = { C(150,166,190), C(92,108,136) },
	tick = { C(150,250,100), C(40,190,40) },
	water = { C(198,244,255), C(104,206,248), C(38,138,216) },   -- a discovered fish's tank
	murk = { C(214,228,242), C(156,178,206), C(112,136,172) },   -- a silhouette's tank
}
function PAL.candy(rarity)
	local c = PAL.card[rarity]
	if type(c) == "string" then c = UI.CANDY[c] end
	if c then return c end
	local r = RCOLOR[rarity] or C(150,160,175)
	return { lighten(r, 0.4), darken(r, 0.1) }
end
function PAL.headKeys(rarity)
	local h = PAL.head[rarity]
	if type(h) == "string" then h = UI.HEAD[h] end
	return h or PAL.candy(rarity)
end
-- a two-stop gradient from one colour (pills, gems, the toast)
function PAL.from(col, up, down)
	return { lighten(col, up or 0.3), darken(col, down or 0.12) }
end

-- K: the small builders this window shares (one table: Luau allows 200 locals per function)
local K = {}
-- a label in the house face (UI.label: TextScaled under a max size, an INK outline that scales with the letters)
function K.text(parent, str, size, o)
	o = o or {}
	local l, stroke = UI.label(parent, str, {
		Name = o.Name or "Text", size = size, color = o.color, drop = o.drop, align = o.align, outline = o.outline,
		minSize = o.minSize, Size = o.Size or UDim2.fromOffset(o.w or 100, o.h or math.ceil(size * 1.3)),
		Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint, ZIndex = o.ZIndex or 3,
		TextWrapped = o.wrap, TextYAlignment = o.yAlign, RichText = o.rich,
	})
	if o.noStroke then stroke.Enabled = false end
	return l, stroke
end
-- change a UI.label's max text size (and its hard drop's, which is a clone with its own constraint)
function K.setMax(l, n)
	local d = l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop")
	for _, t in ipairs({ l, d }) do
		local cn = t and t:FindFirstChildOfClass("UITextSizeConstraint")
		if cn then
			cn.MinTextSize = math.min(cn.MinTextSize, n)
			cn.MaxTextSize = n
		end
	end
end
-- a transparent button that swallows taps (a plain Active Frame does NOT stop a Backdrop under it). Silent: the
-- SndHooked attribute is set before parenting, so AudioController leaves it alone.
function K.guard(parent, size, z, pos)
	local b = UI.new("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, Position = pos or UDim2.new(), ZIndex = z,
	})
	b:SetAttribute("SndHooked", true)
	b.Parent = parent
	return b
end
-- a candy slab: an INK hard drop carrying the outline, a gradient face with an INK outline and a gloss cap
function K.slab(parent, colours, o)
	o = o or {}
	local R = o.radius or 14
	local root = UI.new("Frame", {
		Name = o.Name or "Slab", BackgroundTransparency = 1, Size = o.Size or UDim2.fromOffset(100, 40),
		Position = o.Position or UDim2.new(), ZIndex = o.ZIndex or 1,
	}, parent)
	UI.hardShadow(root, R, o.stroke or 3.5, o.dy or 5, 1)
	local face = UI.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, root)
	UI.corner(face, R)
	UI.stroke(face, o.stroke or 3.5)
	UI.vgrad(face, colours)
	UI.gloss(face, { frac = o.frac or 0.45, alpha = 0.5, inset = 3, radius = math.max(R - 3, 2), ZIndex = 1 })
	return root, face
end
-- a pill (a rarity tag, an id tag): gradient face, INK outline, white text; it sizes itself to its text.
-- Returns p = { root, face, label, pad, set(text, colours, textSize, height) }
function K.pill(parent, o)
	o = o or {}
	local p = { ts = o.ts or 13, h = o.h or 20, pad = o.pad or 7, dy = o.dy or 0 }
	p.root = UI.new("Frame", {
		Name = o.Name or "Pill", BackgroundTransparency = 1, Size = UDim2.fromOffset(40, p.h),
		Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint or Vector2.zero, ZIndex = o.ZIndex or 8,
	}, parent)
	if p.dy > 0 then
		p.shadow = UI.hardShadow(p.root, math.floor(p.h / 2), o.stroke or 2, p.dy, 1)
	end
	p.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, p.root)
	p.corner = UI.corner(p.face, math.floor(p.h / 2))
	UI.stroke(p.face, o.stroke or 2)
	p.label = UI.label(p.face, "", { Name = "Text", size = p.ts, scaled = false, outline = 0.16, ZIndex = 2 })
	function p.set(text, colours, ts, h)
		p.ts, p.h = ts or p.ts, h or p.h
		if text then p.label.Text = text end
		if colours then UI.vgrad(p.face, colours) end
		p.label.TextSize = p.ts
		p.root.Size = UDim2.fromOffset(math.ceil(UI.textWidth(p.label.Text, p.ts)) + 2 * p.pad + 4, p.h)
		p.corner.CornerRadius = UDim.new(0, math.floor(p.h / 2))
		local sc = p.shadow and p.shadow:FindFirstChildOfClass("UICorner")
		if sc then sc.CornerRadius = UDim.new(0, math.floor(p.h / 2)) end
	end
	return p
end
-- an aquarium "water tank" (a fish's ViewportFrame goes on top of it): bright water + a light ray + a sandy
-- seabed for a discovered fish, paler water for a silhouette. INK outlined like everything else.
function K.paintTank(f, disc)
	UI.vgrad(f, disc and PAL.water or PAL.murk)
	local top = disc and lighten(SAND, 0.2) or C(206,210,214)
	local sand, sandTop = f:FindFirstChild("Sand"), f:FindFirstChild("SandTop")
	if sand then UI.vgrad(sand, { top, disc and darken(SAND, 0.14) or C(160,168,180) }) end
	if sandTop then sandTop.BackgroundColor3 = top end
end
function K.tank(parent, disc, cr, o)
	o = o or {}
	cr = cr or 12
	local f = UI.new("Frame", { Name = o.Name or "Tank", BackgroundColor3 = WHITE, ClipsDescendants = true, ZIndex = o.ZIndex or 3 }, parent)
	UI.corner(f, cr)
	UI.stroke(f, o.stroke or 3)
	local ray = UI.new("Frame", {
		Name = "Ray", BackgroundColor3 = WHITE, Size = UDim2.new(0.4, 0, 1.6, 0), Position = UDim2.new(0.12, 0, -0.3, 0),
		Rotation = 16, ZIndex = 1,
	}, f)
	UI.new("UIGradient", {
		Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) }),
	}, ray)
	-- the seabed: rounded bottom corners to match the tank (ClipsDescendants only clips to a rectangle), plus a
	-- square filler over its top so the sand line reads flat
	local sand = UI.new("Frame", { Name = "Sand", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0.19, 0), Position = UDim2.new(0, 0, 0.81, 0), ZIndex = 2 }, f)
	UI.corner(sand, cr)
	UI.new("Frame", { Name = "SandTop", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, cr), Position = UDim2.new(0, 0, 0.81, 0), ZIndex = 2 }, f)
	K.paintTank(f, disc)
	return f
end
-- a UI.window's header at a new height / width: the crest's discs are offset-placed, so they are re-spaced over
-- the CURRENT width (a window is built at its widest so there are always enough of them)
function K.head(win, hh, W)
	win.header.Size = UDim2.new(1, 0, 0, hh)
	win.ocean.Position = UDim2.fromOffset(0, hh)
	win.ocean.Size = UDim2.new(1, 0, 1, -hh)
	win.crest.Position = UDim2.fromOffset(0, hh)
	local D = 26
	local n = math.ceil((W - 10) / D)
	local x0 = (W - n * D) / 2
	local i = 0
	for _, d in ipairs(win.crest:GetChildren()) do
		if d.Name == "Wave" then
			i += 1
			d.Visible = i <= n
			d.Position = UDim2.fromOffset(x0 + (i - 1) * D, -1)
		end
	end
end
-- repaint a UI.window's header (the detail window wears the fish's rarity)
function K.paintHead(win, keys)
	if win.headKeys == keys then return end
	win.headKeys = keys
	UI.vgrad(win.header, ColorSequence.new({
		ColorSequenceKeypoint.new(0, keys[1]), ColorSequenceKeypoint.new(0.7, keys[2]), ColorSequenceKeypoint.new(1, keys[2]),
	}))
	local sq = win.header:FindFirstChild("Square")
	if sq then sq.BackgroundColor3 = keys[2] end
	for _, d in ipairs(win.crest:GetChildren()) do
		if d:IsA("Frame") then d.BackgroundColor3 = keys[2] end
	end
end
-- the Shop's sea behind the rows: soft light rays and rising bubbles in a window's Ocean layer
function K.sea(ocean, n, rayXs)
	local s = { rays = {}, bubbles = {} }
	for i, x in ipairs(rayXs or {}) do
		local ray = UI.new("Frame", {
			Name = "Ray", BackgroundColor3 = WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, ocean)
		UI.new("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(s.rays, { f = ray, phase = i * 1.3 })
	end
	for i = 1, n do
		local sz = 6 + (i * 7) % 13
		local b = UI.new("Frame", {
			Name = "Bubble", BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, AnchorPoint = V2(0.5, 0.5),
			Size = UDim2.fromOffset(sz, sz), ZIndex = 2,
		}, ocean)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		UI.new("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		local bb = { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i }
		b.Position = UDim2.new(bb.x, 0, bb.y, 0)
		table.insert(s.bubbles, bb)
	end
	return s
end
function K.stepSea(s, dt, t)
	for _, b in ipairs(s.bubbles) do
		b.y -= b.speed * dt
		if b.y < -0.05 then
			b.y = 1.05
			b.x = (b.x + 0.37) % 1
		end
		b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
	end
	for _, r in ipairs(s.rays) do
		r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
	end
end

-- ===== root gui =====
local gui
if script.Parent:IsA("ScreenGui") then
	gui = script.Parent
	for _,c in ipairs(gui:GetChildren()) do if c ~= script then c:Destroy() end end
else
	local ex = pg:FindFirstChild("IndexMenu"); if ex then ex:Destroy() end
	gui = Instance.new("ScreenGui"); gui.Name="IndexMenu"; gui.Parent=pg
end
gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.DisplayOrder = 26
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ===== window =====
local WIN_W, WIN_H = 1180, 700
-- the chrome that reaches past the window's box: the breakout book (44 above, 36 left) and the X (18 above, 18
-- right), the hard drop (9 below). Phone: a smaller book tucked in, so 18 / 18 / 9.
-- 2026-10-11 (the owner: "make the button uis centered to the phone screen"): on a phone all three windows are now
-- centred by MenuFit.centre and their icons sit INSIDE the 60px header, so nothing at the top-LEFT reaches above the
-- box: cUp = 0 is the reach centre is told (the X is not counted there). cT stays 18 in the phone sizing, so the
-- phone layouts keep their design width and only the scale drops (~9-12%) to clear the top bar.
local REACH = { T = 44, B = 9, X = 36, cT = 18, cB = 9, cX = 18, cUp = 0 }
-- MenuFit: shared with every other pop-up window in the game. On a small screen it makes the window SHORTER rather
-- than smaller, so the WIDTH drives the scale, and centres it below the Roblox top bar. MIN_H is the shortest
-- design height this layout survives: below the 158px of header + filter row everything is the Grid
-- ScrollingFrame, and 460 still shows a whole row of cards. Desktop and iPad keep the authored height.
local MIN_H = 460
-- PHONES (short side < 500) get their own layout instead of the desktop window shrunk to ~0.54: the window is
-- DESIGNED narrower there - 4 grid columns, a 60px header, a smaller book - so the scale lands near 0.8: the
-- design height is pinned to ~370 and the design width is whatever the screen gives at that scale. Everything is
-- re-decided on every ViewportSize change (LAY.after), never once at build.
-- ALL layout state lives in this ONE table (Luau's 200-locals-per-function ceiling).
local LAY = { compact = false, tablet = false, W = WIN_W, H = WIN_H, DW = 760, DH = 470, RW = 760, RH = 540, stats = {},
	DESK   = { cols = 6, gap = 14, cellH = 192, tankH = 118, nameY = 128, nameH = 28, nameTS = 19, sizeY = 157, sizeH = 22, sizeTS = 15, chipTS = 12, chipH = 20, badge = 26 },
	-- iPad: the desktop grid, but the rarity tag rendered 10.5px there
	TABLET = { cols = 6, gap = 14, cellH = 192, tankH = 118, nameY = 128, nameH = 28, nameTS = 19, sizeY = 157, sizeH = 22, sizeTS = 15, chipTS = 14, chipH = 22, badge = 26 },
	PHONE  = { cols = 4, gap = 12, cellH = 178, tankH = 108, nameY = 118, nameH = 28, nameTS = 20, sizeY = 147, sizeH = 24, sizeTS = 17, chipTS = 15, chipH = 24, badge = 30 },
}
LAY.cur = LAY.DESK
-- viewport, the usable height below the platform top bar (MenuFit's own formula), inset
function LAY.screen()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.zero
	local inset = GuiService:GetGuiInset().Y
	return vp, math.max(160, vp.Y - inset - 12), inset
end

-- IX: the window's parts
local IX = {}
-- the scrim: a dark full-screen BUTTON under the window - a tap outside the window closes the Index (a Frame
-- would let the tap through to the MenuBar and the water behind)
IX.backdrop = UI.new("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = C(2,10,26),
	BackgroundTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(4, 4), ZIndex = 1,
}, gui)
IX.win = UI.window(gui, "INDEX", { Name = "Window", w = WIN_W, h = WIN_H, emoji = "📖", headColour = "teal", ZIndex = 5 })
local root = IX.win.root
local uiscale = UI.new("UIScale", {}, root)
-- the window catches its own taps (over Shadow / Body, under everything else) and so does the breakout book
UI.corner(K.guard(root, UDim2.new(1, 0, 1, 9), 3), 24)
K.guard(IX.win.icon, UDim2.new(1, 0, 1, 5), 20)
IX.sea = K.sea(IX.win.ocean, 26, { 0.1, 0.3, 0.5, 0.7, 0.9 })

-- progress: a green meter on a navy track in the header ("12 / 61 discovered")
IX.prog = {}
IX.prog.root = UI.new("Frame", { Name = "Progress", BackgroundTransparency = 1, Size = UDim2.fromOffset(380, 44), Position = UDim2.fromOffset(480, 13), ZIndex = 7 }, root)
UI.hardShadow(IX.prog.root, 14, 4, 5, 1)
IX.prog.track = UI.new("Frame", { Name = "Track", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, IX.prog.root)
UI.corner(IX.prog.track, 14)
UI.stroke(IX.prog.track, 4)
UI.vgrad(IX.prog.track, { UI.KEY.navy.hi, UI.KEY.navy.base })
IX.prog.fill = UI.new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(0, 0, 1, -8), ZIndex = 2 }, IX.prog.track)
UI.corner(IX.prog.fill, 10)
UI.vgrad(IX.prog.fill, UI.BRICK.green)
UI.gloss(IX.prog.fill, { frac = 0.5, alpha = 0.5, inset = 2, radius = 8, ZIndex = 1 })
IX.prog.label = K.text(IX.prog.track, "0 / 61 discovered", 22, { Name = "Count", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), drop = 2, ZIndex = 4 })

-- REWARDS: a candy key in the header (gold; green with a red "!" while something is ready to claim). Parented to
-- the window ROOT - never to a frame with a layout, which would lay it out as another chip.
IX.rw = UI.candyKey(root, "gold", { Name = "RewardsButton", Size = UDim2.fromOffset(210, 52), Position = UDim2.fromOffset(874, 9), ZIndex = 7 })
IX.dot = UI.new("Frame", {
	Name = "Dot", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 6, 0, -8), Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = WHITE, Visible = false, ZIndex = 8,
}, IX.rw.button)
UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, IX.dot)
UI.stroke(IX.dot, 3)
UI.vgrad(IX.dot, UI.BRICK.red)
IX.dotTxt = K.text(IX.dot, "!", 18, { Name = "Mark", Size = UDim2.fromScale(1, 1), ZIndex = 2 })

-- ===== filter keys: ALL + one per rarity (gold = the one you're on, sea = the rest; a gem in each rarity's colour)
IX.filters = UI.new("Frame", { Name = "Filters", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 52), ZIndex = 6 }, root)
local FILTERS = { "All" }
for _, r in ipairs(RORDER) do table.insert(FILTERS, r) end
local currentFilter = "All"; local chips = {}; local applyFilter
for _, name in ipairs(FILTERS) do
	local k = UI.candyKey(IX.filters, "sea", { Name = "Filter_" .. name, Size = UDim2.fromOffset(120, 46), ZIndex = 2 })
	k.word = string.upper(name)
	k.gem = name ~= "All" and RCOLOR[name] or nil
	TouchKit.press(k.button, function() currentFilter = name; applyFilter() end)
	chips[name] = k
end
-- lay the keys out centred over the row: each as wide as its word (+ gem); if the row cannot fit the words at
-- `ts`, the type shrinks, and if that costs more than 15% the gems go first
function LAY.filters(W, h, ts, margin, gap)
	local avail = W - 2 * margin
	local function measure(withGem, size)
		local total = 0
		for _, name in ipairs(FILTERS) do
			local k = chips[name]
			local gw = (withGem and k.gem) and (math.floor(size * 0.8) + 6) or 0
			k.w = math.ceil(UI.textWidth(k.word, size)) + 30 + gw
			total += k.w
		end
		return total + gap * (#FILTERS - 1)
	end
	local gems, size = true, ts
	local total = measure(true, size)
	while total > avail and size > 12 do size -= 1; total = measure(true, size) end
	if size < ts * 0.85 then
		gems, size = false, ts
		total = measure(false, size)
		while total > avail and size > 10 do size -= 1; total = measure(false, size) end
	end
	local grow = math.clamp(math.floor((avail - total) / #FILTERS), 0, 20)
	total += grow * #FILTERS
	local x = math.floor((W - total) / 2)
	for _, name in ipairs(FILTERS) do
		local k = chips[name]
		k.button.Size = UDim2.fromOffset(k.w + grow, h)
		k.button.Position = UDim2.fromOffset(x, 0)
		x += k.w + grow + gap
		local parts = { { text = k.word, size = size } }
		if gems and k.gem then
			parts = { { icon = "gem", size = math.floor(size * 0.8), drop = 0 }, { text = k.word, size = size, gap = 6 } }
		end
		k.setParts(nil, parts)
		local img = gems and k.gem and k.parts[1] and k.parts[1].obj
		if img and not img:FindFirstChild("Gem") then
			-- the gem: a glossy disc in the rarity's colour, drawn into the key's (imageless) icon slot
			local g = UI.new("Frame", { Name = "Gem", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, img)
			UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, g)
			UI.stroke(g, 2.5)
			UI.vgrad(g, PAL.from(k.gem, 0.35, 0.05))
			local sh = UI.new("Frame", { Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, Position = UDim2.fromScale(0.2, 0.14), Size = UDim2.fromScale(0.36, 0.26), ZIndex = 2 }, g)
			UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, sh)
		end
	end
end
-- the desktop row and key faces once at build, so nothing is blank if the viewport is not ready yet (LAY.after
-- lays them out again on every fit)
LAY.filters(WIN_W, 46, 22, 22, 10)
IX.rw.setParts(nil, { { icon = "treasure", size = 44, drop = 0 }, { text = "REWARDS", size = 26, gap = 8 } })

-- ===== grid scroller (the Shop's scroll style: a gold thumb over a faint INK track) =====
IX.track = UI.new("Frame", {
	Name = "GridTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	Position = UDim2.new(1, -26, 0, 158), Size = UDim2.new(0, 10, 1, -172), ZIndex = 4,
}, root)
UI.corner(IX.track, 5)
local scroller = UI.new("ScrollingFrame", {
	Name = "Grid", Active = true, BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 158), Size = UDim2.new(1, -32, 1, -172),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 10,
	ScrollBarImageColor3 = UI.SCROLL.thumb, ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarInset = Enum.ScrollBarInset.None, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = 5,
}, root)
UI.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 22), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 14) }, scroller)
-- cells are sized so the columns fill the scroller (LAY.after re-derives them for the current width)
local grid = UI.new("UIGridLayout", {
	CellSize = UDim2.fromOffset(175, LAY.DESK.cellH), CellPadding = UDim2.fromOffset(14, 14),
	HorizontalAlignment = Enum.HorizontalAlignment.Left, SortOrder = Enum.SortOrder.LayoutOrder,
}, scroller)

-- ===== discovered state (hooks) =====
-- Starts EMPTY: every species is a silhouette until it is actually caught.
-- Cards only reveal via markDiscovered (IndexRemotes.Discover / Discover / DevDiscover).
local discovered={}
-- SAVED COLLECTION (SaveServer writes IndexSeen - a JSON list of species names - before this script starts).
-- Restored silently: never through markDiscovered, which would pay the bounty and announce it in chat again.
pcall(function()
	for _,n in ipairs(game:GetService("HttpService"):JSONDecode(plr:GetAttribute("IndexSeen") or "[]")) do
		if type(n)=="string" then discovered[n]=true end
	end
end)

-- ===== viewport helpers =====
local CAM_DIR=Vector3.new(0.5,0.42,1).Unit
-- Fit the model's actual bounding box inside the viewport, accounting for the
-- viewport's aspect ratio (portrait tanks fit less horizontally) + a padding margin.
local function frameModel(vpf, clone, aspect, margin)
	local cf,size=clone:GetBoundingBox()
	local cam=Instance.new("Camera"); cam.FieldOfView=50; vpf.CurrentCamera=cam; cam.Parent=vpf
	aspect = aspect or ((vpf.AbsoluteSize.Y>0) and (vpf.AbsoluteSize.X/vpf.AbsoluteSize.Y) or 1)
	local tanV = math.tan(math.rad(25))        -- half of the 50° vertical FOV
	local tanH = tanV * aspect                 -- horizontal half-angle
	local halfH = size.Y*0.5 + math.max(size.X,size.Z)*0.12  -- vertical extent (+slight tilt)
	local halfW = math.max(size.X, size.Z)*0.5               -- horizontal extent
	local dist = math.max(halfH/tanV, halfW/tanH) * (margin or 1.28)
	dist = math.max(dist, 3)
	cam.CFrame=CFrame.lookAt(cf.Position+CAM_DIR*dist, cf.Position)
	return cam, cf.Position, dist
end
local function makeSil(model)
	local c=model:Clone()
	for _,p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then p.Color=C(18,32,58); p.Material=Enum.Material.SmoothPlastic; p.Transparency=0 end end
	return c
end

-- ===== cards =====
local cards={}     -- name -> entry
local spinning=nil
local order=0
local openDetail

local function buildViewport(entry)
	if entry.built then return end
	entry.built=true
	local f=entry.fish
	local src=FishModels:FindFirstChild(f.model); if not src then return end
	local vpf=Instance.new("ViewportFrame"); vpf.Name="Fish"; vpf.BackgroundTransparency=1; vpf.Size=UDim2.new(1,-6,1,-6); vpf.Position=UDim2.fromOffset(3,3); vpf.ZIndex=4
	vpf.Ambient = entry.disc and C(206,224,238) or C(120,138,162); vpf.LightColor=C(255,255,255); vpf.LightDirection=Vector3.new(-0.35,-1,-0.55)
	vpf.Parent=entry.tank
	pcall(function()
		local clone = entry.disc and src:Clone() or makeSil(src)
		clone.Parent=vpf
		local ta = (entry.tank.AbsoluteSize.Y>0) and (entry.tank.AbsoluteSize.X/entry.tank.AbsoluteSize.Y) or 1.35
		local cam,center,dist=frameModel(vpf, clone, ta)
		entry.cam=cam; entry.center=center; entry.dist=dist; entry.model=clone
	end)
	entry.vpf=vpf
end

-- a card's colours and words for its state: a discovered fish wears its rarity's candy, a bright tank, its
-- rarity tag and a green tick; an undiscovered one is a slate card with a silhouette, "???" and a "?"
function K.paintCard(e)
	local f, disc = e.fish, e.disc
	UI.vgrad(e.face, disc and PAL.candy(f.rarity) or PAL.unknown)
	K.paintTank(e.tank, disc)
	e.q.Visible = not disc
	e.chip.set(disc and string.upper(f.rarity) or "???", disc and PAL.from(RCOLOR[f.rarity] or C(150,160,175), 0.15, 0.15) or PAL.unknownChip)
	e.tick.Visible, e.qmark.Visible = disc, not disc
	UI.vgrad(e.badge, disc and PAL.tick or PAL.unknownChip)
	-- An undiscovered card says unknown ONCE: the silhouette under the big question mark. The ??? tag and the
	-- ? badge on top of it made three question marks per card (the owner's playtest sweep, 2026-10-10), so both
	-- hide until the fish is caught; the rarity tag and the green tick arrive with the discovery.
	e.chip.root.Visible, e.badge.Visible = disc, disc
	e.nameL.Text = disc and f.name or "? ? ?"
	e.sizeL.Text = disc and (f.sizeClass .. " \u{00B7} " .. f.lengthCm .. " cm") or "Undiscovered"
	e.sizeL.TextColor3 = disc and UI.TEXT.white or UI.TEXT.soft
end
-- one grid card's inner layout for the current tier (LAY.cur)
function LAY.card(e)
	local L = LAY.cur
	e.tank.Size = UDim2.new(1, -14, 0, L.tankH)
	e.nameL.Position = UDim2.fromOffset(8, L.nameY); e.nameL.Size = UDim2.new(1, -16, 0, L.nameH); K.setMax(e.nameL, L.nameTS)
	e.sizeL.Position = UDim2.fromOffset(8, L.sizeY); e.sizeL.Size = UDim2.new(1, -16, 0, L.sizeH); K.setMax(e.sizeL, L.sizeTS)
	e.badge.Size = UDim2.fromOffset(L.badge, L.badge)
	K.setMax(e.qmark, math.floor(L.badge * 0.7))
	-- the rarity tag must stay clear of the badge in the narrowest cell
	local maxW = (grid.CellSize.X.Offset - 14) - L.badge - 18
	local ts = L.chipTS
	while ts > 9 and UI.textWidth(e.chip.label.Text, ts) + 2 * e.chip.pad + 4 > maxW do ts -= 1 end
	e.chip.set(nil, nil, ts, L.chipH)
end

local function styleDiscovered(entry)
	entry.disc=true
	-- the silhouette's viewport goes; markDiscovered builds the real fish into the same tank
	if entry.vpf then entry.vpf:Destroy(); entry.vpf=nil end
	entry.built=false; entry.model=nil; entry.cam=nil
	K.paintCard(entry)
	LAY.card(entry)
end

local function makeCard(f)
	order=order+1
	local e = { fish = f, disc = discovered[f.name] == true }
	-- a candy card: INK drop, a face in the rarity's colour with a gloss cap, the water tank on top
	local btn = UI.new("TextButton", {
		Name = f.name, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = order,
		Size = UDim2.fromOffset(160, 188), ZIndex = 2,
	})
	e.btn = btn
	e.scale = UI.new("UIScale", {}, btn)
	UI.hardShadow(btn, 16, 3.5, 5, 1)
	e.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, btn)
	UI.corner(e.face, 16)
	UI.stroke(e.face, 3.5)
	UI.gloss(e.face, { frac = 0.3, alpha = 0.5, inset = 3, radius = 13, ZIndex = 1 })
	e.tank = K.tank(btn, e.disc, 12, { ZIndex = 3 })
	e.tank.Position = UDim2.fromOffset(7, 7)
	e.q = K.text(e.tank, "?", 60, { Name = "Unknown", Size = UDim2.fromScale(1, 0.84), ZIndex = 6, drop = 3 })
	-- rarity tag (top-left) and the discovered badge (top-right) on the glass
	e.chip = K.pill(e.tank, { Name = "Rarity", Position = UDim2.fromOffset(6, 6), ZIndex = 8, stroke = 2 })
	e.badge = UI.new("Frame", {
		Name = "Badge", BackgroundColor3 = WHITE, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26), ZIndex = 8,
	}, e.tank)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, e.badge)
	UI.stroke(e.badge, 2)
	e.tick = UI.icon(e.badge, "check", UDim2.fromScale(0.7, 0.7), {
		Name = "Tick", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2, flat = true,
	})
	e.qmark = K.text(e.badge, "?", 18, { Name = "Q", Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	e.nameL = K.text(btn, "", 19, { Name = "FishName", ZIndex = 6, drop = 2 })
	e.sizeL = K.text(btn, "", 15, { Name = "Size", ZIndex = 6 })
	cards[f.name] = e
	K.paintCard(e)
	LAY.card(e)
	btn.Parent = scroller

	btn.MouseEnter:Connect(function()
		TweenService:Create(e.scale, TweenInfo.new(0.12,Enum.EasingStyle.Back), {Scale=1.06}):Play()
		if e.disc and e.vpf then spinning=e end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(e.scale, TweenInfo.new(0.12), {Scale=1}):Play()
		if spinning==e then spinning=nil end
	end)
	TouchKit.press(btn, function()
		if e.disc then openDetail(e)
		else TweenService:Create(e.scale, TweenInfo.new(0.05,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,3,true), {Scale=0.95}):Play() end
	end)
	return e
end
for _,f in ipairs(FishData.fish) do makeCard(f) end

-- ===== progress =====
local function updateProgress()
	local n=0; for _,f in ipairs(FishData.fish) do if discovered[f.name] then n=n+1 end end
	local total=#FishData.fish
	local frac=n/total
	IX.prog.label.Text = n .. " / " .. total .. " discovered" .. DOT .. math.floor(frac * 100 + 0.5) .. "%"
	TweenService:Create(IX.prog.fill, TweenInfo.new(0.5,Enum.EasingStyle.Quad), {Size=UDim2.new(frac, -8 * frac, 1, -8)}):Play()
	gui:SetAttribute("Discovered", n); gui:SetAttribute("Total", total)
end

-- ===== lazy viewport culling =====
local function refreshVisible()
	local h=scroller.AbsoluteSize.Y
	for _,f in ipairs(FishData.fish) do
		local e=cards[f.name]
		if e and e.btn.Visible then
			local relY=e.btn.AbsolutePosition.Y - scroller.AbsolutePosition.Y
			local inband = (relY < h+150) and (relY + e.btn.AbsoluteSize.Y > -150)
			if inband then buildViewport(e); if e.vpf then e.vpf.Visible=true end
			elseif e.vpf then e.vpf.Visible=false; if spinning==e then spinning=nil end end
		end
	end
end
scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshVisible)
scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshVisible)

-- ===== filter =====
function applyFilter()
	for name, k in pairs(chips) do
		local on = name == currentFilter
		if k.lit ~= on then
			k.lit = on
			k.recolour(on and "gold" or "sea")
		end
	end
	for _,f in ipairs(FishData.fish) do local e=cards[f.name]; if e then e.btn.Visible=(currentFilter=="All") or (f.rarity==currentFilter) end end
	scroller.CanvasPosition=Vector2.new(0,0)
	task.defer(refreshVisible)
end

-- ================= DETAIL OVERLAY (aquarium) =================
-- A window of its own over a dim backdrop: the fish's name as the title on a header in its RARITY's colour, the
-- aquarium on the left in a rarity-coloured frame, its rarity tag, three stat slabs and the field note on the right.
local DT = {}
local detail = UI.new("Frame", { Name = "Detail", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20 }, gui)
DT.back = UI.new("TextButton", {
	Name = "DetailBackdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = C(2,10,26),
	BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1), ZIndex = 1,
}, detail)
-- built at its widest (the phone's 900) so the crest always has discs enough; LAY.detail sizes it
DT.win = UI.window(detail, "", { Name = "DetailWindow", w = 900, h = 470, emoji = "🐠", headColour = "teal", ZIndex = 2 })
local dwin = DT.win.root
DT.win.close.button.Name = "DetailClose"   -- NOT "TextButton": closeButtonOf must only ever find the main window's X
local dscale = UI.new("UIScale", {}, dwin)
UI.corner(K.guard(dwin, UDim2.new(1, 0, 1, 9), 3), 24)
K.guard(DT.win.icon, UDim2.new(1, 0, 1, 5), 20)
DT.sea = K.sea(DT.win.ocean, 10, { 0.2, 0.62 })
-- LEFT: the aquarium in a frame of the rarity's candy
DT.frame, DT.frameFace = K.slab(dwin, PAL.candy("Rare"), { Name = "TankFrame", ZIndex = 5, radius = 22, stroke = 4, dy = 6, frac = 0.3 })
DT.tank = K.tank(dwin, true, 16, { Name = "Tank", ZIndex = 6, stroke = 3 })
local dvp=Instance.new("ViewportFrame"); dvp.Name="Fish"; dvp.BackgroundTransparency=1; dvp.Size=UDim2.fromScale(1,1); dvp.ZIndex=4; dvp.Parent=DT.tank
dvp.Ambient=C(210,226,240); dvp.LightColor=C(255,255,255); dvp.LightDirection=Vector3.new(-0.35,-1,-0.55)
-- tank bubbles
local tankBubbles={}
local tbLayer=Instance.new("Frame"); tbLayer.Name="Bubbles"; tbLayer.BackgroundTransparency=1; tbLayer.Size=UDim2.fromScale(1,1); tbLayer.ClipsDescendants=true; tbLayer.ZIndex=5; tbLayer.Parent=DT.tank
for i=1,12 do
	local b=Instance.new("Frame"); b.BackgroundColor3=Color3.new(1,1,1); b.BackgroundTransparency=0.5; b.BorderSizePixel=0
	local s=math.random(6,16); b.Size=UDim2.fromOffset(s,s); b.Position=UDim2.fromScale(math.random(),math.random()); b.ZIndex=1
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	UI.new("UIStroke", { Color = WHITE, Thickness = 1, Transparency = 0.55 }, b)
	b.Parent=tbLayer; tankBubbles[i]={f=b, sp=math.random(6,16)/100}
end
-- id tag on the glass ("#12 / 61")
DT.idTag = K.pill(DT.tank, { Name = "IdTag", ts = 15, h = 26, pad = 10, ZIndex = 8, stroke = 2.5, AnchorPoint = V2(0, 1), Position = UDim2.new(0, 10, 1, -10) })
DT.idTag.set("#1", { UI.KEY.navy.hi, UI.KEY.navy.base })
-- RIGHT: rarity tag, the stats, the field note
DT.rar = K.pill(dwin, { Name = "Rarity", ts = 22, h = 38, pad = 18, ZIndex = 6, stroke = 3.5, dy = 4 })
for i, s in ipairs({ { "📏", "Size" }, { "📐", "Length" }, { "🌊", "Habitat" } }) do
	local slab, face = K.slab(dwin, UI.CANDY.royal, { Name = "Stat" .. s[2], ZIndex = 5, radius = 12, stroke = 3, dy = 4, frac = 0.5 })
	local st = { root = slab, face = face }
	st.ic = K.text(face, s[1], 22, { Name = "Icon", Size = UDim2.new(0, 34, 1, 0), Position = UDim2.fromOffset(8, 0), ZIndex = 3, noStroke = true })
	st.l = K.text(face, s[2], 18, { Name = "Key", align = "left", color = UI.TEXT.soft, Size = UDim2.new(0.42, -46, 1, -6), Position = UDim2.fromOffset(46, 3), ZIndex = 3 })
	st.v = K.text(face, "", 20, { Name = "Value", align = "right", Size = UDim2.new(0.58, -14, 1, -6), Position = UDim2.new(0.42, 0, 0, 3), ZIndex = 3, drop = 2 })
	LAY.stats[i] = st
end
DT.note, DT.noteFace = K.slab(dwin, UI.CANDY.purple, { Name = "FieldNote", ZIndex = 5, radius = 16, stroke = 3.5, dy = 5, frac = 0.3 })
DT.noteHead = K.text(DT.noteFace, "FIELD NOTE", 18, { Name = "Heading", color = UI.TEXT.gold, Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 8), ZIndex = 3, drop = 2 })
DT.desc = K.text(DT.noteFace, "", 21, { Name = "Desc", wrap = true, Size = UDim2.new(1, -28, 1, -44), Position = UDim2.fromOffset(14, 34), ZIndex = 3, drop = 2 })

-- Phone layout of the detail window: 470 -> 380 tall and wider (fitDetail sets LAY.DW), the tank shorter, the right
-- column stretched to the width, the type a notch larger.
function LAY.detail(c)
	local W = LAY.DW
	local hh = c and 60 or 74
	K.head(DT.win, hh, W)
	-- phone: the fish tucked INSIDE the header, left of the title at 74, not breaking out above it (REACH.cUp)
	DT.win.icon.Size = UDim2.fromOffset(c and 56 or 124, c and 56 or 124)
	DT.win.icon.Position = UDim2.fromOffset(c and 8 or -36, c and 2 or -44)
	local tx = c and 74 or 112
	DT.win.title.Position = UDim2.fromOffset(tx, 0)
	DT.win.title.Size = UDim2.fromOffset(W - tx - 60, hh)
	K.setMax(DT.win.title, c and 36 or 46)
	-- the aquarium: an 8px band of the rarity's candy around the water
	local fx, fy, fw, fh = c and 16 or 22, c and 74 or 92, c and 296 or 316, c and 290 or 356
	DT.frame.Position = UDim2.fromOffset(fx, fy); DT.frame.Size = UDim2.fromOffset(fw, fh)
	DT.tank.Position = UDim2.fromOffset(fx + 8, fy + 8); DT.tank.Size = UDim2.fromOffset(fw - 16, fh - 16)
	DT.idTag.set(nil, nil, c and 17 or 15, c and 28 or 26)
	-- the right column
	local rx = fx + fw + (c and 18 or 22)
	local rw = W - rx - (c and 20 or 26)
	DT.rar.root.Position = UDim2.fromOffset(rx, fy + 2)
	DT.rar.set(nil, nil, c and 20 or 22, c and 34 or 38)
	local sy, sh, step = c and 120 or 146, c and 36 or 42, c and 42 or 50
	for i, st in ipairs(LAY.stats) do
		st.root.Position = UDim2.fromOffset(rx, sy + (i - 1) * step)
		st.root.Size = UDim2.fromOffset(rw, sh)
		K.setMax(st.l, c and 17 or 18)
		K.setMax(st.v, c and 19 or 20)
	end
	local ny = sy + 3 * step + (c and 6 or 8)
	DT.note.Position = UDim2.fromOffset(rx, ny)
	DT.note.Size = UDim2.fromOffset(rw, fy + fh - ny)
	K.setMax(DT.noteHead, c and 17 or 18)
	K.setMax(DT.desc, c and 19 or 21)
end
local function fitDetail()
	local vp, availH = LAY.screen()
	if vp.X < 100 or vp.Y < 100 then return end
	local c = math.min(vp.X, vp.Y) < 500
	local rt, rb, rx = c and REACH.cT or REACH.T, c and REACH.cB or REACH.B, c and REACH.cX or REACH.X
	local s
	if c then
		-- phone: a wider, shorter card (380 tall), centred on the screen below (MenuFit.centre)
		s = math.clamp(availH / (380 + rt + rb), 0.6, 0.95)
		LAY.DW, LAY.DH = math.clamp(math.floor((vp.X - 24) / s) - 2 * rx, 760, 900), 380
	else
		LAY.DW, LAY.DH = 760, 470
		s = math.clamp(math.min(vp.X / (820 + 2 * rx), vp.Y / (540 + rt + rb)), 0.4, 1.12)
		dwin.Position = UDim2.new(0.5, 0, 0.5, math.floor((rt - rb) / 2 * s + 0.5))
	end
	dscale.Scale = s
	dwin.Size = UDim2.fromOffset(LAY.DW, LAY.DH)
	-- 2026-10-11, "centered to the phone screen": a phone's card is centred on the real screen (it sat centred in the
	-- band below the top bar), shrinking only as far as the bar needs. Desktop and iPad keep their placement above.
	if c then MenuFit.centre(dwin, dscale, REACH.cUp, rb) end
	LAY.detail(c)
end

local detailCam, detailCenter, detailDist, detailModel
local function closeDetail()
	detail.Visible=false
	if detailModel then detailModel:Destroy(); detailModel=nil end
	detailCam=nil
	scroller.Visible=true
	task.defer(refreshVisible)
end
TouchKit.press(DT.win.close.button, closeDetail)
TouchKit.press(DT.back, closeDetail)

function openDetail(entry)
	fitDetail()
	local f=entry.fish; local rcol=RCOLOR[f.rarity] or C(150,160,175)
	DT.win.title.Text=f.name
	K.paintHead(DT.win, PAL.headKeys(f.rarity))
	UI.vgrad(DT.frameFace, PAL.candy(f.rarity))
	DT.rar.set(string.upper(f.rarity), PAL.from(rcol, 0.2, 0.12))
	LAY.stats[1].v.Text=f.sizeClass; LAY.stats[2].v.Text=f.lengthCm.." cm"; LAY.stats[3].v.Text=f.habitat
	DT.desc.Text='"'..f.desc..'"'
	DT.idTag.set("#"..f.id.." / "..#FishData.fish)
	if detailModel then detailModel:Destroy(); detailModel=nil end
	for _,ch in ipairs(dvp:GetChildren()) do if ch:IsA("Camera") then ch:Destroy() end end
	local src=FishModels:FindFirstChild(f.model)
	if src then pcall(function()
		local clone=src:Clone(); clone.Parent=dvp
		local cam,center,dist=frameModel(dvp, clone, DT.tank.Size.X.Offset/DT.tank.Size.Y.Offset)
		detailCam=cam; detailCenter=center; detailDist=dist; detailModel=clone
	end) end
	scroller.Visible=false       -- stop grid viewports rendering -> smooth spin
	spinning=nil
	detail.Visible=true
	-- pop in
	local target = dscale.Scale
	dscale.Scale = target * 0.92
	TweenService:Create(dscale, TweenInfo.new(0.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Scale=target}):Play()
end

-- ================= COLLECTION REWARDS =================
-- "The Index should give rewards." Filling the book now pays, two ways:
--
--   1. a one-off DISCOVERY BOUNTY the moment a species first enters the book, scaled
--      by rarity - this is what makes a new fish feel like a find at the moment it
--      happens, and it fires during normal fishing with the menu shut (hence its own
--      always-on toast ScreenGui, not a Frame inside this window);
--   2. a claimable REWARDS ladder behind the REWARDS key in the header: twelve count
--      milestones (5 → 61 species) plus one bonus per rarity SET completed.
--
-- Claim state lives on the player as IX_<id> attributes - the same seam Quests uses for
-- QC_/QT_/MT_ - so a future authoritative server can persist and validate it without
-- this file changing. Coins go to leaderstats.Money when it exists (the ONE shared
-- balance GameClient earns into and every menu spends from), else the Coins attribute;
-- Pearls are the real rebirth currency RebirthController reads.

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
local function addPearls(n) plr:SetAttribute("Pearls", (plr:GetAttribute("Pearls") or 0) + n) end

local function rewardText(coins, pearls)
	local s = "💰 " .. UI.cash(coins or 0)
	if (pearls or 0) > 0 then s = s .. "   🦪 " .. pearls end
	return s
end

local function ixClaimed(id) return plr:GetAttribute("IX_" .. id) == true end

local function discoveredCount()
	local n = 0
	for _, f in ipairs(FishData.fish) do if discovered[f.name] then n = n + 1 end end
	return n
end
local function discoveredIn(rarity)
	local n = 0
	for _, f in ipairs(FishData.fish) do if f.rarity == rarity and discovered[f.name] then n = n + 1 end end
	return n
end
local RARITY_TOTAL = {}
for _, f in ipairs(FishData.fish) do RARITY_TOTAL[f.rarity] = (RARITY_TOTAL[f.rarity] or 0) + 1 end

-- Paid ONCE per species, the first time it is discovered. Sized against the rest of the
-- economy rather than by feel: the whole book is worth ~$7.9M in bounties, which is a
-- fraction of one maxed upgrade branch (~$28M) - a real reward for exploring, never a
-- substitute for fishing. Pearls only start at Epic so the common tail stays cash-only.
-- \226\154\160 A BOUNTY IS ONE EXTRA COPY OF THAT FISH, and it has to stay that way.
-- These were 20-41x the fish that earns them (Common 3,000 against a Common worth ~150), which
-- made the book, not fishing, the game's income. Measured before the fix: one cast sold $458 of
-- fish and paid $9,458 - 95% bounty - which is exactly the "I caught $800 and gained $10k" bug.
-- Each figure below is the MEAN sale value of that rarity: fishValue = RARITY_BASE * (1 + cm/70)
-- over the 61-fish roster gives 149.75 / 288.80 / 728.39 / 4,530 / 17,841 / 139,542.
-- If RARITY_BASE in GameClient is ever retuned, re-derive these from it.
local BOUNTY = {
	Common    = { coins = 150,     pearls = 0 },
	Uncommon  = { coins = 290,     pearls = 0 },
	Rare      = { coins = 730,     pearls = 0 },
	Epic      = { coins = 4500,    pearls = 1 },
	Legendary = { coins = 18000,   pearls = 2 },
	Mythic    = { coins = 140000,  pearls = 5 },
}
-- Count milestones. The last one is the whole book, so it is the biggest single payout
-- in the game outside a rebirth - 61/61 is the longest goal Tiny Fishing has.
-- Cut 20x alongside BOUNTY above - they have to move together or the ladder simply becomes the
-- new dominant faucet. PEARLS ARE DELIBERATELY UNCHANGED: pearls are already far too scarce for
-- what the rebirth perk grid charges, so thinning them would make a separate problem worse.
local COUNT_REWARDS = {
	{ n = 5,  coins = 750,      pearls = 0 },
	{ n = 10, coins = 2000,     pearls = 0 },
	{ n = 15, coins = 4500,     pearls = 1 },
	{ n = 20, coins = 9000,     pearls = 1 },
	{ n = 25, coins = 16000,    pearls = 2 },
	{ n = 30, coins = 30000,    pearls = 2 },
	{ n = 35, coins = 55000,    pearls = 3 },
	{ n = 40, coins = 100000,   pearls = 3 },
	{ n = 45, coins = 175000,   pearls = 4 },
	{ n = 50, coins = 300000,   pearls = 5 },
	{ n = 55, coins = 600000,   pearls = 8 },
	{ n = 61, coins = 1250000,  pearls = 20 },
}
-- Set bonuses. Mythic pays less than Legendary on purpose: it is a ONE-fish set, so the
-- Kraken's own bounty ($3M) is most of what completing it is worth.
local SET_REWARD = {
	Common    = { coins = 12500,   pearls = 1 },
	Uncommon  = { coins = 30000,   pearls = 2 },
	Rare      = { coins = 75000,   pearls = 3 },
	Epic      = { coins = 200000,  pearls = 6 },
	Legendary = { coins = 500000,  pearls = 12 },
	Mythic    = { coins = 250000,  pearls = 10 },
}

-- each reward's look: a count milestone is a reef row with two fish (a trophy from 40, a crown for the whole
-- book on a fire row); a set bonus is a star on its rarity's candy
local REWARD_LIST = {}
for _, r in ipairs(COUNT_REWARDS) do
	local whole, late = r.n >= #FishData.fish, r.n >= 40
	REWARD_LIST[#REWARD_LIST+1] = {
		id = "c" .. r.n,
		iconName = whole and "crown" or (late and "trophy" or "twofish"), iconFlat = whole or late,
		colour = whole and "fire" or (late and "royal" or "reef"),
		name = r.n .. " Species",
		blurb = "Fill the book to " .. r.n .. " of " .. #FishData.fish .. " species",
		goal = r.n, coins = r.coins, pearls = r.pearls,
		have = discoveredCount,
	}
end
for _, rar in ipairs(RORDER) do
	local total, rw = RARITY_TOTAL[rar] or 0, SET_REWARD[rar]
	if total > 0 and rw then
		REWARD_LIST[#REWARD_LIST+1] = {
			id = "s" .. rar, iconName = "star", iconFlat = true, colour = PAL.candy(rar),
			name = "Complete " .. rar,
			blurb = "Discover all " .. total .. " " .. rar .. " species",
			goal = total, coins = rw.coins, pearls = rw.pearls,
			have = function() return discoveredIn(rar) end,
		}
	end
end

local function claimableCount()
	local n = 0
	for _, e in ipairs(REWARD_LIST) do
		if not ixClaimed(e.id) and e.have() >= e.goal then n += 1 end
	end
	return n
end

-- ===== toast (its OWN ScreenGui) =====
-- A discovery happens while you are fishing, i.e. with this menu shut - a toast parented
-- to `gui` would never be seen. Top-centre, below the StatsHUD pills, above the menus.
-- The look: a candy pill (INK drop, a gradient in the toast's colour, a gloss cap, white type) inside a
-- CanvasGroup, so ONE GroupTransparency tween fades every piece of it together.
local toastGui = pg:FindFirstChild("IndexToast")
if not toastGui then
	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "IndexToast"; toastGui.ResetOnSpawn = false; toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 60; toastGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toastGui.Parent = pg
end
for _, c in ipairs(toastGui:GetChildren()) do c:Destroy() end
local T = {}
-- the group is the pill + its 14px of chrome (4 each side for the outline, 5 more below for the drop)
T.group = UI.new("CanvasGroup", {
	Name = "Toast", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152), Size = UDim2.fromOffset(470, 66),
	BackgroundTransparency = 1, Visible = false, ZIndex = 2,
}, toastGui)
T.shadow = UI.new("Frame", { Name = "Shadow", BackgroundColor3 = INK, Position = UDim2.fromOffset(4, 9), Size = UDim2.new(1, -8, 1, -13), ZIndex = 1 }, T.group)
T.shadowCorner = UI.corner(T.shadow, 26)
UI.stroke(T.shadow, 3)
T.body = UI.new("Frame", { Name = "Body", BackgroundColor3 = WHITE, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -13), ZIndex = 2 }, T.group)
T.bodyCorner = UI.corner(T.body, 26)
UI.stroke(T.body, 3)
UI.vgrad(T.body, PAL.from(C(74,204,120)))
UI.gloss(T.body, { frac = 0.5, alpha = 0.45, inset = 3, radius = 20, ZIndex = 1 })
T.txt = K.text(T.body, "", 18, { Name = "Text", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -30, 0, 26), ZIndex = 3 })
local toastToken = 0
local fadeTweens = {}
-- WHERE the toast goes: the NOTICE SLOT that IdleClient publishes on AfkHUD (HUD_CONTRACT §1/§2),
-- in LOCAL px - every HUD gui here is IgnoreGuiInset + DeviceSafeInsets, so they share one origin.
-- It sits under the pills / AutoToggle / meters, under the AFK pill while that is up, and in the
-- phone's MAIN lane. The old constant y 152 overlapped the meters row (124..168 on an iPhone 7,
-- 158..220 on a laptop) and, 360px wide on a phone, the left lane's boost chips too.
-- Returns the centre x and top y; sizes the toast to the lane (pill width <= 470).
function LAY.toastSlot()
	local W = toastGui.AbsoluteSize.X
	if W < 100 then W = workspace.CurrentCamera.ViewportSize.X end
	local afk = pg:FindFirstChild("AfkHUD")
	local l = afk and afk:GetAttribute("NoticeLeft") or W * 0.25
	local r = afk and afk:GetAttribute("NoticeRight") or W * 0.75
	local top = afk and afk:GetAttribute("NoticeTop") or 152
	local pill = afk and afk.Enabled and afk:FindFirstChild("AfkPill")
	if pill and pill.Visible then
		-- below the pill's ink (its 3px stroke) with a small gap
		top = math.max(top, pill.AbsolutePosition.Y - afk.AbsolutePosition.Y + pill.AbsoluteSize.Y + 8)
	end
	local h = LAY.compact and 40 or 52
	T.group.Size = UDim2.fromOffset(math.max(160, math.min(470, math.floor(r - l))) + 8, h + 13)
	T.bodyCorner.CornerRadius = UDim.new(0, math.floor(h / 2))
	T.shadowCorner.CornerRadius = UDim.new(0, math.floor(h / 2))
	return math.floor((l + r) / 2 + 0.5), math.floor(top + 0.5)
end
local function showToast(text, colour)
	toastToken += 1; local mine = toastToken
	-- \226\154\160 The token only guards the DELAYED callbacks - it cannot stop a fade that has already
	-- started, and TweenService only cancels an earlier tween when a new one targets the SAME
	-- property. The re-entry below only tweens Position, so without this cancel the previous
	-- fade keeps driving the group's transparency to 1 and the NEW toast is invisible for its whole
	-- life. Reachable with two discoveries 2.1-2.5s apart, i.e. across two hauls.
	for _, t in ipairs(fadeTweens) do t:Cancel() end
	fadeTweens = {}
	T.txt.Text = text
	UI.vgrad(T.body, PAL.from(colour or C(74,204,120), 0.3, 0.1))
	T.group.Visible = true; T.group.GroupTransparency = 0
	local tx, ty = LAY.toastSlot()
	T.group.Position = UDim2.new(0, tx, 0, ty - 16)
	TweenService:Create(T.group, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, tx, 0, ty) }):Play()
	task.delay(2.1, function()
		if mine ~= toastToken then return end
		fadeTweens = { TweenService:Create(T.group, TweenInfo.new(0.4), { GroupTransparency = 1 }) }
		for _, t in ipairs(fadeTweens) do t:Play() end
		task.delay(0.44, function() if mine == toastToken then T.group.Visible = false end end)
	end)
end

-- ===== the rewards window =====
local RWD = {}
local rwOverlay = UI.new("Frame", { Name = "RewardsOverlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 34 }, gui)
RWD.back = UI.new("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = C(2,10,26),
	BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1), ZIndex = 1,
}, rwOverlay)
local RW_W, RW_H, RW_ROW_H = 760, 540, 108
-- built at its widest (the phone's 1000) so the crest always has discs enough; LAY.rewards sizes it
RWD.win = UI.window(rwOverlay, "COLLECTION REWARDS", { Name = "RewardsWindow", w = 1000, h = RW_H, icon = "treasure", headColour = "teal", ZIndex = 2 })
local rwWin = RWD.win.root
RWD.win.close.button.Name = "RewardsClose"   -- NOT "TextButton" (see the contract)
local rwScale = UI.new("UIScale", {}, rwWin)
UI.corner(K.guard(rwWin, UDim2.new(1, 0, 1, 9), 3), 24)
K.guard(RWD.win.icon, UDim2.new(1, 0, 1, 5), 20)
RWD.sea = K.sea(RWD.win.ocean, 16, { 0.15, 0.45, 0.78 })
-- "12 / 61 discovered · 2 rewards ready to claim!" under the header
RWD.sub = K.text(rwWin, "", 22, { Name = "Status", rich = true, Size = UDim2.new(1, -48, 0, 30), Position = UDim2.fromOffset(24, 86), ZIndex = 6, drop = 2 })
RWD.track = UI.new("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	Position = UDim2.new(1, -28, 0, 122), Size = UDim2.new(0, 10, 1, -136), ZIndex = 4,
}, rwWin)
UI.corner(RWD.track, 5)
local rwList = UI.new("ScrollingFrame", {
	Name = "RewardList", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 122), Size = UDim2.new(1, -28, 1, -136),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb, VerticalScrollBarInset = Enum.ScrollBarInset.None,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = 5,
}, rwWin)
UI.new("UIListLayout", { Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }, rwList)
UI.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 16) }, rwList)

local rwRecs = {}
local refreshRewards   -- fwd decl (claim -> refresh)

local function claimReward(e)
	if ixClaimed(e.id) then return end
	if e.have() < e.goal then return end
	plr:SetAttribute("IX_" .. e.id, true)
	addCoins(e.coins)
	if (e.pearls or 0) > 0 then addPearls(e.pearls) end
	showToast("🎁  " .. e.name .. "   +" .. rewardText(e.coins, e.pearls), C(74,204,120))
	refreshRewards()
end

-- a reward row: a candy row in the reward's colour, its icon on a glow, name / blurb / progress bar in the text
-- column, the prize in gold over its key on the right: green CLAIM!, grey LOCKED, gold CLAIMED (+ the owned band)
for i, e in ipairs(REWARD_LIST) do
	local rowW = RW_W - 56
	local kx = rowW - 176 - 16
	local r = UI.candyRow(rwList, {
		kind = "card", Name = e.id, colour = e.colour, icon = e.iconName, iconFlat = e.iconFlat, LayoutOrder = i,
		w = rowW, h = RW_ROW_H, iconSize = 72, iconX = 14, iconY = 18, glow = 104,
		mid = { x = 100, w = kx - 116 }, key = { colour = "grey", w = 176, h = 54, x = kx, y = 44 },
	})
	r.key.button.Name = "Claim"
	local rec = { e = e, r = r }
	rec.nm = K.text(r.mid, e.name, 28, { Name = "Title", align = "left", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 8), drop = 3, ZIndex = 2 })
	rec.bl = K.text(r.mid, e.blurb, 19, { Name = "Blurb", align = "left", color = UI.TEXT.soft, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 43), drop = 2, ZIndex = 2 })
	rec.bar = UI.new("Frame", { Name = "Bar", BackgroundColor3 = INK, BackgroundTransparency = 0.45, Position = UDim2.fromOffset(2, 74), Size = UDim2.new(1, -4, 0, 22), ZIndex = 2 }, r.mid)
	UI.corner(rec.bar, 11)
	UI.stroke(rec.bar, 3)
	rec.fill = UI.new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, Size = UDim2.new(0, 0, 1, 0), ZIndex = 1 }, rec.bar)
	UI.corner(rec.fill, 11)
	UI.vgrad(rec.fill, UI.BRICK.gold)
	rec.barTxt = K.text(rec.bar, "", 16, { Name = "Count", Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	local prize = UI.cash(e.coins) .. (((e.pearls or 0) > 0) and ("  +" .. e.pearls .. " 🦪") or "")
	rec.prize = K.text(r.button, prize, 22, { Name = "Prize", color = UI.TEXT.gold, Size = UDim2.fromOffset(176, 30), Position = UDim2.fromOffset(kx, 8), ZIndex = 8 })
	TouchKit.press(r.key.button, function() claimReward(e) end)
	rwRecs[#rwRecs+1] = rec
end
-- a row at a new width (the phone's window is wider): the key and prize ride the right edge, the text column
-- takes the rest
function LAY.rwRow(rec, rowW)
	local r = rec.r
	local kx = rowW - 176 - 16
	r.button.Size = UDim2.fromOffset(rowW, RW_ROW_H)
	r.key.button.Position = UDim2.fromOffset(kx, 44)
	rec.prize.Position = UDim2.fromOffset(kx, 8)
	r.mid.Size = UDim2.fromOffset(kx - 116, RW_ROW_H)
end

-- Same idea as MenuFit: centre in the band BELOW the platform top bar, because this
-- ScreenGui ignores the GUI inset and the panel's close X lives in its top-right corner - and count the chrome
-- that reaches past the box (the treasure above, the drop below) in what has to fit.
local function fitRewards()
	local vp, availH, inset = LAY.screen()
	if vp.X < 100 or vp.Y < 100 then return end
	local c = math.min(vp.X, vp.Y) < 500
	local rt, rb, rx = c and REACH.cT or REACH.T, c and REACH.cB or REACH.B, c and REACH.cX or REACH.X
	local s
	if c then
		-- phone: the panel was height-bound at ~0.55 (7px blurbs, 21px CLAIM buttons). Pin
		-- the design height to ~360 so the scale lands near 0.8 and take the full width.
		s = math.clamp(availH / (360 + rt + rb), 0.6, 0.95)
		LAY.RW = math.clamp(math.floor((vp.X - 24) / s) - 2 * rx, 700, 1000)
		LAY.RH = math.floor(availH / s) - rt - rb
	else
		LAY.RW, LAY.RH = RW_W, RW_H
		s = math.clamp(math.min(vp.X / (RW_W + 60 + 2 * rx), availH / (RW_H + 20 + rt + rb)), 0.4, 1.12)
	end
	rwScale.Scale = s
	rwWin.Size = UDim2.fromOffset(LAY.RW, LAY.RH)
	if c then
		-- 2026-10-11, "centered to the phone screen": centred on the real screen, the treasure tucked into the header
		-- (LAY.rewards), shrinking only as far as the top bar needs
		MenuFit.centre(rwWin, rwScale, REACH.cUp, rb)
	else
		rwWin.Position = UDim2.new(0.5, 0, 0, math.floor(inset + availH / 2 + (rt - rb) / 2 * s + 0.5))
	end
	if LAY.rewards then LAY.rewards(c) end
end

-- Phone layout of the rewards window (fitRewards picks the scale): a 60px header and a smaller treasure; the
-- rows keep their size (CLAIM stays 54 tall, ~44px on a phone) and stretch to the wider window.
function LAY.rewards(c)
	local W, hh = LAY.RW, c and 60 or 74
	K.head(RWD.win, hh, W)
	-- phone: the treasure tucked INSIDE the header, its drop too, left of the title at 76 (REACH.cUp)
	RWD.win.icon.Size = UDim2.fromOffset(c and 54 or 124, c and 54 or 124)
	RWD.win.icon.Position = UDim2.fromOffset(c and 8 or -36, c and 1 or -44)
	local tx = c and 76 or 112
	RWD.win.title.Position = UDim2.fromOffset(tx, 0)
	RWD.win.title.Size = UDim2.fromOffset(W - tx - 60, hh)
	K.setMax(RWD.win.title, c and 34 or 44)
	local subH = c and 26 or 30
	RWD.sub.Position = UDim2.fromOffset(24, hh + 12)
	RWD.sub.Size = UDim2.new(1, -48, 0, subH)
	K.setMax(RWD.sub, c and 19 or 22)
	local listY = hh + 12 + subH + 6
	rwList.Position = UDim2.fromOffset(10, listY)
	rwList.Size = UDim2.new(1, -28, 1, -(listY + 14))
	RWD.track.Position = UDim2.new(1, -28, 0, listY)
	RWD.track.Size = UDim2.new(0, 10, 1, -(listY + 14))
	for _, rec in ipairs(rwRecs) do LAY.rwRow(rec, W - 56) end
end

-- The Index row on the main menu bar gets the same "!" every other claimable menu has.
-- Cloned from a row that ships with one rather than re-styled by hand (MenuLogic's
-- sizeRows has already sized the donor, so the clone lands correct too).
local function ensureIndexNotif()
	local mm = pg:FindFirstChild("MainMenu")
	local lst = mm and mm:FindFirstChild("MenuBar") and mm.MenuBar:FindFirstChild("List")
	local btn = lst and lst:FindFirstChild("Index")
	if not btn then return nil end
	local n = btn:FindFirstChild("Notif")
	if not n then
		local donor = lst:FindFirstChild("Upgrades") and lst.Upgrades:FindFirstChild("Notif")
		if not donor then return nil end
		n = donor:Clone(); n.Parent = btn
	end
	return n
end

function refreshRewards()
	local total = discoveredCount()
	local claimable = claimableCount()
	local ready = claimable > 0
		and ('<font color="#AAFF64">' .. claimable .. " reward" .. (claimable == 1 and "" or "s") .. " ready to claim!</font>")
		or "keep fishing to unlock more"
	RWD.sub.Text = total .. " / " .. #FishData.fish .. " discovered" .. DOT .. ready
	IX.dot.Visible = claimable > 0
	IX.rw.recolour(claimable > 0 and "green" or "gold")
	local notif = ensureIndexNotif()
	if notif then notif.Visible = claimable > 0 end
	gui:SetAttribute("RewardsClaimable", claimable)

	for _, rec in ipairs(rwRecs) do
		local e, r = rec.e, rec.r
		local have = math.min(e.have(), e.goal)
		local done = e.have() >= e.goal
		local claimed = ixClaimed(e.id)
		rec.fill.Size = UDim2.new(have / e.goal, 0, 1, 0)
		local state = claimed and "claimed" or (done and "ready" or "locked")
		rec.barTxt.Text = have .. "  /  " .. e.goal
		if rec.state ~= state then
			rec.state = state
			UI.vgrad(rec.fill, done and UI.BRICK.green or UI.BRICK.gold)
			r.setOwned(claimed)
			if claimed then
				r.key.recolour("gold")
				r.key.setParts("check", { { text = "CLAIMED", size = 24 } }, { leadSize = 44 })
			elseif done then
				r.key.recolour("green")
				r.key.setParts(nil, { { text = "CLAIM!", size = 30 } })
			else
				r.key.recolour("grey")
				r.key.setParts(nil, { { icon = "lock", size = 28, flat = true, drop = 0 }, { text = "LOCKED", size = 24 } })
			end
		end
	end
end

local function openRewards()
	fitRewards(); refreshRewards()
	scroller.Visible = false      -- same trick the detail overlay uses: stop the grid's
	spinning = nil                -- ViewportFrames rendering behind a full-cover panel
	rwOverlay.Visible = true
	local target = rwScale.Scale
	rwScale.Scale = target * 0.9
	TweenService:Create(rwScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end
local function closeRewards()
	rwOverlay.Visible = false
	-- The fish DETAIL is a full-cover overlay that hides the grid for the same reason, so
	-- closing this panel must not switch 61 ViewportFrames back on underneath it. (Reachable
	-- the other way round: shutting the whole menu closes both, and the detail can outlive
	-- that - it does not clear itself on Enabled = false.)
	if detail.Visible then return end
	scroller.Visible = true
	task.defer(refreshVisible)
end
TouchKit.press(IX.rw.button, openRewards)
TouchKit.press(RWD.win.close.button, closeRewards)
TouchKit.press(RWD.back, closeRewards)

-- Discovery is what MOVES every one of these bars, so recompute whenever the count does.
-- updateProgress() is the single writer of that attribute, which keeps this off the
-- discovery path itself (and out of the __ALL__ loop's inner cost).
gui:GetAttributeChangedSignal("Discovered"):Connect(refreshRewards)

-- ===== animation loop (camera orbit spin + the sea + tank bubbles) =====
RunService.RenderStepped:Connect(function(dt)
	local t=os.clock()
	if gui.Enabled then
		-- Settings > Menu Animations gates the decor; the hover spin is content. Only the window on top moves.
		if plr:GetAttribute("Set_MenuFX") ~= false then
			if rwOverlay.Visible then K.stepSea(RWD.sea, dt, t)
			elseif detail.Visible then K.stepSea(DT.sea, dt, t)
			else K.stepSea(IX.sea, dt, t) end
		end
		if spinning and spinning.cam and spinning.built and spinning.vpf and spinning.vpf.Visible then
			local off=CFrame.Angles(0,t*1.0,0)*(CAM_DIR*spinning.dist)
			spinning.cam.CFrame=CFrame.lookAt(spinning.center+off, spinning.center)
		end
	end
	if detail.Visible then
		if detailCam then
			local off=CFrame.Angles(0,t*0.6,0)*(CAM_DIR*detailDist)
			detailCam.CFrame=CFrame.lookAt(detailCenter+off, detailCenter)
		end
		for _,b in ipairs(tankBubbles) do
			local p=b.f.Position; local ny=p.Y.Scale-b.sp*(1/60)
			if ny<-0.06 then ny=1.06 end
			b.f.Position=UDim2.new(p.X.Scale,p.X.Offset,ny,0)
		end
	end
end)

-- ===== discover / re-skin =====
local function markDiscovered(name, silent)
	if discovered[name] then return end
	local f; for _,x in ipairs(FishData.fish) do if x.name==name then f=x break end end
	if not f then return end
	discovered[name]=true
	-- for the save (IndexSeen) and the Fish Index funnel (FunnelDefs reads the PLAYER's Discovered)
	do
		local seen={}
		for _,x in ipairs(FishData.fish) do if discovered[x.name] then seen[#seen+1]=x.name end end
		plr:SetAttribute("IndexSeen", game:GetService("HttpService"):JSONEncode(seen))
		plr:SetAttribute("Discovered", #seen)
	end
	-- First catch of this species: FirstCatchServer decides whether it is rare enough to announce in
	-- everyone's chat. Never for the silent bulk reveal (DevDiscover "__ALL__").
	if not silent then
		local cr = game:GetService("ReplicatedStorage"):FindFirstChild("ChatRemotes")
		local fc = cr and cr:FindFirstChild("FirstCatch")
		if fc then fc:FireServer(name) end
	end
	-- DISCOVERY BOUNTY. Paid here rather than in GameClient because this is the one place
	-- that knows a species is NEW - GameClient fires Discover on every catch, discovered
	-- or not, and the early return above is what makes "first time only" true.
	local b = BOUNTY[f.rarity]
	if b then
		addCoins(b.coins)
		if b.pearls > 0 then addPearls(b.pearls) end
		-- Silent while the TUTORIAL is up. This toast is its own ScreenGui at DisplayOrder 60,
		-- top-centre, so it draws straight over the tutorial card (14) and buries the step the
		-- player is meant to be reading - and the tutorial's very first haul is all but certain
		-- to discover something. The bounty is still paid and the card still flips over; only
		-- the popup is withheld. TutorialController clears the attribute the moment it finishes
		-- OR is skipped, and never sets it at all on a client where the tutorial did not run.
		if not silent and plr:GetAttribute("TutorialActive") ~= true then
			showToast("📖  NEW SPECIES!  " .. f.name .. "   +" .. rewardText(b.coins, b.pearls), RCOLOR[f.rarity] or C(90,224,248))
		end
	end
	local e=cards[name]
	if e then
		styleDiscovered(e)
		-- the silhouette is gone: build the real fish
		if e.vpf then e.vpf:Destroy(); e.vpf=nil end
		buildViewport(e); if e.vpf then e.vpf.Visible=true end
		TweenService:Create(e.scale, TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,true), {Scale=1.14}):Play()
	end
	updateProgress()
end

-- ===== hooks =====
local remotes=RS:FindFirstChild("IndexRemotes")
if remotes then local d=remotes:FindFirstChild("Discover"); if d and d:IsA("RemoteEvent") then d.OnClientEvent:Connect(function(nm) markDiscovered(nm) end) end end
-- Production hook: GameClient fires this the moment a species is hauled in, the same
-- shape as InventoryMenu.AddCatch. Kept separate from DevDiscover so the dev verbs
-- (__ALL__ / __RESET__ / __DETAIL__) stay a test-only surface.
local liveHook=gui:FindFirstChild("Discover"); if not liveHook then liveHook=Instance.new("BindableEvent"); liveHook.Name="Discover"; liveHook.Parent=gui end
liveHook.Event:Connect(function(nm) if type(nm)=="string" then markDiscovered(nm) end end)

local devHook=gui:FindFirstChild("DevDiscover"); if not devHook then devHook=Instance.new("BindableEvent"); devHook.Name="DevDiscover"; devHook.Parent=gui end
devHook.Event:Connect(function(arg)
	if typeof(arg)=="string" and arg:sub(1,11)=="__DETAIL__:" then local e=cards[arg:sub(12)]; if e then openDetail(e) end
	elseif arg=="__ALL__" then for _,f in ipairs(FishData.fish) do markDiscovered(f.name, true) end
	elseif arg=="__RESET__" then
		for _,f in ipairs(FishData.fish) do discovered[f.name]=false end
		for _,f in ipairs(FishData.fish) do local e=cards[f.name]; if e then e.btn:Destroy() end end
		cards={}; order=0; spinning=nil; for _,f in ipairs(FishData.fish) do makeCard(f) end
		-- the reward ladder is part of the collection, so a reset clears its claims too
		for _,e in ipairs(REWARD_LIST) do plr:SetAttribute("IX_"..e.id, false) end
		plr:SetAttribute("IndexSeen", "[]"); plr:SetAttribute("Discovered", 0)
		updateProgress(); applyFilter(); refreshRewards()
	else markDiscovered(arg) end
end)

TouchKit.press(IX.win.close.button, function() gui.Enabled=false end)
TouchKit.press(IX.backdrop, function() gui.Enabled=false end)

-- Phone/desktop re-layout of everything built above. Runs from fitScale on every viewport
-- change (switching the device simulator mid-session is the test) and on every open. The
-- non-phone branch of each line is the authored desktop value.
LAY.after = function()
	local c, W = LAY.compact, LAY.W
	-- header: 74 -> 60 on a phone, the book tucked INSIDE it, left of the title at 72 (2026-10-11, "centered to the
	-- phone screen": nothing pokes above the centred window - REACH.cUp)
	local hh = c and 60 or 74
	K.head(IX.win, hh, W)
	IX.win.icon.Size = UDim2.fromOffset(c and 56 or 124, c and 56 or 124)
	IX.win.icon.Position = UDim2.fromOffset(c and 8 or -36, c and 2 or -44)
	-- title | progress | REWARDS | X  (the X is UI.window's, on the top-right corner)
	local rwW, rwH = c and 176 or 210, c and 46 or 52
	local rwX = W - 96 - rwW + (c and 6 or 0)
	IX.rw.button.Size = UDim2.fromOffset(rwW, rwH)
	IX.rw.button.Position = UDim2.fromOffset(rwX, math.floor((hh - rwH) / 2) - 2)
	IX.rw.setParts(nil, { { icon = "treasure", size = c and 38 or 44, drop = 0 }, { text = "REWARDS", size = c and 22 or 26, gap = 8 } })
	local tx = c and 72 or 112
	local px = tx + (c and 132 or 150) + 12
	local pw = math.clamp(rwX - 14 - px, 150, 380)
	local ph = c and 40 or 44
	IX.prog.root.Size = UDim2.fromOffset(pw, ph)
	IX.prog.root.Position = UDim2.fromOffset(rwX - 14 - pw, math.floor((hh - ph) / 2) - 2)
	K.setMax(IX.prog.label, c and 18 or 22)
	IX.win.title.Position = UDim2.fromOffset(tx, 0)
	IX.win.title.Size = UDim2.fromOffset(rwX - 14 - pw - 12 - tx, hh)
	K.setMax(IX.win.title, c and 36 or 46)
	-- filter keys: one row under the crest, 46 tall (42 on a phone)
	local keyH = c and 42 or 46
	local fy = hh + (c and 16 or 22)
	IX.filters.Position = UDim2.fromOffset(0, fy)
	IX.filters.Size = UDim2.new(1, 0, 0, keyH + 6)
	LAY.filters(W, keyH, c and 19 or 22, c and 16 or 22, c and 8 or 10)
	-- grid: 4 big columns on a phone instead of 6 tiny ones
	local m = c and 12 or 16
	local gy = fy + keyH + 6 + (c and 8 or 10)
	local gb = c and 10 or 14
	scroller.Position = UDim2.fromOffset(m, gy)
	scroller.Size = UDim2.new(1, -2 * m, 1, -(gy + gb))
	IX.track.Position = UDim2.new(1, -m - 10, 0, gy)
	IX.track.Size = UDim2.new(0, 10, 1, -(gy + gb))
	local L = c and LAY.PHONE or (LAY.tablet and LAY.TABLET or LAY.DESK)
	LAY.cur = L
	grid.CellSize = UDim2.fromOffset(math.floor((W - 2 * m - 28 - (L.cols - 1) * L.gap) / L.cols), L.cellH)
	grid.CellPadding = UDim2.fromOffset(L.gap, L.gap)
	for _, e in pairs(cards) do LAY.card(e) end
	-- the two overlays fit themselves the same way
	fitDetail(); fitRewards()
	-- the toast's size and place come from the notice slot at show time (LAY.toastSlot). Here only
	-- its text box: the phone lane is ~230px, so long copy wraps onto two 14-16px lines instead of
	-- shrinking to one 11px line. (TextScaled does the wrapping by itself: a TextScaled label always wraps, and
	-- setting TextWrapped = false on one turns TextScaled OFF - which left this toast at the 8px default size.)
	T.txt.Size = UDim2.new(1, c and -20 or -30, 0, c and 32 or 26)
	K.setMax(T.txt, c and 16 or 18)
	if T.group.Visible then LAY.toastSlot() end
end

-- MenuFit on the window's whole FOOTPRINT (the box + the chrome reaching past it: REACH), then the box is set
-- back inside it - so the book and the X never run off the top of the screen or under the top bar. With no
-- reach this is exactly the old call: desktop keeps MenuFit's untouched branch, phones the adaptive one.
function LAY.fitRoot()
	local vp, availH = LAY.screen()
	if vp.X < 100 or vp.Y < 100 then return end
	if LAY.popTween then LAY.popTween:Cancel(); LAY.popTween = nil end
	LAY.compact = math.min(vp.X, vp.Y) < 500
	LAY.tablet = (not LAY.compact) and UIS.TouchEnabled
	local c = LAY.compact
	local rt, rb, rx = c and REACH.cT or REACH.T, c and REACH.cB or REACH.B, c and REACH.cX or REACH.X
	if c then
		local s = math.clamp(availH / (370 + rt + rb), 0.62, 0.95)
		LAY.W = math.clamp(math.floor(vp.X / s - 50) - 2 * rx, 700, WIN_W)
		MenuFit.apply(root, uiscale, LAY.W + 2 * rx, WIN_H + rt + rb, 0.4, 1.15, math.min(availH / s, WIN_H + rt + rb))
	else
		LAY.W = WIN_W
		MenuFit.apply(root, uiscale, WIN_W + 2 * rx, WIN_H + rt + rb, 0.4, 1.15, MIN_H + rt + rb)
	end
	LAY.H = root.Size.Y.Offset - rt - rb
	root.Size = UDim2.fromOffset(LAY.W, LAY.H)
	root.Position = root.Position + UDim2.fromOffset(0, math.floor((rt - rb) / 2 * uiscale.Scale + 0.5))
	-- centred on the screen - phones too since 2026-10-11 ("centered to the phone screen"), told only the reach the
	-- tucked book leaves above the box (none: REACH.cUp); desktop and iPad pass the breakout book's 44 as before
	MenuFit.centre(root, uiscale, c and REACH.cUp or rt, rb)
	if LAY.after then LAY.after() end
end
local fitScale = LAY.fitRoot
-- the house pop on open (from 85% of the fit, springing back)
function LAY.pop()
	local s = uiscale.Scale
	if LAY.popTween then LAY.popTween:Cancel() end
	uiscale.Scale = s * 0.85
	LAY.popTween = TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = s })
	LAY.popTween:Play()
end

fitScale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale) end

applyFilter()
updateProgress()
refreshRewards()
task.defer(function() task.wait(0.05); refreshVisible() end)
-- hide the player's rod hotbar (Roblox Backpack) while the index is open
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
	if gui.Enabled then fitScale(); LAY.pop(); refreshRewards(); task.defer(refreshVisible); setInventoryHidden(true)
	else closeDetail(); closeRewards(); setInventoryHidden(false) end
end)
if gui.Enabled then setInventoryHidden(true) end

print("[FishIndex] built - "..#FishData.fish.." species, "..(function() local n=0 for _,f in ipairs(FishData.fish) do if discovered[f.name] then n=n+1 end end return n end)().." discovered")
