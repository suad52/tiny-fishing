--[==[
	LoadingScreen (ReplicatedFirst) - the curtain over the first seconds of a session.

	Replaces Roblox's default loading screen with the game's own: a sunny sea in the ShopKit look
	(INK outlines, FredokaOne, a candy progress bar). It is SELF-CONTAINED on purpose: a ReplicatedFirst
	script runs before ReplicatedStorage has arrived, so it cannot require ShopKit - the colours are copied.

	It stays up until the things the first frame of play needs are in:
		game.Loaded -> FishModels -> ShopIcons -> every Sound -> the character, Zone1 and Rowboat
		(GameClient blocks on both) -> MainMenu + leaderstats.
	The bar never runs ahead of MinSeconds (script attribute, default 3), so a fast load still reads as a
	smooth fill instead of a flash. MAX_SECONDS lets it go whatever happens, and a SKIP key shows after
	SKIP_AFTER on a slow connection.

	Input never leaks through: the curtain is an Active TextButton, so a click on it is gameProcessed
	and GameClient's cast guard ignores it. On exit it is yanked up off the screen like a reeled line,
	and publishes plr.LoadingDone = true for anything that wants to wait for it.
]==]

local Players           = game:GetService("Players")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

local MIN_SECONDS = tonumber(script:GetAttribute("MinSeconds")) or 3
local MAX_SECONDS = 45
local SKIP_AFTER  = 10
local WATER       = 0.53   -- the waterline, as a fraction of screen height
local FRONT_Y     = 12     -- front wave disc centres sit this far (design px) under the waterline = the sea's top

local INK     = Color3.fromRGB(8, 22, 44)
local WHITE   = Color3.new(1, 1, 1)
local FONT    = Enum.Font.FredokaOne
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local SEA_TOP = rgb(88, 200, 248)
local BACK    = rgb(140, 224, 252)

local function cs(...)
	local a, kp = { ... }, {}
	for i = 1, #a, 2 do table.insert(kp, ColorSequenceKeypoint.new(a[i], a[i + 1])) end
	return ColorSequence.new(kp)
end
local function ns(...)
	local a, kp = { ... }, {}
	for i = 1, #a, 2 do table.insert(kp, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(kp)
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for key, v in pairs(props) do o[key] = v end
	if parent then o.Parent = parent end
	return o
end
local function round(o, r) return new("UICorner", { CornerRadius = r or UDim.new(1, 0) }, o) end
local function ink(o, t, c, tr)
	return new("UIStroke", { Thickness = t, Color = c or INK, Transparency = tr or 0, LineJoinMode = Enum.LineJoinMode.Round }, o)
end
local function grad(o, seq, rot) return new("UIGradient", { Color = seq, Rotation = rot or 90 }, o) end
local function box(props, parent)
	props.BorderSizePixel = 0
	if props.BackgroundTransparency == nil then props.BackgroundTransparency = 0 end
	return new("Frame", props, parent)
end
local function disc(parent, x, y, d, color, z)
	local f = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d, d),
		BackgroundColor3 = color, ZIndex = z or 1 }, parent)
	round(f)
	return f
end
local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	return new("TextLabel", props, parent)
end

-- every scaled group registers here; relayout() keeps them at k (times their own factor)
local scales = {}
local function scaled(o, f)
	local sc = new("UIScale", {}, o)
	table.insert(scales, { sc = sc, f = f or 1 })
	return sc
end

------------------------------------------------------------------------------------------------ the gui
local gui = new("ScreenGui", {
	Name = "LoadingScreen", DisplayOrder = 1000, IgnoreGuiInset = true, ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
gui.Parent = pg
ReplicatedFirst:RemoveDefaultLoadingScreen()

local curtain = new("TextButton", {
	Name = "Curtain", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 38, 104), BorderSizePixel = 0,
	Text = "", AutoButtonColor = false, Active = true, Selectable = false,
}, gui)
curtain:SetAttribute("SndHooked", true)   -- AudioController: a click on the curtain is not a button press

local function layer(name, z)
	return new("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z }, curtain)
end

-- sky ---------------------------------------------------------------------------------------------
local sky = box({ Name = "Sky", Size = UDim2.new(1, 0, WATER, 4), BackgroundColor3 = WHITE, ZIndex = 1 }, curtain)
grad(sky, cs(0, rgb(64, 180, 252), 0.65, rgb(140, 222, 255), 1, rgb(204, 246, 255)))

local sun = new("Frame", { Name = "Sun", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.86, 0.16),
	Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 1, ZIndex = 1 }, sky)
scaled(sun)
local rays = new("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, sun)
for i = 0, 5 do
	local r = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 236),
		Rotation = i * 30, BackgroundColor3 = rgb(255, 240, 150), BackgroundTransparency = 0.35, ZIndex = 1 }, rays)
	round(r)
end
local glow = disc(sun, 120, 120, 172, rgb(255, 250, 210), 2)
glow.BackgroundTransparency = 0.45
local sunDisc = disc(sun, 120, 120, 118, WHITE, 3)
grad(sunDisc, cs(0, rgb(255, 246, 160), 1, rgb(255, 182, 24)))
ink(sunDisc, 5)
local sunGloss = disc(sun, 98, 98, 30, WHITE, 4)
sunGloss.Size = UDim2.fromOffset(34, 22)
sunGloss.Rotation = -35
sunGloss.BackgroundTransparency = 0.35

-- clouds: an INK copy of every puff, 5px bigger, drawn behind the white ones = one clean outline
local CLOUD = { { 110, 80, 190, 46 }, { 68, 64, 64, 64 }, { 118, 50, 84, 84 }, { 164, 68, 56, 56 } }
local clouds = {}
local function cloud(y, f, speed, x)
	local g = new("Frame", { Name = "Cloud", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x, y, 0),
		Size = UDim2.fromOffset(220, 120), BackgroundTransparency = 1, ZIndex = 2 }, sky)
	for pass = 1, 2 do
		for _, p in ipairs(CLOUD) do
			local grow = pass == 1 and 10 or 0
			local c = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p[1], p[2]),
				Size = UDim2.fromOffset(p[3] + grow, p[4] + grow), BackgroundColor3 = pass == 1 and INK or WHITE, ZIndex = pass }, g)
			round(c)
		end
	end
	table.insert(clouds, { g = g, y = y, speed = speed, x = x, sc = scaled(g, f) })
end
cloud(0.10, 0.95, 16, 180)
cloud(0.25, 0.7, 11, 760)
cloud(0.36, 0.55, 8, 1250)

-- water -------------------------------------------------------------------------------------------
local backInk, backFill   = layer("BackInk", 2), layer("BackFill", 3)
local frontInk, frontFill = layer("FrontInk", 4), layer("FrontFill", 5)
local floatL              = layer("Float", 6)
local sea = box({ Name = "Sea", BackgroundColor3 = WHITE, ZIndex = 7, ClipsDescendants = true }, curtain)
grad(sea, cs(0, SEA_TOP, 0.25, rgb(52, 160, 232), 0.65, rgb(22, 86, 190), 1, rgb(10, 38, 104)))
local surface = layer("Surface", 8)
local front   = layer("Front", 20)

-- the waves: rows of discs whose lower halves the sea body covers, so only scalloped crests show
local WAVES = {
	{ inkL = backInk,  fillL = backFill,  d = 46, gap = 0.72, y = -15,     speed = -14, line = 3.5, color = BACK },
	{ inkL = frontInk, fillL = frontFill, d = 62, gap = 0.72, y = FRONT_Y, speed = 22,  line = 5,   color = SEA_TOP },
}

-- light shafts swaying under the surface
local shafts = {}
for i, x in ipairs({ 0.14, 0.38, 0.63, 0.86 }) do
	local s = box({ Name = "Shaft", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, -6),
		Size = UDim2.new(0, 80, 1.3, 0), BackgroundColor3 = WHITE, ZIndex = 1 }, sea)
	-- fully clear where it meets the waterline, so the shaft fades in instead of starting on a hard edge
	new("UIGradient", { Rotation = 90, Transparency = ns(0, 1, 0.22, 0.74, 0.6, 0.9, 1, 1) }, s)
	table.insert(shafts, { f = s, base = 14 + i * 3, phase = i * 1.7, w = 60 + i * 12 })
end

-- the bobber, floating on the waterline at the end of a line from off-screen
local bob = new("Frame", { Name = "Bobber", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(80, 90),
	BackgroundTransparency = 1, ZIndex = 2 }, floatL)
scaled(bob)
local antenna = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(40, 12), Size = UDim2.fromOffset(9, 30),
	BackgroundColor3 = rgb(236, 36, 44), ZIndex = 1 }, bob)
round(antenna, UDim.new(0, 5))
ink(antenna, 3)
local body = disc(bob, 40, 54, 54, WHITE, 2)
grad(body, cs(0, rgb(255, 92, 92), 0.499, rgb(220, 18, 30), 0.5, WHITE, 1, rgb(214, 228, 244)))
ink(body, 4.5)
box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(40, 54), Size = UDim2.fromOffset(52, 4),
	BackgroundColor3 = INK, ZIndex = 3 }, bob)
local bobGloss = disc(bob, 29, 41, 14, WHITE, 4)
bobGloss.Size = UDim2.fromOffset(16, 9)
bobGloss.Rotation = -32
bobGloss.BackgroundTransparency = 0.25
local line = box({ Name = "Line", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = INK, BackgroundTransparency = 0.25,
	ZIndex = 1 }, floatL)

-- title -------------------------------------------------------------------------------------------
local title = new("Frame", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.25),
	Size = UDim2.fromOffset(900, 260), BackgroundTransparency = 1, ZIndex = 1 }, front)
scaled(title)
-- a word with a solid INK copy dropped behind it: the snowball's chunky 3D lettering
local function word(text, y, size, drop, seq, rot)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(900, size + 20), BackgroundTransparency = 1, Rotation = rot or 0 }, title)
	local shadow = label({ Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, drop), Text = text, TextSize = size,
		TextColor3 = INK, ZIndex = 1 }, holder)
	ink(shadow, size * 0.06)
	local face = label({ Size = UDim2.fromScale(1, 1), Text = text, TextSize = size, ZIndex = 2 }, holder)
	ink(face, size * 0.06)
	grad(face, seq)
	return holder
end
local tiny = word("TINY", 46, 78, 7, cs(0, rgb(255, 248, 170), 1, rgb(255, 168, 0)), -5)
word("FISHING", 156, 146, 11, cs(0, WHITE, 0.5, WHITE, 1, rgb(132, 226, 255)))

-- progress ----------------------------------------------------------------------------------------
local panel = new("Frame", { Name = "Progress", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.73),
	Size = UDim2.fromOffset(640, 140), BackgroundTransparency = 1 }, front)
scaled(panel)
local BAR_W, BAR_H = 600, 52
local outer = box({ Name = "Bar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22),
	Size = UDim2.fromOffset(BAR_W, BAR_H), BackgroundColor3 = INK }, panel)
round(outer)
local rim = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8),
	BackgroundColor3 = WHITE }, outer)
round(rim)
local trough = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8),
	BackgroundColor3 = rgb(12, 48, 108) }, rim)
round(trough)
local FILL_H, FILL_MAX = BAR_H - 24, BAR_W - 24
-- a CanvasGroup so the moving shine is clipped to the ROUNDED fill, not its bounding box
local fill = new("CanvasGroup", { Name = "Fill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0),
	Size = UDim2.fromOffset(FILL_H, FILL_H), BackgroundTransparency = 1, BorderSizePixel = 0 }, trough)
round(fill)
-- the gold lives on its own Frame: a UIGradient on the CanvasGroup itself would tint the gloss and shine too
grad(box({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 1 }, fill), cs(0, rgb(255, 240, 120), 1, rgb(255, 166, 0)))
local gloss = box({ Position = UDim2.new(0, 6, 0, 3), Size = UDim2.new(1, -12, 0.4, 0), BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.45, ZIndex = 2 }, fill)
round(gloss)
local shine = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 70, 1.6, 0),
	Rotation = 20, BackgroundColor3 = WHITE, ZIndex = 3 }, fill)
new("UIGradient", { Transparency = ns(0, 1, 0.5, 0.45, 1, 1) }, shine)
local pct = label({ Name = "Percent", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1), Text = "0%", TextSize = 26, ZIndex = 5 }, trough)
ink(pct, 3)

local statusRow = new("Frame", { Name = "Status", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92),
	Size = UDim2.fromOffset(640, 44), BackgroundTransparency = 1 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, statusRow)
local status = label({ Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Text = "Casting off",
	TextSize = 32, LayoutOrder = 1 }, statusRow)
ink(status, 3.5)
-- the dots live in their own fixed-width label so the centred line does not twitch as they count
local dots = label({ Size = UDim2.new(0, 34, 1, 0), Text = "", TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 2 }, statusRow)
ink(dots, 3.5)

-- tip pill ----------------------------------------------------------------------------------------
local TIPS = {
	"Steer the hook while it reels back up!",
	"Deeper water hides rarer fish.",
	"Every new zone pays more for each fish.",
	"Roll for better bait to find rarer fish.",
	"Rebirth for a permanent boost to fish value.",
	"Upgrade Hook Capacity to haul more fish at once.",
	"Spin the wheel for free prizes!",
}
local tipHolder = new("Frame", { Name = "Tip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22),
	Size = UDim2.fromOffset(900, 50), BackgroundTransparency = 1 }, front)
scaled(tipHolder)
local tipPill = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 48),
	AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, BackgroundTransparency = 0.3 }, tipHolder)
round(tipPill)
ink(tipPill, 2, WHITE, 0.75)
new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24) }, tipPill)
local tipText = label({ Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextSize = 24, RichText = true,
	Text = "" }, tipPill)
local tipN = math.random(#TIPS)
local function setTip()
	tipText.Text = '<font color="#FFE46E">TIP</font>   ' .. TIPS[tipN]
end
setTip()

-- skip key (slow connections only) ----------------------------------------------------------------
local skip = new("TextButton", { Name = "Skip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -18),
	Size = UDim2.fromOffset(150, 56), BackgroundColor3 = WHITE, BorderSizePixel = 0, AutoButtonColor = false,
	Text = "", Visible = false, ZIndex = 2 }, front)
round(skip, UDim.new(0, 16))
ink(skip, 4)
grad(skip, cs(0, rgb(104, 196, 246), 1, rgb(36, 112, 196)))
ink(label({ Size = UDim2.fromScale(1, 1), Text = "SKIP", TextSize = 28, ZIndex = 3 }, skip), 3)
scaled(skip)

------------------------------------------------------------------------------------------------ fish
-- 3D fish from the game's own FishModels, in ViewportFrames. Every model's head points +X, so a
-- camera on +Z sees it swim right and one on -Z sees it swim left.
local FISH = { "Clownfish", "Blue Tang", "Goldfish", "Pufferfish", "Koi", "Angelfish", "Mandarinfish", "Parrotfish",
	"Sea Turtle", "Lionfish", "Betta", "Tuna", "Swordfish", "Tilapia", "Rainbow Trout" }
local fishFolder
local function fishView(name, h, parent, z)
	local src = fishFolder and fishFolder:FindFirstChild(name)
	if not src then return nil end
	local m = src:Clone()
	local cf, sz = m:GetBoundingBox()
	m:PivotTo(cf:Inverse() * m:GetPivot())
	local aspect = math.clamp(sz.X / math.max(sz.Y, 0.1), 0.9, 3.2)
	local vf = new("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(h * aspect, h),
		BackgroundTransparency = 1, Ambient = rgb(214, 218, 226), LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(0.2, -1, 0), ZIndex = z or 1 }, parent)
	local cam = new("Camera", { FieldOfView = 30 }, vf)
	vf.CurrentCamera = cam
	m.Parent = vf
	local t = math.tan(math.rad(15))
	local dist = math.max(sz.Y / 2 / t, sz.X / 2 / (t * aspect)) * 1.1 + sz.Z / 2
	return { vf = vf, cam = cam, dist = dist, w = h * aspect }
end
local function aimFish(f, dir, wiggle)
	local a = wiggle
	local p = Vector3.new(math.sin(a) * f.dist, f.dist * 0.1, math.cos(a) * f.dist) * Vector3.new(dir, 1, dir)
	f.cam.CFrame = CFrame.lookAt(p, Vector3.zero)
end

local swimmers, bubbles = {}, {}
local barFish

------------------------------------------------------------------------------------------------ layout
local k, vw, vh, seaTop = 1, 0, 0, 0
local function buildWaves()
	for _, w in ipairs(WAVES) do
		if w.inkH then w.inkH:Destroy(); w.fillH:Destroy() end
		local d, sp = w.d * k, w.d * w.gap * k
		w.sp = sp
		local n = math.ceil(vw / sp) + 4
		w.inkH = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(n * sp, 0) }, w.inkL)
		w.fillH = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(n * sp, 0) }, w.fillL)
		for i = 0, n do
			disc(w.inkH, i * sp, 0, d + 2 * w.line * k, INK)
			disc(w.fillH, i * sp, 0, d, w.color)
		end
	end
end
local function relayout()
	local s = gui.AbsoluteSize
	if s.X < 50 or s.Y < 50 then return end
	if s.X == vw and s.Y == vh then return end
	vw, vh = s.X, s.Y
	k = math.clamp(math.min(vw / 1280, vh / 720), 0.42, 1.6)
	for _, e in ipairs(scales) do e.sc.Scale = k * e.f end
	seaTop = math.floor(vh * WATER + FRONT_Y * k)
	sea.Position = UDim2.fromOffset(0, seaTop)
	sea.Size = UDim2.fromOffset(vw, vh - seaTop + 2)
	for _, sh in ipairs(shafts) do sh.f.Size = UDim2.new(0, sh.w * k, 1.3, 0) end
	buildWaves()
end
relayout()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

------------------------------------------------------------------------------------------------ loading
local STEPS = {
	{ text = "Casting off",         w = 1 },
	{ text = "Waking up the fish",  w = 4 },
	{ text = "Polishing the lures", w = 2 },
	{ text = "Tuning the waves",    w = 1.5 },
	{ text = "Rowing out to sea",   w = 2.5 },
	{ text = "Setting up the deck", w = 1 },
}
local TOTAL = 0
for _, s in ipairs(STEPS) do TOTAL += s.w end
local stepIdx, stepFrac, loaded = 1, 0, false
local function target()
	if loaded then return 1 end
	local done = 0
	for i = 1, stepIdx - 1 do done += STEPS[i].w end
	return (done + STEPS[stepIdx].w * math.clamp(stepFrac, 0, 1)) / TOTAL
end
local function report(f) stepFrac = math.max(stepFrac, f) end

local function preloadChildren(folder)
	if not folder then return end
	local kids = folder:GetChildren()
	local CH = 6
	for i = 1, #kids, CH do
		local chunk = table.move(kids, i, math.min(i + CH - 1, #kids), 1, {})
		pcall(ContentProvider.PreloadAsync, ContentProvider, chunk)
		report((i + CH - 1) / #kids)
	end
end

local WORK = {
	function()
		if not game:IsLoaded() then game.Loaded:Wait() end
	end,
	function()
		fishFolder = ReplicatedStorage:WaitForChild("FishModels", 20)
		preloadChildren(fishFolder)
	end,
	function()
		preloadChildren(ReplicatedStorage:WaitForChild("ShopIcons", 10))
	end,
	function()
		local list = {}
		for _, root in ipairs({ game:GetService("SoundService"), ReplicatedStorage, workspace }) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Sound") then table.insert(list, d) end
			end
		end
		if #list == 0 then return end
		local n = 0
		pcall(ContentProvider.PreloadAsync, ContentProvider, list, function()
			n += 1
			report(n / #list)
		end)
	end,
	function()
		local deadline = os.clock() + 20
		while not plr.Character and os.clock() < deadline do task.wait(0.1) end
		report(0.3)
		workspace:WaitForChild("Zone1", 15)
		report(0.55)
		workspace:WaitForChild("Rowboat", 10)
		report(0.75)
		local hrp = plr.Character and plr.Character:WaitForChild("HumanoidRootPart", 5)
		if hrp then pcall(function() plr:RequestStreamAroundAsync(hrp.Position, 8) end) end
	end,
	function()
		pg:WaitForChild("MainMenu", 10)
		report(0.5)
		plr:WaitForChild("leaderstats", 10)
		task.wait(0.3)   -- one beat for GameClient to build the HUD under the curtain
	end,
}
task.spawn(function()
	for i, fn in ipairs(WORK) do
		stepIdx, stepFrac = i, 0
		local ok, err = pcall(fn)
		if not ok then warn("[LoadingScreen] step " .. i .. ": " .. tostring(err)) end
		stepFrac = 1
	end
	loaded = true
end)

------------------------------------------------------------------------------------------------ motion
local t0 = os.clock()
local shown, finished = 0, false
local nextFish, nextBubble, nextTip = 0.4, 0, 4.5
local conn

local function spawnFish(midScreen)
	if not fishFolder or #swimmers >= 6 or vw == 0 then return end
	local dir = math.random() < 0.5 and 1 or -1
	local depth = 0.14 + math.random() * 0.74
	local h = (52 + math.random() * 44) * k
	local f = fishView(FISH[math.random(#FISH)], h, sea, 2)
	if not f then return end
	f.dir, f.depth, f.phase = dir, depth, math.random() * 6
	f.speed = (55 + math.random() * 45) * k
	f.x = midScreen and (0.1 + math.random() * 0.8) * vw or (dir == 1 and -f.w or vw + f.w)
	-- deeper fish sit further into the blue
	f.vf.ImageColor3 = WHITE:Lerp(rgb(150, 196, 240), depth * 0.45)
	table.insert(swimmers, f)
end

local function spawnBubble()
	if #bubbles >= 28 or vw == 0 then return end
	local d = (5 + math.random() * 11) * k
	local b = disc(sea, 0, 0, d, WHITE, 3)
	b.BackgroundTransparency = 0.82
	ink(b, math.max(1, 1.6 * k), WHITE, 0.2)
	table.insert(bubbles, { f = b, x = math.random() * vw, y = vh - seaTop + d, speed = (36 + math.random() * 50) * k,
		amp = (3 + math.random() * 8) * k, phase = math.random() * 6 })
end

local function finish()
	if finished then return end
	finished = true
	status.Text, dots.Text = "Ready to fish!", ""
	pct.Text = "100%"
	task.delay(0.4, function()
		local tw = TweenService:Create(curtain, TweenInfo.new(0.85, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0, -1.2) })
		tw:Play()
		tw.Completed:Wait()
		if conn then conn:Disconnect() end
		gui:Destroy()
		plr:SetAttribute("LoadingDone", true)
	end)
end
skip.Activated:Connect(finish)

conn = RunService.RenderStepped:Connect(function(dt)
	if vw == 0 then relayout() return end
	local now = os.clock() - t0

	-- progress: never ahead of the MinSeconds pace, so even an instant load reads as a fill
	local goal = math.min(target(), now / MIN_SECONDS)
	if finished then goal = 1 end
	shown += (goal - shown) * math.min(1, dt * 5)
	if goal - shown < 0.002 then shown = goal end
	fill.Size = UDim2.fromOffset(FILL_H + (FILL_MAX - FILL_H) * shown, FILL_H)
	shine.Position = UDim2.new((now * 0.55) % 1.6 - 0.3, 0, 0.5, 0)
	if not finished then
		pct.Text = math.floor(shown * 100 + 0.5) .. "%"
		local acc, txt = 0, STEPS[#STEPS].text
		for _, st in ipairs(STEPS) do
			acc += st.w / TOTAL
			if shown < acc - 1e-3 then txt = st.text break end
		end
		status.Text = txt
		dots.Text = string.rep(".", 1 + math.floor(now * 2.5) % 3)
		if (loaded and shown >= 0.999) or now > MAX_SECONDS then finish() end
		if now > SKIP_AFTER and not skip.Visible then skip.Visible = true end
	end

	-- sky
	rays.Rotation = now * 9
	glow.BackgroundTransparency = 0.45 + math.sin(now * 2) * 0.08
	for _, c in ipairs(clouds) do
		c.x += c.speed * k * dt
		local half = 120 * c.sc.Scale
		if c.x - half > vw then c.x = -half end
		c.g.Position = UDim2.new(0, c.x, c.y, 0)
	end
	title.Rotation = math.sin(now * 1.2) * 1.6
	title.Position = UDim2.new(0.5, 0, 0.25, math.sin(now * 1.7) * 5 * k)
	tiny.Rotation = -5 + math.sin(now * 2.4) * 2

	-- waves scroll in opposite directions and breathe a little
	local waterY = vh * WATER
	for i, w in ipairs(WAVES) do
		if w.sp then
			local off = (now * w.speed * k) % w.sp
			local p = UDim2.fromOffset(off - 2 * w.sp, waterY + (w.y + math.sin(now * 1.3 + i * 2) * 2) * k)
			w.inkH.Position = p
			w.fillH.Position = p
		end
	end
	for _, sh in ipairs(shafts) do sh.f.Rotation = sh.base + math.sin(now * 0.45 + sh.phase) * 5 end

	-- bobber
	local bx, by = vw * 0.17, seaTop - 24 * k + math.sin(now * 2.2) * 4 * k
	bob.Position = UDim2.fromOffset(bx, by)
	bob.Rotation = math.sin(now * 1.6) * 7
	local p0, p1 = Vector2.new(bx - 150 * k, -20), Vector2.new(bx, by - 33 * k)
	local dv = p1 - p0
	line.Position = UDim2.fromOffset((p0.X + p1.X) / 2, (p0.Y + p1.Y) / 2)
	line.Size = UDim2.fromOffset(dv.Magnitude, math.max(1.5, 2.2 * k))
	line.Rotation = math.deg(math.atan2(dv.Y, dv.X))

	-- sea life
	if fishFolder and not barFish then
		barFish = fishView("Clownfish", 46, outer, 8) or false
		for _ = 1, 3 do spawnFish(true) end
	end
	if barFish then
		barFish.vf.Position = UDim2.fromOffset(8 + FILL_H + (FILL_MAX - FILL_H) * shown, -7 + math.sin(now * 5) * 2)
		aimFish(barFish, 1, math.sin(now * 9) * 0.22)
	end
	if now > nextFish then
		nextFish = now + 1.4 + math.random() * 1.4
		spawnFish(false)
	end
	for i = #swimmers, 1, -1 do
		local f = swimmers[i]
		f.x += f.dir * f.speed * dt
		f.vf.Position = UDim2.fromOffset(f.x, (vh - seaTop) * f.depth + math.sin(now * 1.8 + f.phase) * 6 * k)
		aimFish(f, f.dir, math.sin(now * 7 + f.phase) * 0.2)
		if f.x < -f.w * 1.2 or f.x > vw + f.w * 1.2 then
			f.vf:Destroy()
			table.remove(swimmers, i)
		end
	end
	if now > nextBubble then
		nextBubble = now + 0.16
		spawnBubble()
	end
	for i = #bubbles, 1, -1 do
		local b = bubbles[i]
		b.y -= b.speed * dt
		b.f.Position = UDim2.fromOffset(b.x + math.sin(now * 3 + b.phase) * b.amp, b.y)
		if b.y < -20 then
			b.f:Destroy()
			table.remove(bubbles, i)
		end
	end

	-- tips
	if now > nextTip and not finished then
		nextTip = now + 4.5
		local out = TweenService:Create(tipText, TweenInfo.new(0.2), { TextTransparency = 1 })
		out:Play()
		out.Completed:Once(function()
			tipN = tipN % #TIPS + 1
			setTip()
			TweenService:Create(tipText, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
		end)
	end
end)
