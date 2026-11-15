--[==[
	SettingsController — fishing-game "Settings" (sea candy edition)

	Two tabs and a jump:
	    ⚡ Performance — quality preset + the effect toggles that cost frames
	    🔊 Audio       — master + per-channel volume sliders, mute
	    💬 Feedback    — not a tab: one tap closes Settings and opens StarterGui.FeedbackMenu

	STATE:  every setting is a player attribute `Set_<key>` (same convention as
	Zone_<id> / Perk_<key>).  Any script can read one, and changing an attribute
	from anywhere re-applies it + refreshes the UI, so the console is a free test
	hook:  game.Players.<you>:SetAttribute("Set_Shadows", false)

	Settings are applied CLIENT-side (graphics + volume are per-player). They do
	not survive a rejoin: there is no save layer yet. If a RemoteEvent shows up at
	ReplicatedStorage.SettingsRemotes.Save this fires the whole table at it.

	Test hook: SettingsMenu.DevSetting:Fire(key, value) / :Fire("__RESET__") / :Fire("__OPEN__")

	2026-10-10 — THE LOOK MOVED ONTO ReplicatedStorage.ShopKit (the Shop's "sea candy" kit, ported from the +1
	snowball game). The owner asked for every MenuBar menu to share the Shop's theme, and this one was still on the
	old "cartoon reef" recipe (DEEP_TOP/MID/BOT panels, pale cards, thin GothamMedium copy). Now: UI.window (lagoon
	body, navy header with gloss + wave crest, gold title, the ⚙️ breaking out of the top-left corner, the red key
	X); every setting is a candy slab in its own UI.CANDY colour with its emoji on the soft glow; toggles are candy
	switches (green ON / grey OFF); sliders are a gold fill in an INK trough with a navy value chip; presets and
	tabs are candy keys (gold = the preset in force / the page you are on, sea = the rest, green = the Feedback
	jump); the Shop's gold scroll thumb on its INK track; the Shop's in-window toast; bubbles + rays in win.ocean.
	NOTHING A SETTING DOES CHANGED: same Set_<key> attributes, appliers, presets, save hook, DevSetting verbs,
	TouchKit.press on every control, MenuFit + the phone branch, Backpack hiding, the Feedback hand-off.
	  * The layout is manual now (no UIListLayout): TouchKit pads need layout-free hosts, and ShopKit's keys centre
	    their line from Size.X.Offset - so every width-dependent offset is re-derived in V.lay(w) whenever the
	    phone branch changes the design width.
	  * fit() also keeps the window's REACH (the ⚙️ 44 px above the box, the X 18 px past its right edge, the 9 px
	    drop) on screen and under the top bar - the old window had nothing poking out. Shorter, not smaller
	    (MenuFit's rule): the list gives up height first, down to MIN_H; the scale drops only when that is not
	    enough. 1313x751: still x1.058, the window 594 tall instead of 660, 47 px below the middle.
	  * The tab keys keep their names (perf / audio / feedback). The only "TextButton" is the window's X.
	Pre-restyle source: ServerStorage.MenuBackup_PreCandy_2026-10-10.SettingsController (a StringValue).
]==]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- The Shop's kit (window, candy rows / keys / chips, labels, palettes). Shared - never edit it from a menu.
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))

local plr = Players.LocalPlayer
local gui = script.Parent

local rgb = Color3.fromRGB
local make = UI.new

----------------------------------------------------------------------
-- setting definitions
--   every emoji here is <= Unicode 11.0 — newer ones render as tofu. The two
--   text-presentation glyphs (☁ U+2601, 🖱 U+1F5B1) carry U+FE0F so they ask for
--   the colour emoji, the way the MenuBar's ⚙️ does.
--   candy = the slab's UI.CANDY colour, one per setting, picked so the emoji does
--   not vanish into it (a green emoji on a green slab disappears).
----------------------------------------------------------------------
local DEFS = {
	-- ⚡ Performance
	{ key="PostFX",     tab="perf",  kind="toggle", def=true,  icon="✨", candy="purple",  name="Post-Processing",    desc="Bloom, sun rays and depth of field." },
	{ key="Atmos",      tab="perf",  kind="toggle", def=true,  icon="\u{2601}\u{FE0F}", candy="royal", name="Atmosphere & Fog", desc="Hazy distance fog out over the water." },
	{ key="Shadows",    tab="perf",  kind="toggle", def=true,  icon="🌓", candy="teal",    name="Shadows",            desc="Real-time shadows cast by the sun." },
	{ key="Particles",  tab="perf",  kind="toggle", def=true,  icon="🔥", candy="blue",    name="Particle Effects",   desc="Campfire, rod embers, smoke and sparkles." },
	{ key="WaterFX",    tab="perf",  kind="toggle", def=true,  icon="🌊", candy="emerald", name="Water Effects",      desc="Ocean waves and surface reflections." },
	{ key="MenuFX",     tab="perf",  kind="toggle", def=true,  icon="🎬", candy="pink",    name="Menu Animations",    desc="Bubbles, god rays and marquee lights in menus." },
	{ key="Blur",       tab="perf",  kind="toggle", def=true,  icon="💧", candy="orange",  name="Menu Blur",          desc="Blur the world behind an open menu." },
	{ key="HideOthers", tab="perf",  kind="toggle", def=false, icon="👥", candy="coral",   name="Hide Other Players", desc="Hide other anglers to claw back frames." },
	-- 🔊 Audio
	{ key="Mute",       tab="audio", kind="toggle", def=false, icon="🔇", candy="red",     name="Mute All",           desc="Silence every sound in the game." },
	{ key="VolMaster",  tab="audio", kind="slider", def=70, min=0, max=100, icon="🔊", candy="orange",  name="Master Volume",  desc="Overall loudness of everything." },
	{ key="VolMusic",   tab="audio", kind="slider", def=55, min=0, max=100, icon="🎵", candy="cyan",    name="Music",          desc="Background music tracks." },
	{ key="VolSFX",     tab="audio", kind="slider", def=80, min=0, max=100, icon="🎣", candy="emerald", name="Sound Effects",  desc="Casts, splashes, bites and catches." },
	{ key="VolUI",      tab="audio", kind="slider", def=70, min=0, max=100, icon="\u{1F5B1}\u{FE0F}", candy="purple", name="Interface", desc="Button clicks and menu sounds." },
	{ key="VolAmb",     tab="audio", kind="slider", def=60, min=0, max=100, icon="🐦", candy="pink",    name="Ambience",       desc="Waves, wind and distant seagulls." },
}
local DEF_BY_KEY = {}
for _, d in ipairs(DEFS) do DEF_BY_KEY[d.key] = d end

-- quality presets: one click sets every effect toggle at once
local PRESET_KEYS = { "PostFX", "Atmos", "Shadows", "Particles", "WaterFX", "MenuFX", "Blur" }
local PRESETS = {
	{ key="potato", icon="🥔", name="Potato",
	  vals={ PostFX=false, Atmos=false, Shadows=false, Particles=false, WaterFX=false, MenuFX=false, Blur=false } },
	{ key="low",    icon="🐟", name="Low",
	  vals={ PostFX=false, Atmos=false, Shadows=false, Particles=true,  WaterFX=false, MenuFX=true,  Blur=false } },
	{ key="med",    icon="🐬", name="Medium",
	  vals={ PostFX=true,  Atmos=true,  Shadows=false, Particles=true,  WaterFX=true,  MenuFX=true,  Blur=false } },
	{ key="high",   icon="🐋", name="High",
	  vals={ PostFX=true,  Atmos=true,  Shadows=true,  Particles=true,  WaterFX=true,  MenuFX=true,  Blur=true  } },
}

----------------------------------------------------------------------
-- state (player attributes)
----------------------------------------------------------------------
local function get(key)
	local v = plr:GetAttribute("Set_" .. key)
	if v == nil then return DEF_BY_KEY[key].def end
	return v
end
local function set(key, v) plr:SetAttribute("Set_" .. key, v) end
for _, d in ipairs(DEFS) do
	if plr:GetAttribute("Set_" .. d.key) == nil then plr:SetAttribute("Set_" .. d.key, d.def) end
end

-- optional server save hook (debounced) — no-op until a save layer exists
local saveQueued = false
local function save()
	if saveQueued then return end
	saveQueued = true
	task.delay(0.4, function()
		saveQueued = false
		local rem = ReplicatedStorage:FindFirstChild("SettingsRemotes")
		local ev  = rem and rem:FindFirstChild("Save")
		if ev and ev:IsA("RemoteEvent") then
			local t = {}
			for _, d in ipairs(DEFS) do t[d.key] = get(d.key) end
			pcall(function() ev:FireServer(t) end)
		end
	end)
end

----------------------------------------------------------------------
-- APPLIERS — the part that actually changes the game
----------------------------------------------------------------------

-- ✨ post-processing. Skips ZoneColorCorrection (that's the zone's look, not a
-- cost) and MenuBlur (owned by the Blur setting / MenuBlurManager).
local function applyPostFX()
	local on = get("PostFX") == true
	for _, d in ipairs(Lighting:GetChildren()) do
		if d:IsA("BloomEffect") or d:IsA("SunRaysEffect") or d:IsA("DepthOfFieldEffect") then
			d.Enabled = on
		end
	end
end

-- 🌁 atmosphere. ZonesController tweens Density/Haze/Glare per zone, so cache
-- whatever the zone asked for and restore it when the setting comes back on.
local atmCache = nil
local function applyAtmos()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then return end
	if get("Atmos") == true then
		if atmCache then
			atm.Density, atm.Haze, atm.Glare = atmCache.d, atmCache.h, atmCache.g
			atmCache = nil
		end
	else
		if not atmCache then atmCache = { d = atm.Density, h = atm.Haze, g = atm.Glare } end
		atm.Density, atm.Haze, atm.Glare = 0, 0, 0
	end
end

-- 🌊 water. Same cache dance — the zone owns WaterColor/Transparency (look), we
-- only touch waves + reflectance (cost).
local waterCache = nil
local function applyWater()
	local T = workspace:FindFirstChildOfClass("Terrain")
	if not T then return end
	if get("WaterFX") == true then
		if waterCache then
			T.WaterWaveSize, T.WaterWaveSpeed, T.WaterReflectance = waterCache.s, waterCache.sp, waterCache.r
			waterCache = nil
		end
	else
		if not waterCache then waterCache = { s = T.WaterWaveSize, sp = T.WaterWaveSpeed, r = T.WaterReflectance } end
		T.WaterWaveSize, T.WaterWaveSpeed, T.WaterReflectance = 0, 0, 0
	end
end

-- travelling to a zone re-tweens atmosphere + water; re-assert the settings once
-- the 0.85s zone tween has landed (and re-capture the new zone's values).
plr:GetAttributeChangedSignal("CurrentZone"):Connect(function()
	task.delay(0.95, function()
		atmCache, waterCache = nil, nil   -- forget the old zone's cached values
		applyAtmos(); applyWater()
	end)
end)

local function applyShadows()
	Lighting.GlobalShadows = get("Shadows") == true
end

-- 🔥 particles / fire / trails
local function isVfx(d)
	return d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
		or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
end
local function applyParticles()
	local on = get("Particles") == true
	for _, d in ipairs(workspace:GetDescendants()) do
		if isVfx(d) then d.Enabled = on end
	end
	local bp = plr:FindFirstChildOfClass("Backpack")
	if bp then
		for _, d in ipairs(bp:GetDescendants()) do
			if isVfx(d) then d.Enabled = on end
		end
	end
end
-- rods get equipped/cloned in at runtime — catch their emitters as they arrive
workspace.DescendantAdded:Connect(function(d)
	if isVfx(d) then d.Enabled = get("Particles") == true end
end)

-- 👥 other players
local function applyHideOthers()
	local on = get("HideOthers") == true
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= plr and p.Character then
			for _, d in ipairs(p.Character:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = on and 1 or 0
				end
			end
		end
	end
end
local function watchPlayer(p)
	if p == plr then return end
	p.CharacterAdded:Connect(function() task.wait(0.35); applyHideOthers() end)
end
for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
Players.PlayerAdded:Connect(function(p) watchPlayer(p); task.wait(0.35); applyHideOthers() end)

-- 🔊 audio. The bus is SoundService.Master with Music/SFX/UI/Ambient parented
-- INSIDE it (SoundGroups nest by parenting — they have no .SoundGroup property),
-- so effective volume is Master * channel. Lookups are recursive for that reason.
-- Sounds with no group get routed to SFX so nothing escapes the sliders.
local function findGroup(name)
	local g = SoundService:FindFirstChild(name, true)
	if g and g:IsA("SoundGroup") then return g end
	return nil
end
local function applyAudio()
	local master = findGroup("Master")
	if master then
		master.Volume = (get("Mute") == true) and 0 or (get("VolMaster") / 100)
	end
	local chans = { Music = "VolMusic", SFX = "VolSFX", UI = "VolUI", Ambient = "VolAmb" }
	for name, key in pairs(chans) do
		local g = findGroup(name)
		if g then g.Volume = get(key) / 100 end
	end
end
local function routeSound(s)
	if s:IsA("Sound") and s.SoundGroup == nil then
		local sfx = findGroup("SFX")
		if sfx then s.SoundGroup = sfx end
	end
end
for _, root in ipairs({ workspace, SoundService, ReplicatedStorage, plr }) do
	for _, d in ipairs(root:GetDescendants()) do routeSound(d) end
end
workspace.DescendantAdded:Connect(routeSound)
SoundService.DescendantAdded:Connect(routeSound)

-- MenuFX / Blur need no applier here: the menus' RenderStepped decor loops and
-- MenuBlurManager read the Set_MenuFX / Set_Blur attributes themselves.
local APPLY = {
	PostFX     = applyPostFX,
	Atmos      = applyAtmos,
	Shadows    = applyShadows,
	Particles  = applyParticles,
	WaterFX    = applyWater,
	HideOthers = applyHideOthers,
	Mute       = applyAudio,
	VolMaster  = applyAudio,
	VolMusic   = applyAudio,
	VolSFX     = applyAudio,
	VolUI      = applyAudio,
	VolAmb     = applyAudio,
}

----------------------------------------------------------------------
-- window (ShopKit's UI.window - the Shop's shell, in this menu's navy)
----------------------------------------------------------------------
local WIN_W, WIN_H = 980, 660
local V = {}   -- every view object hangs off this one table (Luau's 200-locals cap)
-- Design px. ROW_H: a setting's slab; TEXT_X: where its name starts (after the emoji on its glow); GAP: slab to
-- slab (its 6 px drop + outline + air); SW: the toggle switch; LIST_Y: where the scroll list starts under the
-- tab keys. REACH: how far the window's art pokes past its own box - the ⚙️ above the top-left corner, the X
-- past the top-right one, the drop under the body. fit() keeps all of it on screen and under the top bar.
local K = {
	ROW_H = 88, TEXT_X = 96, GAP = 18,
	SW = { w = 116, h = 50, knob = 40 },
	HEAD_H = { desk = 74, phone = 58 },
	TAB = { desk = { y = 96, h = 54 }, phone = { y = 78, h = 44 } },
	LIST_Y = { desk = 166, phone = 136 },
	REACH = { up = 44, down = 9, left = 36, right = 18, upPhone = 20, leftPhone = 0 },
	-- 2026-10-11 (the owner: "centered to the phone screen"): on a phone the ⚙️ sits INSIDE the 58 px header instead
	-- of breaking out, so nothing pokes left of the box (leftPhone 0) and upPhone only covers the X's 18 now.
	ICON_PHONE = { size = 54, x = 8, y = 2 },
}

-- the scrim: a full-screen BUTTON behind the window (a Frame would let the tap through and cast the rod behind
-- the menu) - a tap anywhere outside the window closes Settings
local backdrop = make("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(4, 4), ZIndex = 1,
}, gui)

V.win = UI.window(gui, "SETTINGS", {
	Name = "Window", w = WIN_W, h = WIN_H, emoji = "\u{2699}\u{FE0F}", headColour = "navy", ZIndex = 5,
})
V.crestW = WIN_W
local root = V.win.root
local uiscale = make("UIScale", { Scale = 1 }, root)

-- The window catches its own taps (an Active Frame does NOT stop the Backdrop under it): transparent, silent
-- ClickGuard buttons with no handler over the body + its drop (ZIndex 3: over Shadow / Body, under the tabs,
-- the list, the title, the ⚙️ and the X) and over the big ⚙️. SndHooked is set before they are parented, so
-- AudioController gives them no click.
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
if V.win.icon then clickGuard(V.win.icon, UDim2.new(1, 0, 1, 5), 20) end

-- the tagline, right of the title on the header (hidden when the header is too narrow for it)
V.sub = UI.label(root, "Turn effects off to reel in more frames", {
	Name = "Subtitle", size = 22, align = "right", drop = 2, outline = 0.15,
	Size = UDim2.fromOffset(580, 30), Position = UDim2.fromOffset(344, 22), ZIndex = 8,
})

-- Shared with every other pop-up window in the game. On a small screen it makes the window
-- SHORTER rather than smaller, so the WIDTH drives the scale and centres it below the Roblox
-- top bar instead of underneath it. Desktop and iPad keep the original call.
-- MIN_H: the list is the only thing that shrinks with the height (everything above LIST_Y is
-- fixed chrome, the toast is bottom-anchored), so nothing can poke out at any height above
-- LIST_Y + 14; 430 keeps the same ~250 px of list the old binary-searched 420 left.
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
local MIN_H = 430
-- PHONE LAYOUT (short side < 500). On a phone the window is authored at the width that fills
-- the safe area at CMP.s (20px margin each side) and as tall as the band under the top bar
-- (less 20 px of reach above the window and the drop below it), so MenuFit settles on exactly
-- CMP.s - then MenuFit.centre centres it on the screen, a little smaller (see fit()). The phone
-- chrome (shorter header, the ⚙️ tucked inside it, shorter tab keys, icon-only reset, taller
-- slider grab areas) is set in V.lay via CMP.apply, re-decided on EVERY fit(), which runs on
-- open and on every viewport change, never once at build time.
-- maxS = CMP.s also pins MenuFit to its adaptive branch (its desktop branch starts at 0.85).
local CMP = { s = 0.8, on = nil, w = nil, apply = nil, hits = {} }

-- the bottom of the Roblox top bar (+4): nothing of the window may reach above it
function V.barBottom()
	local bar = GuiService:GetGuiInset().Y
	local ok, ti = pcall(function() return GuiService.TopbarInset end)
	if ok and ti then bar = math.max(bar, ti.Max.Y) end
	return bar + 4
end

-- MenuFit places the window BOX; the ⚙️ breaks out 44 px above it, the X 18 px past its right edge and
-- the drop 9 px below. Keep all of that on screen and under the top bar: sideways only the scale can
-- give; vertically the window first gets SHORTER (only the list shrinks, never below minH) and the
-- scale drops only if that is not enough; then it slides into the free band.
function V.keepReach(vp, phone, minH)
	if vp.X < 100 or vp.Y < 100 then return end
	local s = uiscale.Scale
	if not (s > 0) then return end
	local R = K.REACH
	local W, H = root.Size.X.Offset, root.Size.Y.Offset
	local up, down = phone and R.upPhone or R.up, R.down
	local side = math.max(phone and R.leftPhone or R.left, R.right)
	local top, bottom = V.barBottom(), vp.Y - 4
	s = math.min(s, (vp.X / 2 - 4) / (W / 2 + side))
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
	cy = math.clamp(cy, lo, hi)
	root.Position = UDim2.new(0.5, 0, 0, math.floor(cy + 0.5))
end

local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
	local phone = vp.X >= 100 and vp.Y >= 100 and math.min(vp.X, vp.Y) < 500
	if phone then
		local reach = (K.REACH.upPhone + K.REACH.down) * CMP.s
		local availH = math.max(160, vp.Y - V.barBottom() - 4 - reach)
		local w = math.clamp(math.floor((vp.X - 40) / CMP.s), 700, 1200)
		local h = math.clamp(math.floor(availH / CMP.s), 300, WIN_H)
		if CMP.apply then CMP.apply(true, w) end
		MenuFit.apply(root, uiscale, w, h, 0.4, CMP.s, h)
		V.keepReach(vp, true, h)
		-- 2026-10-11, the owner: "make the button uis centered to the phone screen". The ⚙️ is tucked into the
		-- header (V.lay), so nothing reaches above the window's top-left: up = 0 (the X rises into the top bar's free
		-- region). Centred, the window comes out 10-14% smaller than the band-under-the-top-bar layout it replaces.
		MenuFit.centre(root, uiscale, 0, K.REACH.down)
	else
		if CMP.apply then CMP.apply(false, WIN_W) end
		MenuFit.apply(root, uiscale, WIN_W, WIN_H, 0.4, 1.1, MIN_H)
		V.keepReach(vp, false, MIN_H)
		MenuFit.centre(root, uiscale, K.REACH.up, K.REACH.down)   -- centred on the screen
	end
end

----------------------------------------------------------------------
-- the sea behind the rows (the Shop's): light rays + rising bubbles in the window's Ocean layer. One
-- loop (below), idle while Settings is shut or Menu Animations are off (its own Set_MenuFX).
----------------------------------------------------------------------
V.rays, V.bubbles = {}, {}
for i, x in ipairs({ 0.1, 0.3, 0.52, 0.74, 0.92 }) do
	local ray = make("Frame", {
		Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
		Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
	}, V.win.ocean)
	make("UIGradient", {
		Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
		}),
	}, ray)
	table.insert(V.rays, { f = ray, phase = i * 1.3 })
end
for i = 1, 22 do
	local s = 6 + (i * 7) % 13
	local b = make("Frame", {
		Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(s, s), ZIndex = 2,
	}, V.win.ocean)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	make("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
	table.insert(V.bubbles, { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i })
end
for _, b in ipairs(V.bubbles) do b.f.Position = UDim2.new(b.x, 0, b.y, 0) end

----------------------------------------------------------------------
-- toast (the Shop's: a keycap chip at the bottom of the window)
----------------------------------------------------------------------
V.toast = UI.chip(root, "navy", {
	Name = "Toast", height = 50, textSize = 24, pad = 26, minWidth = 240, AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18), ZIndex = 40,
})
V.toast.block.root.Visible = false
V.toastScale = make("UIScale", {}, V.toast.block.root)
local toastToken = 0
-- kind: "good" (green), "info" (gold), "bad" (red), else navy
local function showToast(text, kind)
	local colour = ({ good = "green", info = "gold", bad = "red" })[kind or ""] or "navy"
	V.toast.set(text, colour)
	local b = V.toast.block.root
	b.Visible = true
	UI.punch(V.toastScale, 0.6, 0.28)
	toastToken += 1
	local my = toastToken
	task.delay(2.2, function()
		if my == toastToken then b.Visible = false end
	end)
end

-- a candy key's one line, with an emoji at its head. ShopKit's setParts lays out icons and text, but an emoji is
-- text that must not get the INK outline or the hard drop (a colour glyph would ghost), so the line carries a
-- blank icon slot the emoji's size and the emoji sits in it as a plain scaled TextLabel, over the same soft white
-- glow the slabs use (a grey 🔊 or a blue 🐬 is otherwise muddy on a sea key). word = nil: emoji only.
-- sticker = a ShopKit image icon drawn instead of the emoji (it brings its own outline and drop).
local function keyLine(k, emoji, word, size, emojiSize, sticker)
	local parts = {}
	if sticker then
		table.insert(parts, { icon = sticker, size = (emojiSize or 34) + 6 })
	elseif emoji then
		table.insert(parts, { icon = "__emoji", size = emojiSize or 34, drop = 0 })
	end
	if word then table.insert(parts, { text = word, size = size or 28, gap = 8 }) end
	k.setParts(nil, parts)
	local slot = (not sticker) and emoji and k.parts[1] and k.parts[1].obj
	if slot then
		if not slot:FindFirstChild("Glow") then
			make("ImageLabel", {
				Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow or "", ScaleType = Enum.ScaleType.Stretch,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.5, 1.5),
				ImageTransparency = 0.3, ZIndex = 2,
			}, slot)
		end
		local e = slot:FindFirstChild("Emoji") or make("TextLabel", {
			Name = "Emoji", BackgroundTransparency = 1, FontFace = UI.FONT, TextScaled = true, TextColor3 = UI.WHITE,
			Size = UDim2.fromScale(1, 1), ZIndex = 3,
		}, slot)
		e.Text = emoji
	end
end

----------------------------------------------------------------------
-- tab keys + reset (candy keys: gold = the page you are on, sea = the other, green = the Feedback jump)
----------------------------------------------------------------------
V.track = make("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	Position = UDim2.new(1, -28, 0, K.LIST_Y.desk), Size = UDim2.new(0, 10, 1, -(K.LIST_Y.desk + 14)), ZIndex = 5,
}, root)
UI.corner(V.track, 5)
-- a page: the Shop's list (gold thumb over the INK track), rows laid out by hand in V.layPage
local function makePage(name)
	return make("ScrollingFrame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, K.LIST_Y.desk),
		Size = UDim2.new(1, -30, 1, -(K.LIST_Y.desk + 14)), Visible = false, ZIndex = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, VerticalScrollBarInset = Enum.ScrollBarInset.None,
		CanvasSize = UDim2.fromOffset(0, 100),
	}, root)
end
-- No feedback page: that key is an ACTION, not a tab (see openFeedbackForm below).
local pages = { perf = makePage("PerfPage"), audio = makePage("AudioPage") }
V.items = { perf = {}, audio = {} }

local TAB_DEFS = {
	-- (ShopKit's lightning sticker, not the ⚡ emoji: a yellow glyph vanishes on the gold key of the page you are on)
	{ name = "perf",  emoji = "⚡", sticker = "lightning", word = "PERFORMANCE" },
	{ name = "audio", emoji = "🔊", word = "AUDIO" },
}
-- Feedback moved OFF the MainMenu bar (11 buttons had filled the right edge to 99%) and
-- INTO Settings. `action` marks it as a JUMP, not a tab: one click opens the feedback form.
-- It briefly selected a page whose only content was an "Open the feedback form" button,
-- which made reaching the form two clicks instead of one for no reason. Its key is held
-- GREEN ("do it now"), never the sea of an unselected tab: it is a live button, not a view
-- you happen not to be looking at.
table.insert(TAB_DEFS, { name = "feedback", emoji = "\u{1F4AC}", word = "FEEDBACK", action = "feedback" })

local currentTab = TAB_DEFS[1].name
local function selectTab(name)
	currentTab = name
	for _, def in ipairs(TAB_DEFS) do
		local on = (def.name == name)
		local colour = def.action and "green" or (on and "gold" or "sea")
		if def.lit ~= colour then
			def.lit = colour
			def.k.recolour(colour)
		end
		if not def.action then pages[def.name].Visible = on end
	end
end

-- Straight to the form, one click.
local function openFeedbackForm()
	local fb = gui.Parent and gui.Parent:FindFirstChild("FeedbackMenu")
	if not fb then showToast("Feedback is unavailable right now", "bad"); return end
	-- Close Settings FIRST. Every full-screen menu here captures the Backpack's state on the
	-- way in and restores what it saw on the way out, so overlapping two of them is exactly
	-- how the hotbar comes back when it should stay hidden.
	gui.Enabled = false
	task.defer(function()
		local ev = fb:FindFirstChild("OpenFeedback")
		if ev then ev:Fire() else fb.Enabled = true end
	end)
end
for i, def in ipairs(TAB_DEFS) do
	def.k = UI.candyKey(root, "sea", {
		Name = def.name, Size = UDim2.fromOffset(232, K.TAB.desk.h), Position = UDim2.fromOffset(16 + (i - 1) * 244, K.TAB.desk.y),
		ZIndex = 7, LayoutOrder = i,
	})
	TouchKit.press(def.k.button, function()
		if def.action == "feedback" then openFeedbackForm() else selectTab(def.name) end
	end)
end
-- Reset sits at the right end of the tab row (red: it throws every choice away)
V.reset = UI.candyKey(root, "red", {
	Name = "ResetDefaults", Size = UDim2.fromOffset(210, K.TAB.desk.h), Position = UDim2.fromOffset(WIN_W - 226, K.TAB.desk.y),
	ZIndex = 7,
})

----------------------------------------------------------------------
-- rows
----------------------------------------------------------------------
local recs = {}

-- a knob: a white disc with an INK outline, a gloss cap and its own hard drop (a holder Frame, so the drop
-- can sit UNDER the face - under ZIndexBehavior.Sibling a child always draws above its parent)
function V.knobFace(holder, d)
	UI.hardShadow(holder, d / 2, 3, 3, 1)
	local face = make("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, face)
	UI.stroke(face, 3)
	UI.vgrad(face, { UI.WHITE, rgb(206, 220, 238) })
	UI.gloss(face, { frac = 0.5, alpha = 0.7, inset = 3, radius = math.max(math.floor(d / 2) - 3, 2) })
	return face
end

-- a section heading on the lagoon (white, INK outline, hard drop)
local function sectionLabel(tab, text)
	local l = UI.label(pages[tab], text, {
		Name = "Section", size = 26, align = "left", drop = 3, outline = 0.15,
		Size = UDim2.fromOffset(400, 34), Position = UDim2.fromOffset(12, 0), ZIndex = 3,
	})
	table.insert(V.items[tab], { obj = l, h = 34, label = true })
	return l
end

-- a setting's slab: ShopKit's candy row (kind "strip": no kit key or icon) in the setting's colour, its emoji on
-- the soft glow at the left, the name (30) over the description (20) in a left column. A toggle's whole slab is
-- its button (tap anywhere on the row, as before); a slider's is a plain Frame (only the slider takes input).
-- Widths are set by V.lay (the labels' right reserve depends on the control on the right).
local function makeSlab(def, asButton)
	local r = UI.candyRow(pages[def.tab], {
		kind = "strip", key = false, static = not asButton, Name = def.key, colour = def.candy, w = 700, h = K.ROW_H, ZIndex = 2,
	})
	r.mid.Visible = false
	local cy = K.ROW_H / 2 - 2
	make("ImageLabel", {
		Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow or "", ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(48, cy), Size = UDim2.fromOffset(104, 104),
		ImageTransparency = 0.15, ZIndex = 4,
	}, r.button)
	make("TextLabel", {
		Name = "Emoji", BackgroundTransparency = 1, Text = def.icon, FontFace = UI.FONT, TextScaled = true,
		TextColor3 = UI.WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(48, cy),
		Size = UDim2.fromOffset(58, 58), ZIndex = 6,
	}, r.button)
	r.nameLbl = UI.label(r.button, def.name, {
		Name = "SettingName", size = 30, align = "left", drop = 3, outline = 0.15,
		Size = UDim2.new(1, -(K.TEXT_X + 160), 0, 38), Position = UDim2.fromOffset(K.TEXT_X, 9), ZIndex = 7,
	})
	r.descLbl = UI.label(r.button, def.desc, {
		Name = "Desc", size = 20, align = "left", drop = 2, outline = 0.15,
		Size = UDim2.new(1, -(K.TEXT_X + 160), 0, 28), Position = UDim2.fromOffset(K.TEXT_X, 48), ZIndex = 7,
	})
	table.insert(V.items[def.tab], { obj = r.button, h = K.ROW_H })
	return r
end

-- ── toggle row: a candy switch (green ON / grey OFF) whose white knob slides ─────
local function makeToggle(def)
	local r = makeSlab(def, true)
	local SW = K.SW
	local sw = UI.candyKey(r.button, "grey", {
		Name = "Switch", static = true, radius = SW.h / 2, Size = UDim2.fromOffset(SW.w, SW.h),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, -3), ZIndex = 10,
	})
	local knob = make("Frame", {
		Name = "Knob", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, SW.h / 2, 0.5, 0), Size = UDim2.fromOffset(SW.knob, SW.knob), ZIndex = 6,
	}, sw.button)
	V.knobFace(knob, SW.knob)
	local state = UI.label(sw.button, "OFF", {
		Name = "State", size = 22, drop = 2, outline = 0.16,
		Size = UDim2.fromOffset(SW.w - SW.knob - 15, SW.h), Position = UDim2.fromOffset(SW.knob + 9, 0), ZIndex = 5,
	})

	local rec = { def = def, kind = "toggle", key = def.key, card = r.button, row = r, sw = sw, knob = knob, state = state,
		nameLbl = r.nameLbl, descLbl = r.descLbl }
	recs[#recs+1] = rec

	r.button.MouseEnter:Connect(function()
		if UIS:GetLastInputType() ~= Enum.UserInputType.Touch then
			TweenService:Create(r.scale, TweenInfo.new(0.1), { Scale = 1.012 }):Play()
		end
	end)
	r.button.MouseLeave:Connect(function() TweenService:Create(r.scale, TweenInfo.new(0.1), { Scale = 1 }):Play() end)
	TouchKit.press(r.button, function() set(def.key, not (get(def.key) == true)) end)
	return rec
end

-- ── slider row: a gold fill in an INK trough, a white knob, the value on a navy chip ─────
local activeSlider = nil
local function makeSlider(def)
	local r = makeSlab(def, false)
	local chip = UI.chip(r.button, "navy", {
		Name = "Value", height = 44, textSize = 22, pad = 12, minWidth = 92,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, -3), ZIndex = 10,
	})
	-- the trough ends 26 px left of the chip so the knob (34) never touches it at 100%
	local track = make("Frame", {
		Name = "Track", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -136, 0.5, -3),
		Size = UDim2.fromOffset(220, 20), BackgroundColor3 = UI.INK, BackgroundTransparency = 0.35, ZIndex = 8,
	}, r.button)
	UI.corner(track, 10); UI.stroke(track, 3)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = UI.WHITE, ZIndex = 1 }, track)
	UI.corner(fill, 10)
	UI.vgrad(fill, UI.BRICK.gold)
	UI.gloss(fill, { frac = 0.5, alpha = 0.5, inset = 2, radius = 6 })
	local knob = make("Frame", {
		Name = "Knob", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(34, 34), ZIndex = 3,
	}, track)
	V.knobFace(knob, 34)

	-- fat invisible grab area so you don't have to hit the 20px track
	local hit = make("TextButton", {
		Name = "Hit", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 34, 0, 44), ZIndex = 5,
	}, track)
	CMP.hits[#CMP.hits+1] = hit   -- taller on a phone (V.lay)

	local rec = { def = def, kind = "slider", key = def.key, card = r.button, row = r,
		track = track, fill = fill, knob = knob, chip = chip, nameLbl = r.nameLbl, descLbl = r.descLbl,
		min = def.min or 0, max = def.max or 100, suffix = def.suffix or "%" }
	recs[#recs+1] = rec

	hit.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			activeSlider = rec
		end
	end)
	return rec
end

-- The ScreenGui has IgnoreGuiInset = true, so GetMouseLocation() and
-- AbsolutePosition share one coordinate space (the inset cancels out).
local function dragSlider(rec)
	local as = rec.track.AbsoluteSize
	if as.X <= 0 then return end
	local m = UIS:GetMouseLocation()
	local frac = math.clamp((m.X - rec.track.AbsolutePosition.X) / as.X, 0, 1)
	set(rec.key, math.floor(rec.min + (rec.max - rec.min) * frac + 0.5))
end
UIS.InputChanged:Connect(function(io)
	if not activeSlider then return end
	if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
		dragSlider(activeSlider)
	end
end)
UIS.InputEnded:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
		if activeSlider then dragSlider(activeSlider) end
		activeSlider = nil
	end
end)

----------------------------------------------------------------------
-- quality preset slab: four keys, gold = the preset the toggles match right now
----------------------------------------------------------------------
local presetBtns = {}
local function buildPresetCard()
	local r = UI.candyRow(pages.perf, {
		kind = "strip", key = false, Name = "QualityPresets", colour = "cosmic", w = 700, h = 140, ZIndex = 2,
	})
	r.mid.Visible = false
	UI.label(r.button, "One tap sets every effect below", {
		Name = "Head", size = 24, drop = 2, outline = 0.15,
		Size = UDim2.new(1, -32, 0, 32), Position = UDim2.fromOffset(16, 10), ZIndex = 7,
	})
	for i, p in ipairs(PRESETS) do
		local k = UI.candyKey(r.button, "sea", {
			Name = p.key, Size = UDim2.fromOffset(200, 66), Position = UDim2.fromOffset(16 + (i - 1) * 214, 52),
			ZIndex = 10, LayoutOrder = i,
		})
		presetBtns[p.key] = { key = k, preset = p, i = i }
		TouchKit.press(k.button, function()
			for kk, v in pairs(p.vals) do set(kk, v) end
			showToast(p.name .. " quality applied!", "good")
		end)
	end
	table.insert(V.items.perf, { obj = r.button, h = 140 })
end

-- which preset (if any) matches the current toggles?
local function activePreset()
	for _, p in ipairs(PRESETS) do
		local match = true
		for _, k in ipairs(PRESET_KEYS) do
			if (get(k) == true) ~= (p.vals[k] == true) then match = false; break end
		end
		if match then return p.key end
	end
	return nil
end

----------------------------------------------------------------------
-- build the pages
----------------------------------------------------------------------
sectionLabel("perf", "QUALITY")
buildPresetCard()
sectionLabel("perf", "EFFECTS")
for _, d in ipairs(DEFS) do
	if d.tab == "perf" then
		if d.kind == "toggle" then makeToggle(d) else makeSlider(d) end
	end
end

sectionLabel("audio", "VOLUME")
for _, d in ipairs(DEFS) do
	if d.tab == "audio" then
		if d.kind == "toggle" then makeToggle(d) else makeSlider(d) end
	end
end
do
	local note = UI.label(pages.audio, "Every sound in the game is routed through these channels.", {
		Name = "Note", size = 20, align = "left", drop = 2, outline = 0.15, color = UI.TEXT.soft,
		Size = UDim2.fromOffset(600, 28), ZIndex = 3,
	})
	table.insert(V.items.audio, { obj = note, h = 28, label = true })
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
local function refreshRec(rec, animate)
	local ti = TweenInfo.new(animate and 0.16 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if rec.kind == "toggle" then
		local on = get(rec.key) == true
		local SW = K.SW
		rec.sw.recolour(on and "green" or "grey")
		TweenService:Create(rec.knob, ti, { Position = UDim2.new(0, on and (SW.w - SW.h / 2) or SW.h / 2, 0.5, 0) }):Play()
		rec.state.Text = on and "ON" or "OFF"
		rec.state.Position = UDim2.fromOffset(on and 6 or (SW.knob + 9), 0)
	else
		local v = get(rec.key)
		local frac = (v - rec.min) / math.max(1, rec.max - rec.min)
		TweenService:Create(rec.fill, ti, { Size = UDim2.new(frac, 0, 1, 0) }):Play()
		TweenService:Create(rec.knob, ti, { Position = UDim2.new(frac, 0, 0.5, 0) }):Play()
		rec.chip.set(tostring(v) .. rec.suffix)
	end
end

local function refreshPresets()
	local act = activePreset()
	for key, pb in pairs(presetBtns) do
		local colour = (key == act) and "gold" or "sea"
		if pb.lit ~= colour then
			pb.lit = colour
			pb.key.recolour(colour)
		end
	end
end

local function refreshAll(animate)
	for _, rec in ipairs(recs) do refreshRec(rec, animate) end
	refreshPresets()
end

----------------------------------------------------------------------
-- react to any setting change, from anywhere
----------------------------------------------------------------------
for _, d in ipairs(DEFS) do
	plr:GetAttributeChangedSignal("Set_" .. d.key):Connect(function()
		local fn = APPLY[d.key]
		if fn then fn() end
		for _, rec in ipairs(recs) do
			if rec.key == d.key then refreshRec(rec, true) end
		end
		refreshPresets()
		save()
	end)
end

TouchKit.press(V.reset.button, function()
	for _, d in ipairs(DEFS) do set(d.key, d.def) end
	showToast("Settings reset to defaults", "info")
end)

----------------------------------------------------------------------
-- decor loop (respects its own Menu Animations setting)
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	if plr:GetAttribute("Set_MenuFX") == false then return end
	local t = os.clock()
	for _, b in ipairs(V.bubbles) do
		b.y -= b.speed * dt
		if b.y < -0.05 then
			b.y = 1.05
			b.x = (b.x + 0.37) % 1
		end
		b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
	end
	for _, r in ipairs(V.rays) do
		r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
	end
end)

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
local function close() gui.Enabled = false end
TouchKit.press(V.win.close.button, close)
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
		fit(); refreshAll(false); selectTab(currentTab); setInventoryHidden(true)
		V.toast.block.root.Visible = false
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		local target = uiscale.Scale
		uiscale.Scale = target * 0.9
		TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	else
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit() end end)
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function() if gui.Enabled then fit() end end)

----------------------------------------------------------------------
-- dev hook: SettingsMenu.DevSetting:Fire("Shadows", false) / :Fire("__RESET__")
----------------------------------------------------------------------
local devHook = gui:FindFirstChild("DevSetting") or make("BindableEvent", { Name = "DevSetting" }, gui)
devHook.Event:Connect(function(key, value)
	if key == "__RESET__" then
		for _, d in ipairs(DEFS) do set(d.key, d.def) end
	elseif key == "__OPEN__" then
		gui.Enabled = true
	elseif DEF_BY_KEY[key] then
		set(key, value)
	end
end)

----------------------------------------------------------------------
-- first paint
----------------------------------------------------------------------
applyPostFX(); applyAtmos(); applyShadows(); applyParticles(); applyWater()
applyHideOthers(); applyAudio()
selectTab(TAB_DEFS[1].name)
refreshAll(false)

----------------------------------------------------------------------
-- layout: everything that depends on the design width or the phone flag
----------------------------------------------------------------------
-- the header's wave crest, re-spaced for a new design width (UI.window lays it once, for WIN_W)
function V.crest(w)
	local crest, D = V.win.crest, 26
	for _, c in ipairs(crest:GetChildren()) do c:Destroy() end
	local n = math.ceil((w - 10) / D)
	local x0 = (w - n * D) / 2
	for i = 0, n - 1 do
		local disc = make("Frame", {
			Name = "Wave", BackgroundColor3 = UI.HEAD.navy[2], AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(x0 + i * D, -1), Size = UDim2.fromOffset(D, D), ZIndex = 3,
		}, crest)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
		UI.stroke(disc, 3.5)
	end
end
-- the title's size cap, on the title AND its hard drop (a clone with its own constraint)
function V.titleMax(n)
	for _, l in ipairs({ V.win.title, root:FindFirstChild("TitleDrop") }) do
		local c = l and l:FindFirstChildOfClass("UITextSizeConstraint")
		if c then c.MaxTextSize = n end
	end
end
-- one page's items, top to bottom: slabs at x 8 (their outline needs the room), headings at x 12
function V.layPage(tab, rowW)
	local y = 10
	for i, it in ipairs(V.items[tab]) do
		if it.label then
			if i > 1 then y += 6 end
			it.obj.Position = UDim2.fromOffset(12, y)
			it.obj.Size = UDim2.fromOffset(rowW - 8, it.h)
			y += it.h + 6
		else
			it.obj.Position = UDim2.fromOffset(8, y)
			it.obj.Size = UDim2.fromOffset(rowW, it.h)
			y += it.h + K.GAP
		end
	end
	pages[tab].CanvasSize = UDim2.fromOffset(0, y)
end

function V.lay(w)
	local phone = CMP.on == true
	local rowW = w - 58   -- list = w - 30 (x 12, its bar in the right 10 px); slabs at x 8 with 20 px to the bar
	-- header: its height (+ the crest and ocean hanging under it), the title, the ⚙️, the tagline
	local hh = phone and K.HEAD_H.phone or K.HEAD_H.desk
	V.win.header.Size = UDim2.new(1, 0, 0, hh)
	V.win.crest.Position = UDim2.fromOffset(0, hh)
	V.win.ocean.Position = UDim2.fromOffset(0, hh)
	V.win.ocean.Size = UDim2.new(1, 0, 1, -hh)
	if V.crestW ~= w then
		V.crestW = w
		V.crest(w)
	end
	V.win.title.Size = UDim2.fromOffset(222, hh)
	V.titleMax(phone and 38 or 46)
	if V.win.icon then
		local s = phone and K.ICON_PHONE.size or 124
		V.win.icon.Size = UDim2.fromOffset(s, s)
		V.win.icon.Position = phone and UDim2.fromOffset(K.ICON_PHONE.x, K.ICON_PHONE.y)
			or UDim2.fromOffset(-K.REACH.left, -K.REACH.up)
	end
	local subW = w - 56 - 344
	V.sub.Position = UDim2.fromOffset(344, math.floor(hh / 2 - 15))
	V.sub.Size = UDim2.fromOffset(math.max(subW, 1), 30)
	V.sub.Visible = subW >= 360
	-- the tab row: three keys from the left, reset on the right (icon-only on a phone, so the tabs keep their words)
	local T = phone and K.TAB.phone or K.TAB.desk
	local resetW = phone and 72 or 210
	local tabW = math.floor((w - 32 - resetW - 20 - 12 * (#TAB_DEFS - 1)) / #TAB_DEFS)
	for i, def in ipairs(TAB_DEFS) do
		def.k.button.Size = UDim2.fromOffset(tabW, T.h)
		def.k.button.Position = UDim2.fromOffset(16 + (i - 1) * (tabW + 12), T.y)
		keyLine(def.k, def.emoji, def.word, phone and 24 or 28, phone and 30 or 34, def.sticker)
	end
	V.reset.button.Size = UDim2.fromOffset(resetW, T.h)
	V.reset.button.Position = UDim2.fromOffset(w - 16 - resetW, T.y)
	keyLine(V.reset, "\u{1F504}", (not phone) and "RESET ALL" or nil, 26, phone and 30 or 32)
	-- the list
	local listY = phone and K.LIST_Y.phone or K.LIST_Y.desk
	for _, p in pairs(pages) do
		p.Position = UDim2.fromOffset(12, listY)
		p.Size = UDim2.new(1, -30, 1, -(listY + 14))
	end
	V.track.Position = UDim2.new(1, -28, 0, listY)
	V.track.Size = UDim2.new(0, 10, 1, -(listY + 14))
	-- rows: the slider trough takes ~27% of the slab, the labels keep everything left of the control
	V.trackW = math.clamp(math.floor(rowW * 0.27), 170, 260)
	for _, rec in ipairs(recs) do
		local reserve = rec.kind == "toggle" and (18 + K.SW.w + 20) or (136 + V.trackW + 29)
		rec.nameLbl.Size = UDim2.new(1, -(K.TEXT_X + reserve), 0, 38)
		rec.descLbl.Size = UDim2.new(1, -(K.TEXT_X + reserve), 0, 28)
		if rec.track then rec.track.Size = UDim2.fromOffset(V.trackW, 20) end
	end
	for _, h in ipairs(CMP.hits) do
		h.Size = phone and UDim2.new(1, 34, 0, 64) or UDim2.new(1, 34, 0, 44)
	end
	local kw = math.floor((rowW - 32 - 3 * 14) / 4)
	for _, pb in pairs(presetBtns) do
		pb.key.button.Size = UDim2.fromOffset(kw, 66)
		pb.key.button.Position = UDim2.fromOffset(16 + (pb.i - 1) * (kw + 14), 52)
		keyLine(pb.key, pb.preset.icon, pb.preset.name:upper(), 28, 38)
	end
	V.layPage("perf", rowW)
	V.layPage("audio", rowW)
end

-- Phone chrome (see CMP above fit()). `w` is the design width fit() chose; a change of either re-lays the window.
CMP.apply = function(on, w)
	if on == CMP.on and w == CMP.w then return end
	CMP.on, CMP.w = on, w
	V.lay(w)
end
fit()

print("[Settings] built — " .. #DEFS .. " settings across " .. #TAB_DEFS .. " tabs, " .. #PRESETS .. " quality presets (ShopKit look)")
