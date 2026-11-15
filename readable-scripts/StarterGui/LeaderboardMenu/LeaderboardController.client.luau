--[==[
	LeaderboardController - fishing-game "Leaderboard" (StarterGui.LeaderboardMenu)

	Four boards, each a podium (top 3) + a ranked list:
	    💎 Robux Spent   · 🐛 Bait Rolls   · 🐟 Fish Caught   · 💰 Coins Earned

	ALL-TIME, EVERY SERVER (2026-10-11, the owner: "do the all-time totals" - servers are 1 player now, so a
	per-server board only ever showed you). ServerScriptService.LeaderboardServer keeps one OrderedDataStore per
	board, adds each visit's progress to it, and pushes each board's top 50 here on LeaderboardRemotes.Boards
	(cached in `global`). YOUR row uses your live all-time total, which the server publishes on you as LB_<key>,
	so you climb the moment you play instead of after the next save + refresh. rankedRows() is the one reader.
	(Before that: REAL PLAYERS ONLY in THIS server, 2026-10-10; before that, 100 seeded fictional rivals.)
	The rest of this paragraph describes the per-server relay this replaced:
	Every angler on a board was a player in THIS server. Their stats live in their own client's attributes, which never replicate, so each
	client reports its four totals to ServerScriptService.LeaderboardServer, which publishes them on the Player as
	LB_robux / LB_rolls / LB_fish / LB_coins (server-set attributes reach every client). Fewer than three anglers:
	the empty podium places hide, and the list says why it is empty. A global all-time board would need an
	OrderedDataStore per board on that server - rankedRows() is the one place that would read it.

	YOUR row reads your live attribute (never the relayed copy), so it never lags behind a report.
	    rolls  <- QT_roll   (LIVE — every bait-reel spin)
	    fish   <- QT_catch  } inert until the fishing loop reports them
	    coins  <- QT_earn   }
	    robux  <- RobuxSpent (no source: the Shop's product/pass IDs are all 0)

	Test hook: LeaderboardMenu.DevBoard:Fire("__OPEN__")
	           / :Fire(boardKey, value)   e.g. :Fire("rolls", 500000)

	2026-10-10 - THE LOOK MOVED ONTO ReplicatedStorage.ShopKit (the owner: "rework the uis of all the buttons based
	on this theme" - the Shop's "sea candy" look, ported from the +1 snowball game), so the window belongs next to
	the Shop. It was the old "cartoon reef" recipe (DEEP_TOP/MID/BOT water, pale cards, pill chips, GothamBold copy).
	Now: UI.window (lagoon body with the Shop's bubbles + light rays, a GOLD header with a wave crest, the trophy
	sticker breaking out of the top-left corner, the red key X); the four boards as candy tab keys (gold = the board
	you are on, sea = the rest); the top three as gold / silver / bronze candy cards with medal stickers and a crown
	on #1; every other angler as a candy slab in the board's colour (💎 purple, 🐛 rose, 🐟 blue, 💰 emerald) with
	the angler's initials on a disc; YOUR row wears the gold ring + a YOU sticker; the pinned YOU bar is a gold slab;
	the angler count is a sea chip; every word is a ShopKit label (FredokaOne, INK outline); the Shop's scroll thumb
	and track. The title is white-on-gold here: ShopKit's gold title vanishes into a gold header.
	Nothing it does changed - same boards, seeded rivals, stats, DevBoard verbs, TouchKit.press on every control,
	MenuFit + the phone column layout, Backpack hiding. One fix rode along: a stat changing while you are scrolled
	down (auto-fishing pays QT_earn on every catch) no longer throws the list back to the top; only opening the
	menu or switching boards does.
	Placement: the trophy breaks 44 design px out of the window's top (not on a phone), the X 18 past its right edge
	and the drop hangs 9 below - MenuFit knows none of it, so after MenuFit.apply LB.keepReach() keeps that reach on
	screen and under Roblox's top bar (the Shop's / Settings' rule): the list gives up height first (down to MIN_H),
	the scale only when that is not enough.
	CONTRACT (kept): PlayerGui.LeaderboardMenu is the same ScreenGui and Enabled is the only open/close signal
	(MenuLogic opens it; MenuBlurManager, DailyController, TutorialController and AudioController read it); the
	window's X is the ONE TextButton named "TextButton" in this gui (TutorialController's closeButtonOf finds it by
	that); the "Backdrop" button behind the window closes it and ClickGuards stop taps on the window reaching it.
	Pre-restyle source: ServerStorage.MenuBackup_PreCandy_2026-10-10.LeaderboardController (a StringValue).
]==]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- The Shop's kit: the window, candy slabs and keys, chips, stickers, labels (see its header).
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))

local plr = Players.LocalPlayer
local gui = script.Parent

local rgb, V2 = Color3.fromRGB, Vector2.new
local WHITE = Color3.new(1, 1, 1)
local make = UI.new   -- make(class, props, parent); BorderSizePixel 0 on every GuiObject

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIX[tier + 1])
end

-- candy: the board's UI.CANDY colour - every slab in its list wears it (one colour per category)
local BOARDS = {
	{ key="robux", icon="💎", label="Robux Spent",  word="ROBUX SPENT",  candy="purple",
	  top=1284500,     decay=0.885, floor=250,   seed=1337,
	  blurb="The biggest spenders of all time",
	  stat=function() return plr:GetAttribute("RobuxSpent") or 0 end },
	{ key="rolls", icon="🐛", label="Bait Rolls",   word="BAIT ROLLS",   candy="rose",
	  top=2412880,     decay=0.89,  floor=600,   seed=2468,
	  blurb="Most bait reel spins of all time",
	  stat=function() return plr:GetAttribute("QT_roll") or 0 end },
	{ key="fish",  icon="🐟", label="Fish Caught",  word="FISH CAUGHT",  candy="blue",
	  top=8940120,     decay=0.892, floor=1200,  seed=9753,
	  blurb="Most fish hauled up of all time",
	  stat=function() return plr:GetAttribute("QT_catch") or 0 end },
	{ key="coins", icon="💰", label="Coins Earned", word="COINS EARNED", candy="emerald",
	  top=88412000000, decay=0.875, floor=40000, seed=8642,
	  blurb="Most coins reeled in, of all time",
	  stat=function() return plr:GetAttribute("QT_earn") or 0 end },
}
local BOARD_BY_KEY = {}
for _, b in ipairs(BOARDS) do BOARD_BY_KEY[b.key] = b end

local function fmtVal(key, v)
	if key == "robux" then return "R$ " .. abbrev(v) end
	if key == "coins" then return "$" .. abbrev(v) end
	return abbrev(v)
end

-- REAL PLAYERS (see the header): report my four totals to LeaderboardServer every few seconds when they change,
-- and rank every player in the server by what it relays back on them.
local LBR = ReplicatedStorage:WaitForChild("LeaderboardRemotes", 10)
local reportRemote = LBR and LBR:FindFirstChild("Report")
local lastSent = ""
local function report()
	if not reportRemote then return end
	local t, parts = {}, {}
	for _, def in ipairs(BOARDS) do
		t[def.key] = math.floor(tonumber(def.stat()) or 0)
		parts[#parts + 1] = tostring(t[def.key])
	end
	local sig = table.concat(parts, "|")
	if sig == lastSent then return end
	lastSent = sig
	reportRemote:FireServer(t)
end
task.spawn(function()
	while true do
		report()
		task.wait(3)
	end
end)

-- the global top lists, as LeaderboardServer last sent them: global[key] = { {u = userId, n = name, v = total}, ... }
local global = {}
local TOP_N = 50
local function myTotal(key) return tonumber(plr:GetAttribute("LB_" .. key)) or 0 end

-- returns rows, loading. A board the server hasn't sent yet is LOADING, not empty: treating it as empty put you
-- at "#1 of 1" for the first minute of every visit.
local function rankedRows(def)
	local list = global[def.key]
	if list == nil then return {}, true end
	local all, meIn = {}, false
	local mine = myTotal(def.key)
	for _, e in ipairs(list) do
		if e.u == plr.UserId then
			-- the stored row lags your unsaved progress: show whichever is higher
			meIn = true
			all[#all+1] = { name = plr.DisplayName, value = math.max(mine, tonumber(e.v) or 0), isMe = true }
		else
			all[#all+1] = { name = tostring(e.n), value = tonumber(e.v) or 0, isMe = false }
		end
	end
	-- not in the stored top 50 yet: you still appear the moment your live total would place
	if not meIn and mine > 0 and (#all < TOP_N or mine > all[#all].value) then
		all[#all+1] = { name = plr.DisplayName, value = mine, isMe = true }
	end
	table.sort(all, function(a, b)
		if a.value == b.value then return (a.name or "") < (b.name or "") end
		return a.value > b.value
	end)
	while #all > TOP_N do table.remove(all) end
	return all
end

local function nameColor(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 360 end
	return Color3.fromHSV(h / 360, 0.55, 0.92)
end
local function initials(s)
	local t = (s:gsub("[^%a]", ""))
	if #t == 0 then return "?" end
	return string.upper(t:sub(1, 2))
end

----------------------------------------------------------------------
-- window (ShopKit's UI.window: the Shop's shell, in gold)
----------------------------------------------------------------------
local WIN_W, WIN_H = 1100, 700
-- Design px, desktop / phone. Every view object hangs off LB too (Luau's 200-locals cap).
--   HEAD_H  the header (UI.window draws it at the desktop height; relayout() re-sizes it for a phone)
--   TITLE   where "LEADERBOARD" starts, its box and its size cap
--   ICON    the trophy sticker breaking out of the top-left corner (on a phone: tucked inside the header, left of
--           the title - 2026-10-11, the owner: "centered to the phone screen")
--   REACH   how far the window's art pokes past its own box: the trophy above / left of it, the X 18 past its
--           right edge (and 18 above, inside the trophy's reach), the drop 9 below. keepReach() keeps it on screen.
--           A phone's trophy is tucked, so compact.left is 0 and compact.up (20) only covers the X's 18 now.
--   TAB     the four board keys under the header
--   POD     desktop podium: 2nd | 1st | 3rd standing on one line (bottom 282), the 1st card taller and wider
--   LIST_Y  where the scroll list starts; ROW: a list slab's height and the gap under it (its 6 px drop + air)
--   BODY_Y  phone: the left column's four cards (1st / 2nd / 3rd / YOU) start here
local LB = {
	HEAD_H = { desk = 74, compact = 58 },
	TITLE = { desk = { x = 112, w = 330, max = 46 }, compact = { x = 72, w = 250, max = 36 } },
	ICON = { desk = { size = 124, x = -36, y = -44 }, compact = { size = 54, x = 8, y = 2 } },
	REACH = { desk = { up = 44, left = 36 }, compact = { up = 20, left = 0 }, right = 18, down = 9 },
	TAB = {
		desk = { y = 96, h = 50, w = 256, gap = 12, emoji = 30, word = 26 },
		compact = { y = 78, h = 42, gap = 10, emoji = 22, word = 20 },
	},
	POD = { bottom = 282, gap = 14, first = { w = 356, h = 104 }, other = { w = 330, h = 88 } },
	LIST_Y = { desk = 300, compact = 128 },
	ROW = { desk = { h = 52, gap = 12 }, compact = { h = 46, gap = 10 } },
	ROW_Y0 = 8,
	BODY_Y = 136,
	-- the podium's candy (ShopKit has no medal colours): gold / silver / bronze. The YOU bar is the gold one.
	MEDAL = {
		{ rgb(255, 240, 128), rgb(255, 172, 0) },
		{ rgb(236, 244, 255), rgb(140, 158, 192) },
		{ rgb(255, 204, 156), rgb(200, 104, 40) },
	},
	stkK = 1, PODW = 374, rowW = WIN_W - 56,
}

-- the scrim: a full-screen BUTTON behind the window (a Frame would let the tap through and cast the rod behind
-- the menu) - a tap anywhere outside the window closes the Leaderboard
local backdrop = make("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(4, 4), ZIndex = 1,
}, gui)

LB.win = UI.window(gui, "LEADERBOARD", {
	Name = "Window", w = WIN_W, h = WIN_H, icon = "trophy", headColour = "gold", ZIndex = 5,
})
local root = LB.win.root
local uiscale = make("UIScale", { Scale = 1 }, root)
-- ShopKit's gold title vanishes into a gold header: white-to-cream letters here (its brown outline + INK drop stay)
UI.vgrad(LB.win.title, { rgb(255, 255, 255), rgb(255, 250, 232), rgb(255, 236, 190) })

-- The window catches its own taps (an Active Frame does NOT stop the Backdrop under it): transparent, silent
-- ClickGuard buttons with no handler over the body + its drop (ZIndex 3: over Shadow / Body, under the podium,
-- the list, the tabs, the title, the trophy and the X) and over the trophy. SndHooked is set before they are
-- parented, so AudioController gives them no click.
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
if LB.win.icon then clickGuard(LB.win.icon, UDim2.new(1, 0, 1, 5), 20) end

-- Shared with every other pop-up window in the game. On a small screen it makes the window
-- SHORTER rather than smaller, so the WIDTH drives the scale (+30-38%% text on a phone) and
-- centres it below the Roblox top bar instead of underneath it. Desktop and iPad keep the
-- original call (then keepReach, below).
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
-- MIN_H: everything above LIST_Y (300) and the pinned YOU bar under the list (86) is fixed chrome; the list is
-- the only thing that shrinks with the height, so at 450 it still shows one whole slab (8 + 52 + its drop).
local MIN_H = 450
-- PHONE LAYOUT (2026-09-25 mobile pass). Fed the 1100-wide design, MenuFit landed a 667px
-- phone at 0.58: the podium ate half the window, two list rows showed, text read 8-10px and
-- the list ran on under the pinned "you" bar. On a compact screen (short side < 500) the
-- window is designed NARROWER instead - W is picked so MenuFit lands near LAY.S - and the
-- podium becomes a column of three cards LEFT of the list (the YOU card under them), so the
-- list keeps the full body height. Re-decided on every fit() (open + ViewportSize change),
-- never once at build time. LAY.MIN_H: the column's four cards are (H - 188) / 4 tall each,
-- 35 at 330 - the shortest that still holds a name over a score.
local LAY = { compact = false, W = WIN_W, S = 0.85, MIN_H = 330 }
local relayout   -- fwd decl: assigned once every piece of the window exists (bottom of file)
-- What fit() would pick for the screen as it is right now.
local function decide()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.zero
	-- The ScreenGui's own size is the device SAFE area (ScreenInsets), but it can be stale:
	-- measured, switching phones with this menu closed left it reading the previous phone's
	-- width on the next open. A stale LARGER value is rejected here; a stale smaller one is
	-- corrected by the AbsoluteSize watcher further down once the real size lands.
	local gs = gui.AbsoluteSize
	local safeW = (gs.X > 100 and gs.X <= vp.X + 1) and gs.X or vp.X
	local compact = math.min(vp.X, vp.Y) < 500
	local W = compact and math.clamp(math.floor(safeW / LAY.S - 50), 700, WIN_W) or WIN_W
	return vp, compact, W, safeW
end
-- the bottom of the Roblox top bar (+4): nothing of the window may reach above it
function LB.barBottom()
	local bar = GuiService:GetGuiInset().Y
	local ok, ti = pcall(function() return GuiService.TopbarInset end)
	if ok and ti then bar = math.max(bar, ti.Max.Y) end
	return bar + 4
end
-- MenuFit places the window BOX; the trophy breaks out above / left of it, the X past its right edge and the
-- drop below. Keep all of that on screen and under the top bar: sideways only the scale can give; vertically the
-- window first gets SHORTER (only the list shrinks, never below minH) and the scale drops only if that is not
-- enough; then it slides into the free band.
function LB.keepReach(vp, compact, minH, safeW)
	local s = uiscale.Scale
	if not (s > 0) then return end
	local R = LB.REACH
	local m = compact and R.compact or R.desk
	local W, H = root.Size.X.Offset, root.Size.Y.Offset
	local up, down, side = m.up, R.down, math.max(m.left, R.right)
	local top, bottom = LB.barBottom(), vp.Y - 4
	local wide = math.min(vp.X, safeW or vp.X)
	s = math.min(s, (wide / 2 - 4) / (W / 2 + side))
	local hFit = math.floor((bottom - top) / s - up - down)
	if hFit < H then
		H = math.max(hFit, math.min(minH or H, H))
		root.Size = UDim2.fromOffset(W, H)
	end
	s = math.max(0.1, math.min(s, (bottom - top) / (H + up + down)))
	if uiscale.Scale ~= s then uiscale.Scale = s end
	local p = root.Position
	local cy = p.Y.Scale * vp.Y + p.Y.Offset
	local lo = top + (H / 2 + up) * s
	local hi = math.max(lo, bottom - (H / 2 + down) * s)
	root.Position = UDim2.new(0.5, 0, 0, math.floor(math.clamp(cy, lo, hi) + 0.5))
end
local function fit()
	local vp, compact, W, safeW = decide()
	if vp.X < 100 or vp.Y < 100 then return end   -- viewport not settled yet (same guard as MenuFit)
	-- a re-fit while the open "pop" is still playing would be undone when that tween lands
	if LAY.tween then LAY.tween:Cancel(); LAY.tween = nil end
	LAY.safeW = safeW
	if compact ~= LAY.compact or W ~= LAY.W then
		LAY.compact, LAY.W = compact, W
		if relayout then relayout() end
	end
	if not compact then
		MenuFit.apply(root, uiscale, WIN_W, WIN_H, 0.4, 1.1, MIN_H)
		LB.keepReach(vp, false, MIN_H, safeW)
		MenuFit.centre(root, uiscale, LB.REACH.desk.up, LB.REACH.down)   -- centred on the screen
		return
	end
	MenuFit.apply(root, uiscale, W, WIN_H, 0.4, 1.1, LAY.MIN_H)
	-- MenuFit measures the camera viewport; on a real notched phone the SAFE area this
	-- ScreenGui lives in is narrower, so never let the window run past 97% of it.
	local maxS = safeW * 0.97 / W
	if uiscale.Scale > maxS then
		uiscale.Scale = maxS
		local availH = math.max(160, vp.Y - GuiService:GetGuiInset().Y - 12)
		root.Size = UDim2.fromOffset(W, math.floor(math.clamp(availH / maxS, LAY.MIN_H, WIN_H)))
	end
	LB.keepReach(vp, true, LAY.MIN_H, safeW)
	-- 2026-10-11, the owner: "make the button uis centered to the phone screen". The trophy is tucked into the
	-- header (LB.ICON.compact), so nothing reaches above the window's top-left: up = 0 (the X rises into the top
	-- bar's free region). Centred, the window comes out 10-16% smaller than the band-under-the-top-bar layout.
	MenuFit.centre(root, uiscale, 0, LB.REACH.down)
end

----------------------------------------------------------------------
-- the sea behind the slabs (the Shop's): light rays and rising bubbles in the window's Ocean layer - only the gaps
-- between the slabs show them. One loop (further down), idle while the menu is shut or Menu Animations are off.
----------------------------------------------------------------------
LB.rays, LB.bubbles = {}, {}
do
	local ocean = LB.win.ocean
	for i, x in ipairs({ 0.08, 0.27, 0.47, 0.66, 0.86 }) do
		local ray = make("Frame", {
			Name = "Ray", BackgroundColor3 = WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, ocean)
		make("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(LB.rays, { f = ray, phase = i * 1.3 })
	end
	for i = 1, 26 do
		local s = 6 + (i * 7) % 13
		local b = make("Frame", {
			Name = "Bubble", BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, AnchorPoint = V2(0.5, 0.5),
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, ocean)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		make("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		local bub = { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i }
		b.Position = UDim2.new(bub.x, 0, bub.y, 0)
		table.insert(LB.bubbles, bub)
	end
end

----------------------------------------------------------------------
-- text: ShopKit labels (FredokaOne, an INK outline that scales with the letters, TextScaled under a size cap so
-- nothing leaves its box). A label's hard drop is a clone beside it ("<Name>Drop") with its own cap and alignment.
----------------------------------------------------------------------
function LB.text(parent, name, size, o)
	o = o or {}
	return UI.label(parent, o.text or "", {
		Name = name, size = size, align = o.align, drop = o.drop, color = o.color, minSize = o.minSize or 10,
		Size = o.Size or UDim2.fromScale(1, 1), Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint or V2(0, 0),
		ZIndex = o.ZIndex or 8, TextTruncate = o.truncate and Enum.TextTruncate.AtEnd or nil,
	})
end
function LB.drop(l)
	return l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop")
end
function LB.cap(l, n)
	for _, t in ipairs({ l, LB.drop(l) }) do
		local c = t and t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MinTextSize = math.min(c.MinTextSize, n)
			c.MaxTextSize = n
		end
	end
end
function LB.align(l, a)
	for _, t in ipairs({ l, LB.drop(l) }) do
		if t then t.TextXAlignment = a end
	end
end

----------------------------------------------------------------------
-- header: the board's blurb right of the title, the angler count in a sea chip left of the X (a phone has room
-- for the blurb alone, as before)
----------------------------------------------------------------------
LB.blurb = LB.text(root, "Blurb", 22, { align = "right", drop = 2 })
LB.count = UI.chip(root, "sea", { Name = "Count", height = 40, textSize = 20, pad = 16, AnchorPoint = V2(1, 0.5), ZIndex = 8 })
function LB.layHeader()
	local c, W = LAY.compact, LAY.W
	local T = c and LB.TITLE.compact or LB.TITLE.desk
	local x0 = T.x + math.min(math.ceil(UI.textWidth("LEADERBOARD", T.max)) + 12, T.w) + 16
	local chip = LB.count.block.root
	chip.Visible = not c
	if c then
		LB.blurb.Position = UDim2.fromOffset(x0, 0)
		LB.blurb.Size = UDim2.fromOffset(math.max(60, W - 50 - x0), LB.HEAD_H.compact)
		LB.cap(LB.blurb, 18)
	else
		chip.Position = UDim2.fromOffset(W - 56, math.floor(LB.HEAD_H.desk / 2))
		local right = W - 56 - chip.Size.X.Offset - 14
		LB.blurb.Position = UDim2.fromOffset(x0, 22)
		LB.blurb.Size = UDim2.fromOffset(math.max(60, right - x0), 30)
		LB.cap(LB.blurb, 22)
	end
end

----------------------------------------------------------------------
-- tabs: one candy key per board under the header - gold is the board you're on, sea blue the rest (the Shop's)
----------------------------------------------------------------------
local currentTab = BOARDS[1].key
local refreshBoard, selectTab
LB.tabs = {}
for _, def in ipairs(BOARDS) do
	local k = UI.candyKey(root, "sea", { Name = def.key, Size = UDim2.fromOffset(256, 50), AnchorPoint = V2(0.5, 0.5), ZIndex = 7 })
	TouchKit.press(k.button, function() selectTab(def.key) end)
	LB.tabs[def.key] = k
end
function LB.layTabs()
	local c, W = LAY.compact, LAY.W
	local T = c and LB.TAB.compact or LB.TAB.desk
	local tw = c and math.floor((W - 28 - 3 * T.gap) / 4) or T.w
	local x0 = (W - (4 * tw + 3 * T.gap)) / 2
	for i, def in ipairs(BOARDS) do
		local k = LB.tabs[def.key]
		k.button.Size = UDim2.fromOffset(tw, T.h)
		k.button.Position = UDim2.fromOffset(math.floor(x0 + tw / 2 + (i - 1) * (tw + T.gap) + 0.5), T.y + T.h / 2)
		-- the board's emoji (no outline, no drop: an emoji cannot be inked) + its name
		k.setParts(nil, { { text = def.icon, size = T.emoji, drop = 0, o = 0 }, { text = def.word, size = T.word, gap = 8 } })
	end
end
function LB.paintTabs()
	for _, def in ipairs(BOARDS) do
		local k = LB.tabs[def.key]
		local want = def.key == currentTab and "gold" or "sea"
		if k.colour ~= want then k.recolour(want) end
	end
end

----------------------------------------------------------------------
-- an entry: a ShopKit candy slab with no key (entries never act) holding a lead (the medal sticker or the rank),
-- an avatar disc (the angler's initials on their own colour), the name and the score. Inside the slab: face 2,
-- these 8, the owned ring 9, the medal / crown / YOU sticker 11-12.
----------------------------------------------------------------------
function LB.slab(parent, name, colour)
	local r = UI.candyRow(parent, { kind = "strip", Name = name, w = 300, h = 52, key = false, colour = colour, mid = { x = 0, w = 300 } })
	local rec = { r = r, row = r.button }
	rec.rank = LB.text(r.button, "Rank", 26, { align = "left", drop = 2 })
	rec.av = make("Frame", { Name = "Avatar", BackgroundColor3 = WHITE, AnchorPoint = V2(0, 0.5), Size = UDim2.fromOffset(38, 38), ZIndex = 8 }, r.button)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, rec.av)
	UI.stroke(rec.av, 3)
	rec.avTxt = LB.text(rec.av, "Initials", 17, {
		Size = UDim2.fromScale(0.84, 0.84), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = V2(0.5, 0.5), ZIndex = 9,
	})
	rec.nm = LB.text(r.button, "Name", 24, { align = "left", drop = 2, truncate = true, minSize = 9 })
	rec.vl = LB.text(r.button, "Value", 28, { align = "right", drop = 2 })
	return rec
end
function LB.paint(rec, name)
	local c = nameColor(name)
	UI.vgrad(rec.av, { c:Lerp(WHITE, 0.4), c })
	rec.avTxt.Text = initials(name)
end
-- the medal stickers are emoji (an emoji cannot be recoloured into an INK drop, so they have none)
function LB.emoji(parent, name, glyph)
	local l = make("TextLabel", {
		Name = name, BackgroundTransparency = 1, Text = glyph, TextScaled = true, FontFace = UI.FONT, TextColor3 = WHITE,
		ZIndex = 11,
	}, parent)
	make("UITextSizeConstraint", { MaxTextSize = 64, MinTextSize = 8 }, l)
	return l
end
-- a "YOU" sticker (one per place it can show: the podium, the list, the YOU bar); 0.8 of its size on a phone
function LB.sticker(parent, colour)
	local s = UI.sticker(parent, colour, "YOU", { Name = "YouSticker", height = 28, textSize = 15, Rotation = -6, ZIndex = 12 })
	s.scale = make("UIScale", {}, s.block.root)
	s.block.root.Visible = false
	return s
end
-- phone: the left column's card i (1st / 2nd / 3rd / YOU), each (H - 188) / 4 tall and 12 apart (drop + air),
-- from BODY_Y down to 10 above the window's bottom - scale-based, so it follows whatever height the fit settles on
function LB.colCard(rec, i)
	rec.row.Position = UDim2.new(0, 14, 0.25 * (i - 1), LB.BODY_Y - 35 * (i - 1))
	rec.row.Size = UDim2.new(0, LB.PODW, 0.25, -47)
	rec.av.Position = UDim2.new(0, 48, 0.5, 0); rec.av.Size = UDim2.fromOffset(30, 30); LB.cap(rec.avTxt, 14)
	rec.nm.AnchorPoint = V2(0, 1); rec.nm.Position = UDim2.new(0, 86, 0.5, 1); rec.nm.Size = UDim2.new(1, -94, 0.42, 0)
	LB.cap(rec.nm, 17)
	rec.vl.AnchorPoint = V2(0, 0); rec.vl.Position = UDim2.new(0, 86, 0.5, 1); rec.vl.Size = UDim2.new(1, -94, 0.42, 0)
	LB.cap(rec.vl, 17); LB.align(rec.vl, Enum.TextXAlignment.Left)
end

----------------------------------------------------------------------
-- podium (top 3): desktop 2nd | 1st | 3rd on one line, the 1st taller, medal stickers breaking out of their
-- top-left corners and a crown on the 1st; a phone stacks them 1st / 2nd / 3rd down the left column
----------------------------------------------------------------------
local podium = make("Frame", { Name = "Podium", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, root)
local MEDAL = { "🥇", "🥈", "🥉" }
local podRecs = {}
for place = 1, 3 do
	local rec = LB.slab(podium, "P" .. place, LB.MEDAL[place])
	rec.rank.Visible = false
	rec.medal = LB.emoji(rec.row, "Medal", MEDAL[place])
	if place == 1 then
		rec.crown = UI.icon(rec.row, "crown", 42, {
			Name = "Crown", flat = true, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -30, 0, 4), Rotation = 14, ZIndex = 11,
		})
		UI.iconDrop(rec.crown, 3, 0.5)
	end
	podRecs[place] = rec
end
LB.podStk = LB.sticker(podium, "gold")
local function stylePod(rec, place)
	local first = place == 1
	if LAY.compact then
		LB.colCard(rec, place)
		rec.medal.AnchorPoint = V2(0, 0.5); rec.medal.Position = UDim2.new(0, 8, 0.5, 0)
		rec.medal.Size = UDim2.new(0, 36, 0.8, 0); rec.medal.Rotation = 0
		if rec.crown then rec.crown.Visible = false end
		return
	end
	local P = first and LB.POD.first or LB.POD.other
	local w2 = LB.POD.other.w
	local x = place == 2 and 18 or (first and 18 + w2 + LB.POD.gap or 18 + w2 + LB.POD.first.w + 2 * LB.POD.gap)
	rec.row.Position = UDim2.fromOffset(x, LB.POD.bottom - P.h)
	rec.row.Size = UDim2.fromOffset(P.w, P.h)
	local ms = first and 58 or 50
	rec.medal.AnchorPoint = V2(0, 0); rec.medal.Position = UDim2.fromOffset(first and -14 or -12, first and -18 or -16)
	rec.medal.Size = UDim2.fromOffset(ms, ms); rec.medal.Rotation = -10
	local avs = first and 60 or 52
	rec.av.Position = UDim2.new(0, first and 46 or 40, 0.5, 4); rec.av.Size = UDim2.fromOffset(avs, avs)
	LB.cap(rec.avTxt, first and 24 or 20)
	local tx = first and 120 or 104
	rec.nm.AnchorPoint = V2(0, 0); rec.nm.Position = UDim2.fromOffset(tx, first and 14 or 10)
	rec.nm.Size = UDim2.fromOffset(P.w - tx - 16, first and 34 or 32); LB.cap(rec.nm, first and 26 or 24)
	rec.vl.AnchorPoint = V2(0, 0); rec.vl.Position = UDim2.fromOffset(tx, first and 50 or 44)
	rec.vl.Size = UDim2.fromOffset(P.w - tx - 16, first and 40 or 36); LB.cap(rec.vl, first and 34 or 30)
	LB.align(rec.vl, Enum.TextXAlignment.Left)
	if rec.crown then rec.crown.Visible = true end
end

----------------------------------------------------------------------
-- the list (rank 4 down): slabs in the board's colour at x 8, the Shop's gold thumb over an INK track
----------------------------------------------------------------------
local track = make("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency, ZIndex = 5,
}, root)
UI.corner(track, 5)
local scroller = make("ScrollingFrame", {
	Name = "List", BackgroundTransparency = 1, ZIndex = 6, ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	VerticalScrollBarInset = Enum.ScrollBarInset.None, CanvasSize = UDim2.new(),
}, root)
LB.rowStk = LB.sticker(scroller, "gold")
-- nobody below the podium (a server of three anglers or fewer): say why the list is empty
LB.empty = UI.label(scroller, "", { Name = "Empty", size = 24, TextWrapped = true, ZIndex = 7, Visible = false,
	Position = UDim2.new(0, 16, 0, 20), Size = UDim2.new(1, -32, 0, 96) })

local rowPool = {}
-- a list slab, by mode: desk = 1044 x 52, phone = the list column's width x 46; placed by its rank
local function styleRow(rec, i)
	local c = LAY.compact
	local m = c and LB.ROW.compact or LB.ROW.desk
	local w, h = LB.rowW, m.h
	rec.row.Size = UDim2.fromOffset(w, h)
	rec.row.Position = UDim2.fromOffset(8, LB.ROW_Y0 + (i - 4) * (h + m.gap))
	rec.rank.Position = UDim2.fromOffset(c and 10 or 16, 0); rec.rank.Size = UDim2.fromOffset(c and 46 or 72, h)
	LB.cap(rec.rank, c and 20 or 26)
	rec.av.Position = UDim2.new(0, c and 58 or 92, 0.5, 0); rec.av.Size = UDim2.fromOffset(c and 30 or 38, c and 30 or 38)
	LB.cap(rec.avTxt, c and 14 or 17)
	rec.nmX, rec.nmCap = c and 96 or 144, c and 19 or 24
	rec.nmW = w - rec.nmX - (c and 124 or 304)
	rec.nm.Position = UDim2.fromOffset(rec.nmX, 0); rec.nm.Size = UDim2.fromOffset(rec.nmW, h); LB.cap(rec.nm, rec.nmCap)
	rec.narrow = nil   -- (refreshBoard narrows the YOU row's name box again)
	rec.vl.AnchorPoint = V2(1, 0); rec.vl.Position = UDim2.new(1, c and -12 or -20, 0, 0)
	rec.vl.Size = UDim2.fromOffset(c and 108 or 280, h); LB.cap(rec.vl, c and 19 or 28)
end
local function getRow(i)
	local rec = rowPool[i]
	if rec then return rec end
	rec = LB.slab(scroller, "Row" .. i, "blue")
	rec.row.Visible = false
	rowPool[i] = rec
	styleRow(rec, i)
	return rec
end

----------------------------------------------------------------------
-- the pinned YOU bar under the list (a phone: the 4th card of the left column) - a gold slab
----------------------------------------------------------------------
LB.me = LB.slab(root, "YouBar", LB.MEDAL[1])
LB.me.row.ZIndex = 6
LB.meStk = LB.sticker(LB.me.row, "sea")
function LB.styleMe()
	local rec = LB.me
	if LAY.compact then
		LB.colCard(rec, 4)
		rec.rank.AnchorPoint = V2(0, 0.5); rec.rank.Position = UDim2.new(0, 6, 0.5, 0); rec.rank.Size = UDim2.new(0, 42, 0.8, 0)
		LB.cap(rec.rank, 18)
	else
		local h = 56
		rec.row.Position = UDim2.new(0, 18, 1, -74); rec.row.Size = UDim2.fromOffset(WIN_W - 56, h)
		rec.rank.AnchorPoint = V2(0, 0); rec.rank.Position = UDim2.fromOffset(18, 0); rec.rank.Size = UDim2.fromOffset(88, h)
		LB.cap(rec.rank, 32)
		rec.av.Position = UDim2.new(0, 108, 0.5, 0); rec.av.Size = UDim2.fromOffset(42, 42); LB.cap(rec.avTxt, 19)
		rec.nm.AnchorPoint = V2(0, 0); rec.nm.Position = UDim2.fromOffset(164, 0); rec.nm.Size = UDim2.fromOffset(440, h)
		LB.cap(rec.nm, 26)
		rec.vl.AnchorPoint = V2(1, 0); rec.vl.Position = UDim2.new(1, -20, 0, 0); rec.vl.Size = UDim2.fromOffset(320, h)
		LB.align(rec.vl, Enum.TextXAlignment.Right)
	end
	-- (the phone card is too narrow for a sticker beside "nothing yet - go fish!"; the gold card says it)
	LB.meStk.block.root.Visible = not LAY.compact
end

----------------------------------------------------------------------
-- refresh. keepScroll: a stat ticking while the menu is open re-ranks in place (only opening the menu or
-- switching boards scrolls back to the top)
----------------------------------------------------------------------
function refreshBoard(keepScroll)
	local def = BOARD_BY_KEY[currentTab]
	local rows, loading = rankedRows(def)
	LB.blurb.Text = def.blurb
	LB.count.set(loading and "ALL TIME" or ("TOP " .. #rows .. " · ALL TIME"))
	LB.layHeader()

	-- podium
	local pstk = LB.podStk.block.root
	pstk.Visible = false
	for place = 1, 3 do
		local r, rec = rows[place], podRecs[place]
		-- fewer than three anglers in the server: the empty places hide (on desktop #1 is the middle card)
		rec.row.Visible = r ~= nil
		if not r then continue end
		rec.nm.Text = r.name
		rec.vl.Text = fmtVal(def.key, r.value)
		LB.paint(rec, r.name)
		rec.r.setOwned(r.isMe == true)
		-- (phone: the sticker sits at the card's bottom-right, so YOUR name stops short of it)
		if LAY.compact then rec.nm.Size = UDim2.new(1, r.isMe and -146 or -94, 0.42, 0) end
		if r.isMe then
			LB.podStk.set("YOU", place == 1 and "sea" or "gold")
			pstk.Parent = rec.row
			pstk.Position = LAY.compact and UDim2.new(1, -30, 0.72, 0) or UDim2.new(1, -40, 1, -2)
			pstk.Visible = true
		end
	end

	-- rows 4..N
	local m = LAY.compact and LB.ROW.compact or LB.ROW.desk
	local valueColour = def.key == "coins" and UI.TEXT.gold or WHITE
	local stk = LB.rowStk.block.root
	stk.Visible = false
	-- Where a YOU sticker goes after a name: the name's RENDERED width in design px. A TextScaled label's size cap
	-- (UITextSizeConstraint) is in SCREEN px - the window's UIScale does not scale it (measured: 30 px at every
	-- scale) - so a name renders at cap / scale design px, as big as its box lets it, not at the cap.
	local sc = math.max(uiscale.Scale, 0.1)
	local stW = 56 * LB.stkK   -- the sticker's width in design px
	local function nameEnd(name, cap, boxH)
		return UI.textWidth(name, math.min(cap / sc, boxH / 1.25))
	end
	for i = 4, #rows do
		local r, rec = rows[i], getRow(i)
		rec.row.Visible = true
		if rec.candy ~= def.candy then
			rec.candy = def.candy
			rec.r.setColour(def.candy)
		end
		rec.rank.Text = "#" .. i
		rec.nm.Text = r.name
		rec.vl.Text = fmtVal(def.key, r.value)
		rec.vl.TextColor3 = valueColour
		LB.paint(rec, r.name)
		rec.r.setOwned(r.isMe == true)
		-- YOUR row: the sticker rides right after the name, and the name's box stops short of it (a long name
		-- shrinks, then truncates, rather than running under the sticker)
		local narrow = r.isMe == true
		if rec.narrow ~= narrow then
			rec.narrow = narrow
			rec.nm.Size = UDim2.fromOffset(narrow and rec.nmW - stW - 12 or rec.nmW, m.h)
		end
		if r.isMe then
			local tw = math.min(nameEnd(r.name, rec.nmCap, m.h), rec.nmW - stW - 12)
			stk.Parent = rec.row
			stk.Position = UDim2.new(0, math.floor(rec.nmX + tw + 8 + stW / 2), 0.5, 0)
			stk.Visible = true
		end
	end
	for i, rec in pairs(rowPool) do
		if i > #rows then rec.row.Visible = false end
	end
	LB.empty.Visible = #rows < 4
	if #rows < 4 then
		LB.empty.Text = (loading and "Loading the all-time board...")
			or (#rows == 0 and "Nobody on this board yet - be the first!")
			or ((#rows == 1 and rows[1].isMe) and "Only you on the board so far!\nEvery angler in every server shows up here.")
			or "Everyone so far made the podium.\nMore anglers show up here as they play!"
	end
	local n = math.max(#rows - 3, 0)
	scroller.CanvasSize = UDim2.fromOffset(0, LB.ROW_Y0 + n * (m.h + m.gap) - m.gap + 12)

	-- the YOU bar
	-- outside the top 50 there is no rank to show (an ordered store has no "what place is this key" query)
	local myRank, myVal = nil, myTotal(def.key)
	for i, r in ipairs(rows) do if r.isMe then myRank = i; myVal = r.value break end end
	local me = LB.me
	-- (myVal > 0 but no row only happens below a full top 50; nothing yet / still loading shows a dash)
	me.rank.Text = myRank and ("#" .. myRank) or ((myVal > 0 and not loading) and (TOP_N .. "+") or "-")
	me.nm.Text = plr.DisplayName
	LB.paint(me, plr.DisplayName)
	if myVal <= 0 then
		-- shorter on a phone: there it sits under your name in the narrow YOU card
		me.vl.Text = LAY.compact and "nothing yet - go fish!" or "nothing yet - get fishing!"
		LB.cap(me.vl, LAY.compact and 17 or 22)
	else
		me.vl.Text = fmtVal(def.key, myVal)
		LB.cap(me.vl, LAY.compact and 17 or 30)
	end
	if not LAY.compact then
		local room = 440 - 56 - 12
		me.nm.Size = UDim2.fromOffset(room, 56)
		local tw = math.min(nameEnd(plr.DisplayName, 26, 56), room)
		LB.meStk.block.root.Position = UDim2.new(0, math.floor(164 + tw + 8 + 28), 0.5, 0)
	end
	if not keepScroll then scroller.CanvasPosition = Vector2.new(0, 0) end
end

function selectTab(key)
	currentTab = key
	LB.paintTabs()
	refreshBoard()
end

-- climb as you play: your all-time totals as LeaderboardServer publishes them on you
for _, def in ipairs(BOARDS) do
	plr:GetAttributeChangedSignal("LB_" .. def.key):Connect(function() if gui.Enabled then refreshBoard(true) end end)
end
-- ...and the global top lists as the server refreshes them (one board every ~19 s)
local boardsRemote = LBR and LBR:WaitForChild("Boards", 10)
if boardsRemote then
	boardsRemote.OnClientEvent:Connect(function(key, list)
		if type(list) ~= "table" or not BOARD_BY_KEY[key] then return end
		global[key] = list
		if gui.Enabled and currentTab == key then refreshBoard(true) end
	end)
	boardsRemote:FireServer()   -- whatever the server already has, now
end
-- ...and as the other anglers in the server climb, join or leave
local function hookAngler(p)
	if p == plr then return end
	for _, def in ipairs(BOARDS) do
		p:GetAttributeChangedSignal("LB_" .. def.key):Connect(function() if gui.Enabled then refreshBoard(true) end end)
	end
end
for _, p in ipairs(Players:GetPlayers()) do hookAngler(p) end
Players.PlayerAdded:Connect(function(p)
	hookAngler(p)
	if gui.Enabled then refreshBoard(true) end
end)
Players.PlayerRemoving:Connect(function()
	task.delay(0.1, function() if gui.Enabled then refreshBoard(true) end end)
end)

----------------------------------------------------------------------
-- decor (obeys Settings > Menu Animations)
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled or plr:GetAttribute("Set_MenuFX") == false then return end
	local t = os.clock()
	for _, b in ipairs(LB.bubbles) do
		b.y -= b.speed * dt
		if b.y < -0.05 then
			b.y = 1.05
			b.x = (b.x + 0.37) % 1
		end
		b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
	end
	for _, r in ipairs(LB.rays) do
		r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
	end
end)

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
local function close() gui.Enabled = false end
TouchKit.press(LB.win.close.button, close)
TouchKit.press(backdrop, close)

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
		fit(); selectTab(currentTab); setInventoryHidden(true)
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		local target = uiscale.Scale
		uiscale.Scale = target * 0.9
		LAY.tween = TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target })
		LAY.tween:Play()
	else
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit() end end)
end
-- ...and again when the gui's own (safe-area) size catches up with a viewport change
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if not gui.Enabled then return end
	local _, compact, W, safeW = decide()
	if compact ~= LAY.compact or W ~= LAY.W or safeW ~= LAY.safeW then fit() end
end)

----------------------------------------------------------------------
-- dev hook
----------------------------------------------------------------------
local devHook = gui:FindFirstChild("DevBoard") or make("BindableEvent", { Name = "DevBoard" }, gui)
devHook.Event:Connect(function(a, b)
	if a == "__OPEN__" then
		gui.Enabled = true
	elseif a == "robux" then plr:SetAttribute("RobuxSpent", b or 0)
	elseif a == "rolls" then plr:SetAttribute("QT_roll", b or 0)
	elseif a == "fish"  then plr:SetAttribute("QT_catch", b or 0)
	elseif a == "coins" then plr:SetAttribute("QT_earn", b or 0)
	end
end)

----------------------------------------------------------------------
-- phone <-> desktop relayout. fit() calls this whenever the mode or the design width changes.
----------------------------------------------------------------------
-- the header's wave crest, re-spaced for a design width (UI.window lays it once, for WIN_W)
function LB.crest(w)
	local crest, D = LB.win.crest, 26
	for _, c in ipairs(crest:GetChildren()) do c:Destroy() end
	local n = math.ceil((w - 10) / D)
	local x0 = (w - n * D) / 2
	for i = 0, n - 1 do
		local disc = make("Frame", {
			Name = "Wave", BackgroundColor3 = UI.HEAD.gold[2], AnchorPoint = V2(0, 0.5),
			Position = UDim2.fromOffset(x0 + i * D, -1), Size = UDim2.fromOffset(D, D), ZIndex = 3,
		}, crest)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
		UI.stroke(disc, 3.5)
	end
end

relayout = function()
	local c, W = LAY.compact, LAY.W
	local win = LB.win
	-- the chrome: a shorter header on a phone, its crest re-spaced, the title and the trophy moved in
	local hh = c and LB.HEAD_H.compact or LB.HEAD_H.desk
	win.header.Size = UDim2.new(1, 0, 0, hh)
	win.crest.Position = UDim2.fromOffset(0, hh)
	win.ocean.Position = UDim2.fromOffset(0, hh)
	win.ocean.Size = UDim2.new(1, 0, 1, -hh)
	if LB.crestW ~= W then
		LB.crestW = W
		LB.crest(W)
	end
	local T = c and LB.TITLE.compact or LB.TITLE.desk
	win.title.Position = UDim2.fromOffset(T.x, 0)
	win.title.Size = UDim2.fromOffset(T.w, hh)
	LB.cap(win.title, T.max)
	if win.icon then
		local ic = c and LB.ICON.compact or LB.ICON.desk
		win.icon.Size = UDim2.fromOffset(ic.size, ic.size)
		win.icon.Position = UDim2.fromOffset(ic.x, ic.y)
	end
	LB.layTabs()
	-- the body: desktop = podium line, list, YOU bar; phone = left column of four cards + the list beside it
	LB.PODW = math.floor(W * 0.34)
	if c then
		local x0 = LB.PODW + 24
		local y0 = LB.LIST_Y.compact
		scroller.Position = UDim2.fromOffset(x0, y0)
		scroller.Size = UDim2.new(0, W - x0 - 14, 1, -(y0 + 10))
		track.Position = UDim2.fromOffset(W - 24, y0)
		track.Size = UDim2.new(0, 10, 1, -(y0 + 10))
		LB.rowW = W - x0 - 14 - 28
	else
		local y0 = LB.LIST_Y.desk
		scroller.Position = UDim2.fromOffset(10, y0)
		scroller.Size = UDim2.new(0, W - 28, 1, -(y0 + 86))
		track.Position = UDim2.fromOffset(W - 28, y0)
		track.Size = UDim2.new(0, 10, 1, -(y0 + 86))
		LB.rowW = W - 56
	end
	LB.stkK = c and 0.8 or 1
	for _, s in ipairs({ LB.podStk, LB.rowStk, LB.meStk }) do s.scale.Scale = LB.stkK end
	for place = 1, 3 do stylePod(podRecs[place], place) end
	LB.styleMe()
	for i, rec in pairs(rowPool) do styleRow(rec, i) end
	LB.layHeader()
	if gui.Enabled then refreshBoard() end
end

----------------------------------------------------------------------
-- first paint
----------------------------------------------------------------------
fit()
relayout()
LB.paintTabs()
print(string.format("[Leaderboard] built — %d boards, all-time top %d across every server", #BOARDS, TOP_N))
