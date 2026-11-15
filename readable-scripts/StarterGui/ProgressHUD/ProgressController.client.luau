-- StarterGui.ProgressHUD.ProgressController
--
-- Three small "how close am I?" meters under the money pill: NEXT BOAT, NEXT ZONE, NEXT ROD.
-- Each shows the next thing you can buy, a bar of cash-you-have against cash-it-costs, and
-- turns green and says READY! the moment you can afford it.
--
-- WHY IT IS A SEPARATE ScreenGui rather than more code inside GameClient: GameClient is 3300+
-- lines and owns the whole fishing loop. This only needs to READ attributes, so it has no
-- business living in there.
--
-- ALL THREE LADDERS ARE STRICTLY SEQUENTIAL (verified in BoatsController, ZonesController and
-- InventoryController), so "the next one" is always just the FIRST tier you do not own. Every
-- scan starts at 2, because tier 1 is the free starter in all three and has no price - a scan
-- from 1 would divide by a nil cost.
--
-- PLACEMENT is measured, not centred on the screen. The usable band is the channel between
-- the BaitRoller column (left) and the MenuBar (right), minus the RewardsHUD Daily/Wheel
-- cluster which hangs down the top-LEFT of that same channel. This mirrors GameClient's own
-- fitHud() exactly, so the meters share a datum with the pills instead of drifting off them.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local gui = script.Parent
local pg  = plr:WaitForChild("PlayerGui")
local cam = workspace.CurrentCamera

local BoatData     = require(ReplicatedStorage:WaitForChild("BoatData"))
local ShopProducts = require(ReplicatedStorage:WaitForChild("ShopProducts"))
local TouchKit     = require(ReplicatedStorage:WaitForChild("TouchKit"))

----------------------------------------------------------------------
-- house style, lifted from GameClient's pill recipe so these match
----------------------------------------------------------------------
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local FONT  = Enum.Font.FredokaOne
local FBODY = Enum.Font.GothamBold
local INK   = rgb(8, 22, 44)
local GOLD  = rgb(255, 214, 64)
local GOOD  = rgb(70, 214, 128)
local WHITE = Color3.new(1, 1, 1)

-- WIDE (tablet / desktop): 176x62 chips, gap 12 - today's look. CHIP_H went 46 -> 62 for the
-- second text line; see the chip() comment for why one line cannot carry the sentence.
-- PHONE (short side < 500): 160x56 chips, gap 8, and the caption shortens to "Next Boat" - the
-- sentence cannot fit a ~390px row at a readable size (HUD_CONTRACT T3). Scale 0.6..0.8 puts the
-- caption at ~13 px and the readout at ~12.5 px on a 667x375 phone.
local CHIP_W, CHIP_H, GAP = 176, 62, 12
local P_CHIP_W, P_CHIP_H, P_GAP = 160, 56, 8
-- The slot's TOP is GameClient's: FishingHUD:GetAttribute("TopStackBottom") is the bottom of the
-- pill row, or of the AutoToggle once Auto Fishing is owned, in LOCAL px. The pill row moves in
-- ONE place now. This row sits ROW_GAP under it (18 wide, 8 on a phone); layout() falls back to
-- the same formula for the first frames before GameClient has published.
local ROW_GAP, P_ROW_GAP = 18, 8
local compact = false       -- phone layout; re-decided on every refresh, never once at build
local styledPhone = nil     -- which geometry the chips currently carry

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(i, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }, i) end
-- ⚠️ ApplyStrokeMode.Border EXPLICITLY, and this is not a style preference - it is a bug fix.
-- UIStroke defaults to Contextual, which means "the BORDER on a Frame, but the TEXT on a
-- TextButton". These chips became TextButtons so they could be clicked, and they carry Text = "",
-- so the moment that changed their 4px outline silently had nothing to draw around and the whole
-- second row lost the chunky black border the pill row above it still had. Nothing errored and
-- the UIStroke was still there reporting Thickness 4 - only a screenshot showed it. Border is
-- what every caller here wants anyway, including the Frames, so it is set once in the helper
-- rather than at the call site, where the next control promoted to a button would hit this again.
local function stroke(i, c, t)
	return make("UIStroke", { Color = c or INK, Thickness = t or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round }, i)
end
local function gstroke(l, c, t)
	return make("UIStroke", { Color = c or INK, Thickness = t or 2,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
end

-- Same suffix ladder the shop, quests and BoatData.price use, so "$1.25M" reads identically
-- everywhere in the game.
local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }
local function money(n)
	n = math.floor(tonumber(n) or 0)
	if n < 1000 then return "$" .. n end
	local i, v = 1, n
	while v >= 1000 and i < #SUFFIX do v /= 1000; i += 1 end
	local s = string.format(v < 10 and "%.2f" or (v < 100 and "%.1f" or "%.0f"), v)
	s = s:gsub("%.?0+$", "")
	return "$" .. s .. SUFFIX[i]
end

----------------------------------------------------------------------
-- the ladders
----------------------------------------------------------------------
-- BOATS and RODS read their real source of truth, so their prices can never drift:
--   ReplicatedStorage.BoatData.TIERS  (name + cost together)
--   ReplicatedStorage.ShopProducts.ROD_CASH  (costs; keys start at [2], tier 1 is free)
--
-- ZONES and ROD NAMES have no shareable module. ZonesController's ZONES table is a `local`
-- carrying full per-zone lighting data and Color3 helpers - extracting it is a refactor of
-- the zones menu, not a read - and InventoryController's RODS table is likewise local.
-- ⚠️ SO THESE TWO TABLES ARE MIRRORS. If the zone prices in
--    StarterGui.ZonesMenu.ZonesController (the ZONES table, cost= fields) are ever retuned,
--    RETUNE THEM HERE TOO or this meter will quietly show the old number.
--    Rod names are cosmetic only - a drifted name is ugly, a drifted price is a lie, and rod
--    prices come from the real module.
local ZONES = {
	[1] = { name = "Cove",       cost = 0 },
	[2] = { name = "Reef",       cost = 20000 },
	[3] = { name = "Sunset Bay", cost = 120000 },
	[4] = { name = "Fjord",      cost = 900000 },
	[5] = { name = "Trench",     cost = 6000000 },
	[6] = { name = "Abyss",      cost = 22000000 },
}
local ZONE_MAX = 6

local ROD_NAMES = {
	[1] = "Oakwood",    [2] = "Fiberglass",    [3] = "Carbon",  [4] = "Bronze Angler",
	[5] = "Silver Tide", [6] = "Golden Lure",  [7] = "Emerald", [8] = "Frost Crystal",
	[9] = "Inferno",    [10] = "Cosmic",
}
local ROD_MAX = 10

-- Cash. Read the source FRESH every time rather than caching the instance: leaderstats is
-- created late by CurrencyClient and there is no start-order guarantee. Same shape as
-- GameClient's getCoins().
local function getCash()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then return m.Value end
	return plr:GetAttribute("Coins") or 0
end

-- Each returns: name, cost  (or nil when the ladder is finished)
local function nextBoat()
	for i = 2, BoatData.MAX_TIER do
		if plr:GetAttribute("Boat_" .. i) ~= true then
			local t = BoatData.TIERS[i]
			if t then return (t.short or t.name), t.cost end
		end
	end
	return nil
end
local function nextZone()
	for i = 2, ZONE_MAX do
		if plr:GetAttribute("Zone_" .. i) ~= true then
			return ZONES[i].name, ZONES[i].cost
		end
	end
	return nil
end
local function nextRod()
	for i = 2, ROD_MAX do
		if plr:GetAttribute("Rod_" .. i) ~= true then
			local cost = ShopProducts.ROD_CASH and ShopProducts.ROD_CASH[i]
			if cost then return ROD_NAMES[i] or ("Rod " .. i), cost end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------
local row = make("Frame", { Name = "Meters", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 100), Size = UDim2.fromOffset(CHIP_W * 3 + GAP * 2, CHIP_H),
	BackgroundTransparency = 1, ZIndex = 2, Visible = false }, gui)
local rowScale = make("UIScale", { Scale = 1 }, row)
local rowList = make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center }, row)

local function chip(order, chipName)
	-- A TextButton, not a Frame: a Frame cannot receive input at all, and TouchKit.press
	-- refuses anything that is not a GuiButton. Going through TouchKit rather than raw
	-- MouseButton1Click also gets the lazily-created 44px touch pad, which is what makes a
	-- 176x46 chip hittable on a phone.
	local f = make("TextButton", { Name = chipName, LayoutOrder = order,
		Size = UDim2.fromOffset(CHIP_W, CHIP_H),
		BackgroundColor3 = WHITE,   -- white body: the UIGradient TINTS, so let it own the colour
		BorderSizePixel = 0, ZIndex = 2, Text = "", AutoButtonColor = false }, row)
	corner(f, 999)
	local edge = stroke(f, INK, 4)
	-- the same top-lit deep blue as GameClient's pills, so these read as the same family
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, rgb(102, 184, 240)),
		ColorSequenceKeypoint.new(0.55, rgb(58, 130, 200)),
		ColorSequenceKeypoint.new(1.00, rgb(32, 88, 158)),
	}) }, f)
	local shine = make("Frame", { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.new(1, -26, 0, 7),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.66, BorderSizePixel = 0,
		ZIndex = 3 }, f)
	corner(shine, 999)

	-- Hover feedback via the STROKE and the gloss, deliberately NOT a UIScale pop. These chips
	-- sit in a horizontal UIListLayout, and a UIScale changes AbsoluteSize, so a pop would
	-- shove its two neighbours sideways every time the cursor crossed one.
	local function hover(on)
		edge.Thickness = on and 5 or 4
		shine.BackgroundTransparency = on and 0.42 or 0.66
	end
	f.MouseEnter:Connect(function() hover(true) end)
	f.MouseLeave:Connect(function() hover(false) end)

	-- NO ICON. Once the caption spells out "Progress to next Boat" the glyph is saying the same
	-- thing twice, and its 33px gutter was the ONLY thing capping the text size: measured with
	-- TextService, the longest caption is already 122px at size 12 inside a 122px box, so there
	-- was no room to grow at all. Reclaiming the gutter gives a 160px box, which fits size 16
	-- with 10px to spare - the vertical space freed by dropping the item line is worth nothing
	-- on its own, because a one-line caption is limited by WIDTH.

	-- RichText so the CATEGORY word can be gold inside the sentence. The specific item is
	-- deliberately NOT shown - the menu one click away names it, and spending the line on it
	-- forced the sentence down to a size that was hard to read while fishing.
	-- FredokaOne, not GothamBold: it is the house display font AND it is narrower here, which
	-- buys a whole size step. Measured widest caption in a 160px box - GothamBold fits 14,
	-- FredokaOne fits 16 (150px, 10px slack). ONE LINE by construction: never let this wrap.
	local caption = make("TextLabel", { BackgroundTransparency = 1, Font = FONT, Text = "",
		TextSize = 16, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, RichText = true,
		Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 24), ZIndex = 4 }, f)
	gstroke(caption, INK, 2)

	-- The bar is deliberately NARROWER than the caption above it. Run it full width and it
	-- stops reading as a meter and starts reading as a second button - as wide as the sentence
	-- and nearly as tall, so the empty state was just a dark slab. Inset 24px a side (128px at
	-- the stock chip width, 73% of it) and centred, so it stays centred if CHIP_W changes.
	-- The widest readout, "$18.4K / $250M", measures 103px at size 15: 25px of slack.
	local barBg = make("Frame", { BackgroundColor3 = rgb(14, 46, 92), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 35),
		Size = UDim2.new(1, -48, 0, 19), ZIndex = 4 }, f)
	corner(barBg, 999)
	stroke(barBg, INK, 2)
	local fill = make("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0), ZIndex = 5 }, barBg)
	corner(fill, 999)
	local bar = make("TextLabel", { BackgroundTransparency = 1, Font = FBODY, Text = "",
		TextSize = 15, TextColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, barBg)
	gstroke(bar, INK, 2)

	return { frame = f, caption = caption, fill = fill, bar = bar, barBg = barBg,
		shown = 0, clearHover = function() hover(false) end }
end

-- Chip interior per mode. WIDE restores exactly what chip() built above.
local function styleChip(c, phone)
	c.frame.Size = UDim2.fromOffset(phone and P_CHIP_W or CHIP_W, phone and P_CHIP_H or CHIP_H)
	if phone then
		c.caption.Position = UDim2.fromOffset(6, 6)
		c.caption.Size = UDim2.new(1, -12, 0, 22)
		c.caption.TextSize = 17
		c.barBg.Position = UDim2.new(0.5, 0, 0, 31)
		c.barBg.Size = UDim2.new(1, -28, 0, 18)
		c.bar.TextSize = 16
	else
		c.caption.Position = UDim2.fromOffset(8, 8)
		c.caption.Size = UDim2.new(1, -16, 0, 24)
		c.caption.TextSize = 16
		c.barBg.Position = UDim2.new(0.5, 0, 0, 35)
		c.barBg.Size = UDim2.new(1, -48, 0, 19)
		c.bar.TextSize = 15
	end
end

----------------------------------------------------------------------
-- clicking a chip opens its menu
----------------------------------------------------------------------
-- `pg.<Menu>.Enabled = true` is the whole contract - MenuLogic's ten open functions do
-- exactly this and nothing else, and every side effect (the blur, the menu's own fit/refresh,
-- the Backpack hiding, the swish) hangs off that property changing.
--
-- BindableEvent first, Enabled as the fallback: the shape RollerController already uses for
-- the baits window. Today only InventoryMenu has an "Open" event (it needs the tab argument);
-- Boats and Zones take the fallback and need no change at all, because both already scroll
-- nowhere and already flag the exact tier this chip names with their gold "NEXT" pill.
--
-- No "is another menu already open?" guard: every menu is DisplayOrder 25/26 with a
-- full-screen backdrop TextButton, and this HUD is 13, so a chip is physically unclickable
-- while one is open. Two menus at once is not reachable from here.
local function openMenu(name, tab)
	local m = pg:FindFirstChild(name)
	if not m then return end
	local ev = m:FindFirstChild("Open")
	if ev and ev:IsA("BindableEvent") then ev:Fire(tab) else m.Enabled = true end
end

-- `word` is the gold half of the caption and also the whole identity of the chip now that
-- there is no icon and no item name.
local METERS = {
	{ word = "Boat", chip = chip(1, "BoatMeter"), get = nextBoat,
		open = function() openMenu("BoatsMenu") end },
	{ word = "Zone", chip = chip(2, "ZoneMeter"), get = nextZone,
		open = function() openMenu("ZonesMenu") end },
	{ word = "Rod",  chip = chip(3, "RodMeter"),  get = nextRod,
		open = function() openMenu("InventoryMenu", "rods") end },
}

for _, m in ipairs(METERS) do
	TouchKit.press(m.chip.frame, function()
		-- Clear the hover state BEFORE opening. Once a full-screen menu covers the cursor,
		-- MouseLeave never fires, so the chip would stay lit underneath and still be lit when
		-- the player closes the menu. RewardsHUD's Daily/Wheel chips reset their scale for
		-- exactly this reason.
		m.chip.clearHover()
		m.open()
	end)
end
local GOLD_HEX = "#FFD640"   -- GOLD as RichText; keep in step with the GOLD constant above

----------------------------------------------------------------------
-- layout - mirrors GameClient's fitHud() so we share the pills' datum
----------------------------------------------------------------------
local function edgePanel(guiName, frameName)
	local scr = pg:FindFirstChild(guiName)
	if not (scr and scr.Enabled) then return nil end
	local f = scr:FindFirstChild(frameName)
	if f and f.Visible and f.AbsoluteSize.X > 4 then return f end
	return nil
end

local visibleCount = 3

-- LOCAL px (HUD_CONTRACT §1): origin = the safe-area top-left every HUD gui shares, W,H = the safe
-- area. This gui is DISABLED through the tutorial, so MainMenu's identical frame stands in then.
local function frameOf()
	local g = gui
	if not (g.Enabled and g.AbsoluteSize.X > 2) then g = pg:FindFirstChild("MainMenu") or gui end
	local sz = g.AbsoluteSize
	if sz.X < 2 then sz = cam.ViewportSize end
	return g.AbsolutePosition, sz.X, sz.Y
end

local function layout()
	local O, W, H = frameOf()
	local phone = math.min(W, H) < 500
	local left, right = 0, W
	local lp = edgePanel("BaitRoller", "Panel")
	if lp then left = lp.AbsolutePosition.X + lp.AbsoluteSize.X - O.X end
	local rp = edgePanel("MainMenu", "MenuBar")
	if rp then right = rp.AbsolutePosition.X - O.X end
	-- The Daily/Wheel cluster narrows the top channel ONLY while it hangs inside it (desktop);
	-- docked into a rail (phone / tablet) it must not. Same geometric test as GameClient.
	local topLeft = left
	local cluster = edgePanel("RewardsHUD", "Cluster")
	if cluster then
		local cl = cluster.AbsolutePosition.X - O.X
		local cr = cl + cluster.AbsoluteSize.X
		if cl >= left - 1 and cr <= right + 1 then topLeft = math.max(topLeft, cr) end
	end

	local topSpan = math.max(120, right - topLeft - 2 * (phone and 8 or 12))
	local centreTop = (topLeft + right) / 2
	local cw, ch, gap = CHIP_W, CHIP_H, GAP
	if phone then cw, ch, gap = P_CHIP_W, P_CHIP_H, P_GAP end
	if phone ~= styledPhone then
		styledPhone = phone
		for _, m in ipairs(METERS) do styleChip(m.chip, phone) end
		rowList.Padding = UDim.new(0, gap)
	end
	local rowW = math.max(1, visibleCount * cw + math.max(0, visibleCount - 1) * gap)
	local s = phone and math.clamp(topSpan / rowW, 0.6, 0.8) or math.clamp(topSpan / rowW, 0.5, 1)
	rowScale.Scale = s
	row.Size = UDim2.fromOffset(rowW, ch)

	-- Slot 3: under GameClient's published stack (pills, plus the AutoToggle once owned).
	local fh = pg:FindFirstChild("FishingHUD")
	local stack = fh and fh:GetAttribute("TopStackBottom")
	if type(stack) ~= "number" then
		local ps = phone and math.clamp(topSpan / 544, 0.6, 0.72) or math.clamp(topSpan / 544, 0.5, 1)
		stack = 44 + 48 * ps
		if (plr:GetAttribute("UpgAuto") or 0) >= 1 then stack += 8 + 40 * (phone and 0.75 or 1) end
	end
	local y = math.floor(stack + (phone and P_ROW_GAP or ROW_GAP) + 0.5)
	row.Position = UDim2.new(0, math.floor(centreTop + 0.5), 0, y)

	-- Don't collide with the bottom cast hint: read its LIVE top rather than re-deriving it.
	local hint = fh and fh:FindFirstChild("CastHint")
	local hintTop = (hint and hint.AbsoluteSize.Y > 0) and (hint.AbsolutePosition.Y - O.Y) or (H - 26 - 34)
	local bottom = y + ch * s
	return (visibleCount > 0) and (bottom + 8 <= hintTop)
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
local function refresh()
	local cash = getCash()
	local shown = 0
	local _, W, H = frameOf()
	compact = math.min(W, H) < 500
	for _, m in ipairs(METERS) do
		-- The item's NAME is still what tells us a next tier exists, but it is no longer shown:
		-- the chip says which ladder, the bar says how close, and the menu one click away says
		-- which thing. Naming it here only shrank the sentence.
		local nextName, cost = m.get()
		if not nextName or not cost or cost <= 0 then
			-- ladder finished: drop the chip entirely rather than leaving a dead "MAX" pill
			-- sitting on the HUD forever. The UIListLayout reflows the survivors.
			m.chip.frame.Visible = false
		else
			shown += 1
			m.chip.frame.Visible = true
			local frac = math.clamp(cash / cost, 0, 1)
			local ready = cash >= cost
			m.chip.caption.Text = string.format(compact and 'Next <font color="%s">%s</font>'
				or 'Progress to next <font color="%s">%s</font>', GOLD_HEX, m.word)
			m.chip.bar.Text = ready and "READY!" or (money(cash) .. " / " .. money(cost))
			m.chip.fill.BackgroundColor3 = ready and GOOD or GOLD
			if math.abs(frac - m.chip.shown) > 0.0005 then
				m.chip.shown = frac
				TweenService:Create(m.chip.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
					{ Size = UDim2.new(frac, 0, 1, 0) }):Play()
			end
		end
	end
	visibleCount = shown
	row.Visible = layout()
end

----------------------------------------------------------------------
-- wiring
----------------------------------------------------------------------
-- Cash moves the bars, so it needs the most reliable hook. CurrencyClient mirrors
-- leaderstats.Money onto the Coins attribute on every change, which covers the common case;
-- binding Money.Changed directly covers the window before that mirror exists.
plr:GetAttributeChangedSignal("Coins"):Connect(refresh)

local moneyConn
local function bindMoney()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then
		if moneyConn then moneyConn:Disconnect() end
		moneyConn = m.Changed:Connect(refresh)
		refresh()
	end
end
bindMoney()
plr.ChildAdded:Connect(function(c)
	if c.Name == "leaderstats" then task.defer(bindMoney) end
end)

-- Ownership and equipped-tier changes. Every ladder writes plain player attributes.
plr.AttributeChanged:Connect(function(a)
	if a == "UpgAuto" or a == "CurrentBoat" or a == "CurrentZone" or a == "EquippedRod"
		or a:sub(1, 5) == "Boat_" or a:sub(1, 5) == "Zone_" or a:sub(1, 4) == "Rod_" then
		refresh()
	end
end)

cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)

-- The three neighbours we measure against are built and resized at RUNTIME by other scripts
-- with no ordering guarantee, so one synchronous read at startup lands on a fallback and
-- freezes there. Poll briefly, then latch - the same thing RewardsHUD and StatsHUD do.
task.spawn(function()
	local WATCH = { { "BaitRoller", "Panel" }, { "RewardsHUD", "Cluster" },
		{ "MainMenu", "MenuBar" }, { "StatsHUD", "Stats" }, { "FishingHUD", "CastHint" } }
	local latched = {}
	for _ = 1, 40 do
		for _, w in ipairs(WATCH) do
			local scr = pg:FindFirstChild(w[1])
			local f = scr and scr:FindFirstChild(w[2])
			if f and not latched[f] then
				latched[f] = true
				f:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
				f:GetPropertyChangedSignal("AbsolutePosition"):Connect(refresh)
			end
		end
		-- the seam GameClient publishes, and MainMenu's frame (this gui's stand-in while disabled)
		local fh = pg:FindFirstChild("FishingHUD")
		if fh and not latched[fh] then
			latched[fh] = true
			fh:GetAttributeChangedSignal("TopStackBottom"):Connect(refresh)
		end
		local mm = pg:FindFirstChild("MainMenu")
		if mm and not latched[mm] then
			latched[mm] = true
			mm:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
		end
		refresh()
		task.wait(0.2)
	end
end)

-- Safety net. Money is client-written by several controllers and the seeding of rod/boat/zone
-- ownership races the HUD on join; a cheap 1Hz sweep guarantees the bars are never stale even
-- if some future writer forgets to fire anything.
task.spawn(function()
	while true do
		task.wait(1)
		refresh()
	end
end)

refresh()

print("[Progress] next-boat / next-zone / next-rod meters online")
