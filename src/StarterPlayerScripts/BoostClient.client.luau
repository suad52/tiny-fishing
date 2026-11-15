--[[
	BoostClient — makes the consumables actually DO something.

	Before this, every potion and the Jackpot Cast were decorative. ShopController.useItem and
	InventoryController.useBoost both decremented Inv_<key>, fired a ShopRemotes.UseItem that
	NOTHING on the server listens to, and toasted "activated!". GameClient contained zero
	references to Inv_, potion, jackpot or boost - so winning Luck or Jackpot on the wheel, or
	buying one in the shop, or claiming one from Daily, all did exactly nothing. Same failure
	as the Pearl Reef perks: a number written and never read.

	THE SEAM is the house one - this publishes derived attributes and GameClient reads them,
	exactly like BaitLuck / BaitValueMult / BaitHaste already do:
	    BoostLuck       additive, joins the luck sum in speciesForDepth
	    BoostValueMult  multiplies in valueOf
	    BoostHaste      multiplies the hook's descent
	    BoostReelMult   multiplies the reel
	    BoostFinish     multiplies the rare-finish chance in rollVariant
	    JackpotCasts    banked charges; startCast spends one and sets JackpotActive

	ONE OWNER. Both use paths fire ReplicatedStorage.BoostRemotes.Activate and this script is
	the only thing that decides what a boost means or when it ends - the alternative was the
	same durations and magnitudes copy-pasted into two controllers.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")

local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local INK = rgb(8,22,44)

----------------------------------------------------------------------
-- what each consumable does
----------------------------------------------------------------------
-- Magnitudes are sized against the systems they join, not picked out of the air:
--   luck 0.60 is what the WHOLE Luck branch gives at 20 tiers (20 x 0.03), so a potion is
--     "a maxed luck tree for ten minutes"
--   value 1.5 sits between a Rare bait (+40%) and an Epic one (+80%)
--   haste / reel 1.6 are a little over the maxed Reel branch (+100% is 2.0)
-- ⚠️ DURATIONS ARE THE BLURBS' PROMISE. InventoryController says "for 10 minutes" on all
-- four potions; if that text changes, change this with it.
local DUR = 600
local BOOSTS = {
	potion_luck  = { name = "Luck Potion",  icon = "\240\159\141\128", tint = rgb(92,220,96),
	                 dur = DUR, add = { BoostLuck = 0.60 }, mul = { BoostFinish = 2 } },
	potion_cast  = { name = "Cast Speed",   icon = "\226\154\161",     tint = rgb(255,190,58),
	                 dur = DUR, mul = { BoostReelMult = 1.6 } },
	potion_bite  = { name = "Hook Speed",   icon = "\240\159\142\163", tint = rgb(252,92,100),
	                 dur = DUR, mul = { BoostHaste = 1.6 } },
	potion_money = { name = "Money Potion", icon = "\240\159\146\176", tint = rgb(240,202,84),
	                 dur = DUR, mul = { BoostValueMult = 1.5 } },
	-- Not timed: a CHARGE, spent by the next cast. See GameClient.startCast.
	jackpot      = { name = "Jackpot Cast", icon = "\240\159\140\159", tint = rgb(120,150,250),
	                 charge = true },
}

-- every attribute this script owns, and its value when nothing is active
local IDENTITY = { BoostLuck = 0, BoostFinish = 1, BoostValueMult = 1, BoostHaste = 1, BoostReelMult = 1 }

----------------------------------------------------------------------
-- the clock
----------------------------------------------------------------------
local active = {}   -- [key] = expiry, in os.clock() seconds

local function publish()
	local out = {}
	for k, v in pairs(IDENTITY) do out[k] = v end
	local now = os.clock()
	for key, till in pairs(active) do
		if till > now then
			local def = BOOSTS[key]
			if def then
				for a, v in pairs(def.add or {}) do out[a] = out[a] + v end
				for a, v in pairs(def.mul or {}) do out[a] = out[a] * v end
			end
		end
	end
	-- game passes (the Shop publishes Pass_<id> = true when Roblox says you own one): permanent, on top of any potion
	if plr:GetAttribute("Pass_luck") == true then out.BoostLuck += 0.30; out.BoostFinish *= 2 end
	if plr:GetAttribute("Pass_money") == true then out.BoostValueMult *= 2 end
	if plr:GetAttribute("Pass_cast") == true then out.BoostReelMult *= 2 end
	if plr:GetAttribute("Pass_bite") == true then out.BoostHaste *= 2 end
	for a, v in pairs(out) do plr:SetAttribute(a, v) end
end

-- ⚠️ A SECOND POTION EXTENDS, IT DOES NOT STACK. Two Luck Potions giving +1.20 luck for ten
-- minutes is a different and much larger promise than the blurb makes; twenty minutes of the
-- advertised effect is the one players expect and the one the economy was not tuned against.
local function activate(key)
	local def = BOOSTS[key]
	if not def then return false end
	if def.charge then
		plr:SetAttribute("JackpotCasts", (plr:GetAttribute("JackpotCasts") or 0) + 1)
		return true
	end
	local now = os.clock()
	active[key] = math.max(active[key] or 0, now) + def.dur
	publish()
	return true
end

----------------------------------------------------------------------
-- activation seam: both use paths fire this
----------------------------------------------------------------------
local folder = ReplicatedStorage:FindFirstChild("BoostRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "BoostRemotes"
	folder.Parent = ReplicatedStorage
end
local activateEv = folder:FindFirstChild("Activate")
if not activateEv then
	activateEv = Instance.new("BindableEvent")
	activateEv.Name = "Activate"
	activateEv.Parent = folder
end
activateEv.Event:Connect(function(key) activate(key) end)
-- a pass bought (or found owned on join) takes effect at once
for _, k in ipairs({ "Pass_luck", "Pass_money", "Pass_cast", "Pass_bite" }) do
	plr:GetAttributeChangedSignal(k):Connect(publish)
end
publish()

----------------------------------------------------------------------
-- HUD: one pill per live boost
----------------------------------------------------------------------
-- WHERE depends on the HUD mode RollerController publishes (BaitRoller.HudMode, HUD_CONTRACT L5):
--   desktop  down the left of the play channel, under the RewardsHUD cluster (today's pills)
--   tablet   the same pills, directly ABOVE the stats, stacking upward
--   phone    a 2-wide grid of 72x22 chips in the LEFT LANE, directly above the stats - icon and
--            time only. The lane stops at the notice slot (AfkHUD.NoticeTop); if the chips would
--            cross it, the rows that fit are shown and the last chip reads "+N".
-- The Boosts frame always hugs its CONTENT: GameClient reads its rect to keep the cast hint clear,
-- and the old fixed 190x240 box claimed space nothing was drawn in.
-- Rects are LOCAL px: every HUD gui is IgnoreGuiInset + DeviceSafeInsets, so all of them share the
-- safe area's top-left as origin, and local = AbsolutePosition - that gui's AbsolutePosition.
local gui = Instance.new("ScreenGui")
gui.Name = "BoostHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 14
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg

local strip = Instance.new("Frame")
strip.Name = "Boosts"
strip.BackgroundTransparency = 1
strip.Size = UDim2.fromOffset(186, 30)
strip.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = strip
-- the phone grid, swapped in for `layout` while the HUD is in phone mode
local CHIP_W, CHIP_H, CHIP_GAP = 72, 22, 4
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(CHIP_W, CHIP_H)
grid.CellPadding = UDim2.fromOffset(CHIP_GAP, CHIP_GAP)
grid.FillDirection = Enum.FillDirection.Horizontal
grid.FillDirectionMaxCells = 2
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
local gridOn = false

-- a FIXED order, so pills never shuffle as their timers tick: the jackpot charge first
local ORDER = { "jackpot", "potion_luck", "potion_money", "potion_cast", "potion_bite" }

local pills = {}
local function pillFor(key)
	if pills[key] then return pills[key] end
	local def = BOOSTS[key]
	local f = Instance.new("Frame")
	f.Name = key
	f.BackgroundColor3 = rgb(18, 62, 116)
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(186, 30)
	f.Parent = strip
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 999); c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = INK; s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border   -- Border, not Contextual: see ProgressHUD
	s.Parent = f
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -16, 1, -8)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = def and def.tint or rgb(220, 232, 250)   -- no def: the phone's "+N" chip
	l.Text = ""
	l.Parent = f
	local ls = Instance.new("UIStroke")
	ls.Color = INK; ls.Thickness = 2.5
	ls.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ls.Parent = l
	pills[key] = { frame = f, label = l, stroke = s, textStroke = ls, phone = false }
	return pills[key]
end

-- chip (phone) vs pill (tablet / desktop) dressing; touches nothing unless it flips
local function dress(p, phone)
	if p.phone == phone then return end
	p.phone = phone
	p.stroke.Thickness = phone and 2 or 3
	p.textStroke.Thickness = phone and 1.5 or 2.5
	p.label.TextScaled = not phone
	p.label.TextSize = 12
	p.label.Size = phone and UDim2.new(1, -6, 1, 0) or UDim2.new(1, -16, 1, -8)
end

-- W,H and the shared HUD origin, read off a gui that is surely enabled (this one is not while no
-- boost is live, and a disabled gui's rects are not to be trusted)
local function frame()
	for _, n in ipairs({ "MainMenu", "BaitRoller", "StatsHUD" }) do
		local g = pg:FindFirstChild(n)
		if g and g:IsA("ScreenGui") and g.Enabled and g.AbsoluteSize.X > 1 then
			return g.AbsoluteSize, g.AbsolutePosition
		end
	end
	local cam = workspace.CurrentCamera
	local inset = game:GetService("GuiService"):GetGuiInset()
	return (cam and cam.ViewportSize or Vector2.new(1280, 720)), Vector2.new(0, -inset.Y)
end

local function hudMode(size)
	local br = pg:FindFirstChild("BaitRoller")
	local m = br and br:GetAttribute("HudMode")
	if m == "phone" or m == "tablet" or m == "desktop" then return m end
	return (math.min(size.X, size.Y) < 500) and "phone" or "desktop"
end

-- Positions the strip for mode m; returns how many chips fit (phone) or math.huge.
local function place(m, size, O)
	local lr = 10
	local rp = pg:FindFirstChild("BaitRoller")
	rp = rp and rp:FindFirstChild("Panel")
	if rp and rp.Visible and rp.AbsoluteSize.X > 4 then lr = rp.AbsolutePosition.X - O.X + rp.AbsoluteSize.X end
	if m == "desktop" then
		-- ⚠️ MEASURE THE CLUSTER'S DESCENDANTS, NOT ITS AbsoluteSize. The RewardsHUD cluster's own
		-- rect stops above its "CLAIM!" / "SPIN!" captions and the timer chip, which hang BELOW it -
		-- so trusting AbsoluteSize.Y put the first boost pill straight through the SPIN button.
		local y = 150
		local rh = pg:FindFirstChild("RewardsHUD")
		local cl = rh and rh:FindFirstChild("Cluster")
		if cl and cl.Visible then
			local bottom = cl.AbsolutePosition.Y + cl.AbsoluteSize.Y
			for _, d in ipairs(cl:GetDescendants()) do
				if d:IsA("GuiObject") and d.Visible and d.AbsoluteSize.Y > 2 then
					bottom = math.max(bottom, d.AbsolutePosition.Y + d.AbsoluteSize.Y)
				end
			end
			y = bottom + 16
		end
		-- ⚠⚠ OUT OF ABSOLUTE SPACE. AbsolutePosition's origin is the bottom of the topbar; this gui's
		-- is the safe area's top-left (O). Writing an absolute Y straight into Position put the strip
		-- 58px up, through the SPIN button - exactly what it looked like.
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Position = UDim2.fromOffset(math.floor(lr + 14), math.floor(y - O.Y))
		return math.huge
	end
	-- phone / tablet: directly above the stats
	local statsTop = size.Y - 8
	local sh = pg:FindFirstChild("StatsHUD")
	local st = sh and sh:FindFirstChild("Stats")
	if st and st.AbsoluteSize.Y > 2 then statsTop = st.AbsolutePosition.Y - O.Y end
	strip.AnchorPoint = Vector2.new(0, 1)
	if m == "tablet" then
		strip.Position = UDim2.fromOffset(math.floor(lr + 12 + 0.5), math.floor(statsTop - 6 + 0.5))
		return math.huge
	end
	local bottom = statsTop - CHIP_GAP
	strip.Position = UDim2.fromOffset(math.floor(lr + 8 + 0.5), math.floor(bottom + 0.5))
	local ah = pg:FindFirstChild("AfkHUD")
	local noticeTop = ah and ah:GetAttribute("NoticeTop")
	if type(noticeTop) ~= "number" then noticeTop = 0.45 * size.Y end
	local rows = math.floor((bottom - noticeTop + CHIP_GAP) / (CHIP_H + CHIP_GAP))
	return math.max(0, rows) * 2
end

local function fmt(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dirty = false
	for key, till in pairs(active) do
		if till <= now then
			active[key] = nil; dirty = true
			plr:SetAttribute("BoostLeft_" .. key, nil)
		else
			-- seconds left, for the save (SaveClient snapshots it; it changes once a second at most)
			local left = math.ceil(till - now)
			if plr:GetAttribute("BoostLeft_" .. key) ~= left then plr:SetAttribute("BoostLeft_" .. key, left) end
		end
	end
	if dirty then publish() end
	local jc = plr:GetAttribute("JackpotCasts") or 0
	local live = {}
	for _, key in ipairs(ORDER) do
		if (key == "jackpot" and jc > 0) or (key ~= "jackpot" and active[key]) then live[#live + 1] = key end
	end
	for key in pairs(active) do   -- a boost ORDER does not list still gets its pill, last
		if not table.find(live, key) then live[#live + 1] = key end
	end
	if #live == 0 then
		for _, p in pairs(pills) do p.frame.Visible = false end
		gui.Enabled = false
		return
	end

	local size, O = frame()
	local m = hudMode(size)
	local phone = m == "phone"
	if gridOn ~= phone then
		gridOn = phone
		layout.Parent = (not phone) and strip or nil
		grid.Parent = phone and strip or nil
	end
	local cap = place(m, size, O)
	local n = #live
	local shown, more = n, 0
	if n > cap then
		shown = math.max(0, cap - 1)
		more = (cap > 0) and (n - shown) or 0
	end
	local on = {}
	for i = 1, shown do
		local key = live[i]
		local p = pillFor(key)
		local def = BOOSTS[key]
		dress(p, phone)
		on[key] = true
		p.frame.LayoutOrder = i
		if key == "jackpot" then
			p.label.Text = phone and (def.icon .. " x" .. jc) or (def.icon .. "  Jackpot Cast  x" .. jc)
		else
			local t = fmt(active[key] - now)
			p.label.Text = phone and (def.icon .. " " .. t) or (def.icon .. "  " .. def.name .. "  " .. t)
		end
	end
	if more > 0 then
		local p = pillFor("more")
		dress(p, phone)
		on.more = true
		p.frame.LayoutOrder = 99
		p.label.Text = "+" .. more
	end
	for key, p in pairs(pills) do
		p.frame.Visible = on[key] == true
	end
	local count = shown + ((more > 0) and 1 or 0)
	if phone then
		local cols, rows = math.min(2, count), math.ceil(count / 2)
		strip.Size = UDim2.fromOffset(cols * CHIP_W + math.max(0, cols - 1) * CHIP_GAP,
			rows * CHIP_H + math.max(0, rows - 1) * CHIP_GAP)
	else
		strip.Size = UDim2.fromOffset(186, count * 30 + math.max(0, count - 1) * 6)
	end
	gui.Enabled = count > 0
end)

----------------------------------------------------------------------
-- boot
----------------------------------------------------------------------
publish()   -- write the identities so GameClient's `or` defaults are never the only guard
plr:SetAttribute("JackpotCasts", plr:GetAttribute("JackpotCasts") or 0)

-- SAVED POTIONS (SaveServer, 2026-10-11): BoostSaved_<key> = seconds that were left when you last saved, written once
-- when your save loads (usually after this script has started, hence the listener). Resumes play time, not wall time.
for key, def in pairs(BOOSTS) do
	if not def.charge then
		local function resume()
			local left = tonumber(plr:GetAttribute("BoostSaved_" .. key))
			if left and left == left and left > 0 then
				active[key] = math.max(active[key] or 0, os.clock() + math.min(left, 100 * def.dur))
				publish()
			end
		end
		resume()
		plr:GetAttributeChangedSignal("BoostSaved_" .. key):Connect(resume)
	end
end

-- Dev hook, same convention as DevRoll / DevUpgrade / DevAfk:
--   BoostHUD.DevBoost:Fire("potion_luck")   activate one, no inventory needed
local dev = Instance.new("BindableEvent")
dev.Name = "DevBoost"
dev.Parent = gui
dev.Event:Connect(function(key) activate(key) end)

print("[Boost] online — 4 potions + jackpot now actually apply")