--[[
	SeaFX — dresses the 2.5D sea so it reads as water instead of a flat blue wall.

	The sea was one Part (Zone1.WaterBack, Z=-3) wearing a SurfaceGui gradient, plus
	a straight foam strip. Two things made it read as a wall: the gradient was the
	ONLY thing in it, and the plane's top edge is a dead-straight horizontal line.
	This adds four layers:

	  1. a richer surface->abyss gradient on the plane itself
	  2. god rays raking down from the surface, inside the plane's own SurfaceGui
	  3. a WAVE RIBBON along the waterline. This is the important one: it is tall
	     enough to always cover the plane's straight top edge, so the visible
	     boundary becomes the ribbon's undulating crest instead of that hard line.
	  4. bubbles rising and marine snow drifting, spread over the whole cast depth

	⚠️ EVERYTHING here stays within ~3 studs of the play plane. Roblox culls past
	~270-320 studs at low graphics quality (see GameClient's header) — nothing in
	here may drift back toward the island or it will vanish for half the players.

	⚠️ The ribbon must always crest ABOVE y=0. If the wave dips below the plane's
	top edge, that straight edge peeks through and the whole illusion dies — hence
	WAVE_BASE > the summed wave amplitudes.

	Honours the Settings menu: Set_WaterFX (ribbon + rays), Set_Particles (bubbles
	+ snow), same Set_<key> attribute convention as the other controllers.
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- The swell itself lives in ReplicatedStorage.SeaWave, because BoatClient rocks the
-- hull on the same function: the boat has to ride the crests this script draws, and
-- two copies of the coefficients would silently fall out of phase the first time the
-- wave is retuned. Everything about the SHAPE below is still this script's business.
local SeaWave = require(game:GetService("ReplicatedStorage"):WaitForChild("SeaWave"))

local plr  = Players.LocalPlayer
local zone = workspace:WaitForChild("Zone1")
local water = zone:WaitForChild("WaterBack")
local foam  = zone:FindFirstChild("Foam")

local WATER_Y = 0

-- Wave shape: three sines so it never visibly repeats. Amplitudes sum to 0.48, so
-- with WAVE_BASE 0.6 the crest lives in y 0.12..1.08. Both ends of that range are
-- load-bearing and were found by screenshotting, not by taste:
--   · the LOW end must keep the crest (at Z=-2.1) projecting ABOVE the plane's top
--     edge (at Z=-3) or that dead-straight edge peeks out over the wave.
--   · the HIGH end must keep the crest BELOW the island's shore line. The shore
--     meets the water at Z=-26, which — with the camera above the waterline —
--     projects ~27px HIGHER than the boat's waterline at Z=0. Crest any taller and
--     the ribbon washes up over the beach as a slab.
local WAVE_BASE = SeaWave.BASE
local WAVE_N    = 48
local WAVE_SPAN = 104         -- studs; the camera only ever sees ~94 across
local BODY_Z    = -2.1        -- in front of the plane's face (-2.5), behind the fish (0)
local CREST_Z   = -1.6

local BUBBLES   = 36
local MOTES     = 48
local DEEP_Y    = -168        -- the camera follows the hook to ~-133, +one screen

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function on(key) return plr:GetAttribute("Set_" .. key) ~= false end

local old = zone:FindFirstChild("SeaFX")
if old then old:Destroy() end
local fx = make("Folder", { Name = "SeaFX" }, zone)

----------------------------------------------------------------------
-- 1. the gradient
----------------------------------------------------------------------
-- Ramped over the PLAYABLE depth, not the plane's full 270 studs: the deepest a
-- cast reaches is ~-155, which is t≈0.57 here, so the abyss colours have to land
-- inside that or the sea just looks uniformly mid-blue all game.
local gradFrame = water:FindFirstChild("Grad") and water.Grad:FindFirstChild("Frame")
local grad = gradFrame and gradFrame:FindFirstChild("UIGradient")
-- ⚠️ The gradient is NOT written here any more. DepthStrata assembles the whole
-- 0..-660 column from its per-zone strata themes, and this block used to run
-- AFTER it on join and stomp it back to the old 270-stud ramp. `grad` is still
-- resolved above because applySea's fallback path refers to it.

----------------------------------------------------------------------
-- 2. god rays  (inside the plane's SurfaceGui, so they sit behind everything)
----------------------------------------------------------------------
local rays = {}
do
	local gui = water:FindFirstChild("Grad")
	if gui then
		local holder = gui:FindFirstChild("Rays")
		if holder then holder:Destroy() end
		holder = make("Frame", { Name = "Rays", BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 2 }, gui)
		-- The plane is 420 studs wide but the camera only sees x ±47, i.e. canvas
		-- scale 0.39..0.61. A ray outside that band is just wasted draw.
		for i = 1, 7 do
			local r = make("Frame", {
				Name = "Ray",
				AnchorPoint = Vector2.new(0.5, 0),
				-- Y must start just BELOW the canvas top, never above it. A ray at a
				-- negative Y pokes ~5 studs over the waterline and lies across the
				-- beach as a pale streak — and ClipsDescendants will NOT save you,
				-- because Roblox does not clip ROTATED gui elements. The 0.005 also
				-- absorbs the corner swing from Rotation about the top-centre.
				Position = UDim2.fromScale(0.405 + (i - 1) * 0.032, 0.005),
				Size = UDim2.fromScale(0.010 + math.random() * 0.012, 0.26 + math.random() * 0.18),
				Rotation = -15 + math.random() * 30,
				BackgroundColor3 = Color3.fromRGB(206, 250, 255),
				BorderSizePixel = 0, ZIndex = 2,
			}, holder)
			local rg = make("UIGradient", { Rotation = 90 }, r)
			rays[#rays + 1] = { f = r, g = rg, rot0 = r.Rotation, x0 = r.Position.X.Scale,
				phase = math.random() * 6.28, amp = 0.55 + math.random() * 0.2 }
		end
	end
end

----------------------------------------------------------------------
-- 3. the wave ribbon
----------------------------------------------------------------------
local waveFolder = make("Folder", { Name = "Waves" }, fx)
local bars = {}

local waveAt = SeaWave.heightAt

for i = 1, WAVE_N do
	local x = -WAVE_SPAN / 2 + (i - 0.5) * (WAVE_SPAN / WAVE_N)
	-- Body: hung so its TOP is the crest, deep enough to always cover the plane's
	-- straight edge. Its colour is DARKER than the gradient's top (132,238,247) on
	-- purpose: the plane's SurfaceGui is unlit (LightInfluence=0) but these are real
	-- parts taking sun + ambient, so an exact colour match renders far too pale and
	-- reads as a slab sitting on the sea. Re-tune this if Lighting changes.
	local body = make("Part", {
		Name = "WaveBody", Size = Vector3.new(3.0, 2.4, 0.6),
		Color = Color3.fromRGB(112, 214, 232), Material = Enum.Material.SmoothPlastic,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false,
	}, waveFolder)
	local crest = make("Part", {
		Name = "WaveCrest", Size = Vector3.new(3.0, 0.38, 0.5),
		Color = Color3.fromRGB(242, 253, 255), Material = Enum.Material.SmoothPlastic,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false,
	}, waveFolder)
	bars[i] = { x = x, body = body, crest = crest }
end

----------------------------------------------------------------------
-- 4. bubbles + marine snow
----------------------------------------------------------------------
local moteFolder = make("Folder", { Name = "Motes" }, fx)
local bubbles, motes = {}, {}

local function seedBubble(b, atBottom)
	b.x = math.random(-48, 48) + math.random()
	b.y = atBottom and (DEEP_Y + math.random() * 20) or (DEEP_Y + math.random() * (2 - DEEP_Y))
	b.z = -2.6 + math.random() * 2.2
	b.speed = 2 + math.random() * 5
	b.wob = 0.3 + math.random() * 0.9
	b.phase = math.random() * 6.28
end

for i = 1, BUBBLES do
	local s = 0.25 + math.random() * 0.65
	local p = make("Part", {
		Name = "Bubble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s),
		Color = Color3.fromRGB(214, 248, 255), Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35 + math.random() * 0.25,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false,
	}, moteFolder)
	local b = { part = p }
	seedBubble(b, false)
	bubbles[i] = b
end

for i = 1, MOTES do
	local s = 0.12 + math.random() * 0.2
	local p = make("Part", {
		Name = "Snow", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s),
		Color = Color3.fromRGB(226, 244, 252), Material = Enum.Material.SmoothPlastic,
		Transparency = 0.45 + math.random() * 0.3,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false,
	}, moteFolder)
	motes[i] = {
		part = p,
		x = math.random(-48, 48) + math.random(),
		y = DEEP_Y + math.random() * (2 - DEEP_Y),
		z = -2.6 + math.random() * 2.2,
		speed = 0.3 + math.random() * 1.0,
		wob = 0.4 + math.random() * 1.2,
		phase = math.random() * 6.28,
	}
end

----------------------------------------------------------------------
-- settings
----------------------------------------------------------------------
local waterOn, partsOn = on("WaterFX"), on("Particles")
local function refresh()
	waterOn, partsOn = on("WaterFX"), on("Particles")
	waveFolder.Parent = waterOn and fx or nil
	moteFolder.Parent = partsOn and fx or nil
	local g = water:FindFirstChild("Grad")
	local holder = g and g:FindFirstChild("Rays")
	if holder then holder.Visible = waterOn end
	-- the flat strip is the fallback waterline when the ribbon is switched off
	if foam then foam.Transparency = waterOn and 1 or 0 end
end
refresh()
plr:GetAttributeChangedSignal("Set_WaterFX"):Connect(refresh)
plr:GetAttributeChangedSignal("Set_Particles"):Connect(refresh)
----------------------------------------------------------------------
-- per-zone sea palette — retint the WHOLE near sea (plane gradient + rays +
-- wave ribbon + foam) when you travel, so the water matches the zone's backdrop
-- instead of staying tropical-cyan everywhere. Mirrors ZonesController's CurrentZone.
----------------------------------------------------------------------
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local SEA = {
	[1] = { surf = rgb(132,238,247), deep = rgb(1,6,22),   body = rgb(112,214,232), crest = rgb(242,253,255), ray = rgb(206,250,255) },
	[2] = { surf = rgb(150,240,230), deep = rgb(2,54,62),  body = rgb(58,206,192),  crest = rgb(214,255,250), ray = rgb(196,252,246) },
	[3] = { surf = rgb(255,200,132), deep = rgb(46,16,40), body = rgb(236,146,92),  crest = rgb(255,228,176), ray = rgb(255,212,150) },
	[4] = { surf = rgb(208,236,248), deep = rgb(26,64,98), body = rgb(156,206,230), crest = rgb(244,252,255), ray = rgb(226,246,255) },
	[5] = { surf = rgb(34,70,108),   deep = rgb(1,5,16),   body = rgb(28,72,118),   crest = rgb(138,196,236), ray = rgb(90,150,210) },
	[6] = { surf = rgb(228,104,50),  deep = rgb(78,26,14), body = rgb(178,66,28),   crest = rgb(255,188,118), ray = rgb(255,148,78) },
}
local STOP = {0.00, 0.05, 0.14, 0.28, 0.44, 0.60, 0.78, 1.00}
local RAMP = {0.00, 0.10, 0.24, 0.42, 0.60, 0.75, 0.90, 1.00}
local function seaSequence(p)
	local kps = {}
	for i = 1, 8 do kps[i] = ColorSequenceKeypoint.new(STOP[i], p.surf:Lerp(p.deep, RAMP[i])) end
	return ColorSequence.new(kps)
end
local function currentZone() return plr:GetAttribute("CurrentZone") or 1 end
local function applySea(id)
	local p = SEA[id] or SEA[1]
	-- The gradient is DepthStrata's now: it assembles the whole 0..-660 column
	-- from the per-zone strata themes. Writing it here too would mean whichever
	-- CurrentZone listener happened to run last won. SeaFX keeps the waterline.
	-- (seaSequence/STOP/RAMP are left in place as the fallback if DepthStrata is
	-- ever removed.)
	for _, r in ipairs(rays) do r.f.BackgroundColor3 = p.ray end
	for _, b in ipairs(bars) do b.body.Color = p.body; b.crest.Color = p.crest end
	if foam then foam.Color = p.body end
end
applySea(currentZone())
plr:GetAttributeChangedSignal("CurrentZone"):Connect(function() applySea(currentZone()) end)

----------------------------------------------------------------------
-- animate
----------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local t = os.clock()

	if waterOn then
		for _, b in ipairs(bars) do
			local h = waveAt(b.x, t)
			-- sample either side for the local slope so the ribbon tilts into the
			-- swell instead of stair-stepping
			local slope = (waveAt(b.x + 0.7, t) - waveAt(b.x - 0.7, t)) / 1.4
			local roll = math.atan(slope)
			b.body.CFrame = CFrame.new(b.x, WATER_Y + h - 1.2, BODY_Z) * CFrame.Angles(0, 0, roll)
			b.crest.CFrame = CFrame.new(b.x, WATER_Y + h - 0.02, CREST_Z) * CFrame.Angles(0, 0, roll)
		end
		for _, r in ipairs(rays) do
			local s = math.sin(t * 0.25 + r.phase)
			r.f.Rotation = r.rot0 + s * 1.8
			r.f.Position = UDim2.fromScale(r.x0 + s * 0.006, 0.005)
			local a = r.amp + math.sin(t * 0.7 + r.phase) * 0.12
			r.g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, a),
				NumberSequenceKeypoint.new(0.5, math.min(1, a + 0.22)),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end

	if partsOn then
		for _, b in ipairs(bubbles) do
			b.y += b.speed * dt
			if b.y > 1.5 then seedBubble(b, true) end
			b.part.CFrame = CFrame.new(b.x + math.sin(t * 1.6 + b.phase) * b.wob, b.y, b.z)
		end
		for _, m in ipairs(motes) do
			m.y -= m.speed * dt
			if m.y < DEEP_Y then m.y = 2 end
			m.part.CFrame = CFrame.new(m.x + math.sin(t * 0.5 + m.phase) * m.wob, m.y, m.z)
		end
	end
end)

print(string.format("[SeaFX] online — %d wave bars, %d rays, %d bubbles, %d snow (waterFX=%s particles=%s)",
	#bars, #rays, #bubbles, #motes, tostring(waterOn), tostring(partsOn)))
