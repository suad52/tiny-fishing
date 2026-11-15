--[[
	DailyController — Daily Rewards.

	THE LOOK IS THE +1 SNOWBALL'S DAILY REWARD POPUP, ported on purpose (the owner's call,
	2026-10-10: "it looks nicer"). It is deliberately NOT the reef style the other menus share:
	an opaque ice body, a glossy gold header with the calendar sticker breaking out of its
	top-left corner, a red X, then the 7-day streak strip, the reward on a candy panel and ONE
	full-width key - green CLAIM, or grey with the countdown to the next gift. The kit below is
	that game's ReplicatedStorage.PlusOneUI (and PlusOneText's Montserrat Heavy) trimmed to what
	this window draws; every size is its design px. The sticker images are the snowball's own
	uploads (UI.ICONS).
	Two changes from the original:
	  * NO LEGO STUDS. The snowball tiles a stud texture over its body, header, keys and toasts;
	    this is not a brick game (the owner, same day), so the header, keys and toast take a
	    gloss band instead and the body carries the reef menus' faint rising bubbles.
	  * The snowball's rewards are images, and this game draws every icon as an emoji, so the
	    cards and the strip show the reward's emoji instead.
	The pre-port script is kept in ServerStorage.DailyController_PreCandy_2026-10-10.

	HOW IT IS REACHED: it isn't - there is NO button for it anywhere (the owner, 2026-10-10). The
	gift offers itself: the first time in a session DailyServer says a claim is open (on joining,
	or when UTC midnight passes mid-session) this window opens on its own, after the tutorial and
	never over another menu, and once claimed it closes itself and stays away until the next UTC
	day. Shut without claiming, it is offered again on the next join (the claim stays open all
	day). The HUD sticker that used to open it is RewardsHUD's Free Gift now.

	DIVISION OF LABOUR: DailyServer owns the clock and the streak (UTC day, persisted).
	This script owns the PAYLOAD — it applies the reward into the same client-side stores
	every other menu uses:
	    cash   -> leaderstats.Money   (CurrencyClient's shared balance)
	    bait   -> Bait_<akey(name)>   (shared with RollerController / InventoryController)
	    boost  -> Inv_<key>           (shared with ShopController / InventoryController)
	    pearls -> Pearls              (RebirthController's currency)
	REWARDS below must stay in step with DailyServer's CYCLE (7).

	DevDaily BindableEvent, same convention as DevRoll / DevZone / DevCast / DevUpgrade:
	    DevDaily:Fire(3)   -> preview + grant day 3 locally (does not touch the server clock)
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
-- the cycle
----------------------------------------------------------------------
-- cards = what that day's claim pays, one candy panel each: { emoji, amount, word, UI.CANDY colour }
local REWARDS = {
	{ icon = "💰", short = "$2.5K",    kind = "cash",  amount = 2500,
		cards = { { "💰", "+$2.5K", "CASH", "orange" } } },
	{ icon = "🐛", short = "3x Grub",  kind = "bait",  key = "Grub", amount = 3,
		cards = { { "🐛", "+3", "GRUB BAIT", "purple" } } },
	{ icon = "💰", short = "$15K",     kind = "cash",  amount = 15000,
		cards = { { "💰", "+$15K", "CASH", "orange" } } },
	{ icon = "🍀", short = "2x Luck",  kind = "boost", key = "potion_luck", amount = 2,
		cards = { { "🍀", "+2", "LUCK POTIONS", "blue" } } },
	{ icon = "💰", short = "$75K",     kind = "cash",  amount = 75000,
		cards = { { "💰", "+$75K", "CASH", "orange" } } },
	{ icon = "🦪", short = "5 Pearls", kind = "pearl", amount = 5,
		cards = { { "🦪", "+5", "PEARLS", "rose" } } },
	{ icon = "🌟", short = "$400K + Jackpot", kind = "mega",
		cards = { { "💰", "+$400K", "CASH", "orange" }, { "🌟", "+1", "JACKPOT CAST", "cosmic" } } },
}

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIX[tier + 1])
end
local function akey(s) return (string.gsub(s, "[^%w]", "")) end
local function bump(attr, n) plr:SetAttribute(attr, (plr:GetAttribute(attr) or 0) + n) end
local function addCash(n)
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then m.Value = m.Value + n; return true end
	return false
end
local function grant(day)
	local r = REWARDS[day]; if not r then return "" end
	if r.kind == "cash" then
		addCash(r.amount);                                   return "+$" .. abbrev(r.amount)
	elseif r.kind == "bait" then
		bump("Bait_" .. akey(r.key), r.amount);               return "+" .. r.amount .. "x " .. r.key
	elseif r.kind == "boost" then
		bump("Inv_" .. r.key, r.amount);                      return "+" .. r.amount .. " Luck Potion"
	elseif r.kind == "pearl" then
		bump("Pearls", r.amount);                             return "+" .. r.amount .. " Pearls"
	elseif r.kind == "mega" then
		addCash(400000); bump("Inv_jackpot", 1);              return "+$400K & a Jackpot Cast"
	end
	return ""
end

-- 18720 s -> "5h 12m"; 725 -> "12m 05s"; 9 -> "9s"
local function span(sec)
	sec = math.max(0, math.floor(sec or 0))
	local h, m, s = sec // 3600, sec % 3600 // 60, sec % 60
	if h > 0 then return string.format("%dh %dm", h, m) end
	if m > 0 then return string.format("%dm %02ds", m, s) end
	return string.format("%ds", s)
end
-- DailyServer's day boundary is UTC midnight (floor(os.time() / 86400)), so the wait is this
local function secsToReset() return 86400 - (workspace:GetServerTimeNow() % 86400) end

----------------------------------------------------------------------
-- the window (the snowball's genreWindow, body = "snow", 560 wide)
----------------------------------------------------------------------
local W = 560
-- desk repeats the snowball's Daily-with-streak layout; phone is its phone look (shorter cards, 88-tall
-- key and X: 44 real px at the 0.5 floor). Per look: h (the window), close = { size, text }, subH / subMax
-- (the sub line), card = { y, h, icon size, icon y, glow }, lines = the card's two text lines { y, h },
-- keyY / keyH, tiles (labels across the whole tile), icon = the calendar { x, y, size } (on a phone it is tucked
-- INSIDE the header, left of the title at x 112, so nothing reaches above the window and it can be centred).
local LOOK = {
	desk  = { h = 522, close = { 60, 34 }, subH = 26, subMax = 20, tiles = false, icon = { -36, -44, 124 },
		card = { 236, 176, 88, 8, 104 }, lines = { { 102, 42 }, { 146, 24 } }, keyY = 434, keyH = 66 },
	phone = { h = 508, close = { 88, 44 }, subH = 30, subMax = 24, tiles = true, icon = { 10, 4, 66 },
		card = { 232, 150, 70, 6, 82 }, lines = { { 80, 40 }, { 120, 26 } }, keyY = 398, keyH = 88 },
}

local backdrop = new("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.4, AutoButtonColor = false, Text = "", ZIndex = 0 }, gui)
local root = new("Frame", { Name = "Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, LOOK.desk.h),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 1 }, gui)
local uiscale = new("UIScale", { Scale = 1 }, root)
local shadow = new("Frame", { Name = "Shadow", BackgroundColor3 = UI.BLACK, Position = UDim2.fromOffset(0, 9),
	Size = UDim2.fromScale(1, 1), ZIndex = 1, Active = true }, root)
UI.corner(shadow, 16)
UI.stroke(shadow, 5)   -- (the drop carries the outline, so all 9 px of it show)
local body = new("Frame", { Name = "Body", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2,
	Active = true }, root)
UI.corner(body, 16)
UI.stroke(body, 5)
UI.vgrad(body, UI.SNOW_BODY)
-- the reef menus' rising bubbles, faint on the pale body (where the snowball lays its stud baseplate).
-- Clipped to the body under the header; they drift only while the window is open and Menu FX is on.
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
-- the header bar: rounded on top, square where it meets the body, then a black rule
local header = new("Frame", { Name = "Header", BackgroundColor3 = UI.WHITE, Size = UDim2.new(1, 0, 0, 74), ZIndex = 3 }, body)
UI.corner(header, 16)
UI.vgrad(header, ColorSequence.new({ ColorSequenceKeypoint.new(0, UI.HEAD[1]), ColorSequenceKeypoint.new(0.7, UI.HEAD[2]),
	ColorSequenceKeypoint.new(1, UI.HEAD[2]) }))
new("Frame", { Name = "Square", BackgroundColor3 = UI.HEAD[2], Position = UDim2.new(0, 0, 1, -18),
	Size = UDim2.new(1, 0, 0, 18), ZIndex = 3 }, header)
UI.gloss(header, 16, 0.5, 4)
new("Frame", { Name = "Rule", BackgroundColor3 = UI.BLACK, Position = UDim2.new(0, 0, 0, 72),
	Size = UDim2.new(1, 0, 0, 4), ZIndex = 5 }, body)
text(root, "DAILY REWARDS", 46, { Name = "Title", align = "left", o = 5, drop = 4, x = 112, w = W - 168, h = 74, ZIndex = 8 })
local calendar = UI.icon(root, "daily", 124, { Position = UDim2.fromOffset(-36, -44), Rotation = -8, ZIndex = 9, Active = true })
UI.iconDrop(calendar, 5, 0.6)
local close = UI.candyKey(root, "red", { Name = "Close", Size = UDim2.fromOffset(60, 60),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -12, 0, 12), ZIndex = 10 })
close.set("X", 34)

-- An Active frame does NOT stop the Backdrop button under it from firing (measured on the snowball,
-- where a click on the body still closed the popup) - only a GuiButton on top sinks a click. So the
-- window carries transparent ClickGuards with no handler: over the body and its 9 px drop (ZIndex 3,
-- under everything live) and over the calendar breaking out of the corner.
local function clickGuard(parent, size, z)
	return new("TextButton", { Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Selectable = false, Size = size, ZIndex = z }, parent)
end
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, 9), 3), 16)
clickGuard(calendar, UDim2.new(1, 0, 1, 5), 20)

-- the two lines under the header: the head (30 px) and the sub line (20 px ExtraBold)
local head = text(root, "", 30, { Name = "Head", x = 18, y = 84, w = W - 36, h = 40, o = 4, drop = 3, ZIndex = 7 })
local sub = text(root, "", 20, { Name = "Sub", x = 18, y = 126, w = W - 36, h = 26, o = 3, drop = 2, bold = true, ZIndex = 7 })

-- the 7-day streak strip: the days of this streak already claimed green with a tick, the next claim's
-- day gold (today's while it is ready, tomorrow's once claimed), the rest grey with their reward
local strip = new("Frame", { Name = "Streak", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 160),
	Size = UDim2.fromOffset(524, 60), ZIndex = 6 }, root)
local tiles = {}
for i = 1, #REWARDS do
	local b = UI.block(strip, "grey", { Name = "Day" .. i, Size = UDim2.fromOffset(70, 60),
		Position = UDim2.fromOffset(math.floor((i - 1) * (524 - 70) / 6), 0),
		lip = 5, radius = 10, outline = 3, highlight = { top = 3, inset = 8, height = 3 } })
	b.scale = new("UIScale", {}, b.root)
	b.day = text(b.face, "DAY " .. i, 20, { Name = "Day", x = 2, y = 3, w = 66, h = 22, o = 3, drop = 2, bold = true })
	b.icon = new("TextLabel", { Name = "Reward", BackgroundTransparency = 1, Text = REWARDS[i].icon, TextScaled = true,
		FontFace = UI.FONT, TextColor3 = UI.WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(35, 38),
		Size = UDim2.fromOffset(26, 26), ZIndex = 4 }, b.face)
	b.tick = UI.icon(b.face, "check", 26, { Name = "Tick", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(35, 38), ZIndex = 4, Visible = false })
	tiles[i] = b
end

-- a reward card (the snowball's POP.card): a candy panel in the reward's colour - black outline, hard
-- drop (+6, same outline), a white shine line - its icon centred at the top on a soft white glow, the
-- amount (40 px) and its word (22 px) under it. Two of them; a one-reward day uses only the first.
local cards = {}
for i = 1, 2 do
	local c = {}
	c.root = new("Frame", { Name = "Card" .. i, BackgroundTransparency = 1, Size = UDim2.fromOffset(250, 176),
		Position = UDim2.fromOffset(i == 1 and 18 or 292, 236), ZIndex = 6 }, root)
	c.scale = new("UIScale", {}, c.root)
	UI.hardShadow(c.root, 8, 4, 6, 1)
	c.face = new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, c.root)
	UI.corner(c.face, 8)
	UI.stroke(c.face, 4)
	UI.corner(new("Frame", { Name = "Shine", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.65,
		Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 4) }, c.face), 2)
	c.glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow,
		ScaleType = Enum.ScaleType.Stretch, AnchorPoint = Vector2.new(0.5, 0.5), ImageTransparency = 0.15, ZIndex = 4 }, c.root)
	c.icon = new("TextLabel", { Name = "Icon", BackgroundTransparency = 1, Text = "", TextScaled = true,
		FontFace = UI.FONT, TextColor3 = UI.WHITE, Rotation = -6, ZIndex = 6 }, c.root)
	c.l1 = new("Frame", { Name = "L1", BackgroundTransparency = 1, ZIndex = 7 }, c.root)
	c.l2 = new("Frame", { Name = "L2", BackgroundTransparency = 1, ZIndex = 7 }, c.root)
	c.amount = text(c.l1, "", 40, { Name = "Amount", x = 8, w = 234, h = 42, o = 5, drop = 3 })
	c.word = text(c.l2, "", 22, { Name = "Word", x = 8, w = 234, h = 24, o = 3, drop = 2 })
	cards[i] = c
end

-- the key, full width under the cards: green CLAIM when the gift is ready, grey with a clock and the
-- countdown while it isn't
local claim = UI.candyKey(root, "grey", { Name = "Claim", Size = UDim2.fromOffset(524, 66),
	Position = UDim2.fromOffset(18, 434), ZIndex = 7 })

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
	calendar.Position = UDim2.fromOffset(L.icon[1], L.icon[2])   -- (its drop re-syncs itself)
	calendar.Size = UDim2.fromOffset(L.icon[3], L.icon[3])
	sub.Size = UDim2.fromOffset(W - 36, L.subH)
	setMax(sub, L.subMax)
	for _, b in ipairs(tiles) do   -- (on a phone "DAY n" and its reward span the whole 70 px tile)
		b.day.Position = UDim2.fromOffset(L.tiles and 0 or 2, L.tiles and 1 or 3)
		b.day.Size = UDim2.fromOffset(L.tiles and 70 or 66, L.tiles and 26 or 22)
		b.icon.Position = UDim2.fromOffset(35, L.tiles and 40 or 38)
		b.icon.Size = UDim2.fromOffset(L.tiles and 28 or 26, L.tiles and 28 or 26)
	end
	local y, h, isz, iy, glow = table.unpack(L.card)
	for _, c in ipairs(cards) do
		c.root.Size = UDim2.fromOffset(250, h)
		c.root.Position = UDim2.fromOffset(c.root.Position.X.Offset, y)
		local ix = math.floor((250 - isz) / 2)
		c.icon.Size, c.icon.Position = UDim2.fromOffset(isz, isz), UDim2.fromOffset(ix, iy)
		c.glow.Size, c.glow.Position = UDim2.fromOffset(glow, glow), UDim2.fromOffset(ix + isz / 2, iy + isz / 2)
		c.l1.Position, c.l1.Size = UDim2.fromOffset(0, L.lines[1][1]), UDim2.new(1, 0, 0, L.lines[1][2])
		c.l2.Position, c.l2.Size = UDim2.fromOffset(0, L.lines[2][1]), UDim2.new(1, 0, 0, L.lines[2][2])
		c.amount.Size = UDim2.fromOffset(234, L.lines[1][2])
		c.word.Size = UDim2.fromOffset(234, L.lines[2][2])
	end
	claim.button.Size = UDim2.fromOffset(524, L.keyH)
	claim.button.Position = UDim2.fromOffset(18, L.keyY)
	toast.Position = UDim2.fromOffset(W / 2, L.keyY + L.keyH / 2)
end

local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1366, 768)
	-- re-decided on every fit (open + every viewport change), never once at build time
	local phone = vp.X >= 100 and vp.Y >= 100 and math.min(vp.X, vp.Y) < 500
	place(phone and "phone" or "desk")
	local h = LOOK[mode].h
	-- maxS 1: the snowball draws this popup at up to 1:1, not the reef windows' 1.1
	local s = MenuFit.apply(root, uiscale, W, h, 0.4, 1, h)
	-- CENTRED ON A PHONE (2026-10-11, the owner: "make the button uis centered to the phone screen"). This used to
	-- slide the window RIGHT until the calendar cleared Roblox's top-bar buttons - 60 px off-centre on an iPhone 6
	-- Plus. On a phone the calendar now sits inside the header (LOOK.phone.icon), nothing reaches above the window,
	-- and MenuFit.centre centres it like every other menu (up 0, the 9 px drop below). Desktop is untouched.
	if phone and type(s) == "number" and s > 0 then MenuFit.centre(root, uiscale, 0, 9) end
end

----------------------------------------------------------------------
-- state, driven entirely by DailyServer
----------------------------------------------------------------------
local canClaim, nextDay, lastClaimed, total = false, 1, 0, 0
local synced = false   -- nothing from the server yet
local busy = false

-- the sub line takes its short form on a phone when the full one would not fit at full size
local function subLine(full, short)
	if mode == "phone" and short and UI.textWidth(full, LOOK.phone.subMax) > W - 40 then full = short end
	sub.Text = full
end

local keyShown
local function renderKey()
	local want = not synced and "..." or (canClaim and "CLAIM" or span(secsToReset()))
	if want == keyShown then return end   -- (re-laid only when it changes: this runs every second)
	keyShown = want
	if synced and canClaim then
		claim.recolour("green")
		claim.set("CLAIM", 36)
	elseif synced then
		claim.recolour("grey")
		claim.setParts({ { icon = "clock", size = 42 }, { text = want, size = 36, gap = 12 } })
	else
		claim.recolour("grey")
		claim.set(want, 36)
	end
end

local function render()
	renderKey()
	local day = math.clamp(nextDay, 1, #REWARDS)
	if not synced then
		head.Text = "Checking your calendar..."
		sub.Text = ""
	else
		head.Text = canClaim and string.format("Your Day %d gift is ready!", day) or string.format("Day %d is on its way", day)
		-- "Day N of 7": N = today's day of the streak (the one you can claim now, or the one you claimed)
		local today = canClaim and day or ((day - 2) % #REWARDS + 1)
		if today == #REWARDS then
			subLine("Day 7 of 7: a new week starts tomorrow", "Day 7 of 7: new week tomorrow")
		else
			local nxt = REWARDS[today % #REWARDS + 1].short
			subLine(string.format("Day %d of 7: come back tomorrow for %s", today, nxt),
				string.format("Day %d of 7. Tomorrow: %s", today, nxt))
		end
	end
	-- the cards: what this claim pays. One sits in the middle (the snowball's Offline popup does the
	-- same), two stand side by side.
	local spec = REWARDS[day].cards
	for i, c in ipairs(cards) do
		local s = spec[i]
		c.root.Visible = s ~= nil
		if s then
			c.icon.Text, c.amount.Text, c.word.Text = s[1], s[2], s[3]
			UI.vgrad(c.face, UI.CANDY[s[4]])
		end
	end
	local y = LOOK[mode].card[1]
	cards[1].root.Position = UDim2.fromOffset(#spec >= 2 and 18 or 155, y)
	for i, b in ipairs(tiles) do
		local done = synced and i < day
		UI.recolour(b, done and "green" or ((synced and i == day) and "gold" or "grey"))
		b.icon.Visible = not done
		b.tick.Visible = done
	end
end

local remotes = ReplicatedStorage:WaitForChild("DailyRemotes", 30)
local stateEvent, claimEvent, syncEvent
if remotes then
	stateEvent = remotes:WaitForChild("State")
	claimEvent = remotes:WaitForChild("Claim")
	syncEvent  = remotes:WaitForChild("Sync")
end

local function celebrate(day)
	local b = tiles[day]
	if b then UI.punch(b.scale, 1.3, 0.36) end
	for _, c in ipairs(cards) do
		if c.root.Visible then UI.punch(c.scale, 1.12, 0.36) end
	end
end

-- the offer (see HOW IT IS REACHED). Once per UTC day per session, so a Sync answer arriving while
-- the window is already up, or a player who shut it, never re-opens it.
local pg = plr:WaitForChild("PlayerGui")
local OTHER_MENUS = { "BaitsMenu", "UpgradesMenu", "InventoryMenu", "BoatsMenu", "ZonesMenu", "RebirthMenu",
	"ShopMenu", "QuestsMenu", "IndexMenu", "SettingsMenu", "LeaderboardMenu", "FeedbackMenu", "WheelMenu", "GiftsMenu" }
local offeredOn   -- the UTC day it was last offered on
local function screenBusy()
	if plr:GetAttribute("TutorialActive") == true then return true end   -- (a new player: after the tutorial)
	for _, n in ipairs(OTHER_MENUS) do
		local m = pg:FindFirstChild(n)
		if m and m.Enabled then return true end
	end
	return false
end
local function offer()
	local today = math.floor(workspace:GetServerTimeNow() / 86400)
	if offeredOn == today then return end
	offeredOn = today
	task.spawn(function()
		task.wait(1.5)   -- let the HUD finish assembling first
		while screenBusy() do task.wait(0.5) end
		if canClaim and not gui.Enabled then gui.Enabled = true end
	end)
end

if stateEvent then
	stateEvent.OnClientEvent:Connect(function(can, next_, claimedDay, tot, grantedDay)
		canClaim    = can and true or false
		nextDay     = tonumber(next_) or 1
		lastClaimed = tonumber(claimedDay) or 0
		total       = tonumber(tot) or 0
		synced, busy = true, false
		render()
		-- grantedDay is only present on a successful claim: apply the payload now
		if grantedDay then
			local what = grant(grantedDay)
			celebrate(grantedDay)
			showToast("🎁 Day " .. grantedDay .. ": " .. what, true)
			-- taken: let the celebration play, then the window goes until tomorrow
			task.delay(2.4, function() if gui.Enabled and not canClaim then gui.Enabled = false end end)
		elseif canClaim then
			offer()
		end
		-- still published for anything that wants to know (nothing on the HUD draws it any more)
		plr:SetAttribute("DailyReady", canClaim)
	end)
end

TouchKit.press(claim.button, function()
	if not synced then return end
	if not canClaim then showToast("Come back in " .. span(secsToReset()), false); return end
	if busy then return end
	if not claimEvent then showToast("Rewards are offline", false); return end
	busy = true
	task.delay(5, function() busy = false end)   -- (a lost answer must not lock the key forever)
	claimEvent:FireServer()
end)

local function closeMenu() gui.Enabled = false end
TouchKit.press(close.button, closeMenu)
TouchKit.press(backdrop, closeMenu)

-- the countdown, and UTC midnight: ask the moment the day turns rather than wait up to 30 s for
-- DailyServer's own sweep
task.spawn(function()
	local lastDay = math.floor(workspace:GetServerTimeNow() / 86400)
	while true do
		task.wait(1)
		local d = math.floor(workspace:GetServerTimeNow() / 86400)
		if d ~= lastDay then
			lastDay = d
			if syncEvent then syncEvent:FireServer() end
		end
		if gui.Enabled then renderKey() end
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
		if syncEvent then syncEvent:FireServer() end
		-- the snowball's pop: from 0.6 of the fit, springing out
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

local dev = gui:FindFirstChild("DevDaily") or new("BindableEvent", { Name = "DevDaily" }, gui)
dev.Event:Connect(function(day)
	day = math.clamp(tonumber(day) or 1, 1, #REWARDS)
	local what = grant(day)
	celebrate(day); showToast("🎁 [dev] Day " .. day .. ": " .. what, true)
end)

print("[Daily] built — " .. #REWARDS .. "-day cycle")
