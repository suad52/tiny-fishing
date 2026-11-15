--[==[
	ShopKit - the +1 snowball shop's look ("Candy Brick", ReplicatedStorage.PlusOneUI over there), ported to the fishing
	game on 2026-10-10 and re-themed for the sea. Used by StarterGui.ShopMenu.ShopController.

	The same anatomy as the snowball shop:
	  * chunky ROWS in the ITEM's colour (CANDY), a big icon on the left over a soft glow, a centred text column;
	  * a KEY on the right in the STATE's colour (BRICK): pink = a Robux price, gold = owned / the tab you're on,
	    green = use it now, grey = not yet;
	  * an outline and a hard drop under everything, so every piece reads as a sticker;
	  * a window with a big icon breaking out of its top-left corner and a red X on its top-right corner;
	  * 3D icons (ReplicatedStorage.ShopIcons) that rock gently in their ViewportFrames, with a flat drop shadow.
	What changed for the sea: no LEGO anywhere (the studs on the keys, header and body are gone - keys and rows get a
	gloss cap instead), outlines and drops are the house INK navy (8,22,44) instead of black, the face is FredokaOne
	(the fishing game's), corners are rounder, the window is a sunny lagoon under a teal header with a wave crest.

	Sizes are design px; the shop scales its window with a UIScale.
]==]

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = {}
local rgb = Color3.fromRGB

UI.FONT = Font.fromEnum(Enum.Font.FredokaOne)
UI.MEASURE_FONT = Enum.Font.FredokaOne
UI.WHITE = Color3.new(1, 1, 1)
UI.INK = rgb(8, 22, 44) -- every outline and hard drop (the fishing menus' INK)

-- keycap colours (chips, stickers, the toast): hi = top of the face, base = bottom, lip = the band under it
UI.KEY = {
	gold = { hi = rgb(255, 238, 120), base = rgb(255, 186, 30), lip = rgb(196, 104, 0) },
	green = { hi = rgb(150, 246, 128), base = rgb(48, 200, 78), lip = rgb(20, 128, 56) },
	red = { hi = rgb(255, 138, 138), base = rgb(236, 48, 64), lip = rgb(148, 20, 36) },
	pink = { hi = rgb(255, 150, 226), base = rgb(238, 50, 160), lip = rgb(150, 20, 100) },
	sea = { hi = rgb(110, 214, 250), base = rgb(30, 128, 214), lip = rgb(12, 66, 140) },
	navy = { hi = rgb(40, 92, 156), base = rgb(18, 52, 104), lip = rgb(8, 26, 60) },
	grey = { hi = rgb(228, 234, 242), base = rgb(160, 172, 194), lip = rgb(94, 106, 132) },
}

UI.TEXT = {
	gold = rgb(255, 222, 80), lime = rgb(170, 255, 100), aqua = rgb(150, 238, 255), red = rgb(255, 120, 130),
	soft = rgb(214, 238, 255), white = rgb(255, 255, 255),
}
UI.LIME = UI.TEXT.lime -- a gain, a count you have, an offer's timer

-- the icon family. Images first (the snowball shop's own stickers - they load here), then any name with a model in
-- ReplicatedStorage.ShopIcons is drawn in 3D over its flat image (see "3D icons").
UI.ICONS = {
	cart = "rbxassetid://73659745331433", -- the snowball Shop's orange cart: this window's header icon
	robux = "rbxassetid://79763108261588", -- the Robux mark on every price chip
	glow = "rbxassetid://91669070851253", -- the soft white glow behind each row's icon
	check = "rbxassetid://79607904170623", lock = "rbxassetid://123732908671204",
	crown = "rbxassetid://135613527112648", lightning = "rbxassetid://132807618278551",
	star = "rbxassetid://73677992141817", clock = "rbxassetid://87281751322669",
	sparkle = "rbxassetid://101425610351596", trophy = "rbxassetid://119865372574900",
	info = "rbxassetid://108615790991524",
}

---------------------------------------------------------------- small helpers
local function new(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
UI.new = new

function UI.corner(obj, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, obj)
end

-- a border outline (INK by default)
function UI.stroke(obj, thickness, color)
	return new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = thickness or 4, Color = color or UI.INK,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, obj)
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
	if not (g and g:IsA("UIGradient")) then
		g = new("UIGradient", { Name = "Fill", Rotation = 90 }, obj)
	end
	g.Color = seq
	return g
end

-- 12345 -> "12,345"; 1234567 -> "1.23M" (K M B T Qa Qi Sx Sp Oc No Dc, as the other menus)
local UNITS = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
function UI.num(n)
	n = math.floor(tonumber(n) or 0)
	if n < 100000 then
		local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (s:gsub("^,", ""))
	end
	local i, v = 0, n
	while v >= 1000 and i < #UNITS do
		v /= 1000
		i += 1
	end
	local s = v < 100 and string.format("%.2f", math.floor(v * 100) / 100):gsub("%.?0+$", "") or tostring(math.floor(v))
	return s .. UNITS[i]
end
-- 1234567 -> "$1.23M" (short: 50000 -> "$50K")
function UI.cash(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1000 and n < 100000 and n % 1000 == 0 then return "$" .. (n // 1000) .. "K" end
	return "$" .. UI.num(n)
end

-- a gloss cap: a white sheen over the top `frac` of its parent, fading out downwards (the fishing kit's shine; it
-- replaces the snowball's stud texture). opts: frac (0.48), alpha (0.55 at the top), inset (px, 3), radius, ZIndex
function UI.gloss(parent, opts)
	opts = opts or {}
	local inset = opts.inset or 3
	local g = new("Frame", {
		Name = "Gloss", BackgroundColor3 = UI.WHITE, Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, opts.frac or 0.48, -inset), ZIndex = opts.ZIndex or 1, Active = false,
	}, parent)
	UI.corner(g, opts.radius or 8)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, opts.alpha or 0.55), NumberSequenceKeypoint.new(1, 1),
		}),
	}, g)
	return g
end

---------------------------------------------------------------- the keycap block (chips, stickers, toast)
-- Returns { root, face, strip, key, lip, radius } -- put content into .face
function UI.block(parent, colour, opts)
	opts = opts or {}
	local key = UI.KEY[colour] or colour
	local lip = opts.lip or 7
	local r = opts.radius or 16
	local root = new("Frame", {
		Name = opts.Name or "Block", Size = opts.Size or UDim2.fromOffset(100, 50), Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero, Rotation = opts.Rotation or 0, ZIndex = opts.ZIndex or 1,
		LayoutOrder = opts.LayoutOrder or 0, BackgroundColor3 = key.lip,
	}, parent)
	UI.corner(root, r)
	UI.stroke(root, opts.outline or 4)
	local face = new("Frame", { Name = "Face", Size = UDim2.new(1, 0, 1, -lip), BackgroundColor3 = UI.WHITE }, root)
	UI.corner(face, r)
	UI.vgrad(face, { key.hi, key.base })
	local strip
	if opts.highlight ~= false then
		local h = opts.highlight or {}
		local inset = h.inset or 12
		strip = new("Frame", {
			Name = "Shine", Position = UDim2.fromOffset(inset, h.top or 4), Size = UDim2.new(1, -2 * inset, 0, h.height or 5),
			BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.5,
		}, face)
		UI.corner(strip, 9)
	end
	return { root = root, face = face, strip = strip, key = key, colour = colour, lip = lip, radius = r }
end

function UI.recolour(block, colour)
	if block.colour == colour then return end
	local key = UI.KEY[colour] or colour
	block.colour, block.key = colour, key
	block.root.BackgroundColor3 = key.lip
	UI.vgrad(block.face, { key.hi, key.base })
end

---------------------------------------------------------------- text
-- a label in the house face with an INK outline that scales with the letters. opts: size (max px, 20), color, align,
-- drop (px hard shadow), outline (fraction of the font size), outlineColor, scaled (true), minSize, + TextLabel props
local PROPS_SKIP = { size = true, color = true, align = true, drop = true, outline = true, outlineColor = true, weight = true, scaled = true, minSize = true }
function UI.label(parent, text, opts)
	opts = opts or {}
	local size = opts.size or 20
	local l = new("TextLabel", {
		Name = opts.Name or "Label", BackgroundTransparency = 1, Text = text or "", FontFace = UI.FONT,
		TextColor3 = opts.color or UI.WHITE, Size = UDim2.fromScale(1, 1),
		TextXAlignment = opts.align == "left" and Enum.TextXAlignment.Left or (opts.align == "right" and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center),
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
		Name = "Outline", Color = opts.outlineColor or UI.INK, LineJoinMode = Enum.LineJoinMode.Round,
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize, Thickness = opts.outline or (size >= 30 and 0.1 or 0.13),
	}, l)
	l.Parent = parent
	if opts.drop and opts.drop > 0 then UI.dropShadow(l, opts.drop) end
	return l, s
end

-- a hard INK copy of a label a few px lower, behind it; follows the label's text, visibility and fade
function UI.dropShadow(l, px)
	local d = l:Clone()
	d.Name = l.Name .. "Drop"
	d.TextColor3 = UI.INK
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("UIGradient") then c:Destroy() end
		if c:IsA("UIStroke") then c.Color = UI.INK end
	end
	d.Position = l.Position + UDim2.fromOffset(0, px)
	d.ZIndex = l.ZIndex - 1
	d.Parent = l.Parent
	local function sync()
		d.Text = d.RichText and (l.Text:gsub("(color%s*=%s*)([\"'])(.-)%2", "%1%2#08162C%2")) or l.Text
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
	local ls = l:FindFirstChildWhichIsA("UIStroke")
	if ls then ls:GetPropertyChangedSignal("Transparency"):Connect(sync) end
	l.Destroying:Connect(function() d:Destroy() end)
	sync()
	return d
end

-- width in px of text at a fixed size (FredokaOne metrics)
function UI.textWidth(text, size)
	text = tostring(text):gsub("<[^>]->", "")
	return TextService:GetTextSize(text, size, UI.MEASURE_FONT, Vector2.new(4000, 400)).X
end

---------------------------------------------------------------- 3D icons
-- ReplicatedStorage.ShopIcons.<name>: AI-generated 3D models (the snowball shop's IconModels technique; its Starter
-- Pack chest came over as ShopIcons.starter). When a model exists for an icon name, UI.icon / UI.setIcon show it in a
-- ViewportFrame inside the image label, over a see-through INK copy of itself a little lower (the hard drop). The label
-- behaves as before: its ImageTransparency / ImageColor3 / ZIndex are mirrored onto the 3D view. On screen the model
-- rocks gently, but not while the player has Menu Animations off (Set_MenuFX = false). Per-model framing:
-- UI.ICON3D[name] = { yaw, pitch, zoom, rock, roll } -- read from the model's attributes Yaw / Pitch / Zoom / Rock / Roll
-- when it has them, so a model is tuned where it lives.
UI.ICON3D = {}
local ICON3D_DEFAULT = { yaw = -25, pitch = 12, zoom = 1, rock = 14, roll = 0 }
local ICON3D_FOV = 22
local live3d = setmetatable({}, { __mode = "k" })
local mirrored = setmetatable({}, { __mode = "k" })
local stepping = false

local function iconModels()
	return ReplicatedStorage:FindFirstChild("ShopIcons")
end

local function shownOnScreen(obj)
	local o = obj
	while o and o ~= game do
		if o:IsA("LayerCollector") then
			return o:IsA("ScreenGui") and o.Enabled
		elseif o:IsA("GuiObject") and not o.Visible then
			return false
		end
		o = o.Parent
	end
	return false
end

local function aim(entry, yawOffset)
	local look = entry.look
	local cf = CFrame.new(entry.centre) * CFrame.Angles(0, math.rad(look.yaw + yawOffset), 0)
		* CFrame.Angles(-math.rad(look.pitch), 0, 0) * CFrame.new(0, 0, entry.dist)
	if look.roll ~= 0 then cf *= CFrame.Angles(0, 0, math.rad(look.roll)) end
	for _, cam in ipairs(entry.cams) do cam.CFrame = cf end
end

local function startStepping()
	if stepping or not RunService:IsClient() or not RunService:IsRunning() then return end
	stepping = true
	task.spawn(function()
		local models = iconModels()
		if models then pcall(game:GetService("ContentProvider").PreloadAsync, game:GetService("ContentProvider"), { models }) end
	end)
	local player = Players.LocalPlayer
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then return end
		acc = 0
		if player and player:GetAttribute("Set_MenuFX") == false then return end
		local t = os.clock()
		for vf, entry in pairs(live3d) do
			if not vf.Parent then
				live3d[vf] = nil
			elseif entry.look.rock > 0 and shownOnScreen(vf) then
				aim(entry, math.sin(t * 0.8 + entry.phase) * entry.look.rock)
			end
		end
	end)
end

local SHADOW_ALPHA = 0.55
local function sync3d(img)
	local main, shade = img:FindFirstChild("Icon3D"), img:FindFirstChild("Icon3DShadow")
	if main then
		main.ImageTransparency, main.ImageColor3, main.ZIndex = img.ImageTransparency, img.ImageColor3, img.ZIndex + 1
	end
	if shade then
		shade.ImageTransparency, shade.ZIndex = 1 - (1 - img.ImageTransparency) * SHADOW_ALPHA, img.ZIndex
	end
end

local function attach3d(img, name)
	local still = img:GetAttribute("IconStill") == true
	for _, n in ipairs({ "Icon3D", "Icon3DShadow" }) do
		local old = img:FindFirstChild(n)
		if old then
			live3d[old] = nil
			old:Destroy()
		end
	end
	local models = iconModels()
	local src = models and models:FindFirstChild(tostring(name))
	if not (src and src:IsA("Model")) then return end
	img.Image = ""
	local tune = UI.ICON3D[name] or {}
	local look = {}
	for k, v in pairs(ICON3D_DEFAULT) do
		local a = src:GetAttribute(k:sub(1, 1):upper() .. k:sub(2))
		look[k] = (tune[k] ~= nil and tune[k]) or (type(a) == "number" and a) or v
	end
	if still then look.rock = 0 end
	local box, size = src:GetBoundingBox()
	local half = math.max(size.Y, math.sqrt(size.X ^ 2 + size.Z ^ 2) * 0.8) / 2
	local entry = {
		cams = {}, centre = box.Position, look = look, phase = (#tostring(name) * 1.7) % 6.28,
		dist = (half / math.tan(math.rad(ICON3D_FOV / 2)) * 1.06 + math.max(size.X, size.Z) / 2) / look.zoom,
	}
	local function view(vfName, shadow)
		local vf = new("ViewportFrame", {
			Name = vfName, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			Position = shadow and UDim2.fromScale(0.02, 0.06) or UDim2.new(),
			Ambient = shadow and UI.INK or rgb(180, 182, 196), LightColor = shadow and UI.INK or rgb(255, 250, 238),
			LightDirection = Vector3.new(0.45, -1, -0.6), ImageColor3 = shadow and UI.INK or img.ImageColor3,
		}, nil)
		local cam = new("Camera", { FieldOfView = ICON3D_FOV }, vf)
		vf.CurrentCamera = cam
		table.insert(entry.cams, cam)
		src:Clone().Parent = vf
		vf.Parent = img
		return vf
	end
	view("Icon3DShadow", true)
	local main = view("Icon3D", false)
	sync3d(img)
	aim(entry, 0)
	live3d[main] = entry
	if not mirrored[img] then
		mirrored[img] = true
		for _, prop in ipairs({ "ImageTransparency", "ImageColor3", "ZIndex" }) do
			img:GetPropertyChangedSignal(prop):Connect(function() sync3d(img) end)
		end
	end
	startStepping()
end

---------------------------------------------------------------- icons
-- a sticker icon (3D when ShopIcons has the name). opts: Position, AnchorPoint, Rotation, ZIndex, Name, ImageColor3,
-- ImageTransparency, Visible; flat = true keeps it 2D.
function UI.icon(parent, name, size, opts)
	opts = opts or {}
	local img = new("ImageLabel", {
		Name = opts.Name or ("Icon_" .. tostring(name)), BackgroundTransparency = 1, Image = UI.ICONS[name] or "",
		ScaleType = Enum.ScaleType.Fit, Size = typeof(size) == "UDim2" and size or UDim2.fromOffset(size, size),
	}, nil)
	for k, v in pairs(opts) do
		if k ~= "flat" and k ~= "still" then img[k] = v end
	end
	img:SetAttribute("Icon", name)
	if opts.flat then img:SetAttribute("IconFlat", true) end
	if opts.still then img:SetAttribute("IconStill", true) end -- (no rocking: it rides something that moves)
	img.Parent = parent
	if not opts.flat then attach3d(img, name) end
	return img
end

function UI.setIcon(img, name)
	img.Image = UI.ICONS[name] or ""
	img:SetAttribute("Icon", name)
	if not img:GetAttribute("IconFlat") then attach3d(img, name) end
end

-- a flat icon's hard drop: an INK copy of the image dy px lower at alpha. While the icon is 3D its Image is empty, so
-- the copy shows nothing (3D icons bring their own drop).
function UI.iconDrop(img, dy, alpha)
	dy, alpha = dy or 4, alpha or 0.5
	local d = new("ImageLabel", { Name = img.Name .. "Drop", BackgroundTransparency = 1, ImageColor3 = UI.INK }, nil)
	local function sync()
		d.Image, d.ScaleType, d.Size, d.AnchorPoint = img.Image, img.ScaleType, img.Size, img.AnchorPoint
		d.Rotation, d.Visible, d.ZIndex = img.Rotation, img.Visible, img.ZIndex - 1
		d.Position = img.Position + UDim2.fromOffset(0, dy)
		d.ImageTransparency = 1 - (1 - img.ImageTransparency) * alpha
	end
	for _, p in ipairs({ "Image", "ScaleType", "Size", "AnchorPoint", "Rotation", "Visible", "ZIndex", "Position", "ImageTransparency" }) do
		img:GetPropertyChangedSignal(p):Connect(sync)
	end
	img:GetPropertyChangedSignal("Parent"):Connect(function()
		if img.Parent then d.Parent = img.Parent end
	end)
	img.Destroying:Connect(function() d:Destroy() end)
	sync()
	d.Parent = img.Parent
	return d
end

---------------------------------------------------------------- chips and stickers
-- a centred chip that grows to fit its text: a coloured keycap. Returns { block, label, set(text, colour?) }.
-- opts: height (44), textSize (18), colour, Position, AnchorPoint, minWidth, pad (20), ZIndex, textColor, lip, radius
function UI.chip(parent, colour, opts)
	opts = opts or {}
	local h = opts.height or 44
	local lip = opts.lip or 6
	local block = UI.block(parent, colour, {
		Name = opts.Name or "Chip", Size = UDim2.fromOffset(opts.minWidth or 120, h), Position = opts.Position,
		AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0), lip = lip, radius = opts.radius or 16, ZIndex = opts.ZIndex,
		highlight = { top = 3, inset = 12, height = 4 },
	})
	local pad = opts.pad or 20
	local label = UI.label(block.face, "", {
		Name = "Text", size = opts.textSize or 18, scaled = false, color = opts.textColor or UI.WHITE,
		Size = UDim2.new(1, -pad * 2, 1, 0), Position = UDim2.fromOffset(pad, 0), outline = 0.14,
	})
	local chip = { block = block, label = label }
	function chip.set(text, newColour)
		label.Text = text
		if newColour then UI.recolour(block, newColour) end
		local w = UI.textWidth(text, opts.textSize or 18) + pad * 2 + 6
		block.root.Size = UDim2.fromOffset(math.max(w, opts.minWidth or 0), h)
	end
	return chip
end

-- a small tilted sticker ("BEST VALUE", "POPULAR"): a keycap chip
function UI.sticker(parent, colour, text, opts)
	opts = opts or {}
	local c = UI.chip(parent, colour, {
		Name = opts.Name or "Sticker", height = opts.height or 34, textSize = opts.textSize or 15, pad = opts.pad or 10,
		lip = 5, radius = 12, Position = opts.Position, AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
		ZIndex = opts.ZIndex, minWidth = opts.minWidth or 40,
	})
	c.block.root.Rotation = opts.Rotation or 7
	c.block.root:FindFirstChildWhichIsA("UIStroke").Thickness = 3
	c.set(text)
	return c
end

-- punch a UIScale (the house "pop")
function UI.punch(scaleObj, amount, time)
	scaleObj.Scale = amount
	TweenService:Create(scaleObj, TweenInfo.new(time or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- the candy palette
-- row faces: vertical gradients, top -> bottom (a 3-colour entry is 0 / 0.5 / 1). One colour per ITEM.
UI.CANDY = {
	blue = { rgb(110, 236, 255), rgb(0, 92, 236) }, orange = { rgb(255, 216, 84), rgb(255, 112, 0) },
	purple = { rgb(214, 164, 255), rgb(116, 34, 236) }, red = { rgb(255, 112, 112), rgb(196, 10, 22) },
	cyan = { rgb(156, 250, 255), rgb(0, 164, 222) }, emerald = { rgb(146, 255, 184), rgb(0, 172, 98) },
	royal = { rgb(150, 186, 255), rgb(34, 60, 216) }, pink = { rgb(255, 172, 255), rgb(232, 16, 226) },
	fire = { rgb(255, 210, 78), rgb(234, 52, 0) }, rose = { rgb(255, 156, 208), rgb(226, 20, 124) },
	teal = { rgb(126, 255, 222), rgb(0, 162, 152) }, coral = { rgb(255, 184, 150), rgb(240, 74, 70) },
	aurora = { rgb(124, 255, 204), rgb(0, 188, 200), rgb(96, 44, 214) },
	cosmic = { rgb(198, 146, 255), rgb(98, 30, 214), rgb(46, 12, 132) },
	reef = { rgb(130, 236, 255), rgb(26, 138, 230), rgb(16, 66, 170) },
}
-- key fills (the STATE): flatter than the rows
UI.BRICK = {
	green = { rgb(140, 250, 96), rgb(56, 214, 30) }, grey = { rgb(224, 230, 240), rgb(150, 162, 186) },
	gold = { rgb(255, 238, 112), rgb(255, 172, 0) }, pink = { rgb(255, 120, 232), rgb(236, 30, 236) },
	red = { rgb(255, 124, 124), rgb(222, 22, 38) }, sea = { rgb(104, 196, 246), rgb(36, 112, 196) },
}
-- the window: a sunny lagoon (bright at the surface, deeper blue at the bottom) under a teal header
UI.LAGOON = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(178, 240, 255)), ColorSequenceKeypoint.new(0.42, rgb(112, 212, 248)),
	ColorSequenceKeypoint.new(1, rgb(46, 148, 226)),
})
UI.HEAD = { teal = { rgb(110, 228, 255), rgb(24, 142, 222) }, gold = { rgb(255, 240, 138), rgb(245, 154, 12) } }
-- one header colour per menu (2026-10-10: the nine menus off the MenuBar moved onto this kit - the snowball's rule,
-- "the HEADER colour is the tab"). UI.window takes any of these names, or a { top, bottom } pair.
UI.HEAD.green  = { rgb(150, 255, 104), rgb(40, 196, 52) }
UI.HEAD.pink   = { rgb(255, 160, 240), rgb(226, 30, 200) }
UI.HEAD.purple = { rgb(206, 160, 255), rgb(118, 48, 236) }
UI.HEAD.orange = { rgb(255, 214, 110), rgb(255, 118, 0) }
UI.HEAD.blue   = { rgb(120, 236, 255), rgb(18, 122, 255) }
UI.HEAD.coral  = { rgb(255, 184, 150), rgb(240, 74, 70) }
UI.HEAD.navy   = { rgb(110, 164, 230), rgb(30, 70, 150) }
UI.TITLE = { keys = { rgb(255, 252, 214), rgb(255, 236, 110), rgb(255, 190, 40), rgb(255, 140, 30) }, outline = rgb(96, 46, 4) }
UI.RING = rgb(255, 214, 60) -- an owned row's band
UI.SCROLL = { thumb = rgb(255, 196, 40), track = rgb(8, 22, 44), trackTransparency = 0.78 }

---------------------------------------------------------------- pieces
-- a hard drop: an INK copy of a box dy px lower WITH the box's outline (without it only dy - stroke px would show)
function UI.hardShadow(parent, radius, stroke, dy, z)
	local s = new("Frame", {
		Name = "Shadow", BackgroundColor3 = UI.INK, Position = UDim2.fromOffset(0, dy or 6), Size = UDim2.fromScale(1, 1),
		ZIndex = z or 1, Active = false,
	}, parent)
	UI.corner(s, radius or 8)
	if stroke and stroke > 0 then UI.stroke(s, stroke) end
	return s
end

-- the house press feel for a button with a UIScale: hover grows it a touch (not on touch screens, which never send a
-- reliable leave), pressing squashes it, letting go springs it back
local function pressFeel(button, scale)
	local tween
	local function to(s, info)
		if tween then tween:Cancel() end
		tween = TweenService:Create(scale, info or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = s })
		tween:Play()
	end
	local function touching()
		return game:GetService("UserInputService"):GetLastInputType() == Enum.UserInputType.Touch
	end
	button.MouseEnter:Connect(function() if not touching() then to(1.05) end end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function()
		if tween then tween:Cancel() end
		scale.Scale = 0.92
	end)
	button.MouseButton1Up:Connect(function() to(touching() and 1 or 1.05, TweenInfo.new(0.22, Enum.EasingStyle.Back)) end)
end
UI.pressFeel = pressFeel

-- a key label's outline px by its size: 40 -> 5, 36 / 34 -> 4.5, 30 -> 4, 28 / 26 -> 3.5
local function keyOutline(size)
	return size >= 40 and 5 or size >= 32 and 4.5 or size >= 30 and 4 or 3.5
end

-- the key (the snowball's price button, without the studs): an INK outline, a WHITE rim, a bright fill with a gloss
-- cap, a hard drop (+6, the same outline). colour = a UI.BRICK key (the STATE) or { top, bottom }.
-- opts: Size (196 x 66), Position, AnchorPoint, ZIndex, Name, LayoutOrder, static (a Frame: no hover / press), radius
-- Returns k = { button, scale, rim, fill, text, badge (the green check disc), label, recolour, set, setParts }:
--   k.recolour(c); k.set(lead, text, size, o); k.setParts(lead, parts, o) -- a centred line of pieces:
--     { text = "40", size = 30, o = outline px, drop = px (3; 0 = none), color, dy, gap }
--     { icon = "robux", size = px or { w, h }, drop = px, rot, dy, gap }
--   lead = "check" (the green check badge breaking out of the left edge) or nil
function UI.candyKey(parent, colour, opts)
	opts = opts or {}
	local static = opts.static == true
	local R = opts.radius or 12
	local k = { parts = {} }
	k.button = new(static and "Frame" or "TextButton", {
		Name = opts.Name or "Key", BackgroundTransparency = 1, Size = opts.Size or UDim2.fromOffset(196, 66),
		Position = opts.Position or UDim2.new(), AnchorPoint = opts.AnchorPoint or Vector2.zero, ZIndex = opts.ZIndex or 1,
		LayoutOrder = opts.LayoutOrder or 0,
	}, nil)
	if not static then
		k.button.Text, k.button.AutoButtonColor = "", false
	end
	UI.hardShadow(k.button, R, 4, 6, 1)
	k.rim = new("Frame", { Name = "Rim", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, k.button)
	UI.corner(k.rim, R)
	UI.stroke(k.rim, 4)
	k.face = k.rim
	k.fill = new("Frame", {
		Name = "Fill", BackgroundColor3 = UI.WHITE, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6),
	}, k.rim)
	UI.corner(k.fill, math.max(R - 3, 2))
	UI.gloss(k.fill, { frac = 0.5, alpha = 0.45, inset = 2, radius = math.max(R - 5, 2) })
	k.text = new("Frame", { Name = "Text", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, k.button)
	-- the check badge (OWNED): a green disc, INK outline, the white tick filling 72%, its own drop
	k.badgeDrop = new("Frame", {
		Name = "CheckDrop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 4), Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = UI.INK, BackgroundTransparency = 0.5, Visible = false, ZIndex = 4,
	}, k.button)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, k.badgeDrop)
	UI.stroke(k.badgeDrop, 4).Transparency = 0.5
	k.badge = new("Frame", {
		Name = "Check", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(52, 52),
		Rotation = -8, BackgroundColor3 = UI.WHITE, Visible = false, ZIndex = 5,
	}, k.button)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, k.badge)
	UI.stroke(k.badge, 4)
	UI.vgrad(k.badge, { rgb(150, 250, 100), rgb(40, 190, 40) })
	UI.icon(k.badge, "check", UDim2.fromScale(0.72, 0.72), {
		Name = "Tick", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2, flat = true,
	})

	function k.recolour(c)
		k.colour = c
		UI.vgrad(k.fill, UI.BRICK[c] or c)
	end

	function k.setParts(lead, parts, o)
		o = o or {}
		parts = parts or {}
		local isCheck = lead == "check"
		k.badge.Visible, k.badgeDrop.Visible = isCheck, isCheck
		if isCheck then
			local s = o.leadSize or 52
			k.badge.Size, k.badgeDrop.Size = UDim2.fromOffset(s, s), UDim2.fromOffset(s, s)
		end
		local pad = o.pad or (isCheck and 28 or 0)
		k.text.Position, k.text.Size = UDim2.fromOffset(pad, 0), UDim2.new(1, -pad, 1, 0)
		-- measure: icons and gaps are fixed; the text shrinks together if the line does not fit
		local avail = k.button.Size.X.Offset - pad
		local gap = o.gap or 6
		local fixed, want = 0, 0
		for i, p in ipairs(parts) do
			if i > 1 then fixed += p.gap or gap end
			if p.icon then
				fixed += type(p.size) == "table" and p.size[1] or p.size or 40
			else
				want += math.ceil(UI.textWidth(p.text or "", p.size or 40)) + 4
			end
		end
		local kf = want > 0 and math.clamp((avail - 12 - fixed) / want, 0.5, 1) or 1
		local widths, total = {}, fixed
		for i, p in ipairs(parts) do
			local kind = p.icon and "icon" or "text"
			local dropPx = p.drop or 3
			local slot = k.parts[i]
			if slot and (slot.kind ~= kind or slot.dropPx ~= dropPx) then
				slot.obj:Destroy()
				slot = nil
			end
			if kind == "text" then
				local size = p.size or 40
				local s = math.max(math.floor(size * kf), 8)
				local wpx = math.ceil(UI.textWidth(p.text or "", s)) + 4
				if not slot then
					local l = UI.label(k.text, "", {
						Name = "Label" .. i, size = s, scaled = false, drop = dropPx, ZIndex = 2, Size = UDim2.fromOffset(wpx, math.ceil(s * 1.3)),
					})
					slot = { kind = kind, dropPx = dropPx, obj = l, drop = k.text:FindFirstChild(l.Name .. "Drop") }
				end
				local l = slot.obj
				l.Text = p.text or ""
				l.TextColor3 = p.color or UI.WHITE
				l.Size = UDim2.fromOffset(wpx, math.ceil(s * 1.3))
				local frac = (p.o or keyOutline(size)) / size
				for _, t in ipairs({ l, slot.drop }) do
					if t then
						t.TextSize = s
						local st = t:FindFirstChildWhichIsA("UIStroke")
						if st then st.Thickness = frac end
					end
				end
				widths[i] = wpx
				total += wpx
			else
				local sz = p.size or 40
				local iw, ih = type(sz) == "table" and sz[1] or sz, type(sz) == "table" and sz[2] or sz
				if not slot then
					local img = UI.icon(k.text, p.icon, UDim2.fromOffset(iw, ih), { Name = "Icon" .. i, ZIndex = 2, flat = p.flat })
					slot = { kind = kind, dropPx = dropPx, obj = img, drop = dropPx > 0 and UI.iconDrop(img, dropPx, 0.5) or nil }
				elseif slot.obj:GetAttribute("Icon") ~= p.icon then
					UI.setIcon(slot.obj, p.icon)
				end
				slot.obj.Size = UDim2.fromOffset(iw, ih)
				slot.obj.Rotation = p.rot or 0
				widths[i] = iw
			end
			slot.obj.Visible = true
			k.parts[i] = slot
		end
		for j = #parts + 1, #k.parts do
			k.parts[j].obj.Visible = false
		end
		local x = (avail - total) / 2
		k.label, k.drop = nil, nil
		for i, p in ipairs(parts) do
			if i > 1 then x += p.gap or gap end
			local slot = k.parts[i]
			slot.obj.AnchorPoint = Vector2.new(0, 0.5)
			slot.obj.Position = UDim2.new(0, math.floor(x + 0.5), 0.5, p.dy or 0)
			x += widths[i]
			if slot.kind == "text" and not k.label then
				k.label, k.drop = slot.obj, slot.drop
			end
		end
	end

	function k.set(lead, str, size, o)
		o = o or {}
		k.setParts(lead, { { text = str, size = size or 40, color = o.color } }, o)
	end

	k.recolour(colour or "grey")
	k.scale = new("UIScale", {}, k.button)
	if not static then pressFeel(k.button, k.scale) end
	if opts.text then k.set(opts.lead, opts.text or "", opts.textSize) end
	k.button.Parent = parent
	return k
end

-- Roblox's live price for a Developer Product or a Game Pass, one fetch per id per session (backing off 5 s .. 60 s
-- after a failure). Returns the price when known, else nil -- and then cb(price) runs once it arrives (never for id 0).
local robuxPrices, robuxWaiting, robuxFailed = {}, {}, {}
function UI.robuxPrice(id, infoType, cb)
	id = tonumber(id)
	if not id or id <= 0 then return nil end
	infoType = infoType or Enum.InfoType.Product
	local key = tostring(infoType) .. ":" .. tostring(id)
	if robuxPrices[key] then return robuxPrices[key] end
	local waiting = robuxWaiting[key]
	if waiting then
		if cb and not table.find(waiting, cb) then table.insert(waiting, cb) end
		return nil
	end
	local failed = robuxFailed[key]
	if failed and os.clock() < failed.retryAt then
		if cb and not table.find(failed.held, cb) and #failed.held < 32 then table.insert(failed.held, cb) end
		if cb and not failed.armed then
			failed.armed = true
			task.delay(failed.retryAt - os.clock() + 0.05, function()
				failed.armed = false
				if robuxFailed[key] == failed and #failed.held > 0 and not robuxWaiting[key] then UI.robuxPrice(id, infoType) end
			end)
		end
		return nil
	end
	waiting = failed and failed.held or {}
	if cb and not table.find(waiting, cb) then table.insert(waiting, cb) end
	robuxWaiting[key] = waiting
	task.spawn(function()
		local market = game:GetService("MarketplaceService")
		local ok, info = pcall(function() return market:GetProductInfoAsync(id, infoType) end)
		if not (ok and type(info) == "table") then
			ok, info = pcall(function() return market:GetProductInfo(id, infoType) end)
		end
		local price = ok and type(info) == "table" and type(info.PriceInRobux) == "number" and info.PriceInRobux or nil
		robuxWaiting[key] = nil
		if price then
			robuxPrices[key] = price
			robuxFailed[key] = nil
			for _, f in ipairs(waiting) do task.spawn(f, price) end
		else
			local n = (failed and failed.n or 0) + 1
			robuxFailed[key] = { n = n, retryAt = os.clock() + math.min(5 * 2 ^ (n - 1), 60), held = {} }
		end
	end)
	return nil
end

-- the Robux price chip (every Robux price uses it): a small pill -- INK outline, a hard drop carrying the outline, a
-- shine line -- with Roblox's mark and the number in white. It sizes itself to the price. price: a number (UI.num)
-- or text; nil shows "...". opts: height (30), textSize (20), iconSize, pad (8), gap (4), colour (a UI.BRICK key:
-- "pink"), Position, AnchorPoint, ZIndex, Name. Returns c = { root, face, icon, label, price, w, h, set(price) }
function UI.robuxChip(parent, price, opts)
	opts = opts or {}
	local h = opts.height or 30
	local ts = opts.textSize or 20
	local is = opts.iconSize or (h - 8)
	local pad, gap = opts.pad or 8, opts.gap or 4
	local z = opts.ZIndex or 1
	local r = math.floor(h / 2)
	local c = { h = h }
	c.root = new("Frame", {
		Name = opts.Name or "RobuxChip", BackgroundTransparency = 1, Size = UDim2.fromOffset(h * 2, h),
		Position = opts.Position or UDim2.new(), AnchorPoint = opts.AnchorPoint or Vector2.zero, ZIndex = z,
	}, nil)
	UI.hardShadow(c.root, r, 3, 3, z)
	c.face = new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = z + 1 }, c.root)
	UI.corner(c.face, r)
	UI.stroke(c.face, 3)
	UI.vgrad(c.face, UI.BRICK[opts.colour or "pink"] or opts.colour)
	local shine = new("Frame", {
		Name = "Shine", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.55, Position = UDim2.fromOffset(r, 3),
		Size = UDim2.new(1, -2 * r, 0, 3), ZIndex = z + 2,
	}, c.face)
	UI.corner(shine, 2)
	c.icon = UI.icon(c.root, "robux", is, {
		Name = "Robux", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, pad, 0.5, 0), ZIndex = z + 3, flat = true,
	})
	c.label = UI.label(c.root, "", {
		Name = "Price", size = ts, scaled = false, align = "left", outline = 0.15, drop = 2,
		Size = UDim2.new(0, 10, 1, 0), Position = UDim2.fromOffset(pad + is + gap, 0), ZIndex = z + 4,
	})
	function c.set(p)
		c.price = p
		local text = p == nil and "..." or (type(p) == "number" and UI.num(p) or tostring(p))
		c.label.Text = text
		local tw = math.ceil(UI.textWidth(text, ts)) + 2
		c.label.Size = UDim2.new(0, tw, 1, 0)
		c.w = pad + is + gap + tw + pad
		c.root.Size = UDim2.fromOffset(c.w, h)
	end
	c.set(price)
	c.root.Parent = parent
	return c
end

---------------------------------------------------------------- the candy row
-- kinds: size, icon { size, x, y }, glow px, text column { x, w }, key { w, h, x, y } (false = none), and the column's
-- lines { y, h } (title / effect / meta). "duo" is the potion row: two keys stacked (BUY over USE).
UI.ROW = {
	tall744 = { w = 744, h = 128, icon = { 108, 8, 10 }, glow = 132, mid = { 118, 404 }, key = { 196, 66, 532, 31 },
		lines = { { 8, 46 }, { 56, 32 }, { 92, 28 } } },
	duo = { w = 744, h = 128, icon = { 104, 10, 12 }, glow = 128, mid = { 118, 404 }, key = { 196, 56, 532, 8 },
		key2 = { 196, 44, 532, 74 }, lines = { { 8, 46 }, { 56, 32 }, { 92, 28 } } },
	card = { w = 744, h = 100, icon = { 90, 7, 5 }, glow = 118, mid = { 106, 418 }, key = { 196, 64, 536, 18 },
		lines = { { 8, 44 }, { 54, 34 } } },
	strip = { w = 744, h = 50, icon = false, glow = false, mid = { 0, 744 }, key = false, lines = { { 0, 50 } } },
}

-- the candy row: a bright gradient slab in the ITEM's colour -- INK outline, hard drop (+6, same outline), a gloss
-- cap -- with the icon straight on the colour (a soft white glow behind it), a centred text column, and a key on the
-- right. opts: kind, colour (a UI.CANDY key or { top, [mid,] bottom }), icon (a UI.ICONS / ShopIcons name), glow,
-- mid = { x =, w = }, key = false | { colour, w, h, x, y }, static (default true: rows never buy, only their keys),
-- Position, ZIndex, Name, LayoutOrder, w, h.
-- Returns r = { button (the root Frame), scale, shadow, face, glow, icon, iconDrop, mid, midW, lines, l1, l2, l3,
--   ring, key, key2 (duo), colour, setColour(c), setOwned(b) }
function UI.candyRow(parent, opts)
	opts = opts or {}
	local kind = UI.ROW[opts.kind or "card"] and (opts.kind or "card") or "card"
	local P = UI.ROW[kind]
	local w, h = opts.w or P.w, opts.h or P.h
	local hasKey
	if opts.key == nil then hasKey = P.key ~= false else hasKey = opts.key ~= false end
	local ko = type(opts.key) == "table" and opts.key or {}
	local static = opts.static ~= false
	local R = 16
	local r = { kind = kind, w = w, h = h }
	r.button = new(static and "Frame" or "TextButton", {
		Name = opts.Name or "Row", BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h), Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero, ZIndex = opts.ZIndex or 1, LayoutOrder = opts.LayoutOrder or 0,
	}, nil)
	if not static then r.button.Text, r.button.AutoButtonColor = "", false end
	r.scale = new("UIScale", {}, r.button)
	r.shadow = UI.hardShadow(r.button, R, 4, 6, 1)
	r.face = new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, r.button)
	UI.corner(r.face, R)
	UI.stroke(r.face, 4)
	r.gloss = UI.gloss(r.face, { frac = 0.42, alpha = 0.62, inset = 4, radius = R - 4 })
	if opts.icon then
		local ic = P.icon or { 90, 8, 5 }
		local size, x, y = opts.iconSize or ic[1], opts.iconX or ic[2], opts.iconY or ic[3]
		r.iconSlot = { x = x, y = y, size = size }
		local glow = opts.glow
		if glow == nil then glow = P.glow end
		if glow then
			r.glow = new("ImageLabel", {
				Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow or "", ScaleType = Enum.ScaleType.Stretch,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + size / 2, y + size / 2),
				Size = UDim2.fromOffset(glow, glow), ImageTransparency = 0.15, ZIndex = 4,
			}, r.button)
		end
		r.icon = UI.icon(r.button, opts.icon, size, { Name = "Icon", Position = UDim2.fromOffset(x, y), ZIndex = 6, flat = opts.iconFlat })
		r.iconDrop = UI.iconDrop(r.icon, 4, 0.5)
	end
	local mid = opts.mid or { x = P.mid[1], w = P.mid[2] }
	r.midW = mid.w
	r.mid = new("Frame", {
		Name = "Mid", BackgroundTransparency = 1, Position = UDim2.fromOffset(mid.x, 0), Size = UDim2.fromOffset(mid.w, h), ZIndex = 7,
	}, r.button)
	r.lines = {}
	for i, ln in ipairs(P.lines) do
		r.lines[i] = new("Frame", {
			Name = "L" .. i, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, ln[1]), Size = UDim2.new(1, 0, 0, ln[2]),
		}, r.mid)
	end
	r.l1, r.l2, r.l3 = r.lines[1], r.lines[2], r.lines[3]
	-- owned: a gold band just inside the outline
	r.ring = new("Frame", {
		Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 9,
		Visible = false,
	}, r.button)
	UI.corner(r.ring, R - 4)
	UI.stroke(r.ring, 4, UI.RING)
	if hasKey then
		local base = P.key or { 196, 66, w - 212, math.floor((h - 66) / 2) }
		r.key = UI.candyKey(r.button, ko.colour or "grey", {
			Name = "Key", Size = UDim2.fromOffset(ko.w or base[1], ko.h or base[2]),
			Position = UDim2.fromOffset(ko.x or base[3], ko.y or base[4]), ZIndex = 10,
		})
		if P.key2 then
			local b2 = P.key2
			r.key2 = UI.candyKey(r.button, "green", {
				Name = "Key2", Size = UDim2.fromOffset(b2[1], b2[2]), Position = UDim2.fromOffset(b2[3], b2[4]), ZIndex = 10,
			})
		end
	end
	function r.setColour(c)
		r.colour = c
		UI.vgrad(r.face, UI.CANDY[c] or c)
	end
	function r.setOwned(b)
		r.owned = b == true
		r.ring.Visible = r.owned
	end
	r.setColour(opts.colour or "blue")
	r.button.Parent = parent
	return r
end

---------------------------------------------------------------- the window
-- the shop window (the snowball's genreWindow, Candy Brick branch, re-themed): an INK hard drop 9 px down carrying the
-- outline; an opaque lagoon body (UI.LAGOON) with an Ocean decor layer at the back (the shop fills it with bubbles
-- and light rays; it replaces the stud baseplate); a teal header with a gloss cap and a WAVE CREST along its bottom
-- edge (scallops of the header's colour, outlined, instead of the snowball's black rule); the gold title; the big icon
-- breaking out of the top-left corner with a hard drop; a red key X on the top-right corner.
-- opts: w, h, icon (a UI.ICONS / ShopIcons name) or emoji (a string), iconSize, iconPos (Vector2), headColour (a UI.HEAD
-- name or { top, bottom }; teal), headerH (74), titleSize (46), Name, ZIndex, Position.
-- Returns { root, shadow, body, ocean, header, crest, title, icon, iconDrop, close, w, h }
-- (close.button is a TextButton named "TextButton": TutorialController's closeButtonOf finds the X by that name.)
function UI.window(parent, title, opts)
	opts = opts or {}
	local w, h = opts.w or 800, opts.h or 580
	local hh = opts.headerH or 74
	local R = 24
	local root = new("Frame", {
		Name = opts.Name or "Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = opts.Position or UDim2.fromScale(0.5, 0.5), ZIndex = opts.ZIndex or 1,
		Active = true,
	}, parent)
	local shadow = new("Frame", { Name = "Shadow", BackgroundColor3 = UI.INK, Position = UDim2.fromOffset(0, 9), Size = UDim2.fromScale(1, 1), ZIndex = 1 }, root)
	UI.corner(shadow, R)
	UI.stroke(shadow, 5)
	local body = new("Frame", { Name = "Body", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2, Active = true }, root)
	UI.corner(body, R)
	UI.stroke(body, 5)
	UI.vgrad(body, UI.LAGOON)
	-- the decor layer: clipped to the body's rounded box, under everything else in it
	local ocean = new("Frame", {
		Name = "Ocean", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(0, hh),
		Size = UDim2.new(1, 0, 1, -hh), ZIndex = 1,
	}, body)
	-- the header: rounded on top, square where it meets the body (a flat patch in its bottom colour)
	local keys = UI.HEAD[opts.headColour or "teal"] or (type(opts.headColour) == "table" and opts.headColour) or UI.HEAD.teal
	local header = new("Frame", { Name = "Header", BackgroundColor3 = UI.WHITE, Size = UDim2.new(1, 0, 0, hh), ZIndex = 4 }, body)
	UI.corner(header, R)
	UI.vgrad(header, ColorSequence.new({
		ColorSequenceKeypoint.new(0, keys[1]), ColorSequenceKeypoint.new(0.7, keys[2]), ColorSequenceKeypoint.new(1, keys[2]),
	}))
	new("Frame", { Name = "Square", BackgroundColor3 = keys[2], Position = UDim2.new(0, 0, 1, -R), Size = UDim2.new(1, 0, 0, R), ZIndex = 4 }, header)
	UI.gloss(header, { frac = 0.46, alpha = 0.5, inset = 5, radius = R - 6, ZIndex = 5 })
	-- the wave crest: discs of the header's bottom colour hanging under it, each outlined; their tops hide behind the
	-- header, so only the scallops show. They touch at a point (step = diameter), so no outline crosses a scallop.
	local crest = new("Frame", { Name = "Crest", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, hh), Size = UDim2.new(1, 0, 0, 0), ZIndex = 3 }, body)
	local D = 26
	local n = math.ceil((w - 10) / D)
	local x0 = (w - n * D) / 2
	for i = 0, n - 1 do
		local disc = new("Frame", {
			Name = "Wave", BackgroundColor3 = keys[2], AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(x0 + i * D, -1),
			Size = UDim2.fromOffset(D, D), ZIndex = 3,
		}, crest)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
		UI.stroke(disc, 3.5)
	end
	-- the line where header and crest meet: the outline only shows under the scallops' gaps, so the header gets none
	local win = { root = root, shadow = shadow, body = body, ocean = ocean, header = header, crest = crest, w = w, h = h }
	local ts = opts.titleSize or 46
	win.title = UI.label(root, title, {
		Name = "Title", size = ts, align = "left", drop = 4, outline = 4.5 / ts, outlineColor = UI.TITLE.outline,
		Size = UDim2.fromOffset(w - 112 - 56, hh), Position = UDim2.fromOffset(112, 0), ZIndex = 8,
	})
	UI.vgrad(win.title, UI.TITLE.keys)
	if opts.icon then
		local size = opts.iconSize or 124
		local at = opts.iconPos or Vector2.new(-36, -44)
		win.icon = UI.icon(root, opts.icon, size, { Position = UDim2.fromOffset(at.X, at.Y), Rotation = -8, ZIndex = 9 })
		win.iconDrop = UI.iconDrop(win.icon, 5, 0.6)
	elseif opts.emoji then
		-- the fishing menus draw their icons as emoji: the same big breakout spot, as a scaled TextLabel (an emoji
		-- cannot be recoloured into a drop shadow, so it has none)
		local size = opts.iconSize or 124
		local at = opts.iconPos or Vector2.new(-36, -44)
		win.icon = new("TextLabel", {
			Name = "Icon", BackgroundTransparency = 1, Text = opts.emoji, TextScaled = true, FontFace = UI.FONT,
			TextColor3 = UI.WHITE, Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(at.X, at.Y),
			Rotation = -8, ZIndex = 9,
		}, root)
	end
	win.close = UI.candyKey(root, "red", {
		Name = "TextButton", Size = UDim2.fromOffset(60, 60), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -12, 0, 12), ZIndex = 10,
	})
	win.close.set(nil, "X", 34)
	return win
end

---------------------------------------------------------------- the device
-- phone = a small screen (its short side under 500 px, the fishing HUD's rule); landscape-locked game, so no portrait.
function UI.form()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local touch = game:GetService("UserInputService").TouchEnabled
	return { phone = math.min(vp.X, vp.Y) < 500, tablet = touch and math.min(vp.X, vp.Y) >= 500, cw = vp.X, ch = vp.Y }
end

return UI
