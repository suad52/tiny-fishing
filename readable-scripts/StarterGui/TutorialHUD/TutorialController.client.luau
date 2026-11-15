-- StarterGui.TutorialHUD.TutorialController
--
-- A five-step walkthrough for a new player: cast, steer, get paid, spend it, then grow.
--
-- LEARN BY DOING WHERE IT IS RELIABLE. The first three steps advance on their own the moment
-- the player actually does the thing (a cast, a landed haul, a payout), because reading
-- "click to cast" is worth far less than having just cast. Every step ALSO has a Next button,
-- so a player who cannot trigger the action - or does not want to - is never trapped.
--
-- It sits in the slot the ProgressHUD meter row vacates, on the same channel datum GameClient's
-- fitHud() and ProgressController both use, so the three can never disagree about where the
-- middle of the play area is.
--
-- ⚠️ NOT PERSISTED, on purpose. Nothing in this game survives a rejoin - money, rods, boats,
-- zones and rebirths are all client-set player attributes and there is no progression
-- DataStore - so a "seen it" flag would be the only durable thing in the place, and it would
-- hide the tutorial from a player whose progress had just been wiped anyway. It runs once per
-- session and is skippable.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local gui = script.Parent
local pg  = plr:WaitForChild("PlayerGui")
local cam = workspace.CurrentCamera

local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local FONT     = Enum.Font.FredokaOne
local FBODY    = Enum.Font.GothamBold
local INK      = rgb(8, 22, 44)
local GOLD     = rgb(255, 214, 64)
local GOLD_HEX = "#FFD640"
local WHITE    = Color3.new(1, 1, 1)

-- Sized to the copy: head 26 / body 20. The longest body line measures 376.5px at 20, inside the
-- 444 a 480 card leaves; 124 tall is the old one-line-per-step shape with room for the bigger type.
local CARD_W, CARD_H = 480, 124
-- PHONE (short side < 500): a 400-wide design card at 0.75..0.85, so the head lands at 22 px and
-- the body at 16 px. The body drops to 19 there: at 20 the longest line (376.5) would WRAP in the
-- 364 a 400 card leaves, and the body box is one line tall. Re-decided on every layout().
local P_CARD_W = 400
local compact = false
-- The slot's TOP is GameClient's: FishingHUD:GetAttribute("TopStackBottom") is the bottom of the
-- pill row, or of the AutoToggle once Auto Fishing is owned, in LOCAL px - the SAME datum
-- ProgressController stacks its meter row under, so the card and the row it stands in for can
-- never disagree. ROW_GAP under it: 18 wide (the pills carry NO stroke while this card carries a
-- 4px one drawn OUTWARD, so the gap you see is 14), 8 on a phone.
local ROW_GAP, P_ROW_GAP = 18, 8

-- How long a step stays up once its condition is met, so it can actually be read.
local MIN_READ = 2.2

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(i, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }, i) end
local function stroke(i, c, t)
	return make("UIStroke", { Color = c or INK, Thickness = t or 3,
		LineJoinMode = Enum.LineJoinMode.Round }, i)
end
local function gstroke(l, c, t)
	return make("UIStroke", { Color = c or INK, Thickness = t or 2,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
end

----------------------------------------------------------------------
-- the script
----------------------------------------------------------------------
-- Wording branches on TouchKit.wanted() exactly the way GameClient's own bottom hint does,
-- so the tutorial and the game can never tell the player two different things.
-- ...or by the viewport: Studio's emulator reports MouseEnabled on a phone, and so may a real
-- tablet with a trackpad. GameClient's hint uses the same test.
local touch = TouchKit.wanted() or math.min(cam.ViewportSize.X, cam.ViewportSize.Y) < 500
local TAP   = touch and "Tap" or "Click"

----------------------------------------------------------------------
-- highlights - ring a real button and make it breathe
----------------------------------------------------------------------
-- ⚠️ THE RING CANNOT LIVE IN THIS SCREENGUI. TutorialHUD is DisplayOrder 14; MainMenu is 20
-- and BaitRoller is 15, and DisplayOrder beats ZIndex across ScreenGuis - so a ring drawn
-- here renders UNDER the very opaque panel it is pointing at, invisible rather than dim.
-- Each ring is therefore parented into the TARGET'S OWN ScreenGui as a top-level sibling,
-- which under ZIndexBehavior.Sibling draws above that ScreenGui's whole tree. Being a sibling
-- rather than a child also dodges MenuBar.List.ClipsDescendants (true) and the BaitRoller's
-- MenuVeil at ZIndex 30000.
--
-- Position is driven from the target's live AbsolutePosition/AbsoluteSize every frame, so the
-- ring tracks both the breathing scale and MenuLogic's own relayout passes for free.
local live = {}
local card       -- forward: an arrow starts at the tutorial card, which is built further down
local setFocus   -- forward: assigned once layout() exists (see the DisplayOrder note there)

local function menuButton(name)
	local mm = pg:FindFirstChild("MainMenu")
	local bar = mm and mm:FindFirstChild("MenuBar")
	local list = bar and bar:FindFirstChild("List")
	local btn = list and list:FindFirstChild(name)
	if btn then return btn, mm end
	return nil
end

-- The roller's three buttons are all UNNAMED - every one is literally "TextButton" - so they
-- have to be told apart by geometry. Heights: 52 = AUTO ROLL, 70 = ROLL, 66 = BAITS. The
-- __TouchPad<N> buttons TouchKit injects are TextButtons in the same parent, hence the filter.
local function rollerButton(heightOffset)
	local br = pg:FindFirstChild("BaitRoller")
	local panel = br and br:FindFirstChild("Panel")
	if not panel then return nil end
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("TextButton") and c.Name:sub(1, 10) ~= "__TouchPad"
			and c.Size.X.Offset == 320 and c.Size.Y.Offset == heightOffset then
			return c, br
		end
	end
	return nil
end

local function addGlow(target, host)
	if not (target and host) then return end
	local ring = make("Frame", { Name = "TutorialGlow", BackgroundTransparency = 1,
		BorderSizePixel = 0, Active = false, ZIndex = 40 }, host)
	corner(ring, 20)
	local rs = make("UIStroke", { Color = GOLD, Thickness = 4,
		LineJoinMode = Enum.LineJoinMode.Round }, ring)

	-- Breathe the target's OWN UIScale, between 1.00 and 1.045 - the exact range MenuLogic's
	-- hover tween already sweeps, so a hover landing mid-pulse is visually indistinguishable.
	-- ⚠️ WRITTEN EVERY FRAME below, never by a looping tween. MenuLogic's hover IS a tween on
	-- this same Scale, and TweenService cancels the older of two tweens on one property - so a
	-- single pass of the pointer over a ringed MenuBar button stopped its pulse for good, while
	-- the ring kept breathing round a dead button (SPEND lost all three, GO BIGGER lost Rebirth).
	-- A per-frame write cannot be cancelled: a hover tween just loses to it every frame.
	local scale = target:FindFirstChildOfClass("UIScale")
	local ours = false
	if not scale then
		scale = make("UIScale", { Scale = 1 }, target)   -- the roller's buttons have none
		ours = true
	end

	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		if not (target.Parent and ring.Parent) then return end
		local beat = 0.5 + 0.5 * math.sin((os.clock() - t0) * 3.6)
		if scale.Parent then scale.Scale = 1 + 0.045 * beat end   -- same beat: button and ring breathe together
		local pad = 5 + 3 * beat
		local p, s = target.AbsolutePosition, target.AbsoluteSize
		-- ⚠️ AbsolutePosition is SCREEN space, but a direct child of a ScreenGui has its Position
		-- measured from that ScreenGui's own origin - and on an IgnoreGuiInset gui the two differ
		-- by the topbar inset. Feeding AbsolutePosition straight into Position drew every ring
		-- about a button too high. Derive the origin from the ring's own current state instead of
		-- hardcoding an inset: it is constant, so this is exact from the first frame and stays
		-- right whatever the inset settings are.
		local ox = ring.AbsolutePosition.X - ring.Position.X.Offset
		local oy = ring.AbsolutePosition.Y - ring.Position.Y.Offset
		ring.Position = UDim2.fromOffset(p.X - ox - pad, p.Y - oy - pad)
		ring.Size = UDim2.fromOffset(s.X + pad * 2, s.Y + pad * 2)
		rs.Transparency = 0.42 - 0.34 * beat
		rs.Thickness = 3.5 + 1.5 * beat
	end)

	live[#live + 1] = { ring = ring, scale = scale, conn = conn, ours = ours }
end

-- Where a ray leaving the centre of a rectangle crosses its border. Used at both ends so the
-- arrow starts ON the card's edge and stops ON the button's, whatever direction it runs in.
local function edgeHit(half, u)
	local tx = (math.abs(u.X) > 1e-4) and (half.X / math.abs(u.X)) or math.huge
	local ty = (math.abs(u.Y) > 1e-4) and (half.Y / math.abs(u.Y)) or math.huge
	return u * math.min(tx, ty)
end

-- An arrow from the tutorial card to a button. It is parented into the TARGET'S ScreenGui for
-- exactly the reason the ring is: the head has to sit ON a button inside a panel that draws
-- above TutorialHUD, and DisplayOrder beats ZIndex across ScreenGuis.
--
-- The head is a PURPOSE-DRAWN image uploaded to this account: a chunky cartoon arrowhead with
-- the house ink outline and top-lit gold gradient baked in, drawn at 512x512 so it stays crisp.
-- Uploaded under the place owner, which is the whole point - third-party Creator Store decals
-- rendered BLANK here, measured in both an ImageLabel and a part Decal. The built-in
-- rbxasset://textures/DeveloperFramework/button_arrow_right.png it replaces always loaded but
-- is a small source texture and went soft the moment it was scaled up.
-- It points RIGHT at rest, so Rotation takes the arrow angle unchanged, and the concave back
-- notch is where the shaft nests.
-- Not a text glyph: a lone glyph is centred on its LINE BOX rather than its ink, so a rotated
-- arrow character drifts off the thing it means.
local function addArrow(target, host)
	if not (target and host and card) then return end
	local root = make("Frame", { Name = "TutorialArrow", BackgroundTransparency = 1,
		Active = false, Size = UDim2.fromOffset(0, 0), ZIndex = 41 }, host)
	-- Sized against a shaft that can run most of the screen: at 7px with a 22px head it read
	-- as a stray line rather than a pointer, and the head was small enough to look like it was
	-- aimed at the button ABOVE the one it meant.
	local TH = 10
	-- Geometry of the drawn head, as fractions of its square image. TIP is how far right of
	-- centre the point sits (x 0.945), so the head can be anchored by its POINT instead of its
	-- box; NOTCH is how far behind the point the concave back sits (x 0.335), which is where the
	-- shaft has to stop so it nests instead of poking through.
	local TIP, NOTCH = 0.445, 0.61
	local HEAD = "rbxassetid://89570372784524"

	local shaft = make("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, TH), ZIndex = 41 }, root)
	corner(shaft, 999)
	stroke(shaft, INK, 2)
	-- One label, not two: the outline is painted into the image, so there is no second tinted
	-- copy to keep in step behind it.
	local head = make("ImageLabel", { BackgroundTransparency = 1, Image = HEAD,
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 43 }, root)

	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		if not (target.Parent and root.Parent and card.Parent) then return end
		-- Park the container so its OWN AbsolutePosition is (0,0). Every child can then be
		-- placed in plain screen coordinates, which is what AbsolutePosition gives us for the
		-- card and the button. Same self-derived origin the ring uses, for the same reason.
		root.Position = UDim2.fromOffset(
			root.Position.X.Offset - root.AbsolutePosition.X,
			root.Position.Y.Offset - root.AbsolutePosition.Y)

		local beat = 0.5 + 0.5 * math.sin((os.clock() - t0) * 3.6)
		local c1 = card.AbsolutePosition + card.AbsoluteSize / 2
		local c2 = target.AbsolutePosition + target.AbsoluteSize / 2
		local d = c2 - c1
		if d.Magnitude < 1 then return end
		local u = d / d.Magnitude
		local from = c1 + edgeHit(card.AbsoluteSize / 2, u) + u * 10
		-- Stop clear of the ring, and breathe along the direction in step with it.
		-- Right up against the button's own border, INSIDE the ring's 5-8px pad, so the head and
		-- the ring read as one pointer. It also has to be this tight: these roller buttons are
		-- 300x70 and stacked, so an arrow arriving from up-right exits through the TOP edge, and
		-- every pixel of standoff parks the head over the button ABOVE the one it means.
		local to = c2 - edgeHit(target.AbsoluteSize / 2, u) - u * (6 - 5 * beat)
		local seg = to - from
		local L = seg.Magnitude
		-- The drawn head only fills about 0.79 of its square box, so this reads smaller than the
		-- box-filling texture it replaced - hence 58 rather than 44 for the same visual weight.
		-- On a phone the card, the rails and the buttons are all ~0.6x, so is the pointer.
		local S = compact and (38 + 4 * beat) or (58 + 6 * beat)   -- the head breathes with the ring
		TH = compact and 7 or 10
		if L < S then
			-- Too short for the head. On a phone the Zones tile sits right beside the card (38px
			-- off its edge on an iPhone 7, ~50 on a Galaxy A06), so step 6's arrow used to vanish
			-- outright - or flicker with the beat. Start it further back instead, over the card's
			-- own margin (this gui draws above the card), so the pointer is always there. Only a
			-- target practically touching the card still hides it.
			if L < 4 then
				shaft.Visible = false; head.Visible = false
				return
			end
			from = to - u * (S + 14)
			seg = to - from
			L = seg.Magnitude
		end
		shaft.Visible = true; head.Visible = true
		local ang = math.deg(math.atan2(seg.Y, seg.X))
		-- Anchored by its POINT, so the tip lands exactly where the maths says regardless of size.
		local c = to - u * (TIP * S)
		head.Position = UDim2.fromOffset(c.X, c.Y)
		head.Size = UDim2.fromOffset(S, S)
		head.Rotation = ang
		-- Stop the shaft just INSIDE the notch, so the head covers its end and the two outlines
		-- never cross.
		local tail = to - u * ((NOTCH - 0.05) * S)
		local sl = (tail - from).Magnitude
		local mid = (from + tail) / 2
		shaft.Position = UDim2.fromOffset(mid.X, mid.Y)
		shaft.Size = UDim2.fromOffset(sl, TH)
		shaft.Rotation = ang
	end)

	-- Registered as a `ring` so clearGlows tears it down on the same path as everything else.
	live[#live + 1] = { ring = root, conn = conn }
end

local function clearGlows()
	for _, h in ipairs(live) do
		-- Disconnect BEFORE restoring, or the next frame writes Scale again after the restore.
		if h.conn then h.conn:Disconnect() end
		if h.scale and h.scale.Parent then
			-- Hardcode 1, never a captured snapshot: a snapshot taken while the pointer was
			-- resting on the button captures 1.045 and enlarges it permanently.
			if h.ours then h.scale:Destroy() else h.scale.Scale = 1 end
		end
		if h.ring then h.ring:Destroy() end
	end
	live = {}
end

-- Named spots a step can point at, resolved lazily because MainMenu and the roller are both
-- built/cloned after this script starts.
local SPOTS = {
	Inventory = function() return menuButton("Inventory") end,
	Upgrades  = function() return menuButton("Upgrades") end,
	Boats     = function() return menuButton("Boats") end,
	Zones     = function() return menuButton("Zones") end,
	Rebirth   = function() return menuButton("Rebirth") end,
	Roll      = function() return rollerButton(70) end,
	Baits     = function() return rollerButton(66) end,
}

-- The EQUIP button of one particular bait card, addressed by the very attribute name that
-- RollerController bumped when the spin landed. InventoryController names each card after that
-- attribute and its action button "Action", so this is an exact lookup rather than a search
-- through twelve look-alike unnamed frames.
local function baitEquipButton(attrName)
	local bm = pg:FindFirstChild("BaitsMenu")
	local win = bm and bm:FindFirstChild("Window")
	local content = win and win:FindFirstChild("Content")
	local sf = content and content:FindFirstChildWhichIsA("ScrollingFrame")
	local c = sf and attrName and sf:FindFirstChild(attrName)
	local btn = c and c:FindFirstChild("Action")
	if btn then return btn, bm end
	return nil
end

-- The next LUCK node in the upgrade tree. Nodes are TextButtons named "<branch><tier>" living
-- in Container.Canvas, and Upg_luck is the tier already owned, so the one to point at is the
-- next one up. luck1 sits inside the default view, so a first-run player needs no panning.
local function nextLuckNode()
	local um = pg:FindFirstChild("UpgradesMenu")
	local cont = um and um:FindFirstChild("Container")
	local canvas = cont and cont:FindFirstChild("Canvas")
	if not canvas then return nil end
	local tier = math.floor(tonumber(plr:GetAttribute("Upg_luck")) or 0) + 1
	local n = canvas:FindFirstChild("luck" .. tier) or canvas:FindFirstChild("luck1")
	if n then return n, um end
	return nil
end

-- Every window's close X is UNNAMED, so it goes by shape. Surveyed all eleven menus: the one
-- in each is a TextButton literally called "TextButton", blank Text, near-square at 46-54, with
-- the two Frames that draw the cross. Sizes are read from the AUTHORED offsets, never from
-- AbsoluteSize - MenuFit scales these windows, so a 52 authored reads 57 here and something
-- else again on a phone. IndexMenu is the only one with several matches (its rewards and detail
-- overlays have their own), so the lowest ZIndex wins - that is the window's own.
local function closeButtonOf(m)
	if not m then return nil end
	local best
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "TextButton" and d.Text == "" then
			local w, h = d.Size.X.Offset, d.Size.Y.Offset
			if w >= 40 and w <= 60 and math.abs(w - h) <= 6 then
				local frames = 0
				for _, k in ipairs(d:GetChildren()) do
					if k:IsA("Frame") then frames += 1 end
				end
				if frames >= 2 and (not best or d.ZIndex < best.ZIndex) then best = d end
			end
		end
	end
	if best then return best, m end
	return nil
end

local function zonesCloseButton() return closeButtonOf(pg:FindFirstChild("ZonesMenu")) end

-- Every full-screen menu, so a step can tell when one is sitting on top of the button it wants
-- to point at.
local MENU_NAMES = { "BaitsMenu", "UpgradesMenu", "InventoryMenu", "BoatsMenu", "ZonesMenu",
	"RebirthMenu", "ShopMenu", "QuestsMenu", "IndexMenu", "SettingsMenu", "LeaderboardMenu", "GiftsMenu" }
local function openMenuOther(except)
	for _, n in ipairs(MENU_NAMES) do
		if n ~= except then
			local m = pg:FindFirstChild(n)
			if m and m.Enabled then return m end
		end
	end
	return nil
end

-- `arrowSpot` names the ONE spot that also gets an arrow. A step can ring several buttons to say
-- "these all spend money" while the arrow still says which single one to press now - more than
-- one arrow leaving the same card reads as a choice, which is the opposite of an instruction.
local function showGlows(names, arrowSpot)
	clearGlows()
	if setFocus then setFocus(nil) end   -- these all point at things OUTSIDE any menu
	if not names then return end
	for _, n in ipairs(names) do
		local get = SPOTS[n]
		if get then
			local target, host = get()
			addGlow(target, host)
			if n == arrowSpot then addArrow(target, host) end
		end
	end
end

----------------------------------------------------------------------
-- gates - a step ends when the player DOES the thing, never on a button
----------------------------------------------------------------------
-- Each gate is arm(done) -> cleanup. There is no Next button anywhere: a Next lets someone
-- click past an instruction they have not actually followed, which is the one thing a
-- tutorial must not allow.
local function onAttr(name)
	return function(done)
		local c = plr:GetAttributeChangedSignal(name):Connect(done)
		return function() c:Disconnect() end
	end
end

-- A purchase is Rod_<tier> / Boat_<id> / Zone_<id> flipping true, or Upg_<branch> reaching a
-- tier above zero. The VALUE is tested, not just the name, because both are also written
-- during SEEDING - InventoryController seeds Rod_2..Rod_10 = false and UpgradesController
-- publishes every branch at 0, and either would otherwise count as a purchase.
local function onPurchase()
	return function(done)
		local c = plr.AttributeChanged:Connect(function(a)
			local v = plr:GetAttribute(a)
			if v == true and (a:sub(1, 4) == "Rod_" or a:sub(1, 5) == "Boat_"
				or a:sub(1, 5) == "Zone_") then
				done()
			elseif a:sub(1, 4) == "Upg_" and type(v) == "number" and v > 0 then
				done()
			end
		end)
		return function() c:Disconnect() end
	end
end

-- Makes the SPEND step's Luck node FREE for as long as the step is live. "Buy a Luck upgrade."
-- has to be doable by everyone, and the first haul does not guarantee the $1,500 it costs.
-- UpgradesController prices whatever node TutorialFreeUpg names at $0 and clears it once it is
-- bought, so this is exactly ONE upgrade.
-- Armed with this step, NOT the whole tutorial: a player who wandered into Upgrades at step 1
-- would spend it early and arrive here pointed at a $2,250 Luck II. The tier is read at arm time
-- the same way nextLuckNode() reads it, so the free node is always the one being ringed.
local function withFreeLuck(gate)
	return function(done)
		local tier = math.floor(tonumber(plr:GetAttribute("Upg_luck")) or 0) + 1
		-- FIRST RUN ONLY (saves exist now): a player who quit mid-tutorial replays it, and must not get a free Luck
		-- tier every visit. Upg_luck and Rebirths are both saved, so this is one $1,500 node per account.
		if tier == 1 and (tonumber(plr:GetAttribute("Rebirths")) or 0) == 0 then
			plr:SetAttribute("TutorialFreeUpg", "luck" .. tier)
		end
		local stop = gate(done)
		return function()
			plr:SetAttribute("TutorialFreeUpg", nil)
			stop()
		end
	end
end

-- A roll always does `Bait_<key> = (old or 0) + 1` (RollerController's announce), so a Bait_
-- attribute INCREASING is the only reliable roll signal.
-- ⚠️ LastRoll and QT_roll both FAIL here: writing an attribute the value it already holds
-- fires nothing, and the weighted odds make roughly half of all rolls repeat the previous
-- bait - a tutorial waiting on either would hang through about every other roll.
-- The current counts are seeded at arm time so that SPENDING a bait (the count going down,
-- one per cast) can never be mistaken for rolling one.
local function onBaitRoll()
	return function(done)
		local seen = {}
		for name, v in pairs(plr:GetAttributes()) do
			if name:sub(1, 5) == "Bait_" and type(v) == "number" then seen[name] = v end
		end
		local c = plr.AttributeChanged:Connect(function(a)
			if a:sub(1, 5) ~= "Bait_" then return end
			local v = plr:GetAttribute(a)
			if type(v) ~= "number" then return end
			local prev = seen[a] or 0
			seen[a] = v
			-- The attribute NAME is handed on: it is exactly the bait that landed, and exactly
			-- the name of that bait's card, so the caller needs no second lookup.
			if v > prev then done(a) end
		end)
		return function() c:Disconnect() end
	end
end

-- Step 4 is THREE BEATS, not one instruction: ROLL (arrowed from the card), then BAITS once
-- the spin has actually landed, then the EQUIP button of the very bait that came out. Each
-- beat rewrites the card body and moves the highlight; the step reports done only once a bait
-- is equipped. Deliberately one gate rather than three STEPS, so the dots still read 4 of 6 -
-- it is one thing being learned, told in the order it has to be done.
local setBody   -- assigned in the run section, once `body` and `shownAt` exist
-- Analytics: every beat cleared is one step of the Onboarding funnel. FunnelServer owns the
-- numbering (ReplicatedStorage.FunnelDefs.ONBOARDING); this only names the beat.
local funnelRemote = ReplicatedStorage:FindFirstChild("AnalyticsRemotes")
funnelRemote = funnelRemote and funnelRemote:FindFirstChild("Funnel")
local function track(key, value)
	if funnelRemote then funnelRemote:FireServer("Onboarding", key, value) end
end
-- what finishing each step means, in STEPS order
local DONE_KEYS = { "cast", "catch", "paid", "equipped", "bought", "complete" }

local function onBaitJourney()
	return function(done)
		local dead, phase, rolledAttr = false, nil, nil
		local conns = {}
		-- Appended to, never built as a literal: an array literal made of maybe-nil handles is
		-- the classic way a teardown silently runs zero iterations.
		local function add(c) conns[#conns + 1] = c end

		local function enter(p)
			if dead then return end
			phase = p
			if p == "roll" then
				setBody("Roll for better bait.")
				showGlows({ "Roll" }, "Roll")
			elseif p == "open" then
				if not pg:FindFirstChild("BaitsMenu") then clearGlows(); done(); return end
				track("rolled")
				setBody("Now open BAITS.")
				showGlows({ "Baits" }, "Baits")
			elseif p == "equip" then
				track("baits")
				local btn, host = baitEquipButton(rolledAttr)
				clearGlows()
				-- Never hang on a card that cannot be found - end the step instead.
				if not btn then done(); return end
				setBody("Equip your new bait.")
				addGlow(btn, host)
				setFocus(btn)
			end
		end

		-- Fires from RollerController's announce(), which runs AFTER the 3s spin tween has
		-- completed - so this lands when the reel has actually STOPPED, which is the moment the
		-- player is being asked to look somewhere else.
		local stopRoll = onBaitRoll()(function(attr)
			if dead then return end
			if phase == "roll" then
				rolledAttr = attr
				enter("open")
			elseif phase == "open" then
				-- Rolled again before opening the window (AUTO ROLL will do this on its own):
				-- point at the newest bait, which is the one they are looking at.
				rolledAttr = attr
			end
		end)

		local bm = pg:FindFirstChild("BaitsMenu")
		if bm then
			add(bm:GetPropertyChangedSignal("Enabled"):Connect(function()
				if dead then return end
				if bm.Enabled then
					if phase == "open" then enter("equip") end
				elseif phase == "equip" and not plr:GetAttribute("EquippedBait") then
					-- That ring lives INSIDE this window, so with it shut there is nothing on
					-- screen to follow. Go back to asking for the window.
					enter("open")
				end
			end))
		end

		-- ANY bait finishes the step. The highlight says which one, but hanging the tutorial
		-- because the player equipped a different bait would be worse than ending a beat early.
		add(plr:GetAttributeChangedSignal("EquippedBait"):Connect(function()
			if dead or phase == "roll" then return end
			if plr:GetAttribute("EquippedBait") then done() end
		end))

		enter("roll")
		return function()
			dead = true
			if stopRoll then stopRoll() end
			for _, c in ipairs(conns) do c:Disconnect() end
			conns = {}
		end
	end
end

-- Two-beat steps that end up INSIDE a menu: point at the MenuBar button with an arrow, wait for
-- the window, then point at the control inside it and wait for the deed. Shared by SPEND and
-- GO BIGGER. (The bait step keeps its own machine: it has a third beat in front of these two,
-- and its inner target is not known until the reel stops.)
local function menuJourney(cfg)
	return function(done)
		local dead, phase = false, nil
		local conns, stopWatch = {}, nil
		local function add(c) conns[#conns + 1] = c end
		-- Resolved BEFORE enter(), which reads it: a `local` declared further down is a global
		-- (nil) as far as a closure defined above it is concerned.
		local m = pg:FindFirstChild(cfg.menu)

		local function enter(p)
			if dead then return end
			phase = p
			if p == "open" then
				-- A step can BEGIN with the previous step's window still covering the screen:
				-- buying the Luck upgrade leaves Upgrades open on top of the very MenuBar button
				-- this beat wants to point at, and equipping a bait leaves Baits open the same
				-- way. Ask for that window to be shut first, and ring its X.
				local blocker = openMenuOther(cfg.menu)
				if blocker then
					phase = "close"
					setBody("Close this first.")
					clearGlows()
					local x = closeButtonOf(blocker)
					if x then addGlow(x, blocker) end
					setFocus(x)
					return
				end
				-- Already standing in the right window (they opened it during the close beat).
				if m and m.Enabled then enter("do"); return end
				setBody(cfg.openBody)
				showGlows(cfg.spots, cfg.arrowSpot)
			else
				if cfg.beat then track(cfg.beat) end
				setBody(cfg.doBody)
				clearGlows()
				-- A control that cannot be found is not worth stranding anyone over: the card
				-- still says what to do, it just says it without a ring.
				local target, host = cfg.inner()
				if target then addGlow(target, host) end
				setFocus(target)   -- lifts the card above the menu it is now talking about
			end
		end

		if not m then
			-- Nothing to point at at all; pass the step rather than hold the tutorial open and
			-- keep the progress meters hidden forever.
			done()
			return function() end
		end

		-- Whatever window is currently in the way, watch for it being shut so the close beat can
		-- hand back to the open beat. Connected once per menu rather than per entry to the beat,
		-- so opening and closing several windows cannot stack duplicates.
		for _, n in ipairs(MENU_NAMES) do
			local other = pg:FindFirstChild(n)
			if other and other ~= m then
				add(other:GetPropertyChangedSignal("Enabled"):Connect(function()
					if dead or phase ~= "close" then return end
					if not openMenuOther(cfg.menu) then enter("open") end
				end))
			end
		end

		add(m:GetPropertyChangedSignal("Enabled"):Connect(function()
			if dead then return end
			if m.Enabled then
				if phase == "open" then enter("do") end
			elseif phase == "do" then
				-- Zones only asks you to LOOK, so shutting the window IS the deed. Everywhere
				-- else the ring lives inside that window, so with it shut there is nothing left
				-- on screen to follow: go back to asking for the window.
				if cfg.closeEnds then done() else enter("open") end
			end
		end))

		if cfg.watch then
			stopWatch = cfg.watch(function()
				if not dead and phase == "do" then done() end
			end)
		end

		enter("open")
		return function()
			dead = true
			if stopWatch then stopWatch() end
			for _, c in ipairs(conns) do c:Disconnect() end
			conns = {}
		end
	end
end

-- QT_cast / QT_catch / QT_earn are written by QuestsController from GameClient's report()
-- calls, so they are exact: +1 per cast, +N when a haul with fish in it breaks the surface,
-- and +value per fish during the payout.
local STEPS = {
	{
		title = "CAST",
		body  = TAP .. " anywhere to cast.",
		-- NOT QT_cast. That fires on the click, which would hand the player the STEER line
		-- while the hook is still plunging - and the plunge ignores steering entirely, so the
		-- one thing it asks for provably does nothing for the next second or two. ReelStarts is
		-- published by GameClient at the single moment STATE becomes "reeling", so the steering
		-- instruction lands on the exact frame steering starts working.
		arg   = onAttr("ReelStarts"),
	},
	{
		title = "STEER",
		-- Deliberately specific about WHEN. Steering only exists in the reeling state -
		-- GameClient leaves hookX alone during the dive on purpose ("the plunge is committed,
		-- you aimed it on the cast"), so "move side to side" without the qualifier would have
		-- players wiggling at a hook that cannot respond. One wording for mouse, touch and gamepad.
		body  = "Move from side to side as it reels back up.",
		arg   = onAttr("QT_catch"),
	},
	{
		title = "PAID",
		body  = "Fish sell themselves for coins.",
		arg   = onAttr("QT_earn"),
	},
	{
		title = "BAIT",
		-- Only the FIRST beat's line; onBaitJourney rewrites it as the player moves through.
		body  = "Roll for better bait.",
		-- No `spot`: the gate owns the highlight, because it moves three times inside one step.
		arg   = onBaitJourney(),
	},
	{
		title = "SPEND",
		body  = "Rods, boats, upgrades. Try it yourself.",
		arg   = withFreeLuck(menuJourney({
			-- All three money sinks are ringed so the sentence is TRUE, but only Upgrades gets
			-- the arrow: three arrows off one card would read as a choice, not an instruction.
			spots = { "Inventory", "Upgrades", "Boats" }, arrowSpot = "Upgrades",
			menu = "UpgradesMenu", beat = "upgrades",
			openBody = "Rods, boats, upgrades. Try it yourself.",
			doBody   = "Buy a Luck upgrade. This one's free!",
			inner    = nextLuckNode,
			-- ANY purchase counts, not only Luck. The ring says which one is meant, but
			-- hanging the tutorial because the player bought a rod instead would be worse.
			-- Always affordable: withFreeLuck makes the ringed node $0 while this step is live.
			-- It used to lean on the first haul's discovery bounties covering a $1,500 tier,
			-- which a poor catch did not.
			watch    = onPurchase(),
		})),
	},
	{
		title = "GO BIGGER",
		body  = "New zones pay more. Rebirth pays forever.",
		-- Deliberately NOT gated on buying a zone: that would withhold the end of the tutorial
		-- until the player had banked $20,000 - a wall, not a tutorial - and would keep the
		-- progress meters hidden for exactly the stretch where they help most. Looking is the
		-- whole lesson, so opening the window and closing it again is the whole gate.
		arg   = menuJourney({
			-- Rebirth is ringed alongside Zones so the second half of the line has something to
			-- look at, but the arrow points only where the step actually leads.
			spots = { "Zones", "Rebirth" }, arrowSpot = "Zones",
			menu = "ZonesMenu", beat = "zones",
			openBody  = "New zones pay more. Rebirth pays forever.",
			doBody    = "Have a look, then close it.",
			inner     = zonesCloseButton,
			closeEnds = true,
		}),
	},
}

----------------------------------------------------------------------
-- card
----------------------------------------------------------------------
card = make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 44 + 48 + ROW_GAP), Size = UDim2.fromOffset(CARD_W, CARD_H),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Visible = false }, gui)
corner(card, 18)
stroke(card, INK, 4)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, rgb(102, 184, 240)),
	ColorSequenceKeypoint.new(0.55, rgb(58, 130, 200)),
	ColorSequenceKeypoint.new(1.00, rgb(32, 88, 158)),
}) }, card)
local cardScale = make("UIScale", { Scale = 1 }, card)
-- The scale layout() WANTS, kept apart from the live one. Every pop has to spring back to
-- this, never to whatever cardScale happens to read: a second pop landing inside the first
-- would capture a mid-tween value as its target and shrink the card permanently. Steps are
-- minutes apart so it never bit there, but the bait step re-pops three times in one step.
local cardTarget = 1
-- The control the current beat is ringing, when it lives inside a menu. Drives both the
-- DisplayOrder lift and the get-out-of-the-way test in layout().
local focus = nil
local shine = make("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.new(1, -36, 0, 8), BackgroundColor3 = WHITE, BackgroundTransparency = 0.66,
	BorderSizePixel = 0, ZIndex = 3 }, card)
corner(shine, 999)

local head = make("TextLabel", { Name = "Head", BackgroundTransparency = 1, Font = FONT, Text = "",
	TextSize = 26, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true, Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -36, 0, 30),
	ZIndex = 4 }, card)
gstroke(head, INK, 2.5)

local body = make("TextLabel", { Name = "Body", BackgroundTransparency = 1, Font = FBODY, Text = "",
	TextSize = 20, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -36, 0, 26), ZIndex = 4 }, card)
gstroke(body, INK, 2)

-- A plain fixed-size Frame as the buttons' parent ON PURPOSE. TouchKit walks up from a button
-- looking for an ancestor with no auto-layout and no AutomaticSize to host its 44px touch pad;
-- if it never finds one it silently creates NO PAD, and the button is untappable on a phone.
local btnRow = make("Frame", { Name = "Buttons", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 80),
	Size = UDim2.new(1, -36, 0, 32), ZIndex = 4 }, card)

-- Step DOTS where the Next button used to be. They answer "how much of this is left?" - the
-- one useful thing a Next button was doing - without offering a way to click past the doing.
local dots = {}
for i = 1, #STEPS do
	local d = make("Frame", { Name = "Dot" .. i, BackgroundColor3 = WHITE, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, (i - 1) * 17, 0.5, 0),
		Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 0.7, ZIndex = 5 }, btnRow)
	corner(d, 999)
	stroke(d, INK, 2)
	dots[i] = d
end

-- The one button left. It DISMISSES, it does not advance - a player who cannot work out a
-- step (or does not want the walkthrough at all) still needs a way out, and without it the
-- card would sit on screen forever holding the progress meters hostage.
local skipBtn = make("TextButton", { Name = "Skip", BackgroundTransparency = 1,
	Font = FBODY, Text = "Skip tutorial", TextSize = 16, TextColor3 = rgb(196, 220, 244),
	TextXAlignment = Enum.TextXAlignment.Right, AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(130, 30), ZIndex = 5 }, btnRow)
gstroke(skipBtn, INK, 2)

----------------------------------------------------------------------
-- placement - the same channel derivation GameClient's fitHud() uses
----------------------------------------------------------------------
local function edgePanel(guiName, frameName)
	local scr = pg:FindFirstChild(guiName)
	if not (scr and scr.Enabled) then return nil end
	local f = scr:FindFirstChild(frameName)
	if f and f.Visible and f.AbsoluteSize.X > 4 then return f end
	return nil
end

-- LOCAL px (HUD_CONTRACT §1): origin = the safe-area top-left every HUD gui shares, W,H = the safe
-- area. This gui is disabled once the tutorial ends, so MainMenu's identical frame stands in then.
local function frameOf()
	local g = gui
	if not (g.Enabled and g.AbsoluteSize.X > 2) then g = pg:FindFirstChild("MainMenu") or gui end
	local sz = g.AbsoluteSize
	if sz.X < 2 then sz = cam.ViewportSize end
	return g.AbsolutePosition, sz.X, sz.Y
end

local function layout()
	local O, W, H = frameOf()
	local phone = math.min(W, H) < 500
	compact = phone
	local left, right = 0, W
	local lp = edgePanel("BaitRoller", "Panel")
	if lp then left = lp.AbsolutePosition.X + lp.AbsoluteSize.X - O.X end
	local rp = edgePanel("MainMenu", "MenuBar")
	if rp then right = rp.AbsolutePosition.X - O.X end
	-- The Daily/Wheel cluster narrows the top channel ONLY while it hangs inside it (desktop);
	-- docked into a rail (phone / tablet) it must not. Same geometric test as GameClient.
	local topLeft = left
	local cluster = edgePanel("RewardsHUD", "Cluster")
	if cluster then
		local cl = cluster.AbsolutePosition.X - O.X
		local cr = cl + cluster.AbsoluteSize.X
		if cl >= left - 1 and cr <= right + 1 then topLeft = math.max(topLeft, cr) end
	end
	local topSpan = math.max(120, right - topLeft - 2 * (phone and 8 or 12))
	local centreTop = (topLeft + right) / 2
	local cw = phone and P_CARD_W or CARD_W
	card.Size = UDim2.fromOffset(cw, CARD_H)
	cardTarget = phone and math.clamp(topSpan / cw, 0.75, 0.85) or math.clamp(topSpan / cw, 0.5, 1)
	cardScale.Scale = cardTarget
	body.TextSize = phone and 19 or 20
	-- Skip: 36 design px on a phone so it is still 30 px tall at 0.85, text 14.5 px
	skipBtn.TextSize = phone and 17 or 16
	skipBtn.Size = UDim2.fromOffset(130, phone and 36 or 30)
	-- Slot 3, the meter row's own slot to the pixel: under GameClient's published stack.
	local fh = pg:FindFirstChild("FishingHUD")
	local stack = fh and fh:GetAttribute("TopStackBottom")
	if type(stack) ~= "number" then
		local ps = phone and math.clamp(topSpan / 544, 0.6, 0.72) or math.clamp(topSpan / 544, 0.5, 1)
		stack = 44 + 48 * ps
		if (plr:GetAttribute("UpgAuto") or 0) >= 1 then stack += 8 + 40 * (phone and 0.75 or 1) end
	end
	local y = math.floor(stack + (phone and P_ROW_GAP or ROW_GAP) + 0.5)
	local cx = centreTop
	-- DisplayOrder 14 was picked so this card could never cover the thing it points at. A beat
	-- that points INSIDE a menu breaks that bargain the other way: menus are 20/25/26 and full
	-- screen, so at 14 the card is invisible at the exact moment the instruction matters. The
	-- lift to 27 comes with the rule that replaces the old guarantee - if the raised card would
	-- land on the ringed control, the card goes to the BOTTOM of the screen instead.
	-- All in LOCAL px now. (The old test mixed AbsolutePosition with Position offsets and parked
	-- the card 58px below the safe area's bottom edge on an inset device.) On a phone the open
	-- menu covers both rails, so the focused card centres on the whole width.
	if focus and focus.Parent then
		if phone then cx = W / 2 end
		local w, h = cw * cardTarget, CARD_H * cardTarget
		local fp, fs = focus.AbsolutePosition - O, focus.AbsoluteSize
		local M = 20   -- the ring's own pad, plus a little air
		if cx - w / 2 < fp.X + fs.X + M and cx + w / 2 > fp.X - M
			and y < fp.Y + fs.Y + M and y + h > fp.Y - M then
			y = math.floor(H - h - (phone and 8 or 24))
		end
	end
	card.Position = UDim2.new(0, math.floor(cx + 0.5), 0, y)
end

setFocus = function(target)
	focus = target
	gui.DisplayOrder = target and 27 or 14
	layout()
end

----------------------------------------------------------------------
-- the progress meters stay away until this is done
----------------------------------------------------------------------
local running = true
-- ⚠⚠ Write the SCREENGUI's Enabled, never the row's Visible. ProgressController re-asserts
-- `row.Visible = layout()` from six signals AND an unconditional 1Hz sweep, so any external
-- write to Visible is clobbered inside a second. It never touches gui.Enabled, so that sticks.
--
-- TutorialActive is the same idea published for OTHER HUDs to read. IndexController uses it to
-- hold back the "NEW SPECIES!" toast, which is its own ScreenGui at DisplayOrder 60 and lands
-- top-centre - directly over this card - so it covers the one instruction the player is meant
-- to be reading. CLEARED rather than set false when the tutorial ends, so the far end is a
-- plain positive test (== true) and a client where this script never ran, or died, is never
-- mistaken for one that is mid-tutorial.
local function applyMeters()
	plr:SetAttribute("TutorialActive", running or nil)
	local ph = pg:FindFirstChild("ProgressHUD")
	if ph then ph.Enabled = not running end
end
applyMeters()
-- ProgressHUD may be cloned into PlayerGui after this script starts; catch it either way.
pg.ChildAdded:Connect(function(c)
	if c.Name == "ProgressHUD" then task.defer(applyMeters) end
end)

----------------------------------------------------------------------
-- run
----------------------------------------------------------------------
local step = 0
local cleanup          -- tears down the current step's gate
local shownAt = 0
local finished = false

-- Rewrite the card's line mid-step, with the same pop a new step gets so the change is not
-- missed. shownAt moves too: MIN_READ then guarantees the LAST thing written stayed on screen
-- long enough to read, not merely the step's opening line.
setBody = function(t)
	body.Text = t
	shownAt = os.clock()
	cardScale.Scale = cardTarget * 0.94
	TweenService:Create(cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back,
		Enum.EasingDirection.Out), { Scale = cardTarget }):Play()
end

local function finish()
	if finished then return end
	finished = true
	running = false
	if cleanup then cleanup(); cleanup = nil end
	clearGlows()
	-- Also drops the DisplayOrder back to 14. It is invisible either way once the gui is off,
	-- but leaving 27 behind means a DevTutorial restart begins ABOVE every menu.
	setFocus(nil)
	applyMeters()
	plr:SetAttribute("TutorialDone", true)
	TweenService:Create(cardScale, TweenInfo.new(0.2), { Scale = cardScale.Scale * 0.85 }):Play()
	task.delay(0.2, function() card.Visible = false; gui.Enabled = false end)
end

local advance   -- forward declaration; render() needs to call it

local function render()
	local s = STEPS[step]
	if not s then finish(); return end
	if cleanup then cleanup(); cleanup = nil end

	head.Text = string.format('<font color="%s">STEP %d/%d</font>   %s',
		GOLD_HEX, step, #STEPS, s.title)
	body.Text = s.body
	showGlows(s.spot)
	for i, d in ipairs(dots) do
		d.BackgroundColor3 = (i <= step) and GOLD or WHITE
		d.BackgroundTransparency = (i <= step) and 0 or 0.7
	end
	layout()
	card.Visible = true
	gui.Enabled = true
	shownAt = os.clock()
	if step == 1 then track("shown") end

	-- a small pop so a new step reads as a new step
	local target = cardScale.Scale
	cardScale.Scale = target * 0.94
	TweenService:Create(cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back,
		Enum.EasingDirection.Out), { Scale = target }):Play()

	if s.arg then
		-- Capture which step armed this gate: a gate can fire many times (a multi-fish payout
		-- writes QT_earn once per fish), and every extra fire would otherwise advance a step.
		local myStep = step
		local satisfied = false
		cleanup = s.arg(function()
			if finished or step ~= myStep or satisfied then return end
			satisfied = true
			-- LATCH the condition, never discard it. The old code ignored anything arriving
			-- inside the read window - which threw away QT_earn, because it fires about 0.14s
			-- behind QT_catch on the SAME haul, and forced the player to cast a second time
			-- just to finish the money step. Now cast, steer, catch and get paid all complete
			-- on ONE cast: the step is simply held until it has been readable.
			local wait = MIN_READ - (os.clock() - shownAt)
			if wait <= 0 then
				advance()
			else
				task.delay(wait, function()
					if not finished and step == myStep then advance() end
				end)
			end
		end)
	end
end

advance = function()
	if finished then return end
	if DONE_KEYS[step] then track(DONE_KEYS[step]) end
	-- past the SPEND step the freebie is spent: from here the tutorial never replays (TutorialDone is saved)
	if step >= 5 then plr:SetAttribute("TutorialDone", true) end
	step += 1
	if step > #STEPS then finish() else render() end
end

TouchKit.press(skipBtn, function()
	if not finished then track("skip", step) end
	finish()
end)
cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if not finished then layout() end end)
plr:GetAttributeChangedSignal("UpgAuto"):Connect(function() if not finished then layout() end end)
-- its own frame too: on a device switch this gui's AbsoluteSize can settle AFTER ViewportSize and
-- the stack attribute have fired, and a layout run in between reads the old mode
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if not finished then layout() end end)

-- The panels we measure against are built at runtime by other scripts with no ordering
-- guarantee, so a single read at startup lands on a fallback. Poll briefly, then latch.
-- Latched even if the tutorial is skipped inside the window, so a DevTutorial restart still tracks.
task.spawn(function()
	local WATCH = { { "BaitRoller", "Panel" }, { "RewardsHUD", "Cluster" }, { "MainMenu", "MenuBar" } }
	local latched = {}
	local function relayout() if not finished then layout() end end
	for _ = 1, 30 do
		for _, w in ipairs(WATCH) do
			local scr = pg:FindFirstChild(w[1])
			local f = scr and scr:FindFirstChild(w[2])
			if f and not latched[f] then
				latched[f] = true
				f:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
				f:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout)
			end
		end
		-- the seam GameClient publishes, and MainMenu's frame (this gui's stand-in when disabled)
		local fh = pg:FindFirstChild("FishingHUD")
		if fh and not latched[fh] then
			latched[fh] = true
			fh:GetAttributeChangedSignal("TopStackBottom"):Connect(relayout)
		end
		local mm = pg:FindFirstChild("MainMenu")
		if mm and not latched[mm] then
			latched[mm] = true
			mm:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		end
		relayout()
		task.wait(0.2)
	end
end)

-- Give the HUD a moment to assemble so the card does not pop in against a half-built screen.
-- ...and for the loading screen (ReplicatedFirst.LoadingScreen) to lift: a card that pops in under
-- the curtain is never seen pop, and would log "Tutorial Started" before "Loaded In".
task.spawn(function()
	-- finished it on an earlier visit (TutorialDone is saved now): never show it again
	if plr:GetAttribute("TutorialDone") == true then finish() return end
	local t0 = os.clock()
	if game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen") then
		while not plr:GetAttribute("LoadingDone") and os.clock() - t0 < 50 do task.wait(0.1) end
	end
	task.wait(math.max(0.6, 1.2 - (os.clock() - t0)))
	advance()
end)

-- Dev hook, the house pattern: :Fire() restarts from step 1, :Fire(3) jumps to a step.
local dev = gui:FindFirstChild("DevTutorial") or make("BindableEvent", { Name = "DevTutorial" }, gui)
dev.Event:Connect(function(atStep)
	finished = false
	running = true
	applyMeters()
	step = math.clamp((tonumber(atStep) or 1) - 1, 0, #STEPS)
	advance()
end)

print("[Tutorial] " .. #STEPS .. "-step walkthrough armed ("
	.. (touch and "touch" or "desktop") .. " wording), meters hidden until done")
