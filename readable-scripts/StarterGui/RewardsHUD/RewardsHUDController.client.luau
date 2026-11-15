--[[
	RewardsHUD — the floating stickers for the Free Gift and the Spin Wheel.

	These deliberately do NOT sit in the right-hand MenuBar: they are time-gated, so they
	need to advertise themselves (a badge, a live countdown) rather than wait to be found
	in a list. The cluster sits in the play area just right of the BaitRoller panel
	(360 wide) and below the top HUD pills, so it collides with neither.

	Daily Rewards has NO sticker any more (the owner, 2026-10-10): it offers itself when you
	join and is gone until the next day - see DailyController. Its slot became Free Gifts
	(GiftsMenu): nine prizes a session for playing, whose clock GiftsController owns and
	publishes as GiftReadyIn - this sticker only shows it and opens the window. The wheel reads WheelSpins / WheelNextIn from WheelController,
	pushed by its server, so its badge is correct without polling anything.

	It DOES own the countdown tick, because it runs whether or not the wheel menu is open.
	WheelController must not decrement WheelNextIn as well or the clock runs double speed.

	CARTOON TREATMENT: every chip is a sticker — a dark base disc offset downward, a bright
	face on top with a fat ink outline, a gloss cap, and a ribbon caption. Ready rewards
	bob, tilt and throw off sparkles; idle ones sit still so the eye goes to what's ready.
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local GuiService   = game:GetService("GuiService")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")
local gui = script.Parent
-- 21, one over the MainMenu (20): on a phone the stickers are docked INTO the MenuBar's reserved
-- sixth row, so they must draw above the bar's own background. Everywhere else they overlap
-- nothing, so the bump from 18 changes nothing there.
gui.DisplayOrder = 21
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

-- THREE PLACEMENTS (HUD_CONTRACT L3), chosen in relayout() and published as gui.Mode:
--   dockRight    phones. MenuLogic leaves the MenuBar's sixth row empty and publishes it as
--                MenuBar.RewardsDockPos / RewardsDockSize (LOCAL px); the two stickers split it.
--   dockTopLeft  tablets (BaitRoller.HudMode "tablet"). The roller is bottom-anchored there, and
--                the stickers sit side by side in the corner above it.
--   channel      desktop: today's column in the play area, just right of the roller.
-- LOCAL px: every HUD gui is IgnoreGuiInset + DeviceSafeInsets, so they all share one origin, the
-- safe area's top-left. A rect read off another gui is its AbsolutePosition minus THIS gui's
-- AbsolutePosition - never an AbsolutePosition written straight into a Position.
--
-- In channel mode the chips hug the BaitRoller panel's right edge, which is NOT a constant
-- (RollerController scales the panel per viewport), so it is read LIVE. This used to be pinned at
-- x=375 - "measured", once, on one viewport - which stranded it mid-screen on a phone.
local FALLBACK_X = 375   -- only until the roller has rendered
local GUTTER     = 12
-- The pills' top is at y=44 in the shared HUD space; 44 lines the stickers' top up with them.
local TOP_Y     = 44

local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local function lighten(c,t) return c:Lerp(Color3.new(1,1,1), t) end
local function darken(c,t)  return c:Lerp(Color3.new(0,0,0), t) end
local INK, GOLD = rgb(8,22,44), rgb(255,224,104)
local FONT = Enum.Font.FredokaOne

local function make(class, props, parent)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(i,r) return make("UICorner", { CornerRadius = UDim.new(0, r or 999) }, i) end
local function stroke(i,c,t) return make("UIStroke", { Color = c or INK, Thickness = t or 4 }, i) end
local function grad(i,a,b,rot) return make("UIGradient", { Color = ColorSequence.new(a,b), Rotation = rot or 90 }, i) end

local function clock(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec/60), sec % 60)
end

local holder = make("Frame", {
	Name = "Cluster", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(FALLBACK_X, TOP_Y),
	Size = UDim2.fromOffset(104, 260), ZIndex = 2 }, gui)
local list = make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0,18), SortOrder = Enum.SortOrder.LayoutOrder }, holder)

local SZ = 78

-- THE STICKERS' LOOK (2026-10-10, the owner: "rework them to look better") - the Shop's candy (ReplicatedStorage.ShopKit):
-- a rounded-square KEY with an INK outline, a white rim, a bright candy face with a gloss cap and a hard INK drop,
-- carrying real art instead of an emoji: a 3D gift box (ShopIcons.gift, rocking like the Shop's icons) and a little
-- candy prize wheel (the Spin Wheel's own, in miniature: it turns slowly, and spins up when a spin is ready). The
-- caption is a candy pill - navy with the countdown, green with OPEN! / SPIN!. Ready stickers glow gold, bob, tilt and
-- throw sparkles; idle ones sit still. style() still sizes every part per placement (channel / dockRight / dockTopLeft).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))
local TILE = {
	Gift = { face = UI.CANDY.orange, art = "gift" },
	Wheel = { face = UI.CANDY.purple, art = "wheel" },
}
local CAPTION = { ready = { rgb(150, 246, 128), rgb(34, 176, 58) }, idle = { rgb(48, 100, 164), rgb(16, 46, 96) } }

-- the little candy wheel: 8 wedges of radial bars (light at the hub, deep at the rim), INK dividers, a gold rim and hub,
-- a red pointer. Built at 64 px; style() scales it with the sticker.
local WHEEL_COLOURS = { UI.CANDY.red, UI.CANDY.blue, UI.CANDY.orange, UI.CANDY.emerald, UI.CANDY.purple,
	{ rgb(255, 246, 150), rgb(255, 190, 10) }, UI.CANDY.pink, UI.CANDY.cyan }
local function miniWheel(parent)
	local R = 32
	local hold = make("Frame", { Name = "MiniWheel", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(R * 2, R * 2), ZIndex = 8 }, parent)
	local sc = make("UIScale", {}, hold)
	local rim = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(R * 2, R * 2), ZIndex = 8 }, hold)
	corner(rim); stroke(rim, INK, 2.5)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 240, 140)),
		ColorSequenceKeypoint.new(0.5, rgb(255, 196, 40)), ColorSequenceKeypoint.new(1, rgb(230, 140, 10)) }) }, rim)
	local disc = make("Frame", { Name = "Disc", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9 }, hold)
	local face, step = R - 5, 360 / #WHEEL_COLOURS
	local plate = make("Frame", { BackgroundColor3 = INK, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(face * 2 + 2, face * 2 + 2), ZIndex = 9 }, disc)
	corner(plate)
	local function ray(len, w, ang, z)
		local t = math.rad(ang)
		return make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, (len / 2) * math.sin(t), 0.5, -(len / 2) * math.cos(t)), Size = UDim2.fromOffset(w, len),
			Rotation = ang, ZIndex = z }, disc)
	end
	for i, c in ipairs(WHEEL_COLOURS) do
		local c0 = (i - 1) * step
		local seq = ColorSequence.new(c[#c], c[1])   -- (a bar's top is its OUTER end: deep at the rim, light at the hub)
		for j = 0, 15 do
			make("UIGradient", { Rotation = 90, Color = seq }, ray(face, 3, c0 - step / 2 + step * j / 15, 10))
		end
	end
	for i = 1, #WHEEL_COLOURS do ray(face + 1, 1.5, (i - 1) * step + step / 2, 11).BackgroundColor3 = INK end
	local hub = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 12 }, hold)
	corner(hub); stroke(hub, INK, 2)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 244, 150), rgb(236, 140, 0)) }, hub)
	local ptr = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(11, 11), Rotation = 45, ZIndex = 13 }, hold)
	corner(ptr, 3); stroke(ptr, INK, 2)
	make("UIGradient", { Rotation = 45, Color = ColorSequence.new(rgb(255, 120, 120), rgb(206, 16, 30)) }, ptr)
	return hold, sc, disc
end

local function chip(name, order)
	local look = TILE[name]
	local wrap = make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(104, 112), LayoutOrder = order, ZIndex = 2 }, holder)

	-- the whole sticker tilts/bobs as one
	local pivot = make("Frame", { Name = "Pivot", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.5,0,0,0),
		Size = UDim2.fromOffset(SZ, SZ), ZIndex = 2 }, wrap)
	local scale = make("UIScale", { Scale = 1 }, pivot)

	-- 0. the ready glow: a soft gold halo behind the key (ring keeps its stroke for style(); the halo is the image)
	local ring = make("Frame", { Name = "Glow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromOffset(SZ+18, SZ+18), ZIndex = 1, Visible = false }, pivot)
	local ringStroke = stroke(ring, GOLD, 4)
	ringStroke.Enabled = false
	local glow = make("ImageLabel", { Name = "Halo", BackgroundTransparency = 1, Image = UI.ICONS.glow, ImageColor3 = rgb(255, 214, 80),
		AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromScale(2.3,2.3), ZIndex = 1 }, ring)

	-- 1. the hard drop: an INK copy of the key, offset down
	local R = UDim.new(0.28, 0)
	local base = make("Frame", { Name = "Drop", BackgroundColor3 = INK, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 7), Size = UDim2.fromOffset(SZ, SZ), ZIndex = 2 }, pivot)
	make("UICorner", { CornerRadius = R }, base)
	local baseStroke = stroke(base, INK, 4)

	-- 2. the key: a white rim inside the INK outline, the candy face inset in it
	local btn = make("TextButton", { Name = "Btn", Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, Size = UDim2.fromOffset(SZ, SZ), ZIndex = 4 }, pivot)
	make("UICorner", { CornerRadius = R }, btn)
	local btnStroke = stroke(btn, INK, 4.5)
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromScale(0.9,0.9), ZIndex = 5 }, btn)
	make("UICorner", { CornerRadius = UDim.new(0.26, 0) }, fill)
	UI.vgrad(fill, look.face)

	-- 3. gloss cap across the top third
	local gloss = make("Frame", { Name = "Gloss", BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.5,0,0,6),
		Size = UDim2.fromOffset(SZ-22, 24), ZIndex = 7 }, btn)
	corner(gloss, 10)
	grad(gloss, Color3.new(1,1,1), Color3.new(1,1,1)).Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })

	-- 4. the art. (The old emoji labels stay, empty and hidden: style() still sizes them.)
	local shadow = make("TextLabel", { BackgroundTransparency = 1, Text = "", Visible = false, Size = UDim2.fromScale(1,1) }, btn)
	local face = make("TextLabel", { BackgroundTransparency = 1, Text = "", Visible = false, Size = UDim2.fromScale(1,1) }, btn)
	local art, artScale, disc
	if look.art == "wheel" then
		art, artScale, disc = miniWheel(btn)
	else
		-- 0.49 / 0.47 at 0.82, not centred-low at 0.92 (the owner, 2026-10-10: "the present should be more centered
		-- to the button"): ShopKit draws a 3D icon's INK drop 2% right and 6% down of the model, so a box framed
		-- dead-centre READS low-right; nudging the art up-left by half that puts the model + its drop on the
		-- key's centre, and 0.82 leaves the same margin the wheel has instead of crowding the bottom edge.
		art = make("Frame", { Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5,0.5),
			Position = UDim2.fromScale(0.49,0.47), Size = UDim2.fromScale(0.82,0.82), ZIndex = 8 }, btn)
		UI.icon(art, look.art, UDim2.fromScale(1,1), { Name = "Icon", ZIndex = 8 })
	end

	-- 6. sparkles around a ready sticker
	local sparks = {}
	for s = 1, 3 do
		sparks[s] = make("TextLabel", { BackgroundTransparency = 1, Text = "✨", Font = FONT,
			TextSize = 20, Size = UDim2.fromOffset(22,22), AnchorPoint = Vector2.new(0.5,0.5),
			ZIndex = 9, Visible = false }, pivot)
	end

	-- 7. the caption: a candy pill under the key (navy + countdown, green + OPEN! / SPIN!)
	local ribbon = make("Frame", { Name = "Caption", BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.5,0,0,SZ+13),
		Size = UDim2.fromOffset(96, 26), ZIndex = 6 }, wrap)
	local ribbonCorner = corner(ribbon, 10)
	local ribbonStroke = stroke(ribbon, INK, 2.5)
	UI.vgrad(ribbon, CAPTION.idle)
	local cap = make("TextLabel", { BackgroundTransparency = 1, Text = "", Font = FONT,
		TextSize = 15, TextColor3 = Color3.new(1,1,1), Size = UDim2.fromScale(1,1), ZIndex = 7 }, ribbon)
	make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, cap)

	-- 8. the badge: a red candy disc with a white "!" (or the spin count)
	local badge = make("Frame", { Name = "Badge", AnchorPoint = Vector2.new(1,0),
		Position = UDim2.new(1,6,0,-6), Size = UDim2.fromOffset(32,32),
		BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, Visible = false, ZIndex = 10 }, btn)
	corner(badge)
	local badgeStroke = stroke(badge, INK, 3)
	grad(badge, rgb(255,124,120), rgb(220,30,40))
	local bgl = make("Frame", { BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,0),
		Position = UDim2.new(0.5,0,0.08,0), Size = UDim2.fromScale(0.6,0.36), ZIndex = 11 }, badge)
	corner(bgl)
	grad(bgl, Color3.new(1,1,1), Color3.new(1,1,1)).Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	local badgeTxt = make("TextLabel", { BackgroundTransparency = 1, Text = "!", Font = FONT,
		TextColor3 = Color3.new(1,1,1), TextScaled = true, Size = UDim2.fromScale(0.8,0.8),
		AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5), ZIndex = 12 }, badge)
	make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, badgeTxt)

	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	btn.MouseButton1Down:Connect(function() scale.Scale = 0.92 end)

	return { wrap=wrap, pivot=pivot, btn=btn, cap=cap, ribbon=ribbon, badge=badge, badgeTxt=badgeTxt,
	         scale=scale, ring=ring, ringStroke=ringStroke, sparks=sparks, face=face, shadow=shadow, tint=look.face[1],
	         base=base, baseStroke=baseStroke, btnStroke=btnStroke, gloss=gloss, ribbonCorner=ribbonCorner,
	         ribbonStroke=ribbonStroke, badgeStroke=badgeStroke, orbit=SZ*0.62,
	         art=art, artScale=artScale, disc=disc, glow=glow }
end

local gift  = chip("Gift",  1)
local wheel = chip("Wheel", 2)

----------------------------------------------------------------------
-- sticker geometry, per placement
----------------------------------------------------------------------
-- channel: today's sticker, exactly (78px disc in a 104x112 wrap, ribbon hanging below it)
local CHANNEL = {
	D = SZ, w = 104, h = 112, pivotY = 0, thick = 7, baseStroke = 4, btnStroke = 4.5,
	glossInset = 22, glossH = 24, glossY = 6, emoji = 42, shadowY = 3, ringPad = 18, ringStroke = 4,
	spark = 20, sparkBox = 22, orbit = SZ * 0.62,
	ribbonAnchor = Vector2.new(0.5, 0), ribbonPos = UDim2.new(0.5, 0, 0, SZ + 13), ribbonW = 96, ribbonH = 26,
	ribbonR = 10, ribbonStroke = 2.5, cap = 15, badge = 32, badgeOff = 6, badgeStroke = 3,
}
-- a D-px disc in a w x h wrap, everything proportional to the 78px sticker unless `over` says otherwise
local function scaled(D, w, h, pivotY, over)
	local r = D / SZ
	local g = {
		D = D, w = w, h = h, pivotY = pivotY,
		thick = math.max(2, math.floor(D * 0.09 + 0.5)),
		baseStroke = math.max(2, 4 * r), btnStroke = math.max(2, 4.5 * r),
		glossInset = math.floor(22 * r + 0.5), glossH = math.floor(24 * r + 0.5),
		glossY = math.max(2, math.floor(6 * r + 0.5)),
		emoji = math.floor(D * 0.54), shadowY = math.max(1, math.floor(3 * r + 0.5)),
		ringPad = math.floor(18 * r + 0.5), ringStroke = math.max(2, 4 * r),
		spark = math.floor(20 * r + 0.5), sparkBox = math.floor(22 * r + 0.5), orbit = D * 0.62,
		badge = math.floor(D * 0.41), badgeOff = math.max(3, math.floor(6 * r + 0.5)),
		badgeStroke = math.max(1.5, 3 * r),
	}
	for k, v in pairs(over) do g[k] = v end
	return g
end
local function style(c, g)
	local D = g.D
	c.wrap.Size = UDim2.fromOffset(g.w, g.h)
	c.pivot.Size = UDim2.fromOffset(D, D)
	c.pivot.Position = UDim2.new(0.5, 0, 0, g.pivotY)
	c.base.Size = UDim2.fromOffset(D, D)
	c.base.Position = UDim2.fromOffset(0, g.thick)
	c.baseStroke.Thickness = g.baseStroke
	c.btn.Size = UDim2.fromOffset(D, D)
	c.btnStroke.Thickness = g.btnStroke
	c.gloss.Size = UDim2.fromOffset(D - g.glossInset, g.glossH)
	c.gloss.Position = UDim2.new(0.5, 0, 0, g.glossY)
	c.face.TextSize = g.emoji
	c.shadow.TextSize = g.emoji
	c.shadow.Position = UDim2.fromOffset(0, g.shadowY)
	c.ring.Size = UDim2.fromOffset(D + g.ringPad, D + g.ringPad)
	c.ringStroke.Thickness = g.ringStroke
	for _, sp in ipairs(c.sparks) do
		sp.TextSize = g.spark
		sp.Size = UDim2.fromOffset(g.sparkBox, g.sparkBox)
	end
	c.orbit = g.orbit
	c.ribbon.AnchorPoint = g.ribbonAnchor
	c.ribbon.Position = g.ribbonPos
	c.ribbon.Size = UDim2.fromOffset(g.ribbonW, g.ribbonH)
	c.ribbonCorner.CornerRadius = UDim.new(0, g.ribbonR)
	c.ribbonStroke.Thickness = g.ribbonStroke
	c.cap.TextSize = g.cap
	c.badge.Size = UDim2.fromOffset(g.badge, g.badge)
	c.badge.Position = UDim2.new(1, g.badgeOff, 0, -g.badgeOff)
	c.badgeStroke.Thickness = g.badgeStroke
	if c.artScale then c.artScale.Scale = D / SZ end   -- the mini wheel is built at the 78 px sticker's size
end

----------------------------------------------------------------------
-- placement
----------------------------------------------------------------------
local function edgePanel(guiName, frameName)
	local scr = pg:FindFirstChild(guiName)
	if not (scr and scr.Enabled) then return nil end
	local f = scr:FindFirstChild(frameName)
	if f and f.Visible and f.AbsoluteSize.X > 4 then return f end
	return nil
end
local function localRect(o)
	local p = o.AbsolutePosition - gui.AbsolutePosition
	return p.X, p.Y, p.X + o.AbsoluteSize.X, p.Y + o.AbsoluteSize.Y
end

local mode = "channel"
local veilOn = false   -- MainMenu.MenuBar.MenuVeil.Visible: a menu is open and the rails are dimmed

local function relayout()
	local W = gui.AbsoluteSize.X
	if W < 2 then
		local cam = workspace.CurrentCamera
		W = cam and cam.ViewportSize.X or 1280
	end
	local br = pg:FindFirstChild("BaitRoller")
	local mm = pg:FindFirstChild("MainMenu")
	local bar = mm and mm:FindFirstChild("MenuBar")
	local dockPos = bar and bar:GetAttribute("RewardsDockPos")
	local dockSize = bar and bar:GetAttribute("RewardsDockSize")
	local lp = edgePanel("BaitRoller", "Panel")
	if typeof(dockPos) == "Vector2" and typeof(dockSize) == "Vector2" and dockSize.X > 0 and dockSize.Y > 0 then
		mode = "dockRight"
	elseif lp and br:GetAttribute("HudMode") == "tablet" then
		mode = "dockTopLeft"
	else
		mode = "channel"
	end
	gui:SetAttribute("Mode", mode)

	if mode == "dockRight" then
		-- Two equal cells, Gift left and Wheel right. The disc rides the top of its cell and the
		-- ribbon overlaps its lower edge sticker-style, 1px off the cell's bottom.
		local dw, dh = math.floor(dockSize.X + 0.5), math.floor(dockSize.Y + 0.5)
		local cellW = math.floor((dw - 6) / 2)
		local D = math.max(16, math.min(cellW - 6, dh - 8))
		local g = scaled(D, cellW, dh, 1, {
			ringPad = 8, spark = 12, sparkBox = 14, badge = math.floor(D * 0.42), badgeOff = 3,
			ribbonAnchor = Vector2.new(0.5, 1), ribbonPos = UDim2.new(0.5, 0, 1, -1),
			ribbonW = cellW - 4, ribbonH = 13, ribbonR = 5, ribbonStroke = 1.5, cap = 11 })
		holder.Position = UDim2.fromOffset(math.floor(dockPos.X + 0.5), math.floor(dockPos.Y + 0.5))
		holder.Size = UDim2.fromOffset(dw, dh)
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, dw - 2 * cellW)
		style(gift, g)
		style(wheel, g)
		-- the bar is veiled while a menu is open; a sticker drawn over the veil would look live
		holder.Visible = not veilOn
	elseif mode == "dockTopLeft" then
		-- the corner above the bottom-anchored roller: x [8, LR-8], y [TOPBAR+6, panelTop-8]
		local _, pTop, pRight = localRect(lp)
		local x0, y0 = 8, GuiService:GetGuiInset().Y + 6
		local rw = math.max(60, math.floor(pRight - 8 - x0))
		local rh = math.max(44, math.floor(pTop - 8 - y0))
		local half = math.floor(rw / 2)
		local D = math.max(24, math.min(64, rh - 20))
		local pivotY = math.max(0, math.floor((rh - (D + 14)) / 2))
		local g = scaled(D, half, rh, pivotY, {
			badge = math.floor(D * 0.41),
			ribbonAnchor = Vector2.new(0.5, 0), ribbonPos = UDim2.new(0.5, 0, 0, pivotY + D - 6),
			ribbonW = math.min(96, half - 8), ribbonH = 20, ribbonR = 8, ribbonStroke = 2, cap = 14 })
		holder.Position = UDim2.fromOffset(x0, y0)
		holder.Size = UDim2.fromOffset(rw, rh)
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, rw - 2 * half)
		style(gift, g)
		style(wheel, g)
		holder.Visible = true
	else
		-- channel: hug the live left panel, never cross the live right one
		local left = FALLBACK_X
		if lp then
			local _, _, x1 = localRect(lp)
			left = x1 + GUTTER
		end
		local right = W - GUTTER
		local rp = edgePanel("MainMenu", "MenuBar")
		if rp then right = localRect(rp) - GUTTER end
		-- a chip's glow ring overhangs its 78px face, hence the holder's 104 rather than 78
		left = math.min(left, math.max(GUTTER, right - 104))
		holder.Position = UDim2.fromOffset(math.floor(left + 0.5), TOP_Y)
		holder.Size = UDim2.fromOffset(104, 260)
		list.FillDirection = Enum.FillDirection.Vertical
		list.Padding = UDim.new(0, 18)
		style(gift, CHANNEL)
		style(wheel, CHANNEL)
		holder.Visible = true
	end
end

-- Re-layout on the viewport, this gui, the roller panel's rect, the MenuBar's rect and dock
-- attributes, the roller's HudMode, and the MenuBar's veil. The panel and bar are built by other
-- scripts and may not exist yet, so poll ~6s and latch each one's signals as it appears.
local hooked = {}
local function hook(inst, props, attrs)
	if not inst then return false end
	if hooked[inst] then return true end
	hooked[inst] = true
	for _, p in ipairs(props) do inst:GetPropertyChangedSignal(p):Connect(relayout) end
	for _, a in ipairs(attrs or {}) do inst:GetAttributeChangedSignal(a):Connect(relayout) end
	return true
end
local function bindVeil(v)
	if v.Name ~= "MenuVeil" or not v:IsA("GuiObject") or hooked[v] then return end
	hooked[v] = true
	local function sync()
		veilOn = v.Visible
		if mode == "dockRight" then holder.Visible = not veilOn end
	end
	v:GetPropertyChangedSignal("Visible"):Connect(sync)
	sync()
end
local function hookAll()
	local br = pg:FindFirstChild("BaitRoller")
	local mm = pg:FindFirstChild("MainMenu")
	local panel = br and br:FindFirstChild("Panel")
	local bar = mm and mm:FindFirstChild("MenuBar")
	local ok = hook(br, {}, { "HudMode" })
	ok = hook(panel, { "AbsoluteSize", "AbsolutePosition" }) and ok
	if bar and not hooked[bar] then
		hook(bar, { "AbsoluteSize", "AbsolutePosition" }, { "RewardsDockPos", "RewardsDockSize" })
		for _, c in ipairs(bar:GetChildren()) do bindVeil(c) end
		bar.ChildAdded:Connect(bindVeil)
	end
	return ok and bar ~= nil
end
relayout()
hook(gui, { "AbsoluteSize" })
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end
task.spawn(function()
	for _ = 1, 30 do
		local done = hookAll()
		relayout()
		if done then break end
		task.wait(0.2)
	end
end)

local function open(menuName)
	local m = pg:FindFirstChild(menuName)
	if m then m.Enabled = true end
end
local TouchKit = require(game:GetService("ReplicatedStorage"):WaitForChild("TouchKit"))
TouchKit.press(wheel.btn, function() wheel.scale.Scale = 1; open("WheelMenu") end)

----------------------------------------------------------------------
-- badges, driven purely by the attributes the two controllers publish
----------------------------------------------------------------------
local function setReady(c, ready)
	c.ready = ready
	c.ring.Visible = ready
	for _, sp in ipairs(c.sparks) do sp.Visible = ready end
	UI.vgrad(c.ribbon, ready and CAPTION.ready or CAPTION.idle)
	c.cap.TextColor3 = ready and Color3.new(1,1,1) or Color3.new(1,1,1)
	if not ready then
		c.pivot.Rotation = 0
		c.scale.Scale = 1
	end
end

----------------------------------------------------------------------
-- Free Gifts: the sticker for GiftsMenu. GiftsController owns the nine gifts and their playtime clock and
-- publishes GiftReadyIn (whole seconds to the next one, 0 = ready, nil = every gift claimed); this shows it.
----------------------------------------------------------------------
local function syncGift()
	local left = plr:GetAttribute("GiftReadyIn")
	local ready = left == 0
	gift.badge.Visible = ready
	gift.badgeTxt.Text = "!"
	gift.cap.Text = ready and "OPEN!" or (type(left) == "number" and clock(left) or "Gifts")
	-- only on a CHANGE: setReady(false) also snaps the scale back to 1, and GiftReadyIn changes every
	-- second, so calling it each time would cancel the hover grow under the pointer
	if gift.ready ~= ready then setReady(gift, ready) end
end
TouchKit.press(gift.btn, function() gift.scale.Scale = 1; open("GiftsMenu") end)
plr:GetAttributeChangedSignal("GiftReadyIn"):Connect(syncGift)
local function syncWheel()
	local n = plr:GetAttribute("WheelSpins") or 0
	wheel.badge.Visible = n > 0
	wheel.badgeTxt.Text = tostring(n)
	wheel.cap.Text = (n > 0) and "SPIN!" or clock(plr:GetAttribute("WheelNextIn") or 300)
	setReady(wheel, n > 0)
end
plr:GetAttributeChangedSignal("WheelSpins"):Connect(syncWheel)
plr:GetAttributeChangedSignal("WheelNextIn"):Connect(syncWheel)
syncGift(); syncWheel()

-- the countdown tick. Lives here, not in WheelController, because it must keep running
-- with the wheel menu shut; WheelController reads the attribute back rather than ticking.
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 then return end
	acc -= 1
	if (plr:GetAttribute("WheelSpins") or 0) > 0 then return end
	local left = (plr:GetAttribute("WheelNextIn") or 300) - 1
	plr:SetAttribute("WheelNextIn", math.max(0, left))
end)

-- A ready reward should catch the eye: bob, tilt and orbit its sparkles. Idle chips sit
-- perfectly still, so motion in the corner of the eye always means "something to collect".
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	-- the little wheel turns slowly, and spins up when a spin is ready; a ready sticker's halo breathes
	if wheel.disc then wheel.disc.Rotation = (wheel.disc.Rotation + dt * (wheel.ready and 160 or 14)) % 360 end
	for _, c in ipairs({ gift, wheel }) do
		if c.ready and c.glow then c.glow.ImageTransparency = 0.25 * (0.5 + 0.5 * math.sin(t * 3)) end
	end
	for _, c in ipairs({ gift, wheel }) do
		if c.ready then
			local ph = (c == gift) and 0 or 1.1
			c.scale.Scale = 1 + 0.06 * math.abs(math.sin(t*2.4 + ph))
			c.pivot.Rotation = 5 * math.sin(t*2.0 + ph)
			c.ringStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5*math.sin(t*3.4 + ph))
			for i, sp in ipairs(c.sparks) do
				local a = t*1.6 + ph + (i-1) * (math.pi*2/3)
				sp.Position = UDim2.new(0.5, math.cos(a)*c.orbit, 0.5, math.sin(a)*c.orbit)
				sp.TextTransparency = 0.15 + 0.5 * (0.5 + 0.5*math.sin(t*4 + i))
			end
		end
	end
end)

print("[RewardsHUD] online — floating Free Gift + Wheel cluster")
