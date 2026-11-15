--[[ FeedbackController — the Feedback menu.

	Roblox experiences CANNOT open external links (GuiService:OpenBrowserWindow is
	RobloxScriptSecurity), so a feedback button can't launch a form, a Discord invite
	or a mail client. Feedback therefore has to be collected IN-GAME and shipped to
	the creator over a RemoteEvent — that's what this does.

	Submissions go to ServerScriptService.FeedbackServer, which re-validates and
	rate-limits (the client is untrusted) and logs + persists them.
	Test hook: FeedbackMenu.DevFeedback:Fire() opens the panel.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui   = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local gui = script.Parent
local remote = ReplicatedStorage:WaitForChild("FeedbackRemote")
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))


local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local function lighten(c,t) return c:Lerp(Color3.new(1,1,1), t) end
local function darken(c,t)  return c:Lerp(Color3.new(0,0,0), t) end

local FONT, FBODY, FMED = Enum.Font.FredokaOne, Enum.Font.GothamBold, Enum.Font.GothamMedium
local INK      = rgb(8,22,44)
local DEEP_TOP, DEEP_MID, DEEP_BOT = rgb(84,196,246), rgb(30,120,206), rgb(10,44,104)
local HEAD_TOP, HEAD_BOT = rgb(96,220,252), rgb(28,132,214)
local GOLD, GOLD_DK = rgb(255,224,104), rgb(150,84,8)
local C = { panelHi = rgb(230,245,255), text = rgb(12,30,56), sub = rgb(70,96,130),
            good = rgb(70,214,128), bad = rgb(240,84,96), aqua = rgb(64,196,224) }

local function make(class, props, parent)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(i,r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }, i) end
local function stroke(i,c,t) return make("UIStroke", { Color = c or INK, Thickness = t or 3,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, i) end
local function grad(i, a, b, rot)
	return make("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }, i)
end

----------------------------------------------------------------------
-- shell
----------------------------------------------------------------------
local backdrop = make("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1,1),
	BackgroundColor3 = rgb(2,10,26), BackgroundTransparency = 0.42, Text = "",
	AutoButtonColor = false, ZIndex = 1 }, gui)

local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5,0.5),
	Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromOffset(600, 528),
	BackgroundColor3 = DEEP_MID, BorderSizePixel = 0, ZIndex = 2 }, gui)
corner(panel, 26); stroke(panel, INK, 4)
grad(panel, DEEP_TOP, DEEP_BOT, 90)
local pop = make("UIScale", { Name = "Pop" }, panel)

-- This was the one menu in the game with NO viewport fit: a fixed 600x528 panel. On an
-- 812x375 phone that is 153px taller than the screen, so the X button sat 62px ABOVE the
-- top edge and SEND FEEDBACK ran off the bottom - the panel could be opened but neither
-- closed nor submitted. It uses the shared MenuFit now like every other window, which also
-- keeps it clear of the Roblox top bar (its X sits in the panel's top-right corner, which
-- is exactly where that bar's own controls are on a phone). MIN_H is 500 because the body
-- is a UIListLayout of fixed-height rows totalling 404 under a 96px header+margin, so there
-- is almost nothing to give; the win here is the placement, not the scale.
-- `pop` doubles as the fit scale, so open() tweens back to fitScale(), not to 1.
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
-- PHONE LAYOUT (short side < 500). The one-column 600x528 form could only shrink to
-- ~0.54-0.61 on a phone: a panel half the screen wide, 10px text, 25px category chips.
-- On a phone the form is re-authored as TWO columns (rating + category + status on the
-- left, message box over SEND on the right) at the width that fills the safe area at CMP.s
-- and as tall as the band under the top bar, so MenuFit settles on exactly CMP.s. maxS =
-- CMP.s also pins MenuFit to its adaptive branch. Decided on every fit (open + every
-- viewport change); desktop and iPad take the untouched original call.
local CMP = { s = 0.8, col = 0.44, on = nil, apply = nil }
local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
	if vp.X >= 100 and vp.Y >= 100 and math.min(vp.X, vp.Y) < 500 then
		if CMP.apply then CMP.apply(true) end
		local availH = math.max(160, vp.Y - game:GetService("GuiService"):GetGuiInset().Y - 12)
		local w = math.clamp(math.floor((vp.X - 40) / CMP.s), 600, 1200)
		local h = math.clamp(math.floor(availH / CMP.s), 300, 528)
		MenuFit.apply(panel, pop, w, h, 0.45, CMP.s, h)
		-- centred on the phone screen like every other menu (2026-10-11, the owner: "centered to the phone
		-- screen"); nothing breaks out of this panel and it has no drop, so up and down are 0
		return MenuFit.centre(panel, pop, 0, 0)
	end
	if CMP.apply then CMP.apply(false) end
	-- max 1.0, not the 1.1 the other menus use: this panel had NO fit at all before, so 1.0
	-- is its authored size and anything above it would grow the desktop panel by 10%.
	return MenuFit.apply(panel, pop, 600, 528, 0.45, 1.0, 500)
end
local function fit() fitScale() end
fit()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if gui.Enabled then fit() end
	end)
end

local header = make("Frame", { Name = "Header", Size = UDim2.new(1,0,0,74),
	BackgroundColor3 = HEAD_BOT, BorderSizePixel = 0, ZIndex = 3 }, panel)
corner(header, 26); grad(header, HEAD_TOP, HEAD_BOT, 90)
make("Frame", { Size = UDim2.new(1,0,0,26), Position = UDim2.new(0,0,1,-26),
	BackgroundColor3 = HEAD_BOT, BorderSizePixel = 0, ZIndex = 3 }, header)

local titleLbl = make("TextLabel", { Size = UDim2.new(1,-120,0,44), Position = UDim2.fromOffset(28, 16),
	BackgroundTransparency = 1, Font = FONT, Text = "💬  FEEDBACK", TextColor3 = Color3.new(1,1,1),
	TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 5 }, header)

local closeBtn = make("TextButton", { Name = "XButton", AnchorPoint = Vector2.new(1,0.5),
	Position = UDim2.new(1,-20,0.5,0), Size = UDim2.fromOffset(46,46), BackgroundColor3 = C.bad,
	Font = Enum.Font.GothamBold, Text = "X", TextColor3 = Color3.new(1,1,1), TextSize = 26, ZIndex = 6,
	AutoButtonColor = false }, header)
corner(closeBtn, 14); stroke(closeBtn, INK, 3)

local body = make("Frame", { Name = "Body", Size = UDim2.new(1,-36,1,-96),
	Position = UDim2.fromOffset(18, 86), BackgroundTransparency = 1, ZIndex = 3 }, panel)
local bodyList = make("UIListLayout", { Padding = UDim.new(0,12), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center }, body)

----------------------------------------------------------------------
-- rating
----------------------------------------------------------------------
local rating = 0
local starBtns = {}
local rateRow = make("Frame", { LayoutOrder = 1, Size = UDim2.new(1,0,0,52),
	BackgroundTransparency = 1, ZIndex = 3 }, body)
local rateLbl = make("TextLabel", { Size = UDim2.new(0,150,1,0), BackgroundTransparency = 1, Font = FBODY,
	Text = "How's it going?", TextColor3 = Color3.new(1,1,1), TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, rateRow)
local starHolder = make("Frame", { AnchorPoint = Vector2.new(1,0.5), Position = UDim2.new(1,0,0.5,0),
	Size = UDim2.fromOffset(5*46, 46), BackgroundTransparency = 1, ZIndex = 4 }, rateRow)
local starList = make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,4),
	SortOrder = Enum.SortOrder.LayoutOrder }, starHolder)

local function paintStars()
	for i, b in ipairs(starBtns) do
		b.TextColor3 = (i <= rating) and GOLD or rgb(150,178,206)
		b.TextTransparency = (i <= rating) and 0 or 0.25
	end
end
for i = 1, 5 do
	local b = make("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(42,42),
		BackgroundTransparency = 1, Font = FONT, Text = "★", TextSize = 34,
		TextColor3 = rgb(150,178,206), AutoButtonColor = false, ZIndex = 5 }, starHolder)
	starBtns[i] = b
	TouchKit.press(b, function()
		rating = (rating == i) and 0 or i
		paintStars()
		local s = make("UIScale", {}, b); s.Scale = 1.5
		TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		task.delay(0.3, function() if s then s:Destroy() end end)
	end)
end
paintStars()

----------------------------------------------------------------------
-- category
----------------------------------------------------------------------
local CATS = { { "🐛", "Bug" }, { "💡", "Idea" }, { "⚖️", "Balance" }, { "💬", "Other" } }
local category = "Bug"
local catBtns = {}
local catRow = make("Frame", { LayoutOrder = 2, Size = UDim2.new(1,0,0,46),
	BackgroundTransparency = 1, ZIndex = 3 }, body)
local catList = make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,8),
	SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, catRow)

local function paintCats()
	for key, b in pairs(catBtns) do
		local on = (key == category)
		b.BackgroundColor3 = on and GOLD or rgb(22,86,158)
		b.TextColor3 = on and GOLD_DK or Color3.new(1,1,1)
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then st.Color = on and GOLD_DK or INK end
	end
end
for i, c in ipairs(CATS) do
	local b = make("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(128, 42),
		BackgroundColor3 = rgb(22,86,158), Font = FBODY, Text = c[1] .. "  " .. c[2],
		TextColor3 = Color3.new(1,1,1), TextSize = 16, AutoButtonColor = false, ZIndex = 4 }, catRow)
	corner(b, 12); stroke(b, INK, 2.5)
	catBtns[c[2]] = b
	TouchKit.press(b, function() category = c[2]; paintCats() end)
end
paintCats()

----------------------------------------------------------------------
-- message
----------------------------------------------------------------------
local boxWrap = make("Frame", { LayoutOrder = 3, Size = UDim2.new(1,0,0,182),
	BackgroundColor3 = C.panelHi, BorderSizePixel = 0, ZIndex = 3 }, body)
corner(boxWrap, 16); stroke(boxWrap, INK, 3)

local box = make("TextBox", { Size = UDim2.new(1,-24,1,-38), Position = UDim2.fromOffset(12, 10),
	BackgroundTransparency = 1, Font = FMED, PlaceholderText = "Tell me what you think…",
	PlaceholderColor3 = rgb(150,168,190), Text = "", TextColor3 = C.text, TextSize = 16,
	TextWrapped = true, MultiLine = true, ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 4 }, boxWrap)

local MAXLEN = 300
local counter = make("TextLabel", { AnchorPoint = Vector2.new(1,1), Position = UDim2.new(1,-12,1,-8),
	Size = UDim2.fromOffset(90,20), BackgroundTransparency = 1, Font = FMED,
	Text = "0/" .. MAXLEN, TextColor3 = C.sub, TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, boxWrap)

----------------------------------------------------------------------
-- send + status
----------------------------------------------------------------------
local sendBtn = make("TextButton", { LayoutOrder = 4, Size = UDim2.new(1,0,0,56),
	BackgroundColor3 = C.good, Font = FONT, Text = "SEND FEEDBACK",
	TextColor3 = Color3.new(1,1,1), TextSize = 24, AutoButtonColor = false, ZIndex = 4 }, body)
corner(sendBtn, 16); stroke(sendBtn, INK, 3)

local status = make("TextLabel", { LayoutOrder = 5, Size = UDim2.new(1,0,0,20),
	BackgroundTransparency = 1, Font = FMED, Text = "", TextColor3 = GOLD, TextSize = 14, ZIndex = 4 }, body)

local function setSendEnabled(on)
	sendBtn.BackgroundColor3 = on and C.good or rgb(96,112,140)
	sendBtn.TextTransparency = on and 0 or 0.35
end
setSendEnabled(false)

-- Phone layout (see CMP above fitScale). The two list layouts are DETACHED on a phone so
-- the rows can sit in two columns; re-parenting them restores the desktop column exactly.
-- TouchKit hosts were chosen at wiring time from ancestors WITHOUT layouts (rateRow for
-- the stars, the panel for everything else), so detaching them does not strand a pad.
CMP.apply = function(on)
	if on == CMP.on then return end
	CMP.on = on
	local col = CMP.col
	header.Size = UDim2.new(1, 0, 0, on and 60 or 74)
	titleLbl.Position = on and UDim2.fromOffset(24, 10) or UDim2.fromOffset(28, 16)
	titleLbl.Size = UDim2.new(1, -120, 0, on and 40 or 44)
	closeBtn.Size = on and UDim2.fromOffset(50, 50) or UDim2.fromOffset(46, 46)
	closeBtn.Position = on and UDim2.new(1, -14, 0.5, 0) or UDim2.new(1, -20, 0.5, 0)
	closeBtn.TextSize = on and 28 or 26
	body.Position = on and UDim2.fromOffset(18, 70) or UDim2.fromOffset(18, 86)
	body.Size = on and UDim2.new(1, -36, 1, -80) or UDim2.new(1, -36, 1, -96)
	bodyList.Parent = (not on) and body or nil
	catList.Parent = (not on) and catRow or nil
	-- left column: the rating prompt over a 5-star row, then a 2x2 category grid
	rateRow.Position = UDim2.new()
	rateRow.Size = on and UDim2.new(col, -6, 0, 88) or UDim2.new(1, 0, 0, 52)
	rateLbl.Size = on and UDim2.new(1, 0, 0, 26) or UDim2.new(0, 150, 1, 0)
	rateLbl.TextSize = on and 18 or 17
	starHolder.AnchorPoint = on and Vector2.new(0, 0) or Vector2.new(1, 0.5)
	starHolder.Position = on and UDim2.fromOffset(0, 32) or UDim2.new(1, 0, 0.5, 0)
	starHolder.Size = on and UDim2.fromOffset(5*52 + 4*6, 52) or UDim2.fromOffset(5*46, 46)
	starList.Padding = UDim.new(0, on and 6 or 4)
	for _, b in ipairs(starBtns) do
		b.Size = on and UDim2.fromOffset(52, 52) or UDim2.fromOffset(42, 42)
		b.TextSize = on and 42 or 34
	end
	catRow.Position = on and UDim2.fromOffset(0, 98) or UDim2.new()
	catRow.Size = on and UDim2.new(col, -6, 0, 102) or UDim2.new(1, 0, 0, 46)
	for i, c in ipairs(CATS) do
		local b = catBtns[c[2]]
		local right = (i - 1) % 2
		b.Position = on and UDim2.new(right * 0.5, right * 5, 0, (i > 2) and 56 or 0) or UDim2.new()
		b.Size = on and UDim2.new(0.5, -5, 0, 46) or UDim2.fromOffset(128, 42)
		b.TextSize = on and 17 or 16
	end
	-- status sits at the foot of the left column, level with SEND
	status.Position = on and UDim2.new(0, 0, 1, -44) or UDim2.new()
	status.Size = on and UDim2.new(col, -6, 0, 44) or UDim2.new(1, 0, 0, 20)
	status.TextSize = on and 15 or 14
	status.TextWrapped = on
	-- right column: the message box over SEND
	boxWrap.Position = on and UDim2.new(col, 6, 0, 0) or UDim2.new()
	boxWrap.Size = on and UDim2.new(1 - col, -6, 1, -68) or UDim2.new(1, 0, 0, 182)
	box.TextSize = on and 17 or 16
	counter.TextSize = on and 14 or 13
	sendBtn.Position = on and UDim2.new(col, 6, 1, -56) or UDim2.new()
	sendBtn.Size = on and UDim2.new(1 - col, -6, 0, 56) or UDim2.new(1, 0, 0, 56)
end

box:GetPropertyChangedSignal("Text"):Connect(function()
	if #box.Text > MAXLEN then box.Text = string.sub(box.Text, 1, MAXLEN) end
	counter.Text = #box.Text .. "/" .. MAXLEN
	setSendEnabled(#box.Text >= 2)
end)

----------------------------------------------------------------------
-- open / close / submit
----------------------------------------------------------------------
local function setHotbar(on)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, on) end)
end

local function close()
	gui.Enabled = false
	setHotbar(true)
end

local function open()
	gui.Enabled = true
	setHotbar(false)
	status.Text = ""
	local target = fitScale()
	pop.Scale = target * 0.86
	TweenService:Create(pop, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = target }):Play()
end

TouchKit.press(closeBtn, close)
backdrop.MouseButton1Click:Connect(close)

local awaiting = false
TouchKit.press(sendBtn, function()
	if awaiting or #box.Text < 2 then return end
	awaiting = true
	setSendEnabled(false)
	status.TextColor3 = GOLD
	status.Text = "Sending…"
	remote:FireServer({ category = category, rating = rating, message = box.Text })
	task.delay(6, function()
		if awaiting then
			awaiting = false
			status.TextColor3 = C.bad
			status.Text = "Couldn't reach the server — try again."
			setSendEnabled(#box.Text >= 2)
		end
	end)
end)

remote.OnClientEvent:Connect(function(ok, why)
	awaiting = false
	if ok then
		status.TextColor3 = C.good
		status.Text = "Thanks! Your feedback was sent. 🎣"
		box.Text = ""
		rating = 0
		paintStars()
		task.delay(1.6, function() if gui.Enabled then close() end end)
	else
		status.TextColor3 = C.bad
		status.Text = why or "Something went wrong."
		setSendEnabled(#box.Text >= 2)
	end
end)

local dev = Instance.new("BindableEvent")
dev.Name = "DevFeedback"
dev.Parent = gui
dev.Event:Connect(open)

local openEvt = Instance.new("BindableEvent")
openEvt.Name = "OpenFeedback"
openEvt.Parent = gui
openEvt.Event:Connect(open)

fit()
print("[Feedback] menu built")
