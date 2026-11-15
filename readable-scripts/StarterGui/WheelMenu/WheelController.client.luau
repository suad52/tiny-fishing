--[[
	WheelController - the Spin Wheel, earned by playtime. Restyled 2026-10-10 in the Shop's look (ReplicatedStorage.
	ShopKit: the +1 snowball shop design, sea theme): the teal window with its wave crest, a candy wheel with an INK
	outline and a gold marquee rim, 3D prize icons (ReplicatedStorage.ShopIcons) on the wedges, a PRIZES panel and a
	big candy SPIN key.

	WheelServer banks a spin per 5 minutes played and PICKS THE WINNING INDEX; this script animates to that index and
	applies the payload into the shared client-side stores (leaderstats.Money / Bait_* / Inv_* / Pearls), exactly like
	DailyController. SEGMENTS below must stay in the same ORDER as WheelServer's WEIGHTS.

	WHEEL GEOMETRY: Roblox UI can't draw pie slices, so every wedge is FILLED with a fan of thin radial bars (a bar of
	width w centred on a ray meets its neighbour with no seam while the angular step obeys w >= 2*face*sin(step/2)).
	Each bar carries a gradient, light at the hub and deep at the rim, so the wedges read as glossy candy. Segment k sits
	at local angle (k-1)*STEP, 0 = straight up under the pointer; to bring segment i under it the disc lands on
	360*TURNS - STEP*(i-1). Rotation is clockwise-positive in Roblox.

	Contract kept: ScreenGui WheelMenu, Enabled = open; the X is the kit's 60 x 60 TextButton named "TextButton"
	(TutorialController's closeButtonOf); WheelSpins / WheelNextIn attributes (RewardsHUD's badge); DevWheel:Fire(i).
]]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))

local plr = Players.LocalPlayer
local gui = script.Parent
for _, c in ipairs(gui:GetChildren()) do
	if c ~= script and not c:IsA("BindableEvent") then c:Destroy() end
end
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true

local rgb, V2 = Color3.fromRGB, Vector2.new
local CENTRE = V2(0.5, 0.5)
local INK = UI.INK
local function lighten(c, t) return c:Lerp(Color3.new(1, 1, 1), t) end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return (string.format("%.2f", n / (1000 ^ tier)):gsub("%.?0+$", "")) .. SUFFIX[tier + 1]
end
local function clock(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

----------------------------------------------------------------------
-- SEGMENTS - order must match WheelServer.WEIGHTS exactly
----------------------------------------------------------------------
-- Colours are a CARNIVAL cycle (neighbours clash), each a candy ramp { hi, base }; icons are ShopIcons models.
-- Cash wedges are sized so one spin is worth a minute or two of fishing and the top wedge ~20 (see the economy notes).
local YELLOW = { rgb(255, 246, 150), rgb(255, 190, 10) }
local SEGMENTS = {
	{ icon = "coins",      label = "$500",    candy = UI.CANDY.red,     kind = "cash",  amount = 500 },
	{ icon = "grub",       label = "Grub x5", candy = UI.CANDY.blue,    kind = "bait",  key = "Grub", amount = 5 },
	{ icon = "cashstack",  label = "$2.5K",   candy = UI.CANDY.orange,  kind = "cash",  amount = 2500 },
	{ icon = "potionluck", label = "Luck",    candy = UI.CANDY.emerald, kind = "boost", key = "potion_luck", amount = 1, name = "Luck Potion" },
	{ icon = "coinpile",   label = "$10K",    candy = UI.CANDY.purple,  kind = "cash",  amount = 10000 },
	{ icon = "pearl",      label = "Pearls",  candy = YELLOW,           kind = "pearl", amount = 10 },
	{ icon = "potioncast", label = "Speed",   candy = UI.CANDY.pink,    kind = "boost", key = "potion_cast", amount = 1, name = "Cast Speed Potion" },
	{ icon = "treasure",   label = "$100K",   candy = UI.CANDY.cyan,    kind = "cash",  amount = 100000 },
}
local N = #SEGMENTS
local STEP = 360 / N

local function akey(s) return (string.gsub(s, "[^%w]", "")) end
local function bump(a, n) plr:SetAttribute(a, (plr:GetAttribute(a) or 0) + n) end
local function addCash(n)
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then m.Value = m.Value + n; return true end
	plr:SetAttribute("Coins", (plr:GetAttribute("Coins") or 0) + n)
	return false
end
local function grant(i)
	local s = SEGMENTS[i]; if not s then return "" end
	if s.kind == "cash" then addCash(s.amount); return "+$" .. abbrev(s.amount)
	elseif s.kind == "bait" then bump("Bait_" .. akey(s.key), s.amount); return "+" .. s.amount .. " " .. s.key
	elseif s.kind == "boost" then bump("Inv_" .. s.key, s.amount); return "+" .. s.amount .. " " .. (s.name or s.label)
	elseif s.kind == "pearl" then bump("Pearls", s.amount); return "+" .. s.amount .. " Pearls" end
	return ""
end

----------------------------------------------------------------------
-- the window (ShopKit: the Shop's)
----------------------------------------------------------------------
local WIN_W = 900
local LAY = { phone = false, H = 640 }
local backdrop = UI.new("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.45, AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(4, 4), ZIndex = 1,
}, gui)
local win = UI.window(gui, "SPIN WHEEL", { Name = "Window", w = WIN_W, h = LAY.H, ZIndex = 5 })
local root = win.root
local uiscale = UI.new("UIScale", {}, root)
local guard = UI.new("TextButton", {
	Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
	Size = UDim2.new(1, 0, 1, 9), ZIndex = 3,
})
guard:SetAttribute("SndHooked", true)
UI.corner(guard, 24)
guard.Parent = root
local closeBtn = win.close.button


----------------------------------------------------------------------
-- a candy wheel (used twice: the big one, and the little one breaking out of the header's corner)
----------------------------------------------------------------------
-- R is the holder's half-size; every radius in G is measured from its centre (the big wheel's design numbers, scaled)
local function buildWheel(parent, R, opts)
	opts = opts or {}
	local k = R / 240
	local G = { face = 206 * k, hub = 58 * k, rimIn = 206 * k, rimTh = 16 * k, gold = 226 * k, goldTh = 14 * k,
		stick = math.max(8 * k, 3), step = 2, div = math.max(6 * k, 2), bulb = 13 * k }
	local w = { segSticks = {}, segLabels = {}, bulbs = {} }
	w.holder = UI.new("Frame", { Name = opts.Name or "Wheel", BackgroundTransparency = 1, Size = UDim2.fromOffset(R * 2, R * 2),
		Position = opts.Position or UDim2.new(), AnchorPoint = opts.AnchorPoint or V2(), Rotation = opts.Rotation or 0, ZIndex = opts.ZIndex or 2 }, parent)
	w.scale = UI.new("UIScale", {}, w.holder)
	-- the hard drop under the whole wheel, and the gold marquee ring (it does not turn: the bulbs chase around it)
	local function ring(r, th, col, z, par)
		local f = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(r * 2, r * 2), ZIndex = z }, par or w.holder)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
		local s = UI.new("UIStroke", { Color = col, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
		return f, s
	end
	local drop = UI.new("Frame", { Name = "Drop", BackgroundColor3 = INK, AnchorPoint = CENTRE, Position = UDim2.new(0.5, 0, 0.5, 8 * k),
		Size = UDim2.fromOffset((G.gold + G.goldTh / 2 + 3) * 2, (G.gold + G.goldTh / 2 + 3) * 2), ZIndex = 1 }, w.holder)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, drop)
	local goldDisc = UI.new("Frame", { Name = "GoldRing", BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset((G.gold + G.goldTh / 2) * 2, (G.gold + G.goldTh / 2) * 2), ZIndex = 2 }, w.holder)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, goldDisc)
	UI.stroke(goldDisc, math.max(4 * k, 2))
	UI.vgrad(goldDisc, { rgb(255, 240, 140), rgb(255, 196, 40), rgb(230, 140, 10) })
	-- the disc: everything on it turns
	w.disc = UI.new("Frame", { Name = "Disc", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, w.holder)
	local plate = UI.new("Frame", { BackgroundColor3 = INK, AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset((G.rimIn + G.rimTh / 2) * 2, (G.rimIn + G.rimTh / 2) * 2), ZIndex = 3 }, w.disc)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, plate)
	-- a bar along the ray `ang` (clockwise from straight up), spanning radius 0..len (positioned on the circle;
	-- Rotation only orients it, since rotation pivots about the bar's own centre)
	local function ray(len, wd, ang, z)
		local t = math.rad(ang)
		return UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = CENTRE,
			Position = UDim2.new(0.5, (len / 2) * math.sin(t), 0.5, -(len / 2) * math.cos(t)),
			Size = UDim2.fromOffset(wd, len), Rotation = ang, ZIndex = z }, w.disc)
	end
	for i, seg in ipairs(SEGMENTS) do
		local c0 = (i - 1) * STEP
		local K = math.ceil(STEP / G.step)
		local hi, base = seg.candy[1], seg.candy[#seg.candy]
		local seq = ColorSequence.new(base, hi) -- (the bar's top is its OUTER end: deep at the rim, light at the hub)
		local sticks = {}
		for j = 0, K do
			local b = ray(G.face, G.stick, c0 - STEP / 2 + STEP * j / K, 4)
			UI.new("UIGradient", { Name = "Fill", Rotation = 90, Color = seq }, b)
			sticks[#sticks + 1] = b
		end
		w.segSticks[i] = { bars = sticks, seq = seq, flash = ColorSequence.new(lighten(base, 0.5), Color3.new(1, 1, 1)) }
		if opts.labels then
			local t = math.rad(c0)
			local mid = (G.hub + G.face) / 2 + 6 * k
			local holder = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = CENTRE,
				Position = UDim2.new(0.5, mid * math.sin(t), 0.5, -mid * math.cos(t)),
				Size = UDim2.fromOffset(96 * k, (G.face - G.hub) * 1.0), Rotation = c0, ZIndex = 7 }, w.disc)
			local glow = UI.new("ImageLabel", { BackgroundTransparency = 1, Image = UI.ICONS.glow, AnchorPoint = V2(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, -2 * k), Size = UDim2.fromOffset(78 * k, 78 * k), ImageTransparency = 0.35, ZIndex = 7 }, holder)
			local ic = UI.icon(holder, seg.icon, math.floor(62 * k), { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6 * k), ZIndex = 8, still = true })
			local lb = UI.label(holder, seg.label, { size = math.floor(22 * k), drop = 2, outline = 0.16, AnchorPoint = V2(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 70 * k), Size = UDim2.new(1, 8, 0, 26 * k), ZIndex = 9 })
			w.segLabels[i] = { holder = holder, icon = ic, label = lb, glow = glow }
		end
	end
	-- dividers over the fill, a white candy rim inside the INK rim, and a bolt on each boundary
	for i = 1, N do
		local edge = (i - 1) * STEP + STEP / 2
		local d = ray(G.face + 2, G.div, edge, 6)
		d.BackgroundColor3 = INK
	end
	ring(G.rimIn, G.rimTh, INK, 10, w.disc)
	ring(G.rimIn - G.rimTh / 2 - 1.5 * k, math.max(3 * k, 1.5), Color3.new(1, 1, 1), 10, w.disc).BackgroundTransparency = 1
	-- the marquee: bulbs on the gold ring (they don't turn)
	local BULBS = opts.bulbs or 20
	for i = 1, BULBS do
		local a = (i - 1) * (math.pi * 2 / BULBS)
		local b = UI.new("Frame", { BackgroundColor3 = rgb(255, 252, 220), AnchorPoint = CENTRE, Size = UDim2.fromOffset(G.bulb, G.bulb),
			Position = UDim2.new(0.5, math.sin(a) * G.gold, 0.5, -math.cos(a) * G.gold), ZIndex = 12 }, w.holder)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		UI.stroke(b, math.max(2 * k, 1))
		w.bulbs[i] = b
	end
	-- the hub (does NOT turn: it carries the countdown): a gold candy disc
	w.hub = UI.new("Frame", { Name = "Hub", BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(G.hub * 2, G.hub * 2), ZIndex = 14 }, w.holder)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, w.hub)
	UI.stroke(w.hub, math.max(4 * k, 2))
	UI.vgrad(w.hub, { rgb(255, 244, 150), rgb(255, 196, 30), rgb(236, 140, 0) })
	local hubGloss = UI.gloss(w.hub, { frac = 0.46, alpha = 0.4, inset = math.max(5 * k, 2), radius = 999 })
	hubGloss.ZIndex = 15
	if opts.hubText then
		w.hubTxt = UI.label(w.hub, "SPIN", { size = 24, drop = 2, outline = 0.16, AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -14, 0, 34), ZIndex = 17 })
	end
	-- the pointer: a red candy tongue hanging from a gold bracket over the top of the rim
	w.post = UI.new("Frame", { Name = "PointerPost", BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = V2(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -30 * k), Size = UDim2.fromOffset(64 * k, 54 * k), ZIndex = 21 }, w.holder)
	UI.corner(w.post, math.floor(14 * k))
	UI.stroke(w.post, math.max(4 * k, 2))
	UI.vgrad(w.post, { rgb(255, 244, 150), rgb(255, 190, 20), rgb(226, 132, 0) })
	UI.gloss(w.post, { frac = 0.45, alpha = 0.45, inset = math.max(3 * k, 1), radius = math.floor(10 * k) }).ZIndex = 22
	w.pointer = UI.new("Frame", { Name = "Pointer", BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = CENTRE,
		Position = UDim2.new(0.5, 0, 0, 26 * k), Size = UDim2.fromOffset(44 * k, 44 * k), Rotation = 45, ZIndex = 20 }, w.holder)
	UI.corner(w.pointer, math.floor(8 * k))
	UI.stroke(w.pointer, math.max(4 * k, 2))
	UI.new("UIGradient", { Rotation = 45, Color = ColorSequence.new(rgb(255, 120, 120), rgb(206, 16, 30)) }, w.pointer)
	return w
end

local big = buildWheel(root, 240, { Name = "Wheel", labels = true, hubText = true, bulbs = 20, ZIndex = 6 })
local hubTxt = big.hubTxt
-- the little wheel breaking out of the header's top-left corner (the Shop's cart spot), turning slowly
local mini = buildWheel(root, 58, { Name = "HeaderWheel", bulbs = 10, Position = UDim2.fromOffset(-40, -46), Rotation = -8, ZIndex = 9 })

----------------------------------------------------------------------
-- the PRIZES panel + the SPIN key
----------------------------------------------------------------------
local prizeTitle = UI.label(root, "PRIZES", { size = 32, drop = 3, outline = 4 / 32, outlineColor = UI.TITLE.outline, ZIndex = 7 })
UI.vgrad(prizeTitle, UI.TITLE.keys)
local chips = {}
for i, seg in ipairs(SEGMENTS) do
	local c = {}
	c.root = UI.new("Frame", { Name = "Prize" .. i, BackgroundTransparency = 1, ZIndex = 7 }, root)
	UI.hardShadow(c.root, 14, 4, 5, 7)
	c.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 8 }, c.root)
	UI.corner(c.face, 14)
	UI.stroke(c.face, 4)
	UI.vgrad(c.face, seg.candy)
	UI.gloss(c.face, { frac = 0.45, alpha = 0.55, inset = 3, radius = 10 })
	c.glow = UI.new("ImageLabel", { BackgroundTransparency = 1, Image = UI.ICONS.glow, AnchorPoint = CENTRE, ImageTransparency = 0.25, ZIndex = 9 }, c.root)
	c.icon = UI.icon(c.root, seg.icon, 52, { AnchorPoint = CENTRE, ZIndex = 10 })
	c.label = UI.label(c.root, seg.label, { size = 22, scaled = false, drop = 2, outline = 0.15, align = "left", ZIndex = 11 })
	chips[i] = c
end
local spinKey = UI.candyKey(root, "green", { Name = "SpinKey", Size = UDim2.fromOffset(346, 84), ZIndex = 8 })
local spinNote = UI.label(root, "", { size = 20, scaled = false, drop = 2, outline = 0.15, ZIndex = 7 })

----------------------------------------------------------------------
-- layout: desktop (640 tall) and a phone (430 tall: the wheel shrinks, the panel tightens)
----------------------------------------------------------------------
local function place()
	local ph = LAY.phone
	local H = ph and 430 or 640
	LAY.H = H
	root.Size = UDim2.fromOffset(WIN_W, H)
	-- the corner wheel breaks out of the top-left corner; on a phone it is TUCKED INSIDE the 74 px header (2026-10-11,
	-- the owner: "make the button uis centered to the phone screen" - centred, a wheel reaching 53 px over the window
	-- would sit under Roblox's top-bar buttons). Its holder scales about its top-left: at 0.55 the drawn extent (the
	-- pointer post 10 px over the holder .. the drop 117 px down) lands at x 8..72, y 2..71, clear of the title at 112.
	mini.holder.Position = ph and UDim2.fromOffset(8, 7) or UDim2.fromOffset(-40, -46)
	mini.scale.Scale = ph and 0.55 or 1
	local top = 96
	local k = ph and (H - top - 14) / 516 or 1 -- the wheel's drawn extent is y -36..480 of its 480 holder
	big.scale.Scale = k
	-- (a UIScale shrinks the holder about its centre: put the centre where a k-sized wheel's centre belongs)
	local cx, cy = 30 + 240 * k, top + 36 * k + 240 * k
	big.holder.AnchorPoint = CENTRE
	big.holder.Position = UDim2.fromOffset(cx, cy)
	local colX = math.floor(cx + 240 * k + 34)
	local colW = WIN_W - colX - 28
	local y = top
	if ph then
		prizeTitle.Visible = false
	else
		prizeTitle.Visible = true
		prizeTitle.Position = UDim2.fromOffset(colX, y)
		prizeTitle.Size = UDim2.fromOffset(colW, 40)
		y += 46
	end
	local chipH = ph and 50 or 72
	local gap = ph and 8 or 12
	local chipW = math.floor((colW - gap) / 2)
	for i, c in ipairs(chips) do
		local col, row = (i - 1) % 2, (i - 1) // 2
		c.root.Position = UDim2.fromOffset(colX + col * (chipW + gap), y + row * (chipH + gap))
		c.root.Size = UDim2.fromOffset(chipW, chipH)
		local is = ph and 42 or 48
		c.glow.Size = UDim2.fromOffset(is + 18, is + 18)
		c.glow.Position = UDim2.fromOffset(8 + is / 2, chipH / 2)
		c.icon.Size = UDim2.fromOffset(is, is)
		c.icon.Position = UDim2.fromOffset(8 + is / 2, chipH / 2)
		c.label.Position = UDim2.fromOffset(14 + is, 0)
		c.label.Size = UDim2.new(1, -(18 + is), 1, 0)
	end
	y += 4 * chipH + 3 * gap
	local keyH = ph and 64 or 84
	spinKey.button.Size = UDim2.fromOffset(colW, keyH)
	spinKey.button.Position = UDim2.fromOffset(colX, H - 22 - keyH)
	spinNote.Visible = not ph
	spinNote.Position = UDim2.fromOffset(colX, y + 6)
	spinNote.Size = UDim2.fromOffset(colW, (H - 22 - keyH) - (y + 6) - 8)
	spinKey.lastText = nil
end

local function layout()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or V2(1280, 720)
	local abs = gui.AbsoluteSize
	local cw = (abs.X > 100 and abs.X < vp.X) and abs.X or vp.X
	local ch = (abs.Y > 100 and abs.Y < vp.Y) and abs.Y or vp.Y
	if cw < 100 or ch < 100 then return uiscale.Scale end
	local phone = math.min(cw, ch) < 500
	if phone ~= LAY.phone or not LAY.placed then
		LAY.phone, LAY.placed = phone, true
		place()
	end
	if phone then
		-- CENTRED ON THE PHONE SCREEN with nothing above the box (the corner wheel is tucked, place()): fit the width,
		-- then MenuFit.centre shrinks it just enough for the top to clear the top bar and the 9 px drop the screen's
		-- foot. A stand-in table carries the scale: the callers set / pop uiscale to what this returns.
		return MenuFit.centre(root, { Scale = math.clamp((cw - 16) / (WIN_W + 76), 0.35, 1.1) }, 0, 9)
	end
	local bar = GuiService.TopbarInset.Max.Y
	local topY = (bar > 0 and bar or 58) + 4
	local room = ch - 8 - topY
	-- centred on the screen: the box plus the corner wheel above it (46) and the drop below (9), with the same
	-- clearance top and bottom, so it never runs under the top bar
	local fit = math.clamp(math.min((cw - 16) / (WIN_W + 76), (ch - 2 * topY) / (LAY.H + 2 * 46), 1.1), 0.35, 1.1)
	root.Position = UDim2.new(0.5, 0, 0, math.floor(ch / 2 + 0.5))
	local _ = room
	return fit
end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------
local spins, secsToNext, spinEvery, maxBanked = 0, 300, 300, 3
local spinning = false
local tickPh = 0

local function setSpinKey(textStr, colour, iconName)
	local sig = textStr .. "|" .. colour .. "|" .. tostring(iconName)
	if spinKey.lastText == sig then return end
	spinKey.lastText = sig
	spinKey.recolour(colour)
	local parts = {}
	if iconName then table.insert(parts, { icon = iconName, size = LAY.phone and 40 or 48, drop = 0, flat = true }) end
	table.insert(parts, { text = textStr, size = LAY.phone and 34 or 40 })
	spinKey.setParts(nil, parts, { gap = 10 })
end

local function refresh()
	if spinning then return end
	if spins > 0 then
		setSpinKey(spins > 1 and ("SPIN! (" .. spins .. ")") or "SPIN!", "green", nil)
		spinNote.Text = "Good luck!"
		hubTxt.Text = "SPIN"
	else
		setSpinKey(clock(secsToNext), "grey", "clock")
		spinNote.Text = "1 free spin every " .. math.floor(spinEvery / 60) .. " minutes"
		hubTxt.Text = "SPIN"
	end
end

----------------------------------------------------------------------
-- the toast (in the window)
----------------------------------------------------------------------
local toastChip = UI.chip(root, "navy", { Name = "Toast", height = 52, textSize = 26, pad = 26, minWidth = 260, AnchorPoint = V2(0.5, 1), ZIndex = 40,
	Position = UDim2.new(0.5, 0, 1, -18) })
toastChip.block.root.Visible = false
local toastScale = UI.new("UIScale", {}, toastChip.block.root)
local toastToken = 0
local function showToast(text, kind)
	toastChip.set(text, ({ good = "gold", bad = "red" })[kind or ""] or "navy")
	toastChip.block.root.Visible = true
	UI.punch(toastScale, 0.6, 0.28)
	toastToken += 1
	local my = toastToken
	task.delay(2.6, function() if my == toastToken then toastChip.block.root.Visible = false end end)
end

----------------------------------------------------------------------
-- remotes
----------------------------------------------------------------------
local remotes = ReplicatedStorage:WaitForChild("WheelRemotes", 30)
local stateEvent, spinEvent, resultEvent
if remotes then
	stateEvent = remotes:WaitForChild("State")
	spinEvent = remotes:WaitForChild("Spin")
	resultEvent = remotes:WaitForChild("Result")
end

-- a burst of candy confetti out of the hub when a prize lands
local CONFETTI = { rgb(255, 214, 84), rgb(255, 120, 150), rgb(120, 220, 255), rgb(150, 240, 160), rgb(200, 160, 255) }
local function confetti()
	for _ = 1, 26 do
		local p = UI.new("Frame", { BackgroundColor3 = CONFETTI[math.random(#CONFETTI)], AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(math.random(9, 15), math.random(9, 15)), Rotation = math.random(0, 360), ZIndex = 30 }, big.holder)
		UI.corner(p, 3)
		local a = math.random() * math.pi * 2
		local d = math.random(150, 300)
		TweenService:Create(p, TweenInfo.new(math.random(70, 110) / 100, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * d, 0.5, math.sin(a) * d + 90), Rotation = p.Rotation + math.random(-260, 260),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(1.3, function() if p.Parent then p:Destroy() end end)
	end
end

local function flashSegment(i, on)
	local s = big.segSticks[i]
	for _, b in ipairs(s.bars) do b.Fill.Color = on and s.flash or s.seq end
	local l = big.segLabels[i]
	if l then UI.punch(UI.new("UIScale", {}, l.holder), on and 1.25 or 1, 0.35) end
end

local TURNS = 5
local function landOn(index)
	spinning = true
	setSpinKey("SPINNING...", "grey", nil)
	spinNote.Text = ""
	local target = 360 * TURNS - STEP * (index - 1)
	big.disc.Rotation = big.disc.Rotation % 360
	local tween = TweenService:Create(big.disc, TweenInfo.new(4.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Rotation = target })
	tween:Play()
	tween.Completed:Connect(function()
		big.disc.Rotation = big.disc.Rotation % 360
		spinning = false
		local what = grant(index)
		confetti()
		showToast("You won " .. what .. "!", "good")
		flashSegment(index, true)
		task.delay(2.2, function() flashSegment(index, false) end)
		UI.punch(UI.new("UIScale", {}, chips[index].root), 1.12, 0.4)
		Audio.play("Fanfare", { volume = 0.85 })
		refresh()
	end)
end

if stateEvent then
	stateEvent.OnClientEvent:Connect(function(s, toNext, every, maxB)
		spins = tonumber(s) or 0
		secsToNext = tonumber(toNext) or 300
		spinEvery = tonumber(every) or 300
		maxBanked = tonumber(maxB) or 3
		plr:SetAttribute("WheelSpins", spins) -- drives the RewardsHUD badge
		plr:SetAttribute("WheelNextIn", secsToNext)
		refresh()
	end)
end
if resultEvent then
	resultEvent.OnClientEvent:Connect(function(index)
		landOn(math.clamp(tonumber(index) or 1, 1, N))
	end)
end

local function doSpin()
	if spinning then return end
	if spins <= 0 then showToast("No spins yet - keep fishing!", "bad"); return end
	if spinEvent then spinEvent:FireServer() else showToast("The wheel is offline", "bad") end
end
TouchKit.press(spinKey.button, doSpin)
local function close() gui.Enabled = false end
TouchKit.press(closeBtn, close)
TouchKit.press(backdrop, close)

----------------------------------------------------------------------
-- the sea behind it all, the countdown between server pushes, the marquee, the flapper
----------------------------------------------------------------------
local bubbles = {}
for i = 1, 20 do
	local s = 6 + (i * 7) % 13
	local b = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.78, AnchorPoint = CENTRE, Size = UDim2.fromOffset(s, s), ZIndex = 2 }, win.ocean)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	UI.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.35 }, b)
	bubbles[i] = { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, sp = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, ph = i }
end
for i, x in ipairs({ 0.1, 0.42, 0.7, 0.92 }) do
	local ray = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
		Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.84, ZIndex = 1 }, win.ocean)
	UI.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) }) }, ray)
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	acc += dt
	if acc >= 1 then
		acc -= 1
		-- RewardsHUD owns the countdown tick (it runs with this menu shut too): read it back
		if spins <= 0 then
			secsToNext = plr:GetAttribute("WheelNextIn") or secsToNext
			refresh()
		end
	end
	-- the flapper ticks: every boundary going past kicks it aside, then it snaps back (not gated on MenuFX: it's
	-- the wheel reading as a wheel). A tick sound per boundary, on the phase wrap, so they slow down with the wheel.
	if spinning then
		local ph = (big.disc.Rotation % STEP) / STEP
		big.pointer.Rotation = 45 + 16 * math.max(0, 1 - ph * 3.2)
		if ph < tickPh then Audio.play("Tick", { pitch = 1.5 + math.random() * 0.2, volume = 0.5 }) end
		tickPh = ph
	elseif big.pointer.Rotation ~= 45 then
		big.pointer.Rotation = 45
	end
	if plr:GetAttribute("Set_MenuFX") ~= false then
		local t = os.clock()
		local rate = spinning and 14 or 5
		local lit = math.floor(t * rate) % 3
		for i, b in ipairs(big.bulbs) do b.BackgroundTransparency = ((i % 3) == lit) and 0 or 0.55 end
		for i, b in ipairs(mini.bulbs) do b.BackgroundTransparency = ((i % 2) == (lit % 2)) and 0 or 0.55 end
		mini.disc.Rotation = (mini.disc.Rotation + dt * (spinning and 240 or 24)) % 360
		for _, bd in ipairs(bubbles) do
			bd.y -= bd.sp * dt
			if bd.y < -0.05 then bd.y = 1.05; bd.x = (bd.x + 0.37) % 1 end
			bd.f.Position = UDim2.new(bd.x, math.sin(t * bd.wob + bd.ph) * 6, bd.y, 0)
		end
	end
end)

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
		local fit = layout()
		refresh()
		setInventoryHidden(true)
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		uiscale.Scale = 0.6 * fit
		TweenService:Create(uiscale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	else
		setInventoryHidden(false)
	end
end)
-- a new screen (a resized window, another device): place it again once the size has settled
local refitToken = 0
local function refitSoon()
	refitToken += 1
	local my = refitToken
	for _, d in ipairs({ 0.15, 0.6 }) do
		task.delay(d, function()
			if my == refitToken and gui.Enabled then uiscale.Scale = layout() end
		end)
	end
end
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refitSoon) end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refitSoon)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitSoon)

uiscale.Scale = layout()

-- DevWheel:Fire(i) animates to segment i locally without spending a server spin
local dev = gui:FindFirstChild("DevWheel") or UI.new("BindableEvent", { Name = "DevWheel" }, gui)
dev.Event:Connect(function(i) landOn(math.clamp(tonumber(i) or 1, 1, N)) end)

refresh()
print("[Wheel] built - " .. N .. " segments (the Shop's look)")
