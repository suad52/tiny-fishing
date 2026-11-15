--[==[
	ZonesController - the Zones window (StarterGui.ZonesMenu).
	6 fishing spots unlocked IN ORDER with coins. Owned zones can be TRAVELED to, swapping the client backdrop
	(Lighting + Atmosphere + ZoneColorCorrection + Terrain water + the painted 2.5D horizon) and applying a coin
	benefit (ZoneCoinMult attr). Only the zone right after your last owned one is buyable; later zones are locked
	(their scene hidden under a lock). Detailed animated preview scene per card. Hides the rod hotbar while open.
	DevZone BindableEvent: "__ALL__" unlock all, <number> unlock+travel.
	ROBUX (2026-10-10, the owner: "give the zones the option to be purchased with robux"): while a zone is still to buy
	its key row splits into the coin key (coin + price) and a Robux key (ReplicatedStorage.ShopProducts: ZONE_ROBUX for
	the price, PRODUCTS.zone_<id> for the Developer Product). Same order rule as coins: only the next zone can be bought,
	a later zone's Robux key is grey and says which zone comes first. A Robux receipt comes back from ProductServer on
	ShopRemotes.ZoneGranted and is applied exactly like a coin purchase (Zone_<id> + travel), so a rebirth re-locks it
	too. A product id of 0 (not set up yet) never prompts: the key is grey and says so.

	2026-10-10 - RESTYLED onto ReplicatedStorage.ShopKit (the Shop's "sea candy" kit) so the window looks like it
	belongs next to the Shop: UI.window shell (lagoon body with the Shop's bubbles + light rays, orange header with
	gloss and a wave crest, gold title, the map emoji breaking out of the top-left corner, ShopKit's red key X), the
	gold cash pill, one candy card per zone in that zone's own colour (the preview scenes and their art are kept,
	now framed in INK; a locked zone's card goes slate grey under the lock sticker), candy keys whose colour is the
	STATE (green UNLOCK when you can afford it, grey when you can't or it is locked, sea TRAVEL, gold FISHING HERE),
	a gold NEXT sticker, ShopKit chips/labels and the Shop's scroll bar. The old dark-reef panels are gone.
	Behaviour is untouched: same attributes, purchase/travel rules, rebirth reset and DevZone hook.
	Placement: the emoji breaks 44 design px out of the window's top, so after MenuFit.apply the window is settled so
	that reach stays below Roblox's top bar (the Shop's rule) - see settle(). On a phone the emoji is tucked inside the
	header and the window is centred on the screen (2026-10-11) - see fit().

	CONTRACT (what other scripts rely on):
	  * This ScreenGui stays the same instance and Enabled is the open/close signal (MenuLogic and ProgressController
	    open it; MenuBlurManager, AudioController, DailyController and TutorialController watch it).
	  * Exactly ONE close X: ShopKit's window X, a TextButton named "TextButton", Text "", 60 x 60, Frame children.
	    TutorialController's closeButtonOf() finds it for the GO BIGGER step, rings it and waits for the window to
	    close. Nothing else in this gui may be named "TextButton" (keys are "Action", guards "ClickGuard").
	  * Attributes: Zone_<id>, CurrentZone, ZoneCoinMult, ZoneName (GameClient, AudioController, SeaFX,
	    QuestsController, Scenery3DClient read them); a rise in Rebirths re-locks zones 2-6. Money is
	    leaderstats.Money (CurrencyClient). ProgressController MIRRORS the cost= fields of ZONES - retune both.
	  * applyEnv / showBackdrop own surface Lighting and the painted backdrops (Scenery3DClient, DeepScenery and
	    SettingsController work around them - see their notes). Unchanged by the restyle.
]==]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local StarterGui   = game:GetService("StarterGui")
local Lighting     = game:GetService("Lighting")
local GuiService   = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- The Shop's kit (window, keys, chips, labels, palettes). Shared - never edit it from a menu.
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))
-- Shared with every other pop-up window in the game (see fit() below).
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
-- Robux prices + Developer Product ids (shared with ProductServer, which grants the receipts)
local ShopProducts = require(ReplicatedStorage:WaitForChild("ShopProducts"))
local MarketplaceService = game:GetService("MarketplaceService")

local plr = Players.LocalPlayer
local gui = script.Parent

local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local function lighten(c,t) return c:Lerp(Color3.new(1,1,1), t) end
local function darken(c,t)  return c:Lerp(Color3.new(0,0,0), t) end
local V2 = Vector2.new

local FONT = Enum.Font.FredokaOne
local INK  = UI.INK
local GOLD = rgb(255,224,104)

---------------------------------------------------------------- scene-art helpers (the preview scenes)
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(inst, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }, inst) end
local function grad(inst, a, b, rot) return make("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }, inst) end
local function txt(parent, s, size, col, font)
	return make("TextLabel", { BackgroundTransparency = 1, Text = s, Font = font or FONT, TextSize = size, TextColor3 = col or INK, RichText = true }, parent)
end
local function disc(parent, d, sx, sy, color, z)
	local f = make("Frame", { Size = UDim2.fromOffset(d,d), AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(sx,0,sy,0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z }, parent)
	corner(f, 999); return f
end
local function rect(parent, w, h, sx, sy, color, z, rot)
	return make("Frame", { Size = UDim2.fromOffset(w,h), AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(sx,0,sy,0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z, Rotation = rot or 0 }, parent)
end
local function cloud(parent, sx, sy, s, z)
	disc(parent, math.floor(20*s), sx-0.06, sy+0.015, Color3.new(1,1,1), z)
	disc(parent, math.floor(28*s), sx, sy, Color3.new(1,1,1), z)
	disc(parent, math.floor(20*s), sx+0.06, sy+0.015, Color3.new(1,1,1), z)
	corner(rect(parent, math.floor(46*s), math.floor(13*s), sx, sy+0.04, Color3.new(1,1,1), z), 999)
end
local function bird(parent, sx, sy, col, z)
	corner(rect(parent, 13, 4, sx-0.016, sy, col, z, 22), 999)
	corner(rect(parent, 13, 4, sx+0.016, sy, col, z, -22), 999)
end
local function coral(parent, sx, sy, col, z)
	disc(parent, 18, sx, sy, col, z); disc(parent, 13, sx-0.045, sy+0.05, col, z); disc(parent, 13, sx+0.045, sy+0.05, col, z)
end
local function sun(parent, sx, sy, d, col, z)
	disc(parent, math.floor(d*1.6), sx, sy, lighten(col,0.25), z).BackgroundTransparency = 0.55
	disc(parent, d, sx, sy, col, z+1)
end

local floaters, twinklers, heroes = {}, {}, {}
local function addFloater(inst, sx, startY, endY, speed)
	inst.Position = UDim2.new(sx, 0, startY, 0)
	floaters[#floaters+1] = { inst = inst, sx = sx, startY = startY, endY = endY, speed = speed, phase = math.random() }
end
local function addTwinkle(inst, speed) twinklers[#twinklers+1] = { inst = inst, phase = math.random()*6, speed = speed } end

local ZONES = {
	{ id=1, name="Lighthouse Cove", tagline="Calm home waters", cost=0, coin=1.0, benefit="Home waters", accent=GOLD,
		prevTop=rgb(150,205,245), prevBot=rgb(80,170,230),
		env={ clock=14.5, brightness=3, exposure=0, ambient=rgb(70,70,70), outdoor=rgb(70,70,70), atmDensity=0, atmHaze=0, atmGlare=0, atmColor=rgb(199,199,199), atmDecay=rgb(106,112,125), cc={ tint=rgb(255,255,255), sat=0, con=0, bri=0 }, water=rgb(12,84,92), waveSize=0.15, waveSpeed=10, waterTrans=0.3, waterRefl=1 } },
	{ id=2, name="Tropical Reef", tagline="Warm turquoise shallows", cost=20000, coin=1.2, benefit="+20% Coins", accent=rgb(0,200,190),
		prevTop=rgb(140,240,235), prevBot=rgb(0,190,180),
		env={ clock=13, brightness=3.2, exposure=0.15, ambient=rgb(120,140,150), outdoor=rgb(150,165,175), atmDensity=0.28, atmHaze=1.2, atmGlare=0.2, atmColor=rgb(180,235,240), atmDecay=rgb(120,200,210), cc={ tint=rgb(210,255,250), sat=0.25, con=0.08, bri=0.03 }, water=rgb(0,190,180), waveSize=0.18, waveSpeed=14, waterTrans=0.18, waterRefl=1 } },
	{ id=3, name="Golden Sunset Bay", tagline="Endless golden hour", cost=120000, coin=1.45, benefit="+45% Coins", accent=rgb(255,170,90),
		prevTop=rgb(255,190,120), prevBot=rgb(230,120,90),
		env={ clock=17.4, brightness=2.6, exposure=0.2, ambient=rgb(120,90,70), outdoor=rgb(150,110,80), atmDensity=0.35, atmHaze=2.2, atmGlare=0.6, atmColor=rgb(255,200,150), atmDecay=rgb(255,150,90), cc={ tint=rgb(255,220,180), sat=0.2, con=0.1, bri=0.02 }, water=rgb(60,120,170), waveSize=0.2, waveSpeed=10, waterTrans=0.28, waterRefl=1 } },
	{ id=4, name="Frostbite Fjord", tagline="Icy, misty and cold", cost=900000, coin=1.9, benefit="+90% Coins", accent=rgb(150,205,240),
		prevTop=rgb(215,238,255), prevBot=rgb(150,200,230),
		env={ clock=9, brightness=2.3, exposure=0.1, ambient=rgb(150,165,185), outdoor=rgb(180,195,210), atmDensity=0.5, atmHaze=3.5, atmGlare=0.1, atmColor=rgb(215,235,255), atmDecay=rgb(170,200,235), cc={ tint=rgb(220,238,255), sat=-0.15, con=0.06, bri=0.04 }, water=rgb(140,200,225), waveSize=0.1, waveSpeed=6, waterTrans=0.22, waterRefl=1 } },
	{ id=5, name="Midnight Trench", tagline="Deep, dark and rare", cost=6000000, coin=2.75, benefit="+175% Coins", accent=rgb(90,120,220),
		prevTop=rgb(30,45,90), prevBot=rgb(6,18,55),
		env={ clock=0, brightness=2.7, exposure=0.05, ambient=rgb(92,110,158), outdoor=rgb(100,120,166), atmDensity=0.55, atmHaze=2, atmGlare=0, atmColor=rgb(30,45,85), atmDecay=rgb(20,30,70), cc={ tint=rgb(130,158,222), sat=-0.05, con=0.10, bri=0.05 }, water=rgb(6,20,60), waveSize=0.16, waveSpeed=8, waterTrans=0.35, waterRefl=1 } },
	{ id=6, name="Molten Abyss", tagline="Volcanic depths", cost=22000000, coin=4.0, benefit="+300% Coins", accent=rgb(240,90,50),
		prevTop=rgb(200,70,40), prevBot=rgb(110,25,20),
		env={ clock=0, brightness=1.6, exposure=0.1, ambient=rgb(90,35,20), outdoor=rgb(80,30,18), atmDensity=0.6, atmHaze=3, atmGlare=0.5, atmColor=rgb(120,40,25), atmDecay=rgb(200,60,20), cc={ tint=rgb(255,150,110), sat=0.15, con=0.14, bri=0 }, water=rgb(120,30,20), waveSize=0.22, waveSpeed=12, waterTrans=0.25, waterRefl=1 } },
}
local ZONE_BY_ID = {}
for _, z in ipairs(ZONES) do ZONE_BY_ID[z.id] = z end
-- each zone's card colour (a UI.CANDY name: the ITEM's colour, never a state colour)
local CARD_COLOUR = { [1] = "blue", [2] = "teal", [3] = "orange", [4] = "cyan", [5] = "cosmic", [6] = "red" }
local LOCKED_FACE = { rgb(206, 214, 230), rgb(118, 132, 158) } -- a locked zone's card: slate, "not yet"

-- The preview scene of one zone (the art is the v2 scenes'; only the water's bottom corners are rounded now, so
-- nothing square pokes past the frame's rounded INK border).
local function buildScene(prev, z)
	local water = make("Frame", { BackgroundColor3 = z.env.water, BorderSizePixel = 0, Size = UDim2.new(1,0,0.3,0), Position = UDim2.new(0,0,0.7,0), ZIndex = 5 }, prev)
	grad(water, lighten(z.env.water, 0.32), darken(z.env.water, 0.16), 90)
	corner(water, 12)
	for i = 0, 8 do disc(prev, 16, i/8, 0.7, lighten(z.env.water, 0.5), 6) end
	local function hero(icon, sx, sy, size)
		local h = txt(prev, icon, size or 46, INK, FONT); h.AnchorPoint = Vector2.new(0.5,0.5); h.Position = UDim2.new(sx,0,sy,0); h.Size = UDim2.fromOffset((size or 46)+16, (size or 46)+16); h.ZIndex = 8
		heroes[#heroes+1] = { inst = h, sx = sx, baseY = sy, phase = math.random()*6 }
	end
	local id = z.id
	if id == 1 then
		sun(prev, 0.84, 0.22, 28, rgb(255,232,120), 4)
		cloud(prev, 0.3, 0.26, 1, 4); cloud(prev, 0.62, 0.16, 0.8, 4)
		corner(make("Frame", { BackgroundColor3 = rgb(120,92,60), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,1), Position = UDim2.new(0.5,0,0.83,0), Size = UDim2.fromOffset(150,44), ZIndex = 6 }, prev), 999)
		corner(make("Frame", { BackgroundColor3 = rgb(104,196,96), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,1), Position = UDim2.new(0.5,0,0.76,0), Size = UDim2.fromOffset(150,20), ZIndex = 6 }, prev), 999)
		hero("🗼", 0.5, 0.52, 50)
	elseif id == 2 then
		sun(prev, 0.85, 0.2, 24, rgb(255,238,150), 4)
		coral(prev, 0.2, 0.82, rgb(255,120,170), 6); coral(prev, 0.5, 0.86, rgb(255,170,80), 6); coral(prev, 0.8, 0.82, rgb(180,120,240), 6)
		hero("🐠", 0.44, 0.48, 44)
		for i = 1, 4 do local b = disc(prev, math.random(6,12), 0, 0, Color3.new(1,1,1), 9); b.BackgroundTransparency = 0.35; addFloater(b, 0.18+i*0.16, 0.68, 0.16, 0.07+math.random()*0.05) end
	elseif id == 3 then
		sun(prev, 0.62, 0.6, 44, rgb(255,214,120), 4)
		local refl = make("Frame", { BackgroundColor3 = lighten(rgb(255,214,120),0.1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.62,0,0.72,0), Size = UDim2.fromOffset(26,42), ZIndex = 6 }, prev); refl.BackgroundTransparency = 0.4; corner(refl, 8)
		bird(prev, 0.26, 0.24, rgb(40,28,44), 5); bird(prev, 0.35, 0.3, rgb(40,28,44), 5); bird(prev, 0.2, 0.33, rgb(40,28,44), 5)
		hero("⛵", 0.4, 0.66, 40)
	elseif id == 4 then
		sun(prev, 0.82, 0.2, 26, rgb(240,248,255), 4)
		local function berg(sx,sy,s,col) corner(rect(prev, s, s, sx, sy, col, 6, 45), 8); disc(prev, math.floor(s*0.45), sx, sy-0.16, Color3.new(1,1,1), 7) end
		berg(0.3, 0.72, 42, rgb(214,236,255)); berg(0.68, 0.76, 56, rgb(196,224,250))
		hero("❄️", 0.5, 0.4, 42)
		for i = 1, 6 do local s = disc(prev, math.random(5,9), 0, 0, Color3.new(1,1,1), 9); addFloater(s, 0.1+i*0.13, 0.04, 0.66, 0.05+math.random()*0.05) end
	elseif id == 5 then
		disc(prev, 44, 0.82, 0.24, rgb(245,240,210), 5)
		disc(prev, 40, 0.86, 0.21, z.prevTop, 5)
		for i = 1, 7 do addTwinkle(disc(prev, math.random(3,5), math.random(8,92)/100, math.random(8,52)/100, Color3.new(1,1,1), 5), 0.6+math.random()) end
		local refl = make("Frame", { BackgroundColor3 = rgb(220,226,200), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.82,0,0.72,0), Size = UDim2.fromOffset(16,38), ZIndex = 6 }, prev); refl.BackgroundTransparency = 0.5; corner(refl, 8)
		disc(prev, 20, 0.42, 0.6, rgb(120,220,255), 7).BackgroundTransparency = 0.55
		addTwinkle(disc(prev, 9, 0.42, 0.6, rgb(180,245,255), 8), 1.2)
	else
		corner(make("Frame", { BackgroundColor3 = rgb(44,26,22), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,1), Position = UDim2.new(0.5,0,0.87,0), Size = UDim2.fromOffset(172,54), ZIndex = 6 }, prev), 40)
		disc(prev, 52, 0.5, 0.5, rgb(255,130,40), 6).BackgroundTransparency = 0.25
		disc(prev, 26, 0.5, 0.5, rgb(255,220,120), 7)
		disc(prev, 20, 0.46, 0.16, rgb(70,60,64), 5).BackgroundTransparency = 0.3
		disc(prev, 26, 0.55, 0.12, rgb(60,52,56), 5).BackgroundTransparency = 0.35
		hero("🌋", 0.5, 0.52, 46)
		for i = 1, 5 do local e = disc(prev, math.random(4,8), 0, 0, rgb(255,150,60), 9); addFloater(e, 0.34+i*0.08, 0.62, 0.16, 0.1+math.random()*0.06) end
	end
end

local function isOwned(id) return id == 1 or plr:GetAttribute("Zone_" .. id) == true end
local function getCurrent() return plr:GetAttribute("CurrentZone") or 1 end
local function zoneState(id)
	if isOwned(id) then return (getCurrent() == id) and "active" or "owned" end
	if isOwned(id-1) then return "buy" end
	return "locked"
end
if plr:GetAttribute("CurrentZone") == nil then plr:SetAttribute("CurrentZone", 1) end
plr:SetAttribute("Zone_1", true)

local DEMO_BALANCE = 0 -- fallback only; the real balance is the shared leaderstats.Money
local cash = DEMO_BALANCE
local cashSource = nil
local refresh
local function bindCash()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then
		cashSource = m; cash = m.Value
		m.Changed:Connect(function(v) cash = v; if gui.Enabled then refresh() end end)
	end
end

local Terrain = workspace.Terrain
local atm = Lighting:FindFirstChildOfClass("Atmosphere") or make("Atmosphere", {}, Lighting)
local cc = Lighting:FindFirstChild("ZoneColorCorrection") or make("ColorCorrectionEffect", { Name = "ZoneColorCorrection" }, Lighting)
local function applyEnv(env, animate)
	local ti = TweenInfo.new(animate and 0.85 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(Lighting, ti, { ClockTime = env.clock, Brightness = env.brightness, ExposureCompensation = env.exposure, Ambient = env.ambient, OutdoorAmbient = env.outdoor }):Play()
	TweenService:Create(atm, ti, { Density = 0, --[[ 2.5D distances bleach at >0; mood comes from ambient/CC/backdrop ]] Haze = env.atmHaze, Glare = env.atmGlare, Color = env.atmColor, Decay = env.atmDecay }):Play()
	TweenService:Create(cc, ti, { TintColor = env.cc.tint, Saturation = env.cc.sat, Contrast = env.cc.con, Brightness = env.cc.bri }):Play()
	TweenService:Create(Terrain, ti, { WaterColor = env.water, WaterWaveSize = env.waveSize, WaterWaveSpeed = env.waveSpeed, WaterTransparency = env.waterTrans, WaterReflectance = env.waterRefl }):Play()
end

-- Swap the painted 2.5D backdrop: zone 1 uses Workspace.Zone1.Horizon, zones 2-6 use
-- Workspace.ZoneBackdrops.ZoneN. Client-side toggle so each player sees their own zone.
local function showBackdrop(id)
	local zone1 = workspace:FindFirstChild("Zone1")
	local horizon = zone1 and zone1:FindFirstChild("Horizon")
	if horizon then for _, d in ipairs(horizon:GetDescendants()) do if d:IsA("SurfaceGui") then d.Enabled = (id == 1) end end end
	local backdrops = workspace:FindFirstChild("ZoneBackdrops")
	if backdrops then
		for _, f in ipairs(backdrops:GetChildren()) do
			local on = (f.Name == "Zone" .. id)
			for _, d in ipairs(f:GetDescendants()) do if d:IsA("SurfaceGui") then d.Enabled = on end end
		end
	end
end

---------------------------------------------------------------- sizes (design px; the window scales with a UIScale)
-- DESIGN_H fits the header and two full rows of cards on a desktop (108 + 538 + 14). MIN_H is the shortest design
-- height MenuFit may give this layout on a small screen: one full card row under the header (nothing outside the
-- List pokes out at any height above the header's 108). Compact = a phone (short side < 500): its own header and
-- bigger card type, the window width chosen so one full card row fits under Roblox's top bar.
-- BoatsController carried the same COMPACT_S - keep the two menus in step if both are retuned.
local DESIGN_W, DESIGN_H = 1100, 660
local MIN_H, MIN_H_C = 392, 300
local COMPACT_S = 0.8
local L = {
	desk = {
		hh = 88, reach = 44, iconPos = V2(-36, -44), iconSize = 124,
		titleY = 2, titleH = 54, titleMax = 46, subY = 56, subH = 26, subMax = 19, pillY = 20,
		card = { h = 248, top = 8, vgap = 20, bottom = 8, side = 16, gap = 20, keyH = 48, tagH = 24, nameH = 34,
			nameMax = 26, tagMax = 18, word = 26, small = 24, price = 26, icon = 30 },
	},
	phone = {
		hh = 76, reach = 0, iconPos = V2(10, 3), iconSize = 70, -- the emoji tucked inside the header (see fit())
		titleY = 2, titleH = 46, titleMax = 40, subY = 48, subH = 24, subMax = 17, pillY = 14,
		card = { h = 252, top = 8, vgap = 18, bottom = 8, side = 12, gap = 16, keyH = 54, tagH = 26, nameH = 36,
			nameMax = 28, tagMax = 20, word = 28, small = 26, price = 28, icon = 34 },
	},
}
-- live state, grouped (Luau's 200-locals cap)
local Z = { compact = false, P = L.desk, listY = 0, listY0 = L.desk.hh + 20, canvasH = 0, flashUntil = 0, layoutKey = "" }

-- a scaled label's cap, on the label AND its hard drop (the drop is a clone with its own constraint)
local function setMax(l, n)
	for _, t in ipairs({ l, l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop") }) do
		local c = t and t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MinTextSize = math.min(c.MinTextSize, n)
			c.MaxTextSize = n
		end
	end
end

---------------------------------------------------------------- the window
-- the backdrop: a dark full-screen BUTTON under the window (a Frame would let the tap through and cast the rod
-- behind the menu) - a tap anywhere outside the window closes Zones
local backdrop = UI.new("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.4, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(4, 4), ZIndex = 1,
}, gui)
local win = UI.window(gui, "ZONES", {
	Name = "Window", w = DESIGN_W, h = DESIGN_H, emoji = "🗺️", headColour = "orange", headerH = L.desk.hh, ZIndex = 5,
})
local root = win.root
local uiscale = UI.new("UIScale", { Scale = 1 }, root)
-- the window catches its own taps (the Shop's ClickGuards): transparent buttons with no handler over the body and
-- its drop (ZIndex 3: over Shadow / Body, under the list, the title, the emoji and the X) and over the emoji.
-- Silent: SndHooked is set before they are parented, so AudioController leaves them alone.
local function clickGuard(parent, size, z)
	local b = UI.new("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, ZIndex = z,
	})
	b:SetAttribute("SndHooked", true)
	b.Parent = parent
	return b
end
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, 9), 3), 24)
if win.icon then clickGuard(win.icon, UDim2.new(1, 0, 1, 5), 20) end

-- the cash pill: your wallet in a gold key that is not pressable, left of the X (the Shop's)
Z.pill = UI.candyKey(root, "gold", {
	Name = "CashPill", static = true, Size = UDim2.fromOffset(196, 48), Position = UDim2.fromOffset(DESIGN_W - 96 - 196, L.desk.pillY), ZIndex = 7,
})
local function setCash(v)
	local s = UI.cash(v)
	local red = os.clock() < Z.flashUntil
	local key = s .. (red and "!" or "")
	if Z.cashShown == key then return end
	Z.cashShown = key
	Z.pill.setParts(nil, {
		{ icon = "coins", size = 40, drop = 0 },
		{ text = s, size = 28, o = 4, drop = 2, color = red and UI.TEXT.red or nil },
	}, { gap = 6 })
end
-- "Now fishing: ..." under the title
Z.sub = UI.label(root, "", {
	Name = "Sub", size = L.desk.subMax, align = "left", RichText = true, drop = 2, ZIndex = 8,
	Size = UDim2.fromOffset(680, L.desk.subH), Position = UDim2.fromOffset(116, L.desk.subY),
})

-- the list: a vertical scroll list under the header, its bar in a 10 px lane on the right (the Shop's thumb + track).
-- CanvasPosition is in SCREEN px, so a UIScale change (the open pop, a resize) would slide the cards under the view:
-- the list keeps its place in design px (Z.listY) and puts it back.
Z.track = UI.new("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	Position = UDim2.new(1, -28, 0, Z.listY0), Size = UDim2.new(0, 10, 1, -(Z.listY0 + 14)), ZIndex = 5,
}, root)
UI.corner(Z.track, 5)
Z.list = UI.new("ScrollingFrame", {
	Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, Z.listY0),
	Size = UDim2.new(1, -28, 1, -(Z.listY0 + 14)), ZIndex = 6, ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	VerticalScrollBarInset = Enum.ScrollBarInset.None, CanvasSize = UDim2.fromOffset(0, 538),
}, root)
local function listK()
	return math.max(Z.list.AbsoluteCanvasSize.Y / math.max(Z.list.CanvasSize.Y.Offset, 1), 1e-3)
end
local function scrollTo(y)
	local viewH = root.Size.Y.Offset - Z.listY0 - 14
	Z.listY = math.clamp(y, 0, math.max(Z.list.CanvasSize.Y.Offset - viewH, 0))
	Z.list.CanvasPosition = V2(0, Z.listY * listK())
end
Z.list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	Z.listY = Z.list.CanvasPosition.Y / listK()
end)
uiscale:GetPropertyChangedSignal("Scale"):Connect(function() scrollTo(Z.listY) end)

---------------------------------------------------------------- the toast (in the window, the Shop's)
Z.toastChip = UI.chip(root, "navy", {
	Name = "Toast", height = 50, textSize = 24, pad = 26, minWidth = 240, AnchorPoint = V2(0.5, 1), ZIndex = 40,
	Position = UDim2.new(0.5, 0, 1, -18),
})
Z.toastChip.block.root.Visible = false
Z.toastScale = UI.new("UIScale", {}, Z.toastChip.block.root)
-- colour: a UI.KEY name - "sea" travel, "gold" unlocked, "red" can't afford
local function showToast(text, colour)
	local c = Z.toastChip
	c.set(text, colour or "navy")
	c.block.root.Visible = true
	UI.punch(Z.toastScale, 0.6, 0.28)
	Z.toastToken = (Z.toastToken or 0) + 1
	local my = Z.toastToken
	task.delay(2.2, function()
		if Z.toastToken == my then c.block.root.Visible = false end
	end)
end

---------------------------------------------------------------- the cards
-- One candy card per zone in its own colour (UI.CANDY): an INK outline + hard drop + gloss cap, the zone's
-- animated scene in a framed preview (its number on a navy coin top-left, its benefit chip bottom-left, a lock
-- over it while it is locked), the name and tagline, and one key along the bottom whose colour is the STATE.
local cards, cardsById = {}, {}
local function makeCard(z)
	local e = { zone = z, clickable = false }
	e.root = UI.new("Frame", { Name = "ZoneCard" .. z.id, BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 248), ZIndex = 2 }, Z.list)
	e.scale = UI.new("UIScale", { Scale = 1 }, e.root)
	UI.hardShadow(e.root, 18, 4, 6, 1)
	e.face = UI.new("Frame", { Name = "Face", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, e.root)
	UI.corner(e.face, 18)
	UI.stroke(e.face, 4)
	UI.vgrad(e.face, UI.CANDY[CARD_COLOUR[z.id]] or UI.CANDY.blue)
	UI.gloss(e.face, { frac = 0.34, alpha = 0.55, inset = 4, radius = 14 })

	-- the preview: the zone's scene, framed
	e.prev = UI.new("Frame", {
		Name = "Preview", BackgroundColor3 = UI.WHITE, ClipsDescendants = true, Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(310, 114), ZIndex = 3,
	}, e.root)
	UI.corner(e.prev, 12)
	UI.stroke(e.prev, 3)
	UI.vgrad(e.prev, { z.prevTop, z.prevBot })
	grad(make("Frame", { BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, Size = UDim2.new(0.35,0,1.7,0), Position = UDim2.new(0.16,0,-0.35,0), Rotation = 18, ZIndex = 4 }, e.prev), Color3.new(1,1,1), Color3.new(1,1,1), 90).Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) })
	buildScene(e.prev, z)

	-- its number: a navy coin
	local num = UI.new("Frame", { Name = "Number", BackgroundColor3 = UI.WHITE, Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(7, 7), ZIndex = 12 }, e.prev)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, num)
	UI.stroke(num, 3)
	UI.vgrad(num, { UI.KEY.navy.hi, UI.KEY.navy.base })
	UI.label(num, tostring(z.id), { Name = "N", size = 20, ZIndex = 13 })
	-- its benefit: a chip (green = a coin bonus; sea for home waters)
	e.ben = UI.chip(e.prev, z.coin > 1 and "green" or "sea", {
		Name = "Benefit", height = 30, textSize = 17, pad = 12, minWidth = 40, lip = 5, radius = 12,
		AnchorPoint = V2(0, 1), Position = UDim2.new(0, 7, 1, -7), ZIndex = 10,
	})
	e.ben.block.root:FindFirstChildWhichIsA("UIStroke").Thickness = 3
	e.ben.set(z.benefit)
	-- the lock: hides the scene of a zone you cannot buy yet
	e.lock = UI.new("Frame", { Name = "Lock", BackgroundColor3 = UI.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 11, Visible = false }, e.prev)
	UI.corner(e.lock, 12)
	UI.vgrad(e.lock, { rgb(150, 164, 192), rgb(84, 98, 128) }) -- slate fog over the scene (no dark reef panels)
	local lockIcon = UI.icon(e.lock, "lock", 58, { Name = "LockIcon", flat = true, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 13 })
	UI.iconDrop(lockIcon, 4, 0.5)

	-- the NEXT sticker (the zone you can buy now), breaking out of the card's top-right corner
	e.next = UI.sticker(e.root, "gold", "NEXT", {
		Name = "Next", Position = UDim2.fromOffset(296, 14), Rotation = 8, height = 32, textSize = 17, ZIndex = 12,
	})
	e.next.block.root.Visible = false

	e.nameLbl = UI.label(e.root, z.name, {
		Name = "ZoneName", size = 26, drop = 2, ZIndex = 7, Size = UDim2.fromOffset(306, 34), Position = UDim2.fromOffset(12, 126),
	})
	e.tagLbl = UI.label(e.root, z.tagline, {
		Name = "Tagline", size = 18, color = UI.TEXT.soft, drop = 2, ZIndex = 7, Size = UDim2.fromOffset(306, 24), Position = UDim2.fromOffset(12, 158),
	})
	-- the zone you are fishing in: a gold band just inside the outline (ShopKit's owned ring)
	e.ring = UI.new("Frame", {
		Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 9, Visible = false,
	}, e.root)
	UI.corner(e.ring, 14)
	UI.stroke(e.ring, 4, UI.RING)

	-- the key: the card's one action (UNLOCK / TRAVEL); its colour is the state
	e.key = UI.candyKey(e.root, "grey", {
		Name = "Action", Size = UDim2.fromOffset(310, 48), Position = UDim2.fromOffset(10, 186), ZIndex = 10,
	})
	TouchKit.press(e.key.button, function() if e.onClick then e.onClick() end end)
	-- the Robux key, beside the coin key while the zone is still to buy (refresh sizes and shows it)
	e.rbx = UI.candyKey(e.root, "grey", {
		Name = "Robux", Size = UDim2.fromOffset(110, 48), Position = UDim2.fromOffset(210, 186), ZIndex = 10,
	})
	e.rbx.button.Visible = false
	TouchKit.press(e.rbx.button, function() if e.onRobux then e.onRobux() end end)

	cards[#cards+1] = e; cardsById[z.id] = e
	return e
end
for _, z in ipairs(ZONES) do makeCard(z) end

-- one card's insides at width cw (C = the layout's card sizes), laid bottom-up: key, tagline, name, preview
local function layoutCard(e, cw, C)
	local keyY = C.h - 14 - C.keyH
	local tagY = keyY - 4 - C.tagH
	local nameY = tagY - C.nameH + 2
	e.cw = cw
	e.root.Size = UDim2.fromOffset(cw, C.h)
	e.prev.Size = UDim2.fromOffset(cw - 20, nameY - 12)
	e.nameLbl.Position = UDim2.fromOffset(12, nameY)
	e.nameLbl.Size = UDim2.fromOffset(cw - 24, C.nameH)
	setMax(e.nameLbl, C.nameMax)
	e.tagLbl.Position = UDim2.fromOffset(12, tagY)
	e.tagLbl.Size = UDim2.fromOffset(cw - 24, C.tagH)
	setMax(e.tagLbl, C.tagMax)
	e.key.button.Position = UDim2.fromOffset(10, keyY)
	e.key.button.Size = UDim2.fromOffset(cw - 20, C.keyH)
	-- (this resets the coin key to the FULL row, so make refresh() lay the row out again - split beside the Robux
	-- key while a zone is still to buy. Its signature does not change on a re-open, so without this the full-width
	-- coin / LOCKED key stayed UNDER the Robux key.)
	e.sig = nil
	e.next.block.root.Position = UDim2.fromOffset(cw - 34, 14)
end

-- The whole window at design width w. compact == false is the desktop / iPad layout (1100 wide, 3 x 2 cards, both
-- rows on screen); compact == true is the phone reflow (its own header, bigger card type, 2 or 3 columns).
local function layoutFor(compact, w)
	local P = compact and L.phone or L.desk
	Z.P = P
	local hh = P.hh
	win.header.Size = UDim2.new(1, 0, 0, hh)
	win.ocean.Position = UDim2.fromOffset(0, hh)
	win.ocean.Size = UDim2.new(1, 0, 1, -hh)
	win.crest.Position = UDim2.fromOffset(0, hh)
	-- the wave crest was built for 1100: re-space it for this width (ShopKit's rule: discs touching, centred)
	local D = 26
	local n = math.ceil((w - 10) / D)
	local x0 = (w - n * D) / 2
	local i = 0
	for _, d in ipairs(win.crest:GetChildren()) do
		if d:IsA("Frame") then
			d.Visible = i < n
			d.Position = UDim2.fromOffset(x0 + i * D, -1)
			i += 1
		end
	end
	if win.icon then
		win.icon.Size = UDim2.fromOffset(P.iconSize, P.iconSize)
		win.icon.Position = UDim2.fromOffset(P.iconPos.X, P.iconPos.Y)
	end
	local pillX = w - 96 - 196
	Z.pill.button.Position = UDim2.fromOffset(pillX, P.pillY)
	local tw = pillX - 12 - 112
	win.title.Position = UDim2.fromOffset(112, P.titleY)
	win.title.Size = UDim2.fromOffset(tw, P.titleH)
	setMax(win.title, P.titleMax)
	Z.sub.Position = UDim2.fromOffset(116, P.subY)
	Z.sub.Size = UDim2.fromOffset(tw - 4, P.subH)
	setMax(Z.sub, P.subMax)

	local listY = hh + 20
	Z.listY0 = listY
	Z.list.Position = UDim2.fromOffset(10, listY)
	Z.list.Size = UDim2.new(1, -28, 1, -(listY + 14))
	Z.track.Position = UDim2.new(1, -28, 0, listY)
	Z.track.Size = UDim2.new(0, 10, 1, -(listY + 14))

	local C = P.card
	local inner = (w - 28) - 10 -- the list minus its scroll lane
	local cols = compact and (w >= 1000 and 3 or 2) or 3
	local cw = math.floor((inner - 2 * C.side - (cols - 1) * C.gap) / cols)
	local cx0 = math.floor((inner - (cols * cw + (cols - 1) * C.gap)) / 2)
	for idx, e in ipairs(cards) do
		local col, row = (idx - 1) % cols, (idx - 1) // cols
		e.root.Position = UDim2.fromOffset(cx0 + col * (cw + C.gap), C.top + row * (C.h + C.vgap))
		layoutCard(e, cw, C)
	end
	local rows = math.ceil(#cards / cols)
	Z.canvasH = C.top + rows * C.h + (rows - 1) * C.vgap + 6 + C.bottom
	Z.list.CanvasSize = UDim2.fromOffset(0, Z.canvasH)
	-- the keys re-lay their parts at the new width on the next refresh
	Z.layoutKey = (compact and "C" or "D") .. cw
	Z.laid = true
end

-- The screen, in this gui's space (IgnoreGuiInset), and the first row below Roblox's top bar.
local function screen()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return nil end
	local abs = gui.AbsoluteSize
	local ch = (abs.Y > 100 and abs.Y < vp.Y) and abs.Y or vp.Y
	local bar = GuiService.TopbarInset.Max.Y
	local top = (bar > 0 and bar or 58) + 4
	return vp, ch, top
end

-- After MenuFit: the emoji breaks P.reach design px out of the window's top and the drop hangs 9 below, which
-- MenuFit does not know about - centred as it leaves it, a 751-tall desktop put the emoji 20 px above the screen and
-- under Roblox's top-left buttons. So keep that reach below the top bar (the Shop's rule): move the window if it
-- fits; otherwise, on MenuFit's small-screen band, trade design HEIGHT (the list just shows less, as MenuFit
-- itself does - never below minH), and on a roomy screen shrink it just enough to keep both card rows whole.
local function settle(P, minH)
	local vp, ch, top = screen()
	if not vp then return end
	local s = uiscale.Scale
	if s <= 0 then return end
	local h = root.Size.Y.Offset
	local up, down = P.reach, 9
	local room = ch - 8 - top
	local cy = root.Position.Y.Scale * ch + root.Position.Y.Offset
	if (h + up + down) * s > room then
		if root.Position.Y.Scale == 0 then
			local h2 = math.floor(room / s - up - down)
			if h2 >= minH then
				h = math.min(h2, h)
			else
				h = minH
				s = room / (h + up + down)
			end
		else
			s = room / (h + up + down)
		end
		s = math.max(s, 0.1)
		root.Size = UDim2.fromOffset(root.Size.X.Offset, h)
		uiscale.Scale = s
		cy = top + up * s + h * s / 2 + math.max(room - (h + up + down) * s, 0) / 2
	else
		cy = math.clamp(cy, top + (h / 2 + up) * s, ch - 8 - (h / 2 + down) * s)
	end
	root.Position = UDim2.new(0.5, 0, 0, math.floor(cy + 0.5))
end

-- Shared fit (MenuFit): on a small screen it makes the window SHORTER rather than smaller, so the WIDTH drives the
-- scale, and centres it below the Roblox top bar. PHONES (short side < 500) get a reflow instead of the shrunken
-- desktop window: the design WIDTH is chosen so one full card row (under the compact header, with the emoji's
-- reach) fits at no more than COMPACT_S, and the cards reflow to 2-3 columns of bigger type (layoutFor).
-- Re-run on every open and viewport change.
local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then
		-- no screen yet (boot): lay the cards out at the desktop size anyway; the open re-fits
		if not Z.laid then layoutFor(false, DESIGN_W) end
		return
	end
	Z.compact = math.min(vp.X, vp.Y) < 500
	if Z.compact then
		-- CENTRED ON THE PHONE SCREEN (2026-10-11, the owner: "make the button uis centered to the phone screen"): the
		-- emoji is tucked into the header (L.phone, reach 0) and MenuFit.centre places the window. Centred, it gives up
		-- the top bar's height at BOTH ends, so the width and the design height traded for it (settle()'s job below the
		-- bar, never under one whole card row here) are budgeted for that band - the window stays as wide as before.
		local P = L.phone
		local _, ch, top = screen()
		local up, down = P.reach, 9
		local rowH = P.hh + 20 + P.card.top + P.card.h + 6 + P.card.bottom + 14 -- the header + one whole card row
		local s = math.max(math.min(COMPACT_S, (ch - 2 * top) / (rowH + 2 * up), (ch - 12) / (rowH + 2 * down)), 0.3)
		local w = math.clamp(math.floor(vp.X / s) - 50, 640, DESIGN_W)
		layoutFor(true, w)
		MenuFit.apply(root, uiscale, w, DESIGN_H, 0.4, 1.1, MIN_H_C)
		s = uiscale.Scale
		local h = root.Size.Y.Offset
		local fitH = math.floor(math.min((ch / 2 - top) / s - up, (ch / 2 - 6) / s - down) * 2)
		root.Size = UDim2.fromOffset(root.Size.X.Offset, math.max(math.min(h, fitH), math.min(h, rowH), MIN_H_C))
		MenuFit.centre(root, uiscale, up, down)
	else
		layoutFor(false, DESIGN_W)
		MenuFit.apply(root, uiscale, DESIGN_W, DESIGN_H, 0.4, 1.1, MIN_H)
		settle(L.desk, MIN_H)
		MenuFit.centre(root, uiscale, L.desk.reach, 9)   -- centred on the screen
	end
	Z.track.Visible = Z.canvasH > root.Size.Y.Offset - Z.listY0 - 14 + 1
	scrollTo(Z.listY)
end

---------------------------------------------------------------- the sea behind the cards (the Shop's)
-- light rays and rising bubbles in the window's Ocean layer: only the gaps between cards show them.
do
	local ocean = win.ocean
	Z.rays, Z.bubbles = {}, {}
	for i, x in ipairs({ 0.1, 0.3, 0.52, 0.74, 0.92 }) do
		local ray = UI.new("Frame", {
			Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 56 + (i % 2) * 34, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, ocean)
		UI.new("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(Z.rays, { f = ray, phase = i * 1.3 })
	end
	for i = 1, 24 do
		local s = 6 + (i * 7) % 13
		local b = UI.new("Frame", {
			Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = V2(0.5, 0.5),
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, ocean)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		UI.new("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		table.insert(Z.bubbles, { f = b, x = ((i * 0.618) % 1), y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i })
	end
	for _, b in ipairs(Z.bubbles) do b.f.Position = UDim2.new(b.x, 0, b.y, 0) end
end

fit()

---------------------------------------------------------------- travel and buy (unchanged rules)
local function pop(id)
	local e = cardsById[id]; if not e then return end
	UI.punch(e.scale, 1.06, 0.3)
end
local function travelTo(id)
	local z = ZONE_BY_ID[id]; if not z then return end
	plr:SetAttribute("CurrentZone", id)
	plr:SetAttribute("ZoneCoinMult", z.coin)
	plr:SetAttribute("ZoneName", z.name)
	applyEnv(z.env, true)
	showBackdrop(id)
	refresh(); pop(id)
	showToast("🌊 Traveled to " .. z.name, "sea")
end
local function buy(id)
	local z = ZONE_BY_ID[id]; if not z or isOwned(id) then return end
	if Z.robuxPending == id then return end   -- a Robux purchase of this zone is going through
	if not isOwned(id-1) then return end
	if cash < z.cost then
		showToast("Not enough coins!", "red")
		-- the wallet flashes red for a moment
		Z.flashUntil = os.clock() + 0.6
		setCash(cash)
		UI.punch(Z.pill.scale, 1.12, 0.3)
		task.delay(0.65, function() setCash(cash) end)
		return
	end
	cash = cash - z.cost
	if cashSource then pcall(function() cashSource.Value = cash end) end
	plr:SetAttribute("Zone_" .. id, true)
	travelTo(id)
	showToast("🔓 Unlocked " .. z.name .. "!", "gold")
end
for _, entry in ipairs(cards) do
	local z = entry.zone
	entry.onClick = function()
		local st = zoneState(z.id)
		if st == "buy" then buy(z.id) elseif st == "owned" then travelTo(z.id) end
	end
	entry.onRobux = function()
		local st = zoneState(z.id)
		if st == "locked" then
			local prev = ZONE_BY_ID[z.id - 1]
			showToast("Unlock " .. (prev and prev.name or "the previous zone") .. " first", "red")
			return
		end
		if st ~= "buy" then return end
		-- one Robux purchase at a time: between the prompt closing and ZoneGranted arriving the card still says
		-- "buy", and a second tap would charge again
		if Z.robuxPending then showToast("Finishing your purchase...", "gold"); return end
		local pid = tonumber(ShopProducts.productId("zone", z.id)) or 0
		if pid <= 0 then
			showToast(z.name .. ": Robux purchase isn't set up yet", "gold")
			return
		end
		Z.robuxPending = z.id
		task.delay(30, function() if Z.robuxPending == z.id then Z.robuxPending = nil end end)
		local ok, err = pcall(function() MarketplaceService:PromptProductPurchase(plr, pid) end)
		if not ok then
			Z.robuxPending = nil
			warn("[Zones] PromptProductPurchase failed:", err)
			showToast("Couldn't open the purchase prompt", "red")
		end
	end
end

-- a Robux receipt, granted by ProductServer: applied exactly like a coin purchase (Zone_<id>, then travel there)
task.spawn(function()
	local rem = ReplicatedStorage:WaitForChild("ShopRemotes", 30)
	local ev = rem and rem:WaitForChild("ZoneGranted", 30)
	if not ev then return end
	-- restore = true: a zone bought in an earlier session, re-sent at join (ProductServer, ZonesBought_v1) - unlocked
	-- quietly. A zone bought with Robux is PAID for: it is kept through a rebirth (resetZones skips Z.paid).
	ev.OnClientEvent:Connect(function(kind, key, _, restore)
		local id = tonumber(key)
		local z = id and ZONE_BY_ID[id]
		if kind ~= "zone" or not z then return end
		Z.paid = Z.paid or {}
		Z.paid[id] = true
		if Z.robuxPending == id then Z.robuxPending = nil end
		if isOwned(id) then refresh(); return end   -- a re-sent receipt: no second "Unlocked!", no teleport
		plr:SetAttribute("Zone_" .. id, true)
		if restore then refresh(); return end
		travelTo(id)
		showToast("🔓 Unlocked " .. z.name .. "!", "gold")
	end)
end)
-- a closed or cancelled prompt frees the card again
MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, pid, purchased)
	if purchased or not Z.robuxPending then return end
	if pid == (tonumber(ShopProducts.productId("zone", Z.robuxPending)) or 0) then Z.robuxPending = nil end
end)

-- Cards are re-dressed only when their state (or the layout) changes: the money tick calls this on every sale.
function refresh()
	setCash(cash)
	local cur = ZONE_BY_ID[getCurrent()] or ZONES[1]
	Z.sub.Text = 'Now fishing: <font color="#FFDE50">' .. cur.name .. '</font>'
		.. (Z.compact and "" or "   \u{00B7}   unlock zones in order for bigger rewards")
	local C = Z.P.card
	for _, e in ipairs(cards) do
		local z = e.zone
		local st = zoneState(z.id)
		local locked = (st == "locked")
		local afford = cash >= z.cost
		e.clickable = (st == "buy" or st == "owned")
		local sig = st .. "|" .. tostring(st == "buy" and afford) .. "|" .. Z.layoutKey
		if e.sig ~= sig then
			e.sig = sig
			e.lock.Visible = locked
			e.ben.block.root.Visible = not locked
			e.next.block.root.Visible = (st == "buy")
			e.ring.Visible = (st == "active")
			UI.vgrad(e.face, locked and LOCKED_FACE or (UI.CANDY[CARD_COLOUR[z.id]] or UI.CANDY.blue))
			if locked then
				e.nameLbl.Text = "? ? ?"
				e.tagLbl.Text = "Unlock the previous zone first"
			else
				e.nameLbl.Text = z.name
				e.tagLbl.Text = z.tagline
			end
			-- the key row: the coin key alone, or split with the Robux key while the zone is still to buy
			local split = (st == "buy" or st == "locked")
			local full = (e.cw or 330) - 20
			local rw = split and math.floor(full * 0.36) or 0
			e.key.button.Size = UDim2.fromOffset(split and (full - rw - 8) or full, C.keyH)
			e.rbx.button.Visible = split
			if split then
				e.rbx.button.Size = UDim2.fromOffset(rw, C.keyH)
				e.rbx.button.Position = UDim2.fromOffset(10 + full - rw, e.key.button.Position.Y.Offset)
				local live = (tonumber(ShopProducts.productId("zone", z.id)) or 0) > 0
				e.rbx.recolour((st == "buy" and live) and "pink" or "grey")
				e.rbx.setParts(nil, {
					{ icon = "robux", size = C.icon },
					{ text = tostring(ShopProducts.ZONE_ROBUX and ShopProducts.ZONE_ROBUX[z.id] or "?"), size = C.price, gap = 6 },
				})
			end
			local k = e.key
			if st == "active" then
				k.recolour("gold")
				k.setParts(nil, { { icon = "check", size = C.icon }, { text = "FISHING HERE", size = C.small } }, { gap = 8 })
			elseif st == "owned" then
				k.recolour("sea")
				k.setParts(nil, { { text = "TRAVEL", size = C.word } })
			elseif st == "buy" then
				k.recolour(afford and "green" or "grey")
				-- coin + price (the word UNLOCK made way for the Robux key; the rods' coin keys read the same)
				k.setParts(nil, {
					{ icon = "coins", size = C.icon + 4, drop = 0 },
					{ text = UI.cash(z.cost), size = C.price, color = afford and UI.TEXT.gold or UI.TEXT.red, gap = 6 },
				})
			else
				k.recolour("grey")
				k.setParts(nil, { { icon = "lock", size = C.icon - 2 }, { text = "LOCKED", size = C.word } }, { gap = 8 })
			end
		end
	end
end

---------------------------------------------------------------- animation (one loop, idle while closed / Menu Animations off)
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	if plr:GetAttribute("Set_MenuFX") == false then return end   -- Settings > Menu Animations
	local t = os.clock()
	for _, b in ipairs(Z.bubbles) do
		b.y -= b.speed * dt
		if b.y < -0.05 then
			b.y = 1.05
			b.x = (b.x + 0.37) % 1
		end
		b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
	end
	for _, r in ipairs(Z.rays) do
		r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
	end
	for _, fl in ipairs(floaters) do
		local prog = ((t*fl.speed) + fl.phase) % 1
		local y = fl.startY + (fl.endY - fl.startY) * prog
		fl.inst.Position = UDim2.new(fl.sx + math.sin(prog*6.28 + fl.phase*6) * 0.02, 0, y, 0)
	end
	for _, tw in ipairs(twinklers) do
		tw.inst.BackgroundTransparency = 0.12 + 0.5 * (0.5 + 0.5*math.sin(t*tw.speed*4 + tw.phase))
	end
	for _, h in ipairs(heroes) do
		h.inst.Position = UDim2.new(h.sx, 0, h.baseY + 0.025*math.sin(t*1.8 + h.phase), 0)
	end
end)

---------------------------------------------------------------- open / close
local function close() gui.Enabled = false end
TouchKit.press(win.close.button, close)
TouchKit.press(backdrop, close)
plr:GetAttributeChangedSignal("CurrentZone"):Connect(function() if gui.Enabled then refresh() end end)

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
		fit(); refresh(); setInventoryHidden(true)
		Z.toastChip.block.root.Visible = false
		scrollTo(0)
		local targetScale = uiscale.Scale
		uiscale.Scale = targetScale * 0.9
		TweenService:Create(uiscale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetScale }):Play()
	else
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

-- A rebirth washes away zone progress along with the cash that bought it: every zone
-- but Lighthouse Cove re-locks and you are put back in home waters, so the ladder is
-- climbed again on the new Tide Current multiplier.
-- Driven off the Rebirths ATTRIBUTE rather than RebirthRemotes, because the attribute is
-- what RebirthController actually commits - the remotes are fired best-effort inside a
-- pcall and the BindableEvent only exists if something else made it. Reacting to the
-- attribute also means any other path that grants a rebirth resets zones for free.
local function resetZones()
	for _, z in ipairs(ZONES) do
		-- (a zone bought with Robux is kept: it was paid for, see ZoneGranted)
		if z.id ~= 1 and not (Z.paid and Z.paid[z.id]) then plr:SetAttribute("Zone_" .. z.id, nil) end
	end
	travelTo(1)   -- reverts env, backdrop, ZoneCoinMult and the card states in one go
	showToast("\240\159\140\138 The tide reset your zones", "gold")
end

local lastRebirths = plr:GetAttribute("Rebirths") or 0
plr:GetAttributeChangedSignal("Rebirths"):Connect(function()
	local n = plr:GetAttribute("Rebirths") or 0
	-- only on a genuine rebirth, never on a load/rollback that lowers the count
	if n > lastRebirths then resetZones() end
	lastRebirths = n
end)

local devHook = gui:FindFirstChild("DevZone") or make("BindableEvent", { Name = "DevZone" }, gui)
devHook.Event:Connect(function(arg)
	if arg == "__ALL__" then
		for _, z in ipairs(ZONES) do if z.id ~= 1 then plr:SetAttribute("Zone_" .. z.id, true) end end
		refresh()
	elseif typeof(arg) == "number" and ZONE_BY_ID[arg] then
		plr:SetAttribute("Zone_" .. arg, true); travelTo(arg)
	end
end)

bindCash()
plr.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then task.wait(0.2); bindCash(); if gui.Enabled then refresh() end end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit(); refresh() end end)
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function() if gui.Enabled then fit(); refresh() end end)

travelTo(getCurrent())
refresh()
print("[Zones] candy built - " .. #ZONES .. " zones, scenes+locks, current = " .. (ZONE_BY_ID[getCurrent()] or ZONES[1]).name)
