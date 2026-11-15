--[[
	IdleClient — the client half of Deep Pockets (Upgrades tree).

	Three jobs:
	  1. Report UpgIdleRate up to IdleServer. The tier lives in a client attribute that does
	     not replicate, and the server is what persists the clock, so it has to be told.
	  2. Take the offline payout on join and show a welcome-back CLAIM card once the loading
	     screen has lifted; claiming banks it into the SAME shared balance every other menu
	     spends from (leaderstats.Money, created by CurrencyClient) and tells IdleServer.
	  3. AFK EARNINGS: pay that same rate while the player is idle but still IN the game.

	WHY ALL THREE LIVE HERE. Deep Pockets is one upgrade and it should have one owner. The
	rate, the offline payout and the AFK payout all read the same UpgIdleRate, so buying a
	Pockets tier moves all three together and there is no second formula to drift.

	⚠️ AFK AND OFFLINE CANNOT DOUBLE-PAY, and that is a property of the design rather than a
	check: AFK only accrues while you are connected, and IdleServer's clock only ever pays for
	(now - at) where `at` is refreshed every 60s while you ARE connected and again on
	PlayerRemoving. The two cover disjoint intervals by construction.

	DisplayOrder 30 keeps the card above the full-screen menus, which sit at 25-26.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(game:GetService("ReplicatedStorage"):WaitForChild("TouchKit"))

local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("IdleRemotes", 30)
if not remotes then return end
local reportRate    = remotes:WaitForChild("ReportRate")
local offlinePayout = remotes:WaitForChild("OfflinePayout")
local claimPayout   = remotes:WaitForChild("Claim", 15)

----------------------------------------------------------------------
-- 1. keep the server's copy of the rate current
----------------------------------------------------------------------
-- nil = UpgradesController hasn't published yet (it starts after the save loads): sending 0 then would overwrite
-- the rate IdleServer loaded, and a leave in that window would save 0
local function push()
	local r = plr:GetAttribute("UpgIdleRate")
	if r == nil then return end
	reportRate:FireServer(r)
end
plr:GetAttributeChangedSignal("UpgIdleRate"):Connect(push)
task.delay(3, push)                                   -- after UpgradesController's publish()
task.spawn(function() while task.wait(45) do push() end end)

----------------------------------------------------------------------
-- 2. bank the payout + welcome-back card
----------------------------------------------------------------------
local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIX[tier + 1])
end
local function awayText(sec)
	local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

local function addMoney(n)
	local stats = plr:FindFirstChild("leaderstats") or plr:WaitForChild("leaderstats", 20)
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then
		m.Value = m.Value + n
		return true
	end
	return false
end

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local INK, GOLD = rgb(8,22,44), rgb(255,224,104)

local cardOpen = false
local function showCard(amount, away)
	local gui = make("ScreenGui", { Name = "IdlePayout", ResetOnSpawn = false, DisplayOrder = 30,
		IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, plr:WaitForChild("PlayerGui"))

	local shade = make("TextButton", { Size = UDim2.fromScale(1,1), BackgroundColor3 = rgb(2,10,26),
		BackgroundTransparency = 0.45, AutoButtonColor = false, Text = "", ZIndex = 1 }, gui)

	local card = make("Frame", { AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5),
		Size = UDim2.fromOffset(420, 250), BackgroundColor3 = rgb(30,120,206), BorderSizePixel = 0, ZIndex = 2 }, gui)
	make("UICorner", { CornerRadius = UDim.new(0,22) }, card)
	make("UIStroke", { Color = INK, Thickness = 5 }, card)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(84,196,246), rgb(10,44,104)) }, card)
	local scale = make("UIScale", { Scale = 0.9 }, card)

	local function txt(s, size, col, y, h, font)
		local l = make("TextLabel", { AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.5,0,0,y),
			Size = UDim2.new(1,-36,0,h), BackgroundTransparency = 1, Text = s, TextScaled = true,
			Font = font or Enum.Font.FredokaOne, TextColor3 = col, ZIndex = 3 }, card)
		make("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
		return l
	end
	txt("🏦  Welcome back!", 30, GOLD, 22, 40)
	txt(away >= 60 and ("Your crew fished for " .. awayText(away)) or "Your crew's catch is waiting", 16,
		Color3.new(1,1,1), 74, 24, Enum.Font.GothamBold)
	txt("+$" .. abbrev(amount), 44, rgb(122,240,158), 108, 58)

	local btn = make("TextButton", { AnchorPoint = Vector2.new(0.5,1), Position = UDim2.new(0.5,0,1,-20),
		Size = UDim2.new(1,-60,0,50), BackgroundColor3 = rgb(46,160,176), AutoButtonColor = true,
		Font = Enum.Font.FredokaOne, Text = "Claim", TextColor3 = Color3.new(1,1,1), TextSize = 22,
		BorderSizePixel = 0, ZIndex = 3 }, card)
	make("UICorner", { CornerRadius = UDim.new(0,14) }, btn)
	make("UIStroke", { Color = INK, Thickness = 3 }, btn)

	TweenService:Create(scale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- CLAIM: the money lands when the player takes it (the button, or a tap outside the card), never on a timer - the
	-- old card closed itself after 12 s, usually while still hidden under the loading screen. Until the claim reaches
	-- IdleServer the amount stays banked there, so leaving without claiming carries it to the next visit.
	local claimed = false
	local function claim()
		if claimed then return end
		claimed = true
		if addMoney(amount) and claimPayout then claimPayout:FireServer() end
		pcall(function() require(ReplicatedStorage:WaitForChild("Audio", 2)).play("Coin", { volume = 0.8 }) end)
		gui:Destroy()
		cardOpen = false
	end
	TouchKit.press(btn, claim)
	TouchKit.press(shade, claim)
end

offlinePayout.OnClientEvent:Connect(function(amount, away)
	if typeof(amount) ~= "number" or amount <= 0 or amount ~= amount or cardOpen then return end
	cardOpen = true
	-- not under the loading screen (ReplicatedFirst.LoadingScreen, DisplayOrder 1000): it sets LoadingDone once its
	-- curtain is gone
	local curtain = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen")
	local t0 = os.clock()
	while curtain and plr:GetAttribute("LoadingDone") ~= true and os.clock() - t0 < 60 do task.wait(0.2) end
	task.wait(0.4)
	showCard(amount, typeof(away) == "number" and away or 0)
end)

----------------------------------------------------------------------
-- 3. AFK earnings
----------------------------------------------------------------------
-- Same rate as offline, same ceiling, same upgrade. The ONLY new idea here is "when does the
-- clock run": after AFK_AFTER seconds with no input, and it stops the instant you touch
-- anything. Alt-tabbing counts immediately - if the window is not focused you are not playing.
local UIS       = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local AFK_AFTER = 90            -- seconds of no input before the crew starts fishing for you
local AFK_CAP   = 8 * 3600      -- matches IdleServer's OFFLINE_CAP: one session banks 8h max
local MAX_RATE  = 50            -- matches IdleServer's MAX_RATE, so both halves agree

local lastInput = os.clock()
local afk, afkSince, banked, acc = false, 0, 0, 0

local pg2  = plr:WaitForChild("PlayerGui")
local ahud = make("ScreenGui", { Name = "AfkHUD", ResetOnSpawn = false, DisplayOrder = 14,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, pg2)
-- AFTER IgnoreGuiInset (setting that resets it): every HUD gui shares the safe-area origin (HUD_CONTRACT §1)
ahud.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
-- ⚠️ Active = false on every piece. This pill sits over the play area and the click that ENDS
-- the AFK state has to reach the water behind it - a pill that eats its own dismissal would
-- leave the player tapping a HUD element wondering why nothing casts.
local pill = make("Frame", { Name = "AfkPill", AnchorPoint = Vector2.new(0.5, 0), Active = false,
	Size = UDim2.fromOffset(300, 44), BackgroundColor3 = rgb(30, 120, 206), BorderSizePixel = 0,
	ZIndex = 2 }, ahud)
make("UICorner", { CornerRadius = UDim.new(0, 999) }, pill)
local pillStroke = make("UIStroke", { Color = INK, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(84, 196, 246), rgb(24, 92, 168)) }, pill)
local alabel = make("TextLabel", { Active = false, BackgroundTransparency = 1, Size = UDim2.new(1, -22, 1, -12),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), TextScaled = true,
	Font = Enum.Font.FredokaOne, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 3 }, pill)
local labelStroke = make("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, alabel)
-- wide: TextScaled capped at 18 (the contract size); phone: 11..13 in a 30px pill
local acap = make("UITextSizeConstraint", { MinTextSize = 1, MaxTextSize = 18 }, alabel)

-- THE NOTICE SLOT (HUD_CONTRACT §1): the free band under the whole top-centre stack - pills,
-- AutoToggle, the progress meters or the tutorial card - where this pill and the IndexToast go.
-- Published on ahud as NoticeTop / NoticeLeft / NoticeRight in LOCAL px (origin = the safe-area
-- top-left every HUD gui shares), and kept current even while NOT AFK, because StatsHUD, BoostHUD
-- and the IndexToast read it too. The old place() read only the meters (and mixed a Position
-- offset with an AbsoluteSize), and ran only on setAfk(true) - which is why the pill was measured
-- stuck across the tutorial card, the Wheel and the roller after a device switch.
local compact = false
local function frameOf()
	local g = pg2:FindFirstChild("MainMenu")
	if not (g and g.Enabled and g.AbsoluteSize.X > 2) then g = ahud end
	local sz = g.AbsoluteSize
	if sz.X < 2 then sz = workspace.CurrentCamera.ViewportSize end
	return g.AbsolutePosition, sz.X, sz.Y
end
local function live(guiName, frameName)
	local g = pg2:FindFirstChild(guiName)
	local f = g and g:FindFirstChild(frameName)
	if g and g.Enabled and f and f.Visible and f.AbsoluteSize.X > 4 then return f end
	return nil
end
local function computeSlot()
	local O, W, H = frameOf()
	local phone = math.min(W, H) < 500
	compact = phone
	local left, right = 0, W
	local lp = live("BaitRoller", "Panel")
	if lp then left = lp.AbsolutePosition.X + lp.AbsoluteSize.X - O.X end
	local rp = live("MainMenu", "MenuBar")
	if rp then right = rp.AbsolutePosition.X - O.X end
	-- the Daily/Wheel cluster narrows the channel only while it hangs inside it (desktop)
	local tl = left
	local cl = live("RewardsHUD", "Cluster")
	if cl then
		local a = cl.AbsolutePosition.X - O.X
		local b = a + cl.AbsoluteSize.X
		if a >= left - 1 and b <= right + 1 then tl = math.max(tl, b) end
	end
	local function bottomOf(f) return f.AbsolutePosition.Y - O.Y + f.AbsoluteSize.Y end
	local bot = 0
	local f = live("FishingHUD", "Pills"); if f then bot = math.max(bot, bottomOf(f)) end
	f = live("FishingHUD", "AutoToggle"); if f then bot = math.max(bot, bottomOf(f)) end
	f = live("ProgressHUD", "Meters"); if f then bot = math.max(bot, bottomOf(f)) end
	f = live("TutorialHUD", "Card")
	-- a card parked at the BOTTOM (focus beat inside a menu) is not part of the top stack
	if f and f.AbsolutePosition.Y - O.Y < H / 2 then bot = math.max(bot, bottomOf(f)) end
	local top = (bot > 0) and (bot + (phone and 8 or 18)) or 0.45 * H
	local nl, nr
	if phone then
		-- the MAIN LANE: the 150px LEFT LANE beside it belongs to StatsHUD + the boost chips
		nl, nr = left + 166, right - 8
	else
		nl, nr = tl + 12, right - 12
		-- desktop parks the boost pills top-left of the channel, under the rewards cluster
		local bs = live("BoostHUD", "Boosts")
		if bs and bs.AbsolutePosition.Y - O.Y < H / 2 then
			nl = math.max(nl, bs.AbsolutePosition.X - O.X + bs.AbsoluteSize.X + 12)
		end
	end
	top, nl, nr = math.floor(top + 0.5), math.floor(nl + 0.5), math.floor(nr + 0.5)
	-- unchanged values fire nothing, so the 5Hz loop costs readers nothing while the HUD is still
	ahud:SetAttribute("NoticeTop", top)
	ahud:SetAttribute("NoticeLeft", nl)
	ahud:SetAttribute("NoticeRight", nr)
	return top, nl, nr
end

local function place()
	local top, nl, nr = computeSlot()
	if compact then
		pill.Size = UDim2.fromOffset(math.max(120, math.floor(math.min(nr - nl, 260))), 30)
		pillStroke.Thickness = 3
		labelStroke.Thickness = 2
		alabel.Size = UDim2.new(1, -16, 1, -10)
		acap.MinTextSize, acap.MaxTextSize = 11, 13
	else
		pill.Size = UDim2.fromOffset(300, 44)
		pillStroke.Thickness = 4
		labelStroke.Thickness = 2.5
		alabel.Size = UDim2.new(1, -22, 1, -12)
		acap.MinTextSize, acap.MaxTextSize = 1, 18
	end
	-- the ink (the outward stroke) starts AT NoticeTop, not the box
	pill.Position = UDim2.new(0, math.floor((nl + nr) / 2 + 0.5), 0, top + pillStroke.Thickness)
end

local function rateNow()
	local r = tonumber(plr:GetAttribute("UpgIdleRate")) or 0
	if r ~= r then r = 0 end                       -- NaN
	return math.clamp(r, 0, MAX_RATE)
end

local function paint()
	local r = rateNow()
	-- single spaces on a phone: the double-spaced copy costs ~20px the 30px pill does not have
	local sep = compact and " \194\183 " or "  \194\183  "
	local lead = compact and "\240\159\146\164 AFK" or "\240\159\146\164  AFK"
	if r <= 0 then
		-- Deep Pockets is what pays this. Say so, rather than showing an idle pill that earns 0.
		alabel.Text = lead .. sep .. "buy Deep Pockets to earn"
	else
		alabel.Text = lead .. sep .. "$" .. abbrev(r * 60) .. "/min" .. sep .. "+$" .. abbrev(banked)
	end
end

local function setAfk(on)
	if afk == on then return end
	afk = on
	if on then
		afkSince, banked, acc = os.clock(), 0, 0
		place(); paint()
		ahud.Enabled = true
	else
		ahud.Enabled = false
	end
	plr:SetAttribute("Afk", on)                    -- the seam, for anything that wants to know
end

local function poke()
	lastInput = os.clock()
	if afk then setAfk(false) end
end
UIS.InputBegan:Connect(poke)
UIS.InputChanged:Connect(poke)
UIS.WindowFocusReleased:Connect(function() lastInput = 0 end)   -- alt-tab is AFK at once
UIS.WindowFocused:Connect(poke)

RunService.Heartbeat:Connect(function(dt)
	if not afk then
		if os.clock() - lastInput >= AFK_AFTER then setAfk(true) end
		return
	end
	if os.clock() - afkSince > AFK_CAP then return end   -- same 8h ceiling as offline
	local r = rateNow()
	if r <= 0 then return end
	-- ⚠️ BANK WHOLE DOLLARS ONLY. leaderstats.Money is an IntValue-shaped balance that every
	-- menu formats; adding 0.33 a frame would either truncate to nothing or leave the balance
	-- fractional. Carry the remainder in `acc` and pay it out as it crosses 1.
	acc += r * dt
	local whole = math.floor(acc)
	if whole >= 1 then
		acc -= whole
		if addMoney(whole) then banked += whole end
	end
	paint()   -- placement is the 5Hz loop's job below
end)

-- 5Hz: keep the notice slot published for its other readers, and re-place the pill while AFK -
-- a device switch, the tutorial ending, Auto Fishing appearing or a boost landing all move it.
task.spawn(function()
	while true do
		if afk then place(); paint() else computeSlot() end
		task.wait(0.2)
	end
end)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	if afk then place(); paint() else computeSlot() end
end)

-- rate can change mid-AFK (a menu is still usable), so keep the readout honest
plr:GetAttributeChangedSignal("UpgIdleRate"):Connect(function() if afk then paint() end end)

-- Dev hook, same convention as DevRoll / DevZone / DevUpgrade: waiting 90 seconds to test is
--   AfkHUD.DevAfk:Fire(true)      -> go AFK now
--   AfkHUD.DevAfk:Fire(false)     -> come back
local devAfk = make("BindableEvent", { Name = "DevAfk" }, ahud)
devAfk.Event:Connect(function(on)
	if on then lastInput = 0 - AFK_AFTER; setAfk(true) else poke() end
end)

print(string.format("[IdleClient] online — Deep Pockets reporting, AFK earnings after %ds", AFK_AFTER))
