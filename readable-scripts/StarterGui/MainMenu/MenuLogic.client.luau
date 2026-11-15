local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
-- Every button on this bar is 0.0892 of the bar's height, so on an 812x375 phone the whole
-- column renders 129x31 and on a 480x320 one 122x26 - all ten under the 44px touch floor.
-- Eleven 44px rows will not fit in 375px of screen, so instead of resizing the art each
-- button gets an invisible 44px hit pad underneath it on touch devices.
local TouchKit = require(game:GetService("ReplicatedStorage"):WaitForChild("TouchKit"))
local gui = script.Parent
local bar = gui:WaitForChild("MenuBar")
local list = bar:WaitForChild("List")
local popup = gui:WaitForChild("Popup")
local window = popup:WaitForChild("Window")
local title = window:WaitForChild("Title")
local body = window:WaitForChild("Body")
local pg = Players.LocalPlayer:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- row height
----------------------------------------------------------------------
-- Each button used to be 0.0892 of the bar's height, which is 62px on a 751-tall screen
-- and 31px on a 375-tall phone - and eleven 44px rows simply do not fit in 375px, so a hit
-- pad cannot rescue them either (the pad is not allowed to reach its neighbour, which is
-- what stops it firing the WRONG menu). The rows get a pixel FLOOR instead and `List` is a
-- ScrollingFrame, so on a short screen the column scrolls rather than shrinking below the
-- touch floor. On a desktop 0.0892 x 698 = 62 exceeds the floor, the canvas fits, and no
-- scrollbar appears - the bar is pixel-identical to before.
local ROW_SCALE, ROW_MIN = 0.0892, 46
local GAP_SCALE, GAP_MIN = 0.012, 6
-- ⚠️ THE STACK NEEDS A MARGIN AT BOTH ENDS, AND MEASURED IT HAD NEITHER. At 1313x751 the ten
-- rows ran 56..748 against a 751px screen: 4px under the header and **2px above the bottom
-- edge**, so Leaderboard read as falling off the screen. The gap between rows was doing all the
-- absorbing (0.012 x 698 = 8px x 9 = 72px of it) while the two ends got whatever was left, which
-- was nothing. So the margin is now reserved FIRST and the gap takes what remains - see sizeRows.
--
-- ⚠️ AND THE MEASUREMENT ITSELF IS A TRAP. This ScreenGui sets IgnoreGuiInset, so every
-- AbsolutePosition here is in INSET space: the bar reports y = -58 and the last row reports
-- 686..748 while the screen is 0..751. A first pass "found" 60px of slack that does not exist.
-- Add GetGuiInset().Y before comparing anything here to ViewportSize.
local PAD_SCALE = 0.017
-- Below this row width a caption cannot be read at any size, so the row goes icon-only.
-- (At 129px wide with a 41px icon the caption box is ~50px, which renders "Leaderboard" at
-- about 9pt. Shrinking type until it fits is the failure mode; hiding it is the fix.)
local COMPACT_W = 170
local layout = list:WaitForChild("UIListLayout")
local listPad = list:FindFirstChildOfClass("UIPadding")

-- The icon, caption and badge were authored as fixed offsets (a 56px square, a 0.30-scale
-- caption inset) against a 62px-tall row. Once the row can be 46px those stop lining up -
-- the 56px icon overflowed a 31px row into its neighbours and covered the caption - so all
-- three are derived from the row height here. Every ratio below reproduces the authored
-- desktop pixel exactly at rowH = 62: 0.903 x 62 = 56, 0.194 x 62 = 12, and icon + gap
-- lands the caption at 84 (it was 0.300 x 282 = 84.6).
-- This bar hugs the right edge, which is exactly where the Roblox top bar keeps its own
-- controls on a phone. The column runs from 0.07 of the bar's height, i.e. 26px on a
-- 375-tall screen - under it. On a short screen the list starts below the inset instead
-- (and, being a ScrollingFrame now, simply scrolls the rows that no longer fit).
local GuiService = game:GetService("GuiService")
local function insetList()
	local cam = workspace.CurrentCamera
	if not cam or cam.ViewportSize.Y < 1 then return end
	local inset = GuiService:GetGuiInset().Y
	local short = (cam.ViewportSize.Y - inset) < 620
	local top = short and inset or 0
	list.Position = UDim2.new(0, 0, 0.07, top)
	list.Size = UDim2.new(1, 0, 0.93, -top)
end
-- (insetList is no longer called or connected here: relayout() at the bottom of the layout
-- section picks the phone grid or this wide column, and re-picks on every resize.)

local function sizeRows()
	local h, w = list.AbsoluteSize.Y, list.AbsoluteSize.X
	if h < 4 or w < 4 then return end
	local n = 0
	for _, b in ipairs(list:GetChildren()) do if b:IsA("TextButton") then n += 1 end end
	if n == 0 then return end
	local rowH = math.max(ROW_MIN, math.floor(h * ROW_SCALE + 0.5))

	-- MARGIN FIRST, GAP SECOND. The rows keep their authored height - the complaint was about
	-- WHERE the last one sits, not how big it is - so the margin is taken out of the gap, which
	-- had 72px to give. At 751 tall that is pad 12 top and bottom, gap 8 -> 6, and the stack
	-- lands 65..739 inside a 751px screen: 12px clear at the bottom instead of 2.
	local pad = math.max(4, math.floor(h * PAD_SCALE + 0.5))
	if listPad then
		listPad.PaddingTop    = UDim.new(0, pad)
		listPad.PaddingBottom = UDim.new(0, pad)
	end
	-- Whatever is left after the margins and the rows, split between the gaps - but never below
	-- GAP_MIN, and never ABOVE the authored proportion (or removing a row would leave the few
	-- that remain floating far apart). On a phone rowH hits its 46px floor and the stack simply
	-- overflows, which is what the ScrollingFrame is for.
	local gap = math.clamp(
		math.floor((h - 2 * pad - n * rowH) / math.max(1, n - 1)),
		GAP_MIN,
		math.max(GAP_MIN, math.floor(h * GAP_SCALE + 0.5)))
	local rowW = w - 22
	local compact = rowW < COMPACT_W
	layout.Padding = UDim.new(0, gap)

	local iconS = math.floor(rowH * (compact and 0.78 or 0.903) + 0.5)
	local iconX = math.floor(rowH * 0.194 + 0.5)
	local capX  = iconX + iconS + math.floor(rowH * 0.26 + 0.5)
	local capW  = rowW - capX - math.floor(rowH * 0.37 + 0.5)

	for _, btn in ipairs(list:GetChildren()) do
		if btn:IsA("TextButton") then
			btn.Size = UDim2.new(1, -22, 0, rowH)
			local icon = btn:FindFirstChild("Icon")
			if icon then
				icon.Size = UDim2.fromOffset(iconS, iconS)
				icon.AnchorPoint = Vector2.new(compact and 0.5 or 0, 0.5)
				icon.Position = compact and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(0, iconX, 0.5, 0)
			end
			local label = btn:FindFirstChild("Label")
			if label then
				label.Visible = not compact
				label.Position = UDim2.new(0, capX, 0.5, 0)
				-- A row with a Notif badge stops its caption 4px short of the badge. Measured on the
				-- iPad (row 248x68): the caption box ran to 1144 under a badge starting at 1126, so
				-- the "!" sat on the "s" of Upgrades. Desktop renders identically: the captions are
				-- left-aligned single words that already fit the shorter box at full size.
				local w = capW
				if not compact and btn:FindFirstChild("Notif") then
					w = math.min(w, rowW - 12 - math.floor(rowH * 0.45 + 0.5) - 4 - capX)
				end
				label.Size = UDim2.fromOffset(math.max(10, w), math.floor(rowH * 0.5 + 0.5))
				-- CAPTION SIZE. These are TextScaled labels, so the rendered size is
				-- min(what fits the box, MaxTextSize) - and MaxTextSize was pinned at 24 in
				-- the place file, which was ALWAYS the binding term on a desktop: the box is
				-- 175x31 and the widest caption ("Leaderboard") drew only 124px of it, so a
				-- third of the row sat empty and the type read small beside the 56px icon.
				-- Deriving the cap from the row instead gives 0.45 x 62 = 28 on desktop -
				-- 3px inside the 31px box (TextBounds height == TextSize for this font, so
				-- that is real slack, descenders included) and 155px of the 175px width at
				-- the longest caption. On a shorter row it shrinks with the box rather than
				-- overflowing it, and below COMPACT_W the caption is hidden anyway.
				local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
				if cap then cap.MaxTextSize = math.max(12, math.floor(rowH * 0.45 + 0.5)) end
			end
			local notif = btn:FindFirstChild("Notif")
			if notif then
				local ns = math.floor(rowH * 0.45 + 0.5)
				notif.Size = UDim2.fromOffset(ns, ns)
				-- in compact the badge would sit ON the centred icon, so it moves to the corner
				notif.AnchorPoint = Vector2.new(1, compact and 0 or 0.5)
				notif.Position = compact and UDim2.new(1, -4, 0, 2) or UDim2.new(1, -12, 0.5, 0)
			end
			local shine = btn:FindFirstChild("Shine")
			if shine then shine.Size = UDim2.new(1, -math.floor(rowH * 0.42 + 0.5), 0, math.max(4, math.floor(rowH * 0.13 + 0.5))) end
		end
	end
end
-- (sizeRows runs from relayout(), wide mode only - on a phone the grid below owns the tiles.)

-- The column's own title sits in MenuBar.Header, outside the row loop, and had the same
-- problem: TextScaled with a 26 cap in a 273x31.5 box, where "TINY FISHING" drew 178px
-- wide - width was never the limit, the cap was. 30 needs 205px of the 273 and the box
-- grows to 0.68 of the header (35.7px) so the bigger type keeps its 5px of slack.
local headerFrame = bar:FindFirstChild("Header")
local headerTitle = headerFrame and headerFrame:FindFirstChild("GameTitle")
local headerCap = headerTitle and headerTitle:FindFirstChildOfClass("UITextSizeConstraint")
if headerTitle then headerTitle.Size = UDim2.new(0.9, 0, 0.68, 0) end
local AUTH_HEADER = headerFrame and headerFrame.Size

----------------------------------------------------------------------
-- PHONE: a 2x5 grid of named tiles + an empty sixth row for the rewards dock
----------------------------------------------------------------------
-- One column cannot work on a phone. Ten rows at the 46px floor need ~520px and a landscape
-- phone has ~375, so on an iPhone 7 only 5 of the 10 were visible and the other half scrolled
-- off the bottom (measured: list 84..374, canvas 524). The bar was icon-only there anyway
-- (captions hide below COMPACT_W), so the same ten tiles are regrouped two to a row, which
-- fits all ten with no scrolling. The SIXTH row is left EMPTY and published as
-- RewardsDockPos/RewardsDockSize (LOCAL px, HUD_CONTRACT R4): RewardsHUDController draws the
-- Daily gift and the Wheel into it, taking them out of the play area.
-- Tablet and desktop never take this path - they keep insetList + sizeRows, pixel for pixel.
-- The mode is re-decided on every resize (switching the simulator mid-session is the test).
local PH_PAD, PH_COLGAP, PH_ROWGAP, PH_BOTTOM = 6, 6, 5, 6
-- List is a ScrollingFrame, and a ScrollingFrame ALWAYS clips. Flush with the tiles it would
-- shave the Notif badge's stroke and the hover pop off the outer tiles, so it is grown by this
-- much on every side and padded back in: the TILE rects are exactly the contract's.
local PH_CLIP = 4
-- a tile stacks its icon (PH_ICON_TOP from the top) over its name (PH_CAP_BOTTOM from the bottom)
local PH_ICON_TOP, PH_CAP_BOTTOM = 3, 2
-- A name that would have to shrink below PH_MIN_TEXT to fit its tile shows its short form instead
-- (measured: the iPhone 8's 57px tile drew "Leaderboard" at 9px, the 568x320 one at 8px, and an iPhone 6
-- Plus at 11px beside 14px names, where it read as a footnote). 12 keeps the full name from 812 wide up.
-- Wide mode puts the full name back.
local PH_MIN_TEXT = 12
local PH_SHORT = { Leaderboard = "Leaders" }
local TextService = game:GetService("TextService")
local grid = Instance.new("UIGridLayout")
grid.Name = "PhoneGrid"
grid.FillDirection = Enum.FillDirection.Horizontal
grid.FillDirectionMaxCells = 2
grid.SortOrder = Enum.SortOrder.LayoutOrder    -- LayoutOrder 1..10 reads Inventory|Upgrades, Zones|Boats ...
grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
grid.VerticalAlignment = Enum.VerticalAlignment.Top
grid.StartCorner = Enum.StartCorner.TopLeft

-- authored values the wide path puts back (captured before anything touches them)
local AUTH_SBT = list.ScrollBarThickness
local AUTH_PADL = listPad and listPad.PaddingLeft
local AUTH_PADR = listPad and listPad.PaddingRight
local AUTH_CORNER = {}
for _, b in ipairs(list:GetChildren()) do
	local c = b:IsA("TextButton") and b:FindFirstChildOfClass("UICorner")
	if c then AUTH_CORNER[b] = c.CornerRadius end
end
-- the caption's own anchor, alignment and outline, which the phone tiles restyle (sizeRows sets the rest)
local AUTH_LABEL = {}
for _, b in ipairs(list:GetChildren()) do
	local l = b:IsA("TextButton") and b:FindFirstChild("Label")
	if l then
		local st = l:FindFirstChildOfClass("UIStroke")
		AUTH_LABEL[l] = { anchor = l.AnchorPoint, align = l.TextXAlignment, stroke = st and st.Thickness, text = l.Text }
	end
end

local function setAttr(name, v)
	if bar:GetAttribute(name) ~= v then bar:SetAttribute(name, v) end
end

local function phoneLayout(H)
	local barW = bar.AbsoluteSize.X             -- RollerController owns MenuBar.Size; we only react
	local listTop = GuiService:GetGuiInset().Y + 4  -- 62: nothing tappable under Roblox's top bar
	local rowH = math.floor((H - PH_BOTTOM - listTop - 5 * PH_ROWGAP) / 6)   -- 5 menu rows + the dock row
	local cellW = math.floor((barW - 2 * PH_PAD - PH_COLGAP) / 2)
	if rowH < 8 or cellW < 8 then return end
	local gridW, gridH = 2 * cellW + PH_COLGAP, 5 * rowH + 4 * PH_ROWGAP

	if headerFrame then headerFrame.Size = UDim2.new(1, 0, 0, listTop - 4) end
	-- 16, not 18: "🐟  TINY FISHING" is 126px on one line at 18 and the iPhone 7 box is 119, so at
	-- 18 TextScaled WRAPPED it to two lines there while wider phones showed one. At 16 it is 116px:
	-- one line on every phone. (Do not turn TextWrapped off to force one line - measured: the label
	-- then dropped out of TextScaled and drew at its 8px TextSize.)
	if headerCap then headerCap.MaxTextSize = 16 end

	grid.CellSize = UDim2.fromOffset(cellW, rowH)
	grid.CellPadding = UDim2.fromOffset(PH_COLGAP, PH_ROWGAP)
	if layout.Parent then layout.Parent = nil end
	if grid.Parent ~= list then grid.Parent = list end
	list.Position = UDim2.fromOffset(PH_PAD - PH_CLIP, listTop - PH_CLIP)
	list.Size = UDim2.fromOffset(gridW + 2 * PH_CLIP, gridH + 2 * PH_CLIP)
	list.ScrollingEnabled = false
	list.ScrollBarThickness = 0
	list.CanvasPosition = Vector2.zero
	if listPad then
		local m = UDim.new(0, PH_CLIP)
		listPad.PaddingTop, listPad.PaddingBottom, listPad.PaddingLeft, listPad.PaddingRight = m, m, m, m
	end

	-- NAMES ON THE TILES (2026-10-11, the owner: "state the names of the button on the right side like how
	-- the pc version has it"). The grid was icon-only because a caption BESIDE a phone icon got ~50px and drew
	-- "Leaderboard" at ~9pt (see COMPACT_W). STACKED it gets the tile's whole width instead - the icon in the
	-- top part, the name centred under it, the mobile tab-bar pattern. One cap for every tile, so the names
	-- read as one size of type; TextScaled only takes the longest word below it.
	local capH = math.floor(rowH * 0.32 + 0.5)
	local iconS = math.floor(math.min(cellW * 0.8, rowH - capH - PH_ICON_TOP - PH_CAP_BOTTOM - 1) + 0.5)
	local ns = math.floor(rowH * 0.40)
	-- the authored 18px corner is 0.28 of the desktop 64px row; keep that proportion on a small tile
	local radius = UDim.new(0, math.floor(rowH * 0.28 + 0.5))
	for _, btn in ipairs(list:GetChildren()) do
		if btn:IsA("TextButton") then
			local icon = btn:FindFirstChild("Icon")
			if icon then
				icon.Size = UDim2.fromOffset(iconS, iconS)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, PH_ICON_TOP)
			end
			local label = btn:FindFirstChild("Label")
			if label then
				label.Visible = true
				label.AnchorPoint = Vector2.new(0.5, 1)
				label.Position = UDim2.new(0.5, 0, 1, -PH_CAP_BOTTOM)
				label.Size = UDim2.new(1, -6, 0, capH)
				label.TextXAlignment = Enum.TextXAlignment.Center
				local full = AUTH_LABEL[label] and AUTH_LABEL[label].text or label.Text
				local text, short = full, PH_SHORT[btn.Name]
				if short then
					local w = TextService:GetTextSize(full, capH, Enum.Font.FredokaOne, Vector2.new(1e4, 1e4)).X
					if capH * math.min(1, (cellW - 6) / math.max(1, w)) < PH_MIN_TEXT then text = short end
				end
				if label.Text ~= text then label.Text = text end
				local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
				if cap then cap.MaxTextSize = capH end
				-- the desktop's 2.6px outline is drawn for 28px type; on 12-17px type it fills the letters in
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Thickness = math.max(1, capH * 0.1) end
			end
			local notif = btn:FindFirstChild("Notif")
			if notif then
				notif.Size = UDim2.fromOffset(ns, ns)
				notif.AnchorPoint = Vector2.new(1, 0)
				notif.Position = UDim2.new(1, -3, 0, 2)
			end
			local shine = btn:FindFirstChild("Shine")
			if shine then shine.Size = UDim2.new(1, -10, 0, math.max(3, math.floor(rowH * 0.12))) end
			local corner = btn:FindFirstChildOfClass("UICorner")
			if corner then corner.CornerRadius = radius end
		end
	end

	-- The dock row, in this gui's LOCAL px (origin = the safe-area top-left, which every HUD gui
	-- shares). Its width is the GRID's, not the bar's, so the two reward cells line up with the
	-- two tile columns above them.
	local barLeft = bar.AbsolutePosition.X - gui.AbsolutePosition.X
	setAttr("RewardsDockPos", Vector2.new(barLeft + PH_PAD, listTop + 5 * (rowH + PH_ROWGAP)))
	setAttr("RewardsDockSize", Vector2.new(gridW, rowH))
end

local function wideLayout()
	if grid.Parent then grid.Parent = nil end
	if layout.Parent ~= list then layout.Parent = list end
	list.ScrollingEnabled = true
	list.ScrollBarThickness = AUTH_SBT
	if listPad then listPad.PaddingLeft, listPad.PaddingRight = AUTH_PADL, AUTH_PADR end
	if headerFrame and AUTH_HEADER then headerFrame.Size = AUTH_HEADER end
	if headerCap then headerCap.MaxTextSize = 30 end
	for b, r in pairs(AUTH_CORNER) do
		local c = b.Parent and b:FindFirstChildOfClass("UICorner")
		if c then c.CornerRadius = r end
	end
	for l, a in pairs(AUTH_LABEL) do
		if l.Parent then
			l.AnchorPoint, l.TextXAlignment = a.anchor, a.align
			if l.Text ~= a.text then l.Text = a.text end
			local st = a.stroke and l:FindFirstChildOfClass("UIStroke")
			if st then st.Thickness = a.stroke end
		end
	end
	insetList()
	sizeRows()   -- reads list.AbsoluteSize; the resize insetList causes re-runs it with the new size
	setAttr("RewardsDockPos", nil)
	setAttr("RewardsDockSize", nil)
end

local busy = false
local function relayout()
	if busy then return end
	busy = true
	local ok, err = pcall(function()
		local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
		if W < 2 or H < 2 then
			local cam = workspace.CurrentCamera
			if not cam then return end
			W, H = cam.ViewportSize.X, cam.ViewportSize.Y
		end
		if W < 2 or H < 2 then return end
		if math.min(W, H) < 500 then phoneLayout(H) else wideLayout() end
	end)
	busy = false
	if not ok then warn("[MenuLogic] relayout: " .. tostring(err)) end
end
relayout()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
bar:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout)
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
-- Index and Quests clone a Notif badge into their button later; size it for the current mode.
for _, b in ipairs(list:GetChildren()) do
	if b:IsA("TextButton") then
		b.ChildAdded:Connect(function(c) if c.Name == "Notif" then task.defer(relayout) end end)
	end
end

local blurbs = {
	Inventory   = "Your caught fish and gear will live here.",
	Upgrades    = "Boost your line, luck, and reel speed here.",
	Zones       = "Travel to new fishing spots and oceans.",
	Boats       = "Trade up from the rowboat to a deep-sea rig.",
	Quests      = "Complete objectives for big rewards.",
	Rebirth     = "Reset for permanent multipliers.",
	Shop        = "Buy rods, bait, and boosts.",
	Index       = "Your fish collection / bestiary.",
	Settings    = "Tune audio, graphics, and controls.",
	Leaderboard = "See the top anglers around the world.",
}

local function openPopup(name)
	title.Text = name
	body.Text = (blurbs[name] or "This menu is coming soon.") .. "\n(placeholder)"
	popup.Visible = true
	window.Size = UDim2.new(0, 356, 0, 260)
	TweenService:Create(window, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 440, 0, 322) }):Play()
end
local function closePopup() popup.Visible = false end

local function openShop()
	local sh = pg:FindFirstChild("ShopMenu")
	if sh then sh.Enabled = true end
end

local function openIndex()
	local ix = pg:FindFirstChild("IndexMenu")
	if ix then ix.Enabled = true end
end

local function openUpgrades()
	local ug = pg:FindFirstChild("UpgradesMenu")
	if ug then ug.Enabled = true end
end

local function openRebirth()
	local rb = pg:FindFirstChild("RebirthMenu")
	if rb then rb.Enabled = true end
end

local function openZones()
	local zn = pg:FindFirstChild("ZonesMenu")
	if zn then zn.Enabled = true end
end

local function openBoats()
	local bt = pg:FindFirstChild("BoatsMenu")
	if bt then bt.Enabled = true end
end

local function openSettings()
	local st = pg:FindFirstChild("SettingsMenu")
	if st then st.Enabled = true end
end

local function openQuests()
	local qs = pg:FindFirstChild("QuestsMenu")
	if qs then qs.Enabled = true end
end

local function openInventory()
	local iv = pg:FindFirstChild("InventoryMenu")
	if iv then iv.Enabled = true end
end

-- Feedback has NO button on this bar any more. Eleven buttons filled the right edge to
-- 99% of its height and read as cluttered, so the entry point moved into the Settings
-- menu as its third tab; SettingsController fires FeedbackMenu.OpenFeedback from there.

local function openLeaderboard()
	local lb = pg:FindFirstChild("LeaderboardMenu")
	if lb then lb.Enabled = true end
end

-- Daily Rewards and the Spin Wheel are NOT in this bar: they live on the floating
-- RewardsHUD cluster in the play area, which owns its own badges and timers.

for _, btn in ipairs(list:GetChildren()) do
	if btn:IsA("TextButton") then
		local scale = btn:FindFirstChildOfClass("UIScale")
		TouchKit.press(btn, function()
			if btn.Name == "Upgrades" then
				openUpgrades()
			elseif btn.Name == "Rebirth" then
				openRebirth()
			elseif btn.Name == "Shop" then
				openShop()
			elseif btn.Name == "Index" then
				openIndex()
			elseif btn.Name == "Zones" then
				openZones()
			elseif btn.Name == "Boats" then
				openBoats()
			elseif btn.Name == "Settings" then
				openSettings()
			elseif btn.Name == "Quests" then
				openQuests()
			elseif btn.Name == "Inventory" then
				openInventory()
			elseif btn.Name == "Leaderboard" then
				openLeaderboard()
			else
				openPopup(btn.Name)
			end
		end)
		if scale then
			btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.045 }):Play() end)
			btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
		end
	end
end

popup:WaitForChild("Backdrop").MouseButton1Click:Connect(closePopup)
TouchKit.press(window:WaitForChild("CloseButton"), closePopup)
TouchKit.press(window:WaitForChild("XButton"), closePopup)
