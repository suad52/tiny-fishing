--[[
	GiftsController — Free Gifts: nine prizes a session for playing, opened from RewardsHUD's 🎁 sticker.

	The +1 Snowball's Gifts popup, ported like DailyController's window (the owner, 2026-10-10: "make it
	to where i can open the menu for the time-based gifts"): the same window shell with a green header,
	nine candy cards five over four - each with its prize and when it unlocks - and one key under them:
	green CLAIM when the next gift is ready, grey with the countdown, gold once every gift is claimed.
	Claimed cards dim with a tick; the next one wears the gold ring. No LEGO studs (this is not a brick
	game): gloss bands and the reef menus' rising bubbles, exactly as DailyController.

	The kit section below is DailyController's (itself the snowball's PlusOneUI, trimmed), COPIED rather
	than shared because every menu here is a self-contained ScreenGui.

	STATE LIVES HERE and is client-side, like every other payout in this place. The clock is this
	session's playtime (it starts again on every join, as the snowball's does); gifts are claimed in order,
	and each one unlocks at its own minute, so a gift left sitting does not hold back the next one's clock.
	Prizes go into the same stores the daily and the wheel pay into. Published for RewardsHUD's sticker:
	    GiftIndex    the next gift, 1..9 (10 = all claimed)
	    GiftReadyIn  whole seconds until it is ready (0 = ready); nil once every gift is claimed

	DevGift BindableEvent (the house pattern): DevGift:Fire() = the next gift is ready now,
	DevGift:Fire(n) = n seconds left, DevGift:Fire("reset") = start this session's gifts over.
]]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- Shared with every other pop-up window: fits it to the screen and, on a small one, centres it
-- in the band below the Roblox top bar.
local MenuFit  = require(ReplicatedStorage:WaitForChild("MenuFit"))

local plr = Players.LocalPlayer
local gui = script.Parent
local rgb = Color3.fromRGB

----------------------------------------------------------------------
-- the kit: +1 Snowball's PlusOneUI, trimmed to this window
----------------------------------------------------------------------
local UI = {}
UI.FONT      = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
UI.FONT_BOLD = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
UI.MEASURE_FONT = Enum.Font.GothamBlack   -- Montserrat Heavy's metrics; GetTextSize needs an Enum.Font
UI.BLACK, UI.WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- the snowball's sticker images (its owner's uploads). A missing one renders as nothing.
UI.ICONS = {
	daily = "rbxassetid://124664336147100",   -- the calendar breaking out of the header
	check = "rbxassetid://79607904170623",    -- a claimed day's tick
	clock = "rbxassetid://87281751322669",    -- in front of the countdown
	glow  = "rbxassetid://91669070851253",    -- the soft white disc behind a card's icon
}
-- keycaps (the streak tiles): hi = top of the face, base = bottom, lip = the band under it
UI.KEY = {
	gold  = { hi = rgb(255, 234, 107), base = rgb(255, 184, 26),  lip = rgb(194, 100, 0) },
	green = { hi = rgb(141, 244, 124), base = rgb(44, 197, 74),   lip = rgb(19, 127, 54) },
	grey  = { hi = rgb(227, 231, 240), base = rgb(163, 171, 192), lip = rgb(94, 102, 128) },
}
UI.HEAD = { rgb(255, 240, 138), rgb(245, 154, 12) }   -- the gold header
-- the window body, opaque ice: white -> pale ice -> ice
UI.SNOW_BODY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 255, 255)), ColorSequenceKeypoint.new(0.45, rgb(236, 247, 255)),
	ColorSequenceKeypoint.new(1, rgb(206, 231, 255)),
})
-- reward cards: the CARD colour is the ITEM, never green / grey / gold (those are states)
UI.CANDY = {
	orange  = { rgb(255, 214, 80),  rgb(255, 104, 0) },
	purple  = { rgb(214, 160, 255), rgb(112, 28, 242) },
	blue    = { rgb(97, 250, 255),  rgb(0, 69, 255) },   -- (the luck card: a green clover vanished on emerald)
	rose    = { rgb(255, 150, 205), rgb(226, 16, 122) },
	cosmic  = { rgb(196, 140, 255), rgb(96, 26, 214), rgb(44, 10, 130) },
}
-- key fills: the KEY colour is the STATE (green = tap it now, grey = not yet)
UI.BRICK = {
	green = { rgb(136, 250, 90),  rgb(70, 230, 18) },
	grey  = { rgb(222, 227, 238), rgb(150, 160, 184) },
	red   = { rgb(255, 120, 120), rgb(222, 18, 34) },
}

local function new(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
function UI.corner(obj, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, obj) end
-- a border outline, pure black by default
function UI.stroke(obj, thickness, color)
	return new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = thickness or 4,
		Color = color or UI.BLACK, LineJoinMode = Enum.LineJoinMode.Round }, obj)
end
-- a vertical gradient from a list of colours, evenly spaced (or a ColorSequence)
function UI.vgrad(obj, colors)
	local seq = colors
	if typeof(colors) == "table" then
		local k = {}
		for i, c in ipairs(colors) do
			table.insert(k, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
		end
		seq = ColorSequence.new(k)
	end
	local g = obj:FindFirstChild("Fill")
	if not (g and g:IsA("UIGradient")) then g = new("UIGradient", { Name = "Fill", Rotation = 90 }, obj) end
	g.Color = seq
	return g
end
function UI.punch(scaleObj, amount, time)
	scaleObj.Scale = amount
	TweenService:Create(scaleObj, TweenInfo.new(time or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- a label in the house face with an outer black outline that scales WITH the letters (a ScaledSize
-- UIStroke: Thickness is a fraction of the font size). opts: size (max px), color, align, drop (px of
-- hard black shadow), outline, outlineColor, weight ("bold"), scaled (default true), + TextLabel props.
local PROPS_SKIP = { size = true, color = true, align = true, drop = true, outline = true, outlineColor = true,
	weight = true, scaled = true, minSize = true }
function UI.label(parent, text, opts)
	opts = opts or {}
	local size = opts.size or 20
	local l = new("TextLabel", {
		Name = opts.Name or "Label", BackgroundTransparency = 1, Text = text or "",
		FontFace = opts.weight == "bold" and UI.FONT_BOLD or UI.FONT, TextColor3 = opts.color or UI.WHITE,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = opts.align == "left" and Enum.TextXAlignment.Left
			or (opts.align == "right" and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center),
	})
	for k, v in pairs(opts) do
		if not PROPS_SKIP[k] then l[k] = v end
	end
	if opts.scaled == false then
		l.TextSize = size
	else
		l.TextScaled = true
		new("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = opts.minSize or math.min(9, size) }, l)
	end
	local s = new("UIStroke", {
		Name = "Outline", Color = opts.outlineColor or UI.BLACK, LineJoinMode = Enum.LineJoinMode.Round,
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize, Thickness = opts.outline or (size >= 30 and 0.1 or 0.13),
	}, l)
	l.Parent = parent
	if opts.drop and opts.drop > 0 then UI.dropShadow(l, opts.drop) end
	return l, s
end

-- a hard black copy of a label a few px lower, behind it; follows its text, visibility and fade
function UI.dropShadow(l, px)
	local d = l:Clone()
	d.Name = l.Name .. "Drop"
	d.TextColor3 = UI.BLACK
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("UIGradient") then c:Destroy() end
		if c:IsA("UIStroke") then c.Color = UI.BLACK end
	end
	d.ZIndex = l.ZIndex - 1   -- siblings: the drop draws under the label
	d.Parent = l.Parent
	local function sync()
		d.Text = d.RichText and (l.Text:gsub("(color%s*=%s*)([\"'])(.-)%2", "%1%2#000000%2")) or l.Text
		d.TextTransparency = l.TextTransparency
		d.Visible = l.Visible
		d.Size = l.Size
		d.Position = l.Position + UDim2.fromOffset(0, px)
		d.AnchorPoint = l.AnchorPoint
		d.Rotation = l.Rotation
		local ls, ds = l:FindFirstChildWhichIsA("UIStroke"), d:FindFirstChildWhichIsA("UIStroke")
		if ls and ds then ds.Transparency = ls.Transparency end
	end
	for _, p in ipairs({ "Text", "TextTransparency", "Visible", "Size", "Position", "AnchorPoint", "Rotation" }) do
		l:GetPropertyChangedSignal(p):Connect(sync)
	end
	l.Destroying:Connect(function() d:Destroy() end)
	sync()
	return d
end

-- width in px of text at a fixed size (house face metrics)
function UI.textWidth(text, size)
	text = tostring(text):gsub("<[^>]->", "")
	return TextService:GetTextSize(text, size, UI.MEASURE_FONT, Vector2.new(4000, 400)).X
end

-- a sticker image by name (flat: this place has no IconModels)
function UI.icon(parent, name, size, opts)
	local img = new("ImageLabel", { Name = "Icon_" .. tostring(name), BackgroundTransparency = 1,
		Image = UI.ICONS[name] or "", ScaleType = Enum.ScaleType.Fit,
		Size = typeof(size) == "UDim2" and size or UDim2.fromOffset(size, size) })
	for k, v in pairs(opts or {}) do img[k] = v end
	img:SetAttribute("Icon", name)
	img.Parent = parent
	return img
end
-- a flat icon's hard drop: a black copy of the image dy px lower at alpha, just under it
function UI.iconDrop(img, dy, alpha)
	dy, alpha = dy or 4, alpha or 0.5
	local d = new("ImageLabel", { Name = img.Name .. "Drop", BackgroundTransparency = 1, ImageColor3 = UI.BLACK })
	local function sync()
		d.Image, d.ScaleType, d.Size, d.AnchorPoint = img.Image, img.ScaleType, img.Size, img.AnchorPoint
		d.Rotation, d.Visible, d.ZIndex = img.Rotation, img.Visible, img.ZIndex - 1
		d.Position = img.Position + UDim2.fromOffset(0, dy)
		d.ImageTransparency = 1 - (1 - img.ImageTransparency) * alpha
	end
	for _, p in ipairs({ "Image", "ScaleType", "Size", "AnchorPoint", "Rotation", "Visible", "ZIndex", "Position", "ImageTransparency" }) do
		img:GetPropertyChangedSignal(p):Connect(sync)
	end
	img.Destroying:Connect(function() d:Destroy() end)
	sync()
	d.Parent = img.Parent
	return d
end

-- a gloss band over the top of a face: white fading to nothing (this game's gloss, where the
-- snowball tiles its LEGO studs). h = the band's share of the face's height.
function UI.gloss(parent, radius, h, z)
	local g = new("Frame", { Name = "Gloss", BackgroundColor3 = UI.WHITE, Size = UDim2.new(1, 0, h or 0.48, 0),
		ZIndex = z or 1 }, parent)
	UI.corner(g, radius or 6)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1) }) }, g)
	-- and the cards' white shine line along the very top, so a flat fill still reads as glossy
	UI.corner(new("Frame", { Name = "Shine", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.5,
		Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 4), ZIndex = g.ZIndex }, parent), 2)
	return g
end
-- a hard drop: a black copy of a box dy px lower WITH the box's outline (without it only dy - stroke px show)
function UI.hardShadow(parent, radius, stroke, dy, z)
	local s = new("Frame", { Name = "Shadow", BackgroundColor3 = UI.BLACK, Position = UDim2.fromOffset(0, dy or 6),
		Size = UDim2.fromScale(1, 1), ZIndex = z or 1 }, parent)
	UI.corner(s, radius or 8)
	if stroke and stroke > 0 then UI.stroke(s, stroke) end
	return s
end

-- the house press feel for a button with a UIScale: hover grows it a touch (not on touch screens,
-- which never send a reliable leave), pressing squashes it, letting go springs it back
local function pressFeel(button, scale)
	local tween
	local function to(s, info)
		if tween then tween:Cancel() end
		tween = TweenService:Create(scale, info or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = s })
		tween:Play()
	end
	local function touching() return UserInputService:GetLastInputType() == Enum.UserInputType.Touch end
	button.MouseEnter:Connect(function() if not touching() then to(1.05) end end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function()
		if tween then tween:Cancel() end
		scale.Scale = 0.92
	end)
	button.MouseButton1Up:Connect(function() to(touching() and 1 or 1.05, TweenInfo.new(0.22, Enum.EasingStyle.Back)) end)
end

-- the keycap block (the streak tiles): a black outline, a darker LIP under a gradient FACE and a white
-- highlight strip along the face's top. Put content into .face.
function UI.block(parent, colour, opts)
	local key = UI.KEY[colour]
	local lip, r = opts.lip or 7, opts.radius or 16
	local root = new("Frame", { Name = opts.Name or "Block", Size = opts.Size, Position = opts.Position,
		BackgroundColor3 = key.lip }, parent)
	UI.corner(root, r)
	UI.stroke(root, opts.outline or 4)
	local face = new("Frame", { Name = "Face", Size = UDim2.new(1, 0, 1, -lip), BackgroundColor3 = UI.WHITE }, root)
	UI.corner(face, r)
	UI.vgrad(face, { key.hi, key.base })
	local h = opts.highlight or {}
	UI.corner(new("Frame", { Name = "Shine", Position = UDim2.fromOffset(h.inset or 12, h.top or 4),
		Size = UDim2.new(1, -2 * (h.inset or 12), 0, h.height or 5), BackgroundColor3 = UI.WHITE,
		BackgroundTransparency = 0.5 }, face), 9)
	return { root = root, face = face, colour = colour }
end
function UI.recolour(block, colour)
	if block.colour == colour then return end
	local key = UI.KEY[colour]
	block.colour = colour
	block.root.BackgroundColor3 = key.lip
	UI.vgrad(block.face, { key.hi, key.base })
end

-- a key label's outline px by its size (the spec's text table): 40 -> 5, 36 / 34 -> 4.5, 30 -> 4, else 3.5
local function keyOutline(size)
	return size >= 40 and 5 or size >= 32 and 4.5 or size >= 30 and 4 or 3.5
end

-- the key: a black outline, a WHITE rim, a bright glossy fill and a hard drop (+6, same
-- 4 px outline). colour = a UI.BRICK key (the STATE). k.set(text, size) = one label;
-- k.setParts({ { text =, size = } | { icon =, size = }, ... }) = a centred line of pieces; a line too
-- wide shrinks its text together (to half at most).
function UI.candyKey(parent, colour, opts)
	local k = { parts = {} }
	k.button = new("TextButton", { Name = opts.Name or "Key", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = opts.Size, Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero, ZIndex = opts.ZIndex or 1 })
	UI.hardShadow(k.button, 6, 4, 6, 1)
	k.rim = new("Frame", { Name = "Rim", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, k.button)
	UI.corner(k.rim, 6)
	UI.stroke(k.rim, 4)
	k.fill = new("Frame", { Name = "Fill", BackgroundColor3 = UI.WHITE, Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6) }, k.rim)
	UI.corner(k.fill, 3)
	UI.gloss(k.fill, 3)
	k.text = new("Frame", { Name = "Text", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, k.button)

	function k.recolour(c)
		k.colour = c
		UI.vgrad(k.fill, UI.BRICK[c] or c)
	end
	function k.setParts(parts, o)
		o = o or {}
		local avail = k.button.Size.X.Offset
		local gap = o.gap or 6
		local fixed, want = 0, 0
		for i, p in ipairs(parts) do
			if i > 1 then fixed += p.gap or gap end
			if p.icon then fixed += p.size or 40 else want += math.ceil(UI.textWidth(p.text or "", p.size or 40)) + 4 end
		end
		local kf = want > 0 and math.clamp((avail - 12 - fixed) / want, 0.5, 1) or 1
		local widths, total = {}, fixed
		for i, p in ipairs(parts) do
			local kind = p.icon and "icon" or "text"
			local slot = k.parts[i]
			if slot and slot.kind ~= kind then slot.obj:Destroy(); slot = nil end   -- (its drop goes with it)
			if kind == "text" then
				local size = p.size or 40
				local s = math.max(math.floor(size * kf), 8)
				local wpx = math.ceil(UI.textWidth(p.text or "", s)) + 4
				if not slot then
					local l = UI.label(k.text, "", { Name = "Label" .. i, size = s, scaled = false, drop = 3, ZIndex = 2,
						Size = UDim2.fromOffset(wpx, math.ceil(s * 1.3)) })
					slot = { kind = kind, obj = l, drop = k.text:FindFirstChild(l.Name .. "Drop") }
				end
				local l = slot.obj
				l.Text = p.text or ""
				l.Size = UDim2.fromOffset(wpx, math.ceil(s * 1.3))
				for _, t in ipairs({ l, slot.drop }) do   -- (UI.dropShadow does not follow TextSize or outline)
					t.TextSize = s
					local st = t:FindFirstChildWhichIsA("UIStroke")
					if st then st.Thickness = keyOutline(size) / size end
				end
				widths[i] = wpx
				total += wpx
			else
				local sz = p.size or 40
				if not slot then
					local img = UI.icon(k.text, p.icon, sz, { Name = "Icon" .. i, ZIndex = 2 })
					slot = { kind = kind, obj = img }
					UI.iconDrop(img, 3, 0.5)
				end
				slot.obj.Image = UI.ICONS[p.icon] or ""
				slot.obj.Size = UDim2.fromOffset(sz, sz)
				widths[i] = sz
			end
			slot.obj.Visible = true
			k.parts[i] = slot
		end
		for j = #parts + 1, #k.parts do k.parts[j].obj.Visible = false end
		-- lay them out, centred
		local x = (avail - total) / 2
		for i, p in ipairs(parts) do
			if i > 1 then x += p.gap or gap end
			local obj = k.parts[i].obj
			obj.AnchorPoint = Vector2.new(0, 0.5)
			obj.Position = UDim2.new(0, math.floor(x + 0.5), 0.5, 0)
			x += widths[i]
		end
	end
	function k.set(str, size) k.setParts({ { text = str, size = size or 40 } }) end

	k.recolour(colour)
	k.scale = new("UIScale", {}, k.button)
	pressFeel(k.button, k.scale)
	k.button.Parent = parent
	return k
end

-- a line of text (the snowball side menu's label()). o: x / y / w / h, align, o (outline px), drop,
-- bold, ZIndex, Name
local function text(parent, str, size, o)
	o = o or {}
	local l = UI.label(parent, str, {
		Name = o.Name or "Text", size = size, align = o.align, drop = o.drop,
		outline = (o.o and o.o > 0) and o.o / size or nil, weight = o.bold and "bold" or nil,
		Size = UDim2.fromOffset(o.w or 100, o.h or math.ceil(size * 1.3)),
		Position = UDim2.fromOffset(o.x or 0, o.y or 0), ZIndex = o.ZIndex or 3,
	})
	return l
end
-- a scaled label's max text size, on it and on its drop
local function setMax(l, n)
	for _, t in ipairs({ l, l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop") }) do
		local c = t and t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then c.MaxTextSize = n end
	end
end

----------------------------------------------------------------------
-- the gifts: nine a session, on the snowball's playtime schedule
----------------------------------------------------------------------
UI.BRICK.gold = { rgb(255, 236, 110), rgb(255, 170, 0) }   -- the key once every gift is claimed
local HEAD_GREEN = { rgb(150, 255, 104), rgb(40, 196, 52) }
local RING = rgb(255, 206, 38)                              -- the next gift's gold band
local DIM = { colour = rgb(8, 10, 30), transparency = 0.74 } -- over a claimed card
local LIME = rgb(160, 255, 90)                              -- READY!

-- at = seconds of this session (the snowball's minutes 3 / 6 / 10 / 15 / 25 / 40 / 60 / 75 / 90). Prizes grow
-- with the wait and are FLAT, as the daily and the wheel are. amount = the card's line; what = the toast's.
local GIFTS = {
	{ at = 180,  icon = "💰", amount = "+$2.5K", what = "$2.5K",          colour = "orange", kind = "cash",  n = 2500 },
	{ at = 360,  icon = "🐛", amount = "+3",     what = "3 Grub",         colour = "purple", kind = "bait",  key = "Grub", n = 3 },
	{ at = 600,  icon = "💰", amount = "+$10K",  what = "$10K",           colour = "orange", kind = "cash",  n = 10000 },
	{ at = 900,  icon = "🍀", amount = "+1",     what = "a Luck Potion",  colour = "blue",   kind = "boost", key = "potion_luck", n = 1 },
	{ at = 1500, icon = "💰", amount = "+$25K",  what = "$25K",           colour = "orange", kind = "cash",  n = 25000 },
	{ at = 2400, icon = "🦪", amount = "+5",     what = "5 Pearls",       colour = "rose",   kind = "pearl", n = 5 },
	{ at = 3600, icon = "🍀", amount = "+2",     what = "2 Luck Potions", colour = "blue",   kind = "boost", key = "potion_luck", n = 2 },
	{ at = 4500, icon = "💰", amount = "+$50K",  what = "$50K",           colour = "orange", kind = "cash",  n = 50000 },
	{ at = 5400, icon = "🌟", amount = "+1",     what = "a Jackpot Cast", colour = "cosmic", kind = "boost", key = "jackpot", n = 1 },
}

-- the same client-side stores the daily and the wheel pay into
local function bump(attr, n) plr:SetAttribute(attr, (plr:GetAttribute(attr) or 0) + n) end
local function addCash(n)
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then m.Value = m.Value + n end
end
local function grantGift(g)
	if g.kind == "cash" then addCash(g.n)
	elseif g.kind == "bait" then bump("Bait_" .. (string.gsub(g.key, "[^%w]", "")), g.n)
	elseif g.kind == "boost" then bump("Inv_" .. g.key, g.n)
	elseif g.kind == "pearl" then bump("Pearls", g.n) end
end

-- 3725 s -> "1h 02m"; 725 -> "12m 05s"; 9 -> "9s"
local function span(sec)
	sec = math.max(0, math.floor(sec or 0))
	local h, m, s = sec // 3600, sec % 3600 // 60, sec % 60
	if h > 0 then return string.format("%dh %02dm", h, m) end
	if m > 0 then return string.format("%dm %02ds", m, s) end
	return string.format("%ds", s)
end

local started = os.clock()   -- this session's playtime clock (DevGift moves it)
local nextGift = 1
local function left()
	local g = GIFTS[nextGift]
	if not g then return nil end
	return math.max(0, g.at - (os.clock() - started))
end
local function publish()
	local l = left()
	plr:SetAttribute("GiftIndex", nextGift)
	plr:SetAttribute("GiftReadyIn", l and math.ceil(l) or nil)
end

----------------------------------------------------------------------
-- the window (DailyController's shell, 600 wide, green)
----------------------------------------------------------------------
local W, KEY_Y = 600, 452
-- desk is the snowball's Gifts popup; phone its phone look (an 88-tall key and X: 44 real px at the 0.5
-- floor, the cards 12 px lower and the sub line 4 px higher so the top row clears it, a 24 px When line)
-- icon = the 🎁 { x, y, size }: on a phone it is tucked INSIDE the header, left of the title at x 112, so nothing
-- reaches above the window and it can be centred on the screen (see fit)
local LOOK = {
	desk  = { h = 540, close = { 60, 34 }, subY = 126, cardDY = 0,  whenMax = 22, keyH = 66, icon = { -36, -44, 124 } },
	phone = { h = 562, close = { 88, 44 }, subY = 122, cardDY = 12, whenMax = 24, keyH = 88, icon = { 10, 4, 66 } },
}

local backdrop = new("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.4, AutoButtonColor = false, Text = "", ZIndex = 0 }, gui)
local root = new("Frame", { Name = "Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, LOOK.desk.h),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 1 }, gui)
local uiscale = new("UIScale", { Scale = 1 }, root)
local shadow = new("Frame", { Name = "Shadow", BackgroundColor3 = UI.BLACK, Position = UDim2.fromOffset(0, 9),
	Size = UDim2.fromScale(1, 1), ZIndex = 1, Active = true }, root)
UI.corner(shadow, 16)
UI.stroke(shadow, 5)
local body = new("Frame", { Name = "Body", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2,
	Active = true }, root)
UI.corner(body, 16)
UI.stroke(body, 5)
UI.vgrad(body, UI.SNOW_BODY)
-- the reef menus' rising bubbles, faint on the pale body; they drift only while open and Menu FX is on
local bubbleBox = new("Frame", { Name = "Bubbles", BackgroundTransparency = 1, ClipsDescendants = true,
	Position = UDim2.fromOffset(6, 76), Size = UDim2.new(1, -12, 1, -82), ZIndex = 1 }, body)
local bubbles = {}
for i = 1, 16 do
	local s = math.random(8, 24)
	local b = new("Frame", { Name = "Bubble", BackgroundColor3 = rgb(150, 205, 245), BackgroundTransparency = 0.8,
		Size = UDim2.fromOffset(s, s), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.random(), math.random()), ZIndex = 1 }, bubbleBox)
	UI.corner(b, 999)
	UI.stroke(b, 1.5, rgb(110, 180, 235)).Transparency = 0.35
	bubbles[i] = { f = b, sp = math.random(4, 10) / 100 }
end
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled or plr:GetAttribute("Set_MenuFX") == false then return end
	for _, bd in ipairs(bubbles) do
		local ny = bd.f.Position.Y.Scale - bd.sp * dt
		bd.f.Position = ny < -0.06 and UDim2.fromScale(math.random(), 1.06) or UDim2.fromScale(bd.f.Position.X.Scale, ny)
	end
end)
local header = new("Frame", { Name = "Header", BackgroundColor3 = UI.WHITE, Size = UDim2.new(1, 0, 0, 74), ZIndex = 3 }, body)
UI.corner(header, 16)
UI.vgrad(header, ColorSequence.new({ ColorSequenceKeypoint.new(0, HEAD_GREEN[1]), ColorSequenceKeypoint.new(0.7, HEAD_GREEN[2]),
	ColorSequenceKeypoint.new(1, HEAD_GREEN[2]) }))
new("Frame", { Name = "Square", BackgroundColor3 = HEAD_GREEN[2], Position = UDim2.new(0, 0, 1, -18),
	Size = UDim2.new(1, 0, 0, 18), ZIndex = 3 }, header)
UI.gloss(header, 16, 0.5, 4)
new("Frame", { Name = "Rule", BackgroundColor3 = UI.BLACK, Position = UDim2.new(0, 0, 0, 72),
	Size = UDim2.new(1, 0, 0, 4), ZIndex = 5 }, body)
text(root, "FREE GIFTS", 46, { Name = "Title", align = "left", o = 5, drop = 4, x = 112, w = W - 168, h = 74, ZIndex = 8 })
-- the big icon breaking out of the top-left corner: the sticker's own 🎁 (this game draws icons as emoji)
local giftIcon = new("TextLabel", { Name = "Icon_gift", BackgroundTransparency = 1, Text = "🎁", TextScaled = true,
	FontFace = UI.FONT, TextColor3 = UI.WHITE, Position = UDim2.fromOffset(-36, -44), Size = UDim2.fromOffset(124, 124),
	Rotation = -8, ZIndex = 9, Active = true }, root)
local close = UI.candyKey(root, "red", { Name = "Close", Size = UDim2.fromOffset(60, 60),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -12, 0, 12), ZIndex = 10 })
close.set("X", 34)
-- only a GuiButton on top sinks a click (an Active frame does not stop the Backdrop under it), so the window
-- carries handler-less ClickGuards over the body + drop and over the icon, as DailyController does
local function clickGuard(parent, size, z)
	return new("TextButton", { Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Selectable = false, Size = size, ZIndex = z }, parent)
end
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, 9), 3), 16)
clickGuard(giftIcon, UDim2.new(1, 0, 1, 5), 20)

local head = text(root, "", 30, { Name = "Head", x = 18, y = 84, w = W - 36, h = 40, o = 4, drop = 3, ZIndex = 7 })
local sub = text(root, "", 20, { Name = "Sub", x = 18, y = 126, w = W - 36, h = 26, o = 3, drop = 2, bold = true, ZIndex = 7 })

-- one candy card per gift, five over four, each row centred (the snowball's 103 x 128 cards, 12 apart):
-- the prize's emoji on a glow, its amount (26 px) and when it unlocks (22 px)
local CW, CH, GAP = 103, 128, 12
local perTop = math.ceil(#GIFTS / 2)
local cards = {}
for i, g in ipairs(GIFTS) do
	local top = i <= perTop
	local inRow = top and perTop or #GIFTS - perTop
	local x = 18 + math.floor((564 - (inRow * CW + (inRow - 1) * GAP)) / 2) + ((top and i or i - perTop) - 1) * (CW + GAP)
	local c = { deskY = top and 160 or 160 + CH + 16 }
	c.root = new("Frame", { Name = "Gift" .. i, BackgroundTransparency = 1, Size = UDim2.fromOffset(CW, CH),
		Position = UDim2.fromOffset(x, c.deskY), ZIndex = 6 }, root)
	c.scale = new("UIScale", {}, c.root)
	UI.hardShadow(c.root, 8, 4, 6, 1)
	c.face = new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, c.root)
	UI.corner(c.face, 8)
	UI.stroke(c.face, 4)
	UI.vgrad(c.face, UI.CANDY[g.colour])
	UI.corner(new("Frame", { Name = "Shine", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.65,
		Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 4) }, c.face), 2)
	c.dim = new("Frame", { Name = "Dim", BackgroundColor3 = DIM.colour, BackgroundTransparency = DIM.transparency,
		Size = UDim2.fromScale(1, 1), ZIndex = 3, Visible = false }, c.root)
	UI.corner(c.dim, 8)
	new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow, ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CW / 2, 34), Size = UDim2.fromOffset(66, 66),
		ImageTransparency = 0.15, ZIndex = 4 }, c.root)
	c.icon = new("TextLabel", { Name = "Icon", BackgroundTransparency = 1, Text = g.icon, TextScaled = true,
		FontFace = UI.FONT, TextColor3 = UI.WHITE, Position = UDim2.fromOffset(math.floor((CW - 56) / 2), 6),
		Size = UDim2.fromOffset(56, 56), Rotation = -6, ZIndex = 6 }, c.root)
	local l1 = new("Frame", { Name = "L1", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 30), ZIndex = 7 }, c.root)
	local l2 = new("Frame", { Name = "L2", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 26), ZIndex = 7 }, c.root)
	c.amount = text(l1, g.amount, 26, { Name = "Amount", x = 4, w = CW - 8, h = 30, o = 4, drop = 2 })
	c.when = text(l2, "", 22, { Name = "When", x = 4, w = CW - 8, h = 26, o = 3, drop = 2, bold = true })
	c.tick = UI.icon(c.root, "check", 40, { Name = "Tick", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CW - 12, 12), Rotation = 8, ZIndex = 9, Visible = false })
	c.ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8), ZIndex = 9, Visible = false }, c.root)
	UI.corner(c.ring, 4)
	UI.stroke(c.ring, 4, RING)
	cards[i] = c
end

-- the key, full width under the cards
local claim = UI.candyKey(root, "grey", { Name = "Claim", Size = UDim2.fromOffset(564, 66),
	Position = UDim2.fromOffset(18, KEY_Y), ZIndex = 7 })

-- the toast: a glossy strip that pops over the key (green = got it, red = not yet)
local toast = new("Frame", { Name = "Toast", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(460, 58), Visible = false, ZIndex = 12 }, root)
local toastScale = new("UIScale", {}, toast)
UI.hardShadow(toast, 6, 4, 6, 1)
local toastRim = new("Frame", { Name = "Rim", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, toast)
UI.corner(toastRim, 6)
UI.stroke(toastRim, 4)
local toastFill = new("Frame", { Name = "Fill", BackgroundColor3 = UI.WHITE, Position = UDim2.fromOffset(3, 3),
	Size = UDim2.new(1, -6, 1, -6) }, toastRim)
UI.corner(toastFill, 3)
UI.gloss(toastFill, 3)
local toastText = text(toast, "", 28, { Name = "Text", x = 10, y = 4, w = 440, h = 44, o = 3.5, drop = 2, ZIndex = 3 })
local toastToken = 0
local function showToast(str, good)
	toastToken += 1
	local my = toastToken
	toastText.Text = str
	UI.vgrad(toastFill, UI.BRICK[good and "green" or "red"])
	toast.Visible = true
	UI.punch(toastScale, 0.6, 0.28)
	task.delay(2, function()
		if my ~= toastToken then return end
		local tw = TweenService:Create(toastScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tw:Play()
		tw.Completed:Wait()
		if my == toastToken then toast.Visible = false end
	end)
end

----------------------------------------------------------------------
-- layout (desk / phone) and fit
----------------------------------------------------------------------
local mode
local function place(m)
	if mode == m then return end
	mode = m
	local L = LOOK[m]
	close.button.Size = UDim2.fromOffset(L.close[1], L.close[1])
	close.set("X", L.close[2])
	giftIcon.Position = UDim2.fromOffset(L.icon[1], L.icon[2])
	giftIcon.Size = UDim2.fromOffset(L.icon[3], L.icon[3])
	sub.Position = UDim2.fromOffset(18, L.subY)
	for _, c in ipairs(cards) do
		c.root.Position = UDim2.fromOffset(c.root.Position.X.Offset, c.deskY + L.cardDY)
		setMax(c.when, L.whenMax)
	end
	claim.button.Size = UDim2.fromOffset(564, L.keyH)
	toast.Position = UDim2.fromOffset(W / 2, KEY_Y + L.keyH / 2)
end

local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1366, 768)
	local phone = vp.X >= 100 and vp.Y >= 100 and math.min(vp.X, vp.Y) < 500
	place(phone and "phone" or "desk")
	local h = LOOK[mode].h
	local s = MenuFit.apply(root, uiscale, W, h, 0.4, 1, h)
	-- CENTRED ON A PHONE (2026-10-11, the owner: "make the button uis centered to the phone screen"), as in
	-- DailyController: the 🎁 sits inside the header on a phone instead of nudging the window 52 px right.
	if phone and type(s) == "number" and s > 0 then MenuFit.centre(root, uiscale, 0, 9) end
end

----------------------------------------------------------------------
-- render, claim
----------------------------------------------------------------------
local keyShown
local function render()
	local done = nextGift > #GIFTS
	local l = left()
	local ready = not done and l <= 0
	head.Text = done and "You've claimed every gift!" or (ready and "Your gift is ready!" or "Free gifts for playing!")
	sub.Text = done and "More gifts next time you play" or "The longer you play, the bigger they get"
	for i, c in ipairs(cards) do
		local g = GIFTS[i]
		local claimed, now = i < nextGift, i == nextGift
		c.dim.Visible, c.tick.Visible, c.ring.Visible = claimed, claimed, now
		c.icon.TextTransparency = claimed and 0.45 or 0
		if claimed then
			-- "CLAIMED" cannot reach 24 px in a 95 px line on a phone; the tick says it too
			c.when.Text, c.when.TextColor3 = mode == "phone" and "DONE" or "CLAIMED", UI.WHITE
		elseif now then
			c.when.Text = l <= 0 and "READY!" or span(l)
			c.when.TextColor3 = l <= 0 and LIME or UI.WHITE
		else
			c.when.Text, c.when.TextColor3 = string.format("%d MIN", math.floor(g.at / 60 + 0.5)), UI.WHITE
		end
	end
	local state = done and "done" or (ready and "ready" or span(l))
	if state ~= keyShown then   -- (re-laid only when it changes: this runs every second while open)
		keyShown = state
		if done then
			claim.recolour("gold")
			claim.setParts({ { icon = "check", size = 40 }, { text = "ALL CLAIMED", size = 34, gap = 10 } })
		elseif ready then
			claim.recolour("green")
			claim.set("CLAIM", 36)
		else
			claim.recolour("grey")
			claim.setParts({ { icon = "clock", size = 42 }, { text = state, size = 36, gap = 12 } })
		end
	end
end

local function claimNext()
	local g = GIFTS[nextGift]
	if not g then showToast("Every gift is claimed!", true); return end
	local l = left()
	if l > 0 then showToast("Next gift in " .. span(l), false); return end
	grantGift(g)
	local card = cards[nextGift]
	nextGift += 1
	publish()
	render()
	UI.punch(card.scale, 1.15, 0.36)
	showToast("🎁 You got " .. g.what .. "!", true)
end
TouchKit.press(claim.button, claimNext)

local function closeMenu() gui.Enabled = false end
TouchKit.press(close.button, closeMenu)
TouchKit.press(backdrop, closeMenu)

-- the clock: publish for the sticker every second, and keep the open window's countdowns live
task.spawn(function()
	while true do
		publish()
		if gui.Enabled then render() end
		task.wait(1)
	end
end)

----------------------------------------------------------------------
-- open / close, hotbar hiding - same as the other full-screen menus
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
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		fit(); render(); setInventoryHidden(true)
		local target = uiscale.Scale
		uiscale.Scale = target * 0.6
		TweenService:Create(uiscale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	else
		setInventoryHidden(false)
	end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit() end end)
end

fit()
render()
publish()

local dev = gui:FindFirstChild("DevGift") or new("BindableEvent", { Name = "DevGift" }, gui)
dev.Event:Connect(function(n)
	if n == "reset" then
		nextGift, started = 1, os.clock()
	else
		local g = GIFTS[nextGift]
		if g then started = os.clock() - (g.at - math.max(0, tonumber(n) or 0)) end
	end
	publish()
	render()
end)

print("[Gifts] built — " .. #GIFTS .. " playtime gifts, the last at " .. math.floor(GIFTS[#GIFTS].at / 60) .. " min")
