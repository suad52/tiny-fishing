--[[
	StatsHUD — live bonus readout, bottom-left of the play area.

	No panel: these are chunky outlined labels floating straight on the scene, so they read
	over water or sky without a box competing with the 2.5D framing. Each line is drawn
	twice - a dark copy offset down, then the bright one - which is what gives the letters
	their cartoon depth without needing a background.

	ONLY shows numbers GameClient actually consumes. Verified against its attribute reads:
	    UpgLuck, UpgValueMult, ZoneCoinMult, UpgReelMult, RodPower, UpgAuto
	The BOAT you are sailing feeds luck, value and reel too (BoatClient publishes
	BoatLuck / BoatCoinMult / BoatReelMult and GameClient folds all three into the same
	sums), so they are added here as well - a trawler showing "+0% luck" while it is really
	applying +14% is exactly the under-reporting this file exists to avoid.
	The EQUIPPED BAIT now sits on top of the stack (2026-07-18) - GameClient consumes its
	buffs for real and spends one per cast, so this is where you watch it run down.

	Under-reporting is the same lie as over-reporting: every total below sums ALL of the
	sources GameClient actually adds together, which now means the rod and the bait too,
	not just the upgrade branch. A "+0% luck" line under a "+1000% luck" bait reads as a bug.

	2026-09-03: the Rebirth "Tide Current" (RebirthMult) and the Tide Fortune pearl perk
	(PerkValueMult) now ARE read by valueOf, so they join the value line - this is the
	"wire those into GameClient first, then add them here" this block used to ask for.

	Still deliberately NOT shown, because the fishing loop still does not read them:
	    Perk_luck / Perk_reach / Perk_reel / Perk_nets.
	    Same rule as before - printing one would claim a bonus the game does not apply.

	Luck is the headline and is always visible. The rest only appear once they are actually
	above base, so a fresh save shows a single clover rather than a wall of x1.00.
]]

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local TextService = game:GetService("TextService")

local plr = Players.LocalPlayer
local gui = script.Parent
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets   -- the HUD's shared origin (HUD_CONTRACT §1)

-- WHERE THIS SITS depends on the HUD mode RollerController publishes (BaitRoller.HudMode):
--   phone    the bottom of the LEFT LANE - x LR+8, bottom H-8, at most 150 wide - in smaller type
--            (luck 15, the rest 12). The boost chips stack above it, and the pair has to stay
--            below the notice slot (AfkHUD.NoticeTop); if the lines alone would not, they tighten.
--   tablet   x LR+12, bottom H-16, today's sizes.
--   desktop  today: x LR+12, stepping right around the Daily/Wheel cluster if it hangs this low.
-- LR is the BaitRoller panel's LIVE right edge in LOCAL px (every HUD gui shares the safe-area
-- origin - HUD_CONTRACT §1). It used to be hardcoded to 332 - measured once, on one viewport.
-- ⚠️ NEVER LEFT OF LR+12. The old clamp against the MenuBar (`right - 120`) could drag the stack
-- over the BAITS button whenever it ran before the bar had its real width - the "+0% luck on
-- BAITS" report - and nothing re-ran it once the bar settled. The bar's rect is watched now too.
-- The frame is sized to its CONTENT (widest line + 8): GameClient reads this rect to keep the
-- cast hint clear, and a channel-wide box claimed space the text never used.
local FALLBACK_LEFT = 332   -- only until the roller has rendered
local GUTTER = 12
local LANE_W = 150          -- the phone's left lane (HUD_CONTRACT §1)

local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local INK  = rgb(8,22,44)
local FONT = Enum.Font.FredokaOne

local function make(class, props, parent)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local root = make("Frame", {
	Name = "Stats", AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, FALLBACK_LEFT, 1, -16),
	Size = UDim2.fromOffset(230, 10), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, ZIndex = 2 }, gui)
local listLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, root)

-- one cartoon line: a dark drop copy, then the bright face on top. `size` is the desktop/tablet
-- TextSize; styleRows() swaps in the phone sizes.
local function line(order, size, colour)
	local holder = make("Frame", { LayoutOrder = order, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 6), ZIndex = 2 }, root)
	local faceStroke
	local function lbl(dark)
		local l = make("TextLabel", { BackgroundTransparency = 1, RichText = true,
			Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, dark and 3 or 0),
			Font = FONT, Text = "", TextSize = size,
			TextColor3 = dark and rgb(6, 18, 38) or colour,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = dark and 0.45 or 0,
			ZIndex = dark and 2 or 3 }, holder)
		if not dark then
			faceStroke = make("UIStroke", { Color = INK, Thickness = math.max(2.5, size * 0.2),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round }, l)
		end
		return l
	end
	local shadow, face = lbl(true), lbl(false)
	local scale = make("UIScale", { Scale = 1 }, holder)
	return { holder = holder, shadow = shadow, face = face, scale = scale, stroke = faceStroke, wide = size, size = size }
end

-- Bait rides on TOP of the stack (the root is bottom-anchored, so LayoutOrder 0 is the
-- highest line). Its colour is per-bait, from the published BaitTint, so unlike the rows
-- below it the tint is applied in refresh() rather than at construction.
local bait  = line(0, 20, rgb(255, 255, 255))
local luck  = line(1, 26, rgb(122, 240, 158))
local value = line(2, 18, rgb(255, 224, 104))
local reel  = line(3, 18, rgb(120, 226, 246))
local rod   = line(4, 18, rgb(255, 158, 200))
local auto  = line(5, 18, rgb(196, 160, 255))
local ROWS  = { bait, luck, value, reel, rod, auto }

----------------------------------------------------------------------
-- sizing
----------------------------------------------------------------------
local BIG = Vector2.new(4000, 400)
local function textW(row, size)
	return TextService:GetTextSize(row.face.Text, size, FONT, BIG).X
end
-- phone type: luck 15 / the rest 12, or 13 / 11 when the stack would reach the notice slot
local function phoneSize(row, tight)
	if row == luck then return tight and 13 or 15 end
	return tight and 11 or 12
end
local function styleRows(phone, tight)
	for _, row in ipairs(ROWS) do
		local size = row.wide
		if phone then
			size = phoneSize(row, tight)
			-- a line wider than the lane shrinks until it fits - down to 11 and no further
			local w = (row.face.Text ~= "") and textW(row, size) or 0
			if w > LANE_W - 8 then size = math.max(11, math.floor(size * (LANE_W - 8) / w)) end
		end
		row.size = size
		row.face.TextSize = size
		row.shadow.TextSize = size
		row.holder.Size = UDim2.new(1, 0, 0, size + (phone and 3 or 6))
		row.shadow.Position = UDim2.fromOffset(0, phone and 2 or 3)
		row.stroke.Thickness = phone and math.max(1.5, size * 0.16) or math.max(2.5, size * 0.2)
	end
	listLayout.Padding = UDim.new(0, phone and 1 or 2)
end
-- the widest visible line + 8 (unscaled: the pop UIScale must not make the frame breathe)
local function contentWidth()
	local w = 0
	for _, row in ipairs(ROWS) do
		if row.holder.Visible and row.face.Text ~= "" then w = math.max(w, textW(row, row.size)) end
	end
	return math.max(60, math.ceil(w) + 8)
end

----------------------------------------------------------------------
-- placement
----------------------------------------------------------------------
local pgRef = plr:WaitForChild("PlayerGui")
local function edgePanel(guiName, frameName)
	local scr = pgRef:FindFirstChild(guiName)
	if not (scr and scr.Enabled) then return nil end
	local f = scr:FindFirstChild(frameName)
	if f and f.Visible and f.AbsoluteSize.X > 4 then return f end
	return nil
end
local function localRect(o)
	local p = o.AbsolutePosition - gui.AbsolutePosition
	return p.X, p.Y, p.X + o.AbsoluteSize.X, p.Y + o.AbsoluteSize.Y
end

local function relayout()
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if W < 2 or H < 2 then
		local cam = workspace.CurrentCamera
		W, H = cam and cam.ViewportSize.X or 1280, cam and cam.ViewportSize.Y or 720
	end
	local br = pgRef:FindFirstChild("BaitRoller")
	local mode = br and br:GetAttribute("HudMode")
	if mode ~= "phone" and mode ~= "tablet" and mode ~= "desktop" then
		mode = (math.min(W, H) < 500) and "phone" or "desktop"
	end
	local LR = FALLBACK_LEFT - GUTTER
	local lp = edgePanel("BaitRoller", "Panel")
	if lp then
		local _, _, x1 = localRect(lp)
		LR = x1
	end

	if mode == "phone" then
		-- the column's top may not rise above the notice slot; the boost chips (BoostClient) take
		-- only the rows left between it and this stack
		local ah = pgRef:FindFirstChild("AfkHUD")
		local noticeTop = ah and ah:GetAttribute("NoticeTop")
		if type(noticeTop) ~= "number" then noticeTop = 0.45 * H end
		local h, n = 0, 0
		for _, row in ipairs(ROWS) do
			if row.holder.Visible then
				n += 1
				h += phoneSize(row, false) + 3
			end
		end
		h += math.max(0, n - 1)
		styleRows(true, H - 8 - h < noticeTop)
		root.Position = UDim2.new(0, math.floor(LR + 8 + 0.5), 1, -8)
		root.Size = UDim2.fromOffset(math.min(LANE_W, contentWidth()), 10)
		return
	end

	styleRows(false, false)
	local left = LR + GUTTER
	if mode == "desktop" then
		local right = W - GUTTER
		local rp = edgePanel("MainMenu", "MenuBar")
		if rp then right = localRect(rp) - GUTTER end
		-- The Daily/Wheel cluster hangs down the same channel from y=44 (desktop only - on a phone
		-- or a tablet it is docked in a rail). On a desktop it ends ~390px above this stack and they
		-- never meet; should a short window bring them together, step round it.
		local rh = pgRef:FindFirstChild("RewardsHUD")
		local cluster = edgePanel("RewardsHUD", "Cluster")
		if cluster and (rh:GetAttribute("Mode") or "channel") == "channel" then
			local _, myTop = localRect(root)
			local _, _, cx1, cy1 = localRect(cluster)
			if myTop < cy1 then left = math.max(left, cx1 + GUTTER) end
		end
		left = math.max(LR + GUTTER, math.min(left, right - 120))
	end
	root.Position = UDim2.new(0, math.floor(left + 0.5), 1, -16)
	root.Size = UDim2.fromOffset(contentWidth(), 10)
end

-- Re-layout on the viewport, this gui, and every live rect/attribute it reads. Those pieces are
-- built by other scripts and may not exist yet, so poll ~6s and latch each one as it appears.
local hooked = {}
local function hook(inst, props, attrs)
	if not inst then return false end
	if hooked[inst] then return true end
	hooked[inst] = true
	for _, p in ipairs(props) do inst:GetPropertyChangedSignal(p):Connect(relayout) end
	for _, a in ipairs(attrs or {}) do inst:GetAttributeChangedSignal(a):Connect(relayout) end
	return true
end
local function child(guiName, frameName)
	local g = pgRef:FindFirstChild(guiName)
	return g and g:FindFirstChild(frameName)
end
local function hookAll()
	local ok = hook(pgRef:FindFirstChild("BaitRoller"), {}, { "HudMode" })
	ok = hook(child("BaitRoller", "Panel"), { "AbsoluteSize", "AbsolutePosition" }) and ok
	ok = hook(child("MainMenu", "MenuBar"), { "AbsoluteSize", "AbsolutePosition" }) and ok
	ok = hook(pgRef:FindFirstChild("RewardsHUD"), {}, { "Mode" }) and ok
	ok = hook(child("RewardsHUD", "Cluster"), { "AbsoluteSize", "AbsolutePosition" }) and ok
	ok = hook(pgRef:FindFirstChild("AfkHUD"), {}, { "NoticeTop" }) and ok
	return ok
end

local function set(row, text, visible)
	row.holder.Visible = visible
	row.face.Text = text
	row.shadow.Text = text
end

local lastLuck, lastBait = -1, -1
local function refresh()
	local a = function(n, d) return plr:GetAttribute(n) or d end

	-- EQUIPPED BAIT: icon + name + how many casts are left in it. BaitLeft is published by
	-- InventoryController so this does not need its own copy of the akey strip.
	local bname = a("EquippedBait", nil)
	local bleft = a("BaitLeft", 0)
	local bshow = bname ~= nil and bname ~= "" and bleft > 0
	set(bait, bshow and string.format("%s %s  x%d", a("BaitIcon", ""), bname, bleft) or "", bshow)
	if bshow then bait.face.TextColor3 = a("BaitTint", rgb(255, 255, 255)) end
	if bleft ~= lastBait then      -- pop as it counts down, same as the clover
		lastBait = bleft
		bait.scale.Scale = 1.25
	end

	-- Every line below sums ALL the sources GameClient adds, not just the upgrade branch.
	local l = a("UpgLuck", 0) + a("RodLuck", 0) + a("BaitLuck", 0) + a("BoatLuck", 0)
	set(luck, string.format("🍀 %+d%% luck", math.floor(l * 100 + 0.5)), true)
	if l ~= lastLuck then      -- pop when it actually changes
		lastLuck = l
		luck.scale.Scale = 1.25
	end

	local v = a("UpgValueMult", 1) * a("ZoneCoinMult", 1) * a("BaitValueMult", 1)
		* a("BoatCoinMult", 1)                                    -- all stack in valueOf()
		* a("RebirthMult", 1) * a("PerkValueMult", 1)              -- Tide Current + Tide Fortune
	set(value, string.format("💰 x%.2f value", v), v > 1.001)

	local r = a("UpgReelMult", 1) * a("RodReelMult", 1) * a("BaitHaste", 1)
		* a("BoatReelMult", 1)
	set(reel, string.format("🎣 x%.2f reel", r), r > 1.001)

	local rp = a("RodPower", 0)
	set(rod, string.format("💪 +%d%% line", math.floor(rp * 100 + 0.5)), rp > 0.001)

	-- Auto Fishing is a single unlock; what matters here is whether it is RUNNING, which is
	-- the on-screen toggle. Read AutoCastOn directly rather than through a(): a() is an
	-- `or` fallback, so a stored `false` would come back as the default `true`.
	local au = a("UpgAuto", 0)
	local aon = plr:GetAttribute("AutoCastOn") ~= false
	set(auto, aon and "🤖 auto ON" or "🤖 auto OFF", au >= 1)
	auto.face.TextColor3 = aon and rgb(196, 160, 255) or rgb(150, 160, 180)

	-- which lines show, and how wide they are, feed the frame's size and (phone) its type
	relayout()
end

local WATCH = {
	UpgLuck=true, UpgValueMult=true, ZoneCoinMult=true,
	UpgReelMult=true, RodPower=true, UpgAuto=true,
	-- rod tier and equipped bait both feed the totals above
	RodLuck=true, RodReelMult=true,
	EquippedBait=true, BaitLeft=true, BaitIcon=true, BaitTint=true,
	BaitLuck=true, BaitValueMult=true, BaitHaste=true,
	AutoCastOn=true,
	-- the boat feeds the same three totals
	BoatLuck=true, BoatCoinMult=true, BoatReelMult=true,
	-- rebirth progression: the Tide Current and the Tide Fortune perk both scale fish value
	RebirthMult=true, PerkValueMult=true,
}
plr.AttributeChanged:Connect(function(name) if WATCH[name] then refresh() end end)
refresh()
task.delay(3, refresh)   -- catch the upgrade tree's first publish()

hook(gui, { "AbsoluteSize" })
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end
task.spawn(function()
	for _ = 1, 30 do
		task.wait(0.2)
		local done = hookAll()
		relayout()
		if done then break end
	end
end)

-- gentle idle bob on the clover + settle the pop; costs nothing when nothing changes
RunService.RenderStepped:Connect(function(dt)
	if luck.scale.Scale > 1 then
		luck.scale.Scale = math.max(1, luck.scale.Scale - dt * 1.4)
	end
	if bait.scale.Scale > 1 then
		bait.scale.Scale = math.max(1, bait.scale.Scale - dt * 1.4)
	end
	luck.holder.Rotation = math.sin(os.clock() * 1.6) * 1.5
end)

print("[StatsHUD] online — boxless cartoon bonus readout")
