--[==[
	ShopController - the Shop window (StarterGui.ShopMenu). Rebuilt 2026-10-10 in the +1 snowball game's shop design
	(SnowballStoreUI over there), re-themed for the sea with ReplicatedStorage.ShopKit (the snowball's kit, ported).

	One window: the cart breaking out of its top-left corner, "SHOP" in gold on a teal header with a wave crest, your
	cash in a gold pill, a red X. Three tabs under it:
	  PASSES  the Starter Pack first (until you buy it), then the six game passes
	  CASH    six cash packs, largest first, with their BEST VALUE / POPULAR stickers
	  BOOSTS  the four potions and the Jackpot Cast (BUY over USE), then Server Luck
	Every row is a candy slab in its item's colour with a 3D icon (ReplicatedStorage.ShopIcons) over a soft glow, and
	one price key on the right: pink BUY + a Robux chip, gold OWNED, grey COMING SOON. Rows never buy, only keys do.

	THE CONTRACT (what the rest of the place relies on - see the 2026-10-10 notes):
	  * This ScreenGui is PlayerGui.ShopMenu and stays the SAME instance. Enabled is the only open/close signal: MenuLogic
	    opens it, MenuBlurManager blurs behind it, TutorialController checks it, AudioController swishes on it.
	  * The close X is a TextButton named exactly "TextButton", 60 x 60, with Frame children - TutorialController's
	    closeButtonOf() finds it by that. Nothing else here may look like it (the tabs and keys have real names).
	  * No sounds of our own for clicks or open/close: AudioController adds them to every button and every *Menu gui.
	  * Prices and ids live in ReplicatedStorage.ShopProducts (the one table). An id of 0 is never prompted: the key
	    still shows its price, tapping it says "coming soon" (in Studio it is a free test purchase instead).
	  * Robux grants: ServerScriptService.ProductServer owns the ONE ProcessReceipt. Potions and the Jackpot Cast go
	    through ShopRemotes.Granted to InventoryController (it grants boosts - we only toast). Cash packs and the Starter
	    Pack come through ShopRemotes.ShopGranted, which only this script listens to.
	  * Potions: Inv_<key> attributes (shared with Inventory, Daily, Wheel); USE decrements and fires
	    BoostRemotes.Activate - BoostClient owns what a boost does.
	  * Decor loops stop while the gui is closed or Menu Animations are off (Set_MenuFX = false).
	Studio lever: PlayerGui.ShopMenu.DevShop:Fire("open", "passes" | "cash" | "boosts")  /  ("tab", t)  /  ("close").
]==]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local StarterGui = game:GetService("StarterGui")

local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))
local ShopProducts = require(ReplicatedStorage:WaitForChild("ShopProducts"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function optional(name)
	local m = ReplicatedStorage:WaitForChild(name, 10)
	local ok, t = pcall(function() return m and require(m) end)
	return ok and type(t) == "table" and t or nil
end
local TouchKit = optional("TouchKit")
local Audio = optional("Audio")

local rgb, V2 = Color3.fromRGB, Vector2.new
local CENTRE = V2(0.5, 0.5)
local DOT = "  \u{00B7}  "
local SHOP = {
	W = 800, H = 580, LIST_Y = 160, MAX_SCALE = 1.1,
	open = false, tab = "passes", rows = {}, tabs = {},
}

---------------------------------------------------------------- the ScreenGui
-- build into the ScreenGui this script lives in (never destroy and recreate it: other scripts hold it)
local gui = script.Parent
if not (gui and gui:IsA("ScreenGui")) then
	gui = playerGui:FindFirstChild("ShopMenu") or Instance.new("ScreenGui")
	gui.Name = "ShopMenu"
	gui.Parent = playerGui
end
for _, c in ipairs(gui:GetChildren()) do
	if c ~= script then c:Destroy() end
end
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function press(btn, fn)
	if TouchKit and type(TouchKit.press) == "function" then return TouchKit.press(btn, fn) end
	return btn.MouseButton1Click:Connect(fn)
end
local function sound(name, o)
	if Audio and type(Audio.play) == "function" then pcall(Audio.play, name, o) end
end

---------------------------------------------------------------- helpers
-- a line of text in the house face. o: x / y / w / h, o (outline px; 0 = none), drop, color, ZIndex, Name
local function text(parent, str, size, o)
	o = o or {}
	local l, stroke = UI.label(parent, str, {
		Name = o.Name or "Text", size = size, color = o.color, drop = o.drop,
		outline = (o.o and o.o > 0) and o.o / size or nil,
		Size = UDim2.fromOffset(o.w or 100, o.h or math.ceil(size * 1.3)), Position = UDim2.fromOffset(o.x or 0, o.y or 0),
		ZIndex = o.ZIndex or 3,
	})
	if o.o == 0 then stroke.Enabled = false end
	return l
end
-- lay pieces out in a row centred on a face `width` px wide. items: { obj, textSize? } -- a textSize marks a label,
-- sized to its text; if the row is too wide the labels narrow and their text shrinks to fit. Hidden pieces take no room.
local function layRow(items, gap, width, pad)
	local shown, fixed, want = {}, 0, 0
	for _, it in ipairs(items) do
		if it[1].Visible then
			table.insert(shown, it)
			if it[2] then
				it.w = math.ceil(UI.textWidth(it[1].Text, it[2])) + 6 + math.ceil(it[2] * 0.3) -- (+ the outline: no slack and TextScaled wraps)
				want += it.w
			else
				fixed += it[1].Size.X.Offset
			end
		end
	end
	fixed += gap * math.max(#shown - 1, 0)
	local k = want > 0 and math.clamp((width - (pad or 16) - fixed) / want, 0.3, 1) or 1
	local total = fixed
	for _, it in ipairs(shown) do
		if it[2] then
			it.w = math.max(math.floor(it.w * k), 1)
			it[1].Size = UDim2.fromOffset(it.w, it[1].Size.Y.Offset)
			total += it.w
		end
	end
	local x = (width - total) / 2
	for _, it in ipairs(shown) do
		it[1].AnchorPoint = V2(0, 0.5)
		it[1].Position = UDim2.new(0, math.floor(x + 0.5), 0.5, 0)
		x += (it[2] and it.w or it[1].Size.X.Offset) + gap
	end
end
-- re-render once, soon (a live price arrived, an attribute changed)
function SHOP.dirty()
	if SHOP.pending or not SHOP.open then return end
	SHOP.pending = true
	task.defer(function()
		SHOP.pending = false
		SHOP.render()
	end)
end
-- a Robux price: Roblox's live one once known (a re-render when it arrives), else the catalog's price as a label
function SHOP.price(id, infoType, fallback)
	id = tonumber(id) or 0
	if id <= 0 then return fallback end
	return UI.robuxPrice(id, infoType or Enum.InfoType.Product, SHOP.dirty) or fallback
end

---------------------------------------------------------------- money and items (the client-side economy)
local function moneyValue()
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and (ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then return m end
	return nil
end
local function getCoins()
	local m = moneyValue()
	if m then return m.Value end
	return player:GetAttribute("Coins") or 0
end
local function addCoins(n)
	local m = moneyValue()
	if m then
		pcall(function() m.Value = m.Value + n end)
	else
		player:SetAttribute("Coins", getCoins() + n)
	end
end
local function invCount(key)
	return tonumber(player:GetAttribute("Inv_" .. key)) or 0
end
local function addInv(key, n)
	player:SetAttribute("Inv_" .. key, invCount(key) + n)
end

-- Starting potion counts: published to the shared Inv_<key> attributes only where nothing has set one yet (Inventory,
-- Daily and Wheel read and write the same attributes). ALL ZERO since 2026-10-10 (the owner: "make it to where the user
-- doesnt spawn in with potions"; it used to hand out luck 1, cast 4, bite 2, money 3). Potions come from the Shop,
-- the daily reward, the Spin Wheel and the free gifts.
for k, v in pairs({ potion_luck = 0, potion_cast = 0, potion_bite = 0, potion_money = 0, jackpot = 0 }) do
	if player:GetAttribute("Inv_" .. k) == nil then player:SetAttribute("Inv_" .. k, v) end
end

---------------------------------------------------------------- the window
-- the scrim: a dark full-screen BUTTON under the window (a Frame would let the tap through and cast the rod behind
-- the shop) - a tap anywhere outside the window closes the Shop
SHOP.scrim = UI.new("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2, 10, 26),
	BackgroundTransparency = 0.45, AnchorPoint = CENTRE, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(4, 4),
	ZIndex = 1,
}, gui)
SHOP.win = UI.window(gui, "SHOP", { Name = "ShopWindow", w = SHOP.W, h = SHOP.H, icon = "cart", ZIndex = 5 })
local root = SHOP.win.root
SHOP.scale = UI.new("UIScale", {}, root)
-- the window catches its own taps: transparent ClickGuard buttons with no handler sit over the body and its drop (ZIndex 3:
-- over Shadow / Body, under the tabs, the list, the title, the icon and the X) and over the big icon. They are silent
-- (SndHooked set before they are parented, so AudioController leaves them alone).
local function clickGuard(parent, size, z, pos)
	local b = UI.new("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, Position = pos or UDim2.new(), ZIndex = z,
	})
	b:SetAttribute("SndHooked", true)
	b.Parent = parent
	return b
end
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, 9), 3), 24)
if SHOP.win.icon then clickGuard(SHOP.win.icon, UDim2.new(1, 0, 1, 5), 20) end

-- the cash pill: your wallet, in a gold key that is not pressable, left of the X
SHOP.pill = UI.candyKey(root, "gold", {
	Name = "CashPill", static = true, Size = UDim2.fromOffset(196, 48), Position = UDim2.fromOffset(SHOP.W - 96 - 196, 13), ZIndex = 7,
})
SHOP.win.title.Size = UDim2.fromOffset(SHOP.W - 96 - 196 - 12 - 112, SHOP.win.title.Size.Y.Offset)
function SHOP.setCash(v)
	local s = UI.cash(v)
	if SHOP.cashShown == s then return end
	SHOP.cashShown = s
	SHOP.pill.setParts(nil, { { icon = "coins", size = 40, drop = 0 }, { text = s, size = 28, o = 4, drop = 2 } }, { gap = 6 })
end
do
	local conn
	local function bind()
		if conn then conn:Disconnect() conn = nil end
		local m = moneyValue()
		if m then
			conn = m.Changed:Connect(function() SHOP.setCash(m.Value) end)
			SHOP.setCash(m.Value)
		else
			SHOP.setCash(player:GetAttribute("Coins") or 0)
		end
	end
	bind()
	player.ChildAdded:Connect(function(c)
		if c.Name == "leaderstats" then
			task.wait(0.2)
			bind()
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if not moneyValue() then SHOP.setCash(player:GetAttribute("Coins") or 0) end
	end)
end

-- the tabs: keys under the header -- gold is the tab you're on, the others sea blue
SHOP.TABS = {
	{ id = "passes", word = "PASSES", icon = "crown" },
	{ id = "cash", word = "CASH", icon = "coins" },
	{ id = "boosts", word = "BOOSTS", icon = "lightning" },
}
SHOP.TAB_OFF = "sea"
SHOP.TAB_Y = 122
for i, t in ipairs(SHOP.TABS) do
	local k = UI.candyKey(root, SHOP.TAB_OFF, {
		Name = t.word:sub(1, 1) .. t.word:sub(2):lower() .. "Tab", Size = UDim2.fromOffset(244, 54), AnchorPoint = CENTRE,
		Position = UDim2.fromOffset(18 + (i - 1) * 260 + 122, SHOP.TAB_Y), ZIndex = 7,
	})
	k.setParts(nil, { { icon = t.icon, size = 40 }, { text = t.word, size = 28, gap = 10 } })
	press(k.button, function()
		if SHOP.tab ~= t.id then
			SHOP.setTab(t.id)
			SHOP.scrollTo(0)
		end
	end)
	t.key = k
	SHOP.tabs[t.id] = t
end
function SHOP.tabId(tab)
	tab = type(tab) == "string" and tab:lower() or nil
	if tab == "pass" or tab == "passes" or tab == "starter" then return "passes" end
	if tab == "cash" or tab == "money" or tab == "packs" then return "cash" end
	if tab == "boost" or tab == "boosts" or tab == "potions" then return "boosts" end
	return nil
end

-- the list: a vertical scroll list, rows 744 wide at x 8 from y 10, its bar in a 10 px lane on the right.
-- CanvasPosition is in SCREEN px, so a UIScale change (the open pop, a resize) would slide the rows under the view:
-- the list keeps its place in design px (SHOP.listY) and puts it back.
SHOP.track = UI.new("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	Position = UDim2.fromOffset(772, SHOP.LIST_Y), Size = UDim2.fromOffset(10, 404), ZIndex = 5,
}, root)
UI.corner(SHOP.track, 5)
SHOP.list = UI.new("ScrollingFrame", {
	Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, SHOP.LIST_Y),
	Size = UDim2.fromOffset(772, 404), ZIndex = 6, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 10,
	ScrollBarImageColor3 = UI.SCROLL.thumb, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	VerticalScrollBarInset = Enum.ScrollBarInset.None, CanvasSize = UDim2.fromOffset(0, 404),
}, root)
SHOP.listY = 0
local function listK()
	return math.max(SHOP.list.AbsoluteCanvasSize.Y / math.max(SHOP.list.CanvasSize.Y.Offset, 1), 1e-3)
end
function SHOP.scrollTo(y)
	SHOP.listY = math.clamp(y, 0, math.max(SHOP.list.CanvasSize.Y.Offset - SHOP.list.Size.Y.Offset, 0))
	SHOP.list.CanvasPosition = V2(0, SHOP.listY * listK())
end
SHOP.list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	SHOP.listY = SHOP.list.CanvasPosition.Y / listK()
end)
SHOP.scale:GetPropertyChangedSignal("Scale"):Connect(function() SHOP.scrollTo(SHOP.listY) end)
SHOP.empty = text(SHOP.list, "Nothing here yet - check back soon!", 28, {
	Name = "Empty", x = 8, y = 40, w = 744, h = 40, o = 4, drop = 2, ZIndex = 4,
})
SHOP.empty.Visible = false

---------------------------------------------------------------- the toast (in the window: no global toast in this game)
SHOP.toastChip = UI.chip(root, "navy", {
	Name = "Toast", height = 50, textSize = 24, pad = 26, minWidth = 240, AnchorPoint = V2(0.5, 1), ZIndex = 40,
	Position = UDim2.new(0.5, 0, 1, -18),
})
SHOP.toastChip.block.root.Visible = false
SHOP.toastScale = UI.new("UIScale", {}, SHOP.toastChip.block.root)
-- kind: "good" (green), "info" (gold), "bad" (red), else navy
function SHOP.toast(msg, kind)
	local colour = ({ good = "green", info = "gold", bad = "red" })[kind or ""] or "navy"
	local c = SHOP.toastChip
	c.set(msg, colour)
	local rootB = c.block.root
	rootB.Visible = true
	UI.punch(SHOP.toastScale, 0.6, 0.28)
	SHOP.toastToken = (SHOP.toastToken or 0) + 1
	local token = SHOP.toastToken
	task.delay(2.4, function()
		if SHOP.toastToken == token then rootB.Visible = false end
	end)
end

---------------------------------------------------------------- buying
-- every purchase comes here. spec: kind ("product" | "pass"), id (0 = not set up), name, test() (what a Studio test
-- purchase hands over - the same grant a real receipt makes)
function SHOP.buy(spec)
	local id = tonumber(spec.id) or 0
	if id <= 0 then
		if RunService:IsStudio() and spec.test then
			spec.test()
			SHOP.toast(spec.name .. " - Studio test, free!", "good")
			sound("Coin", { volume = 0.8 })
			SHOP.dirty()
		else
			SHOP.toast(spec.name .. " - coming soon!", "info")
		end
		return
	end
	local ok = pcall(function()
		if spec.kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	if not ok then SHOP.toast("The store isn't answering - try again!", "bad") end
end

-- grants for the kinds only this shop sells (the receipt comes through ShopRemotes.ShopGranted)
SHOP.GRANT = {}
function SHOP.GRANT.cash(key)
	local pack = ShopProducts.cashPack and ShopProducts.cashPack(key)
	if not pack then return nil end
	addCoins(pack.cash)
	return "+" .. UI.cash(pack.cash) .. " cash"
end
function SHOP.GRANT.starter()
	local st = ShopProducts.STARTER or {}
	for _, k in ipairs({ "potion_luck", "potion_cast", "potion_bite", "potion_money" }) do addInv(k, st.potions or 0) end
	addInv("jackpot", st.jackpot or 0)
	if (st.cash or 0) > 0 then addCoins(st.cash) end
	player:SetAttribute("StarterBought", true)
	return "Starter Pack"
end
task.spawn(function()
	local rem = ReplicatedStorage:WaitForChild("ShopRemotes", 30)
	local mine = rem and rem:WaitForChild("ShopGranted", 30)
	if mine and mine:IsA("RemoteEvent") then
		mine.OnClientEvent:Connect(function(kind, key, _qty, _restore, receiptId)
			local fn = SHOP.GRANT[kind]
			local what = fn and fn(key)
			if what then
				-- applied: tell SaveClient, so the purchase completes once this is saved (SaveServer "ROBUX")
				local sr = ReplicatedStorage:FindFirstChild("SaveRemotes"); local ack = sr and sr:FindFirstChild("Ack")
				if ack and type(receiptId) == "string" then ack:Fire(receiptId) end
				SHOP.toast(what .. " delivered!", "good")
				sound("Fanfare", { volume = 0.7 })
				SHOP.dirty()
			end
		end)
	end
	-- potions / the Jackpot Cast bought here are granted by InventoryController (kind "boost"); we only say so
	local inv = rem and rem:WaitForChild("Granted", 30)
	if inv and inv:IsA("RemoteEvent") then
		inv.OnClientEvent:Connect(function(kind, key)
			if kind == "boost" and SHOP.open then
				local look = SHOP.BOOST_LOOK and SHOP.BOOST_LOOK[key]
				SHOP.toast((look and look.name or "Boost") .. " delivered!", "good")
				SHOP.dirty()
			end
		end)
	end
end)

-- game passes: owned = the Pass_<id> attribute (set from Roblox on join and when a purchase finishes)
local function passIdOf(id)
	return tonumber(ShopProducts.PASS_IDS and ShopProducts.PASS_IDS[id]) or 0
end
task.spawn(function()
	-- Roblox gives a pass's CREATOR a free copy, so the game's owner "owns" all six and was always playing with
	-- 2x reel, 2x hook speed, 2x money, Double Catch... (2026-10-11, owner: "why does reel speed feel so fast").
	-- Skip those free copies so the owner plays the game a normal player plays. To test the passes on the owner
	-- account, tick the OwnerPasses attribute on ReplicatedStorage.ShopProducts.
	if not ReplicatedStorage.ShopProducts:GetAttribute("OwnerPasses") then
		local owner = game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
		if game.CreatorType == Enum.CreatorType.Group then
			local ok, info = pcall(function() return game:GetService("GroupService"):GetGroupInfoAsync(game.CreatorId) end)
			owner = ok and type(info) == "table" and type(info.Owner) == "table" and info.Owner.Id == player.UserId
		end
		if owner then return end
	end
	for id in pairs(ShopProducts.PASS_IDS or {}) do
		local pid = passIdOf(id)
		if pid > 0 then
			task.spawn(function()
				local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pid) end)
				if ok and owns then player:SetAttribute("Pass_" .. id, true) end
			end)
		end
	end
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, pid, purchased)
	if who ~= player or not purchased then return end
	for id in pairs(ShopProducts.PASS_IDS or {}) do
		if passIdOf(id) == pid then
			player:SetAttribute("Pass_" .. id, true)
			SHOP.toast("Pass unlocked!", "good")
			sound("Fanfare", { volume = 0.7 })
		end
	end
	SHOP.dirty()
end)

---------------------------------------------------------------- rows
-- a row: a UI.candyRow (kind "card" 744 x 100, "tall744" 744 x 128, "duo" 744 x 128 with BUY over USE) in the item's
-- colour, its title (34) and one or two lines (25 / 22) in the text column, and its key on the right in one of three
-- states (SHOP.setKey): "buy" pink (BUY + the price chip), "owned" gold (a check + OWNED), "soon" grey (COMING SOON).
-- r.refresh(r) fills it in and returns true when it shows now; r.onBuy(r) runs when its key is tapped.
function SHOP.row(tab, kind, name, colour, iconName)
	local r = UI.candyRow(SHOP.list, { kind = kind, Name = name, colour = colour, icon = iconName, Position = UDim2.fromOffset(8, 10) })
	r.tabId = tab
	r.button.Visible = false
	r.t1 = text(r.l1, "", 34, { Name = "Title", h = r.l1.Size.Y.Offset, o = 5, drop = 3 })
	r.t2 = text(r.l2, "", 25, { Name = "Line2", h = r.l2.Size.Y.Offset, o = 3.5, drop = 2 })
	if r.l3 then r.t3 = text(r.l3, "", 22, { Name = "Line3", h = r.l3.Size.Y.Offset, o = 3, drop = 2 }) end
	local bh = r.key.button.Size.Y.Offset
	r.words = text(r.key.text, "BUY", 28, { Name = "Buy", h = 40, o = 4, drop = 2, ZIndex = 4 })
	r.chip = UI.robuxChip(r.key.text, nil, { height = math.min(40, bh - 16), textSize = 26, ZIndex = 5 })
	press(r.key.button, function()
		if r.onBuy then r.onBuy(r) end
	end)
	table.insert(SHOP.rows, r)
	return r
end
-- a row's key: "buy" (price: a number, or nil while it loads), "owned" or "soon"
function SHOP.setKey(r, state, price)
	local k = r.key
	if r.keyState ~= state then
		r.keyState = state
		if state == "buy" then
			k.recolour("pink")
			k.setParts(nil, {})
		elseif state == "owned" then
			k.recolour("gold")
			k.setParts("check", { { text = "OWNED", size = 30 } })
		else
			k.recolour("grey")
			k.setParts(nil, { { text = "COMING SOON", size = 24 } })
		end
		r.words.Visible, r.chip.root.Visible = state == "buy", state == "buy"
		r.setOwned(state == "owned")
		r.laid = nil
	end
	if state == "buy" and (r.chip.price ~= price or not r.laid) then
		r.chip.set(price)
		layRow({ { r.words, 28 }, { r.chip.root } }, 10, k.button.Size.X.Offset, 12)
		r.laid = true
	end
end
-- a row's lines (nil hides one; c2 / c3 colour lines 2 / 3), laid out again only when they change
function SHOP.lines(r, t1, t2, t3, c2, c3)
	local sig = table.concat({ t1 or "", t2 or "", t3 or "", tostring(c2), tostring(c3) }, "|")
	if r.sig == sig then return end
	r.sig = sig
	for _, it in ipairs({ { r.t1, t1, nil, 34 }, { r.t2, t2, c2, 25 }, { r.t3, t3, c3, 22 } }) do
		local l = it[1]
		if l then
			l.Visible = it[2] ~= nil
			l.Text = it[2] or ""
			l.TextColor3 = it[3] or UI.WHITE
			if l.Visible then layRow({ { l, it[4] } }, 0, r.midW, 0) end
		end
	end
end

---------------------------------------------------------------- PASSES
-- the Starter Pack: one time (StarterBought), contents from ShopProducts.STARTER; its WORTH is what the contents cost
-- on their own (the potions and the Jackpot Cast at their Robux prices), shown when that beats its own price
do
	local st = ShopProducts.STARTER or { robux = 99, potions = 2, jackpot = 1, cash = 25000 }
	local r = SHOP.row("passes", "tall744", "StarterPack", "rose", "starter")
	r.timer = text(r.l1, "ONE TIME ONLY", 25, { Name = "Timer", h = r.l1.Size.Y.Offset, o = 3.5, drop = 2, color = UI.LIME })
	r.worthWord = text(r.l3, "WORTH", 22, { Name = "Worth", h = r.l3.Size.Y.Offset, o = 3, drop = 2 })
	r.worth = UI.robuxChip(r.l3, nil, { Name = "WorthChip", height = 28, textSize = 18, colour = "grey", ZIndex = 4 })
	local function boostRobux(k)
		local b = ShopProducts.BOOST and ShopProducts.BOOST[k]
		return b and b.robux or 0
	end
	local worth = 0
	for _, k in ipairs({ "potion_luck", "potion_cast", "potion_bite", "potion_money" }) do worth += boostRobux(k) * (st.potions or 0) end
	worth += boostRobux("jackpot") * (st.jackpot or 0)
	r.worth.set(worth)
	local bits = {}
	if (st.potions or 0) > 0 then table.insert(bits, st.potions .. " of every potion") end
	if (st.jackpot or 0) > 0 then table.insert(bits, st.jackpot == 1 and "a Jackpot Cast" or (st.jackpot .. " Jackpot Casts")) end
	r.contents = table.concat(bits, " + ")
	r.extra = (st.cash or 0) > 0 and ("+" .. UI.cash(st.cash) .. " cash") or ""
	function r.refresh()
		if player:GetAttribute("StarterBought") == true then return false end
		local id = tonumber(ShopProducts.productId("starter", "pack")) or 0
		local price = SHOP.price(id, Enum.InfoType.Product, st.robux)
		r.t1.Text, r.t2.Text, r.t3.Text = "STARTER PACK", r.contents, r.extra
		local show = tonumber(price) ~= nil and worth > price
		r.worthWord.Visible, r.worth.root.Visible = show, show
		layRow({ { r.t1, 34 }, { r.timer, 25 } }, 14, r.midW, 0)
		layRow({ { r.t2, 25 } }, 0, r.midW, 0)
		layRow({ { r.t3, 22 }, { r.worthWord, 22 }, { r.worth.root } }, 8, r.midW, 0)
		SHOP.setKey(r, "buy", price)
		return true
	end
	function r.onBuy()
		SHOP.buy({ kind = "product", id = ShopProducts.productId("starter", "pack"), name = "Starter Pack", test = SHOP.GRANT.starter })
	end
end

-- the passes (ShopProducts.PASS_IDS / PASS_ROBUX), in this order
SHOP.PASSES = {
	{ id = "luck", name = "2x Luck", colour = "emerald", icon = "clover", text = "2x shiny finds + 30% luck, forever" },
	{ id = "money", name = "2x Money", colour = "orange", icon = "moneybag", text = "Every fish sells for double" },
	{ id = "cast", name = "2x Cast Speed", colour = "blue", icon = "reel", text = "Reel your line in twice as fast" },
	{ id = "bite", name = "2x Hook Speed", colour = "red", icon = "bobber", text = "Your hook sinks twice as fast" },
	{ id = "slot", name = "+1 Hook Slot", colour = "teal", icon = "rod", text = "Hook one more fish every cast" },
	{ id = "double", name = "Double Catch", colour = "purple", icon = "twofish", text = "Your hook holds twice as many fish" },
}
for _, p in ipairs(SHOP.PASSES) do
	local r = SHOP.row("passes", "card", "Pass_" .. p.id, p.colour, p.icon)
	function r.refresh()
		SHOP.lines(r, p.name, p.text)
		if player:GetAttribute("Pass_" .. p.id) == true then
			SHOP.setKey(r, "owned")
		else
			local fallback = ShopProducts.PASS_ROBUX and ShopProducts.PASS_ROBUX[p.id]
			SHOP.setKey(r, "buy", SHOP.price(passIdOf(p.id), Enum.InfoType.GamePass, fallback))
		end
		return true
	end
	function r.onBuy()
		if player:GetAttribute("Pass_" .. p.id) == true then return end
		SHOP.buy({ kind = "pass", id = passIdOf(p.id), name = p.name, test = function() player:SetAttribute("Pass_" .. p.id, true) end })
	end
end

---------------------------------------------------------------- CASH
-- the cash packs (ShopProducts.CASH_PACKS), largest first, each with its own name, icon and colour
SHOP.CASH_LOOK = {
	["1"] = { name = "A handful of coins", icon = "coins", colour = "emerald" },
	["2"] = { name = "A stack of cash", icon = "cashstack", colour = "teal" },
	["3"] = { name = "A sack full of cash", icon = "moneybag", colour = "cyan" },
	["4"] = { name = "A heap of gold", icon = "coinpile", colour = "purple", sticker = "POPULAR" },
	["5"] = { name = "A briefcase of cash", icon = "briefcase", colour = "pink" },
	["6"] = { name = "Sunken treasure!", icon = "treasure", colour = "aurora", sticker = "BEST VALUE" },
}
do
	local packs = ShopProducts.CASH_PACKS or {}
	for i = #packs, 1, -1 do
		local pack = packs[i]
		local look = SHOP.CASH_LOOK[tostring(pack.key)] or { name = "Cash", icon = "coins", colour = "emerald" }
		local r = SHOP.row("cash", "card", "Cash_" .. tostring(pack.key), look.colour, look.icon)
		if look.sticker then
			r.sticker = UI.sticker(r.button, "gold", look.sticker, {
				Name = "Sticker", Position = UDim2.fromOffset(88, 12), Rotation = -8, textSize = 15, height = 30, ZIndex = 12,
			})
		end
		function r.refresh()
			SHOP.lines(r, "+" .. UI.cash(pack.cash) .. " Cash", look.name)
			local id = tonumber(ShopProducts.productId("cash", pack.key)) or 0
			SHOP.setKey(r, "buy", SHOP.price(id, Enum.InfoType.Product, pack.robux))
			return true
		end
		function r.onBuy()
			SHOP.buy({
				kind = "product", id = ShopProducts.productId("cash", pack.key), name = "+" .. UI.cash(pack.cash) .. " Cash",
				test = function() SHOP.GRANT.cash(pack.key) end,
			})
		end
	end
end

---------------------------------------------------------------- BOOSTS
-- the note first: how a potion's time works (BoostClient: 10 min, a second one of the same kind adds 10 more)
do
	local n = UI.candyRow(SHOP.list, {
		kind = "strip", Name = "PotionNote", colour = "royal", Position = UDim2.fromOffset(8, 10),
	})
	n.tabId = "boosts"
	n.button.Visible = false
	local l = text(n.l1, "Each potion lasts 10 min - drink another to add 10 more!", 22, { Name = "Note", h = 50, o = 3, drop = 2 })
	layRow({ { l, 22 } }, 0, 744, 16)
	function n.refresh() return true end
	table.insert(SHOP.rows, n)
end
-- the potions and the Jackpot Cast: BUY (ShopProducts.BOOST[key].robux, product "boost_<key>") over USE (Inv_<key>).
-- The effects are BoostClient's (keep this copy in step with its BOOSTS table).
SHOP.BOOST_ORDER = { "potion_luck", "potion_money", "potion_cast", "potion_bite", "jackpot" }
SHOP.BOOST_LOOK = {
	potion_luck = { name = "Luck Potion", colour = "emerald", icon = "potionluck", text = "+60% luck" .. DOT .. "2x shiny finds" },
	potion_money = { name = "Money Potion", colour = "orange", icon = "potionmoney", text = "Fish sell for 1.5x" },
	potion_cast = { name = "Cast Speed Potion", colour = "blue", icon = "potioncast", text = "Reel in 1.6x faster" },
	potion_bite = { name = "Hook Speed Potion", colour = "red", icon = "potionhook", text = "Your hook sinks 1.6x faster" },
	jackpot = { name = "Jackpot Cast", colour = "cosmic", icon = "jackpot", text = "Your next cast hits the jackpot!", charge = true },
}
for _, key in ipairs(SHOP.BOOST_ORDER) do
	local look = SHOP.BOOST_LOOK[key]
	local def = ShopProducts.BOOST and ShopProducts.BOOST[key] or { robux = 29 }
	local r = SHOP.row("boosts", "duo", "Boost_" .. key, look.colour, look.icon)
	r.useWords = text(r.key2.text, "USE", 26, { Name = "Use", h = 36, o = 3.5, drop = 2, ZIndex = 4 })
	function r.refresh()
		local n = invCount(key)
		local have = "You have " .. n
		local tail = look.charge and "spent by your next cast" or "10 min each"
		SHOP.lines(r, look.name, look.text, have .. DOT .. tail, nil, n > 0 and UI.LIME or UI.TEXT.soft)
		local id = tonumber(ShopProducts.productId("boost", key)) or 0
		SHOP.setKey(r, "buy", SHOP.price(id, Enum.InfoType.Product, def.robux))
		local can = n > 0
		if r.canUse ~= can or r.useN ~= n then
			r.canUse, r.useN = can, n
			r.key2.recolour(can and "green" or "grey")
			r.useWords.Text = can and ("USE (" .. n .. ")") or "NONE LEFT"
			layRow({ { r.useWords, 26 } }, 0, r.key2.button.Size.X.Offset, 12)
		end
		return true
	end
	function r.onBuy()
		SHOP.buy({ kind = "product", id = ShopProducts.productId("boost", key), name = look.name, test = function() addInv(key, 1) end })
	end
	press(r.key2.button, function()
		local n = invCount(key) -- (fresh: Inventory, Daily and Wheel write it too)
		if n <= 0 then
			SHOP.toast("No " .. look.name .. " left - buy one first!", "bad")
			return
		end
		local folder = ReplicatedStorage:FindFirstChild("BoostRemotes")
		local ev = folder and folder:FindFirstChild("Activate")
		if not ev then
			SHOP.toast("Boosts aren't ready yet - try again!", "bad")
			return
		end
		player:SetAttribute("Inv_" .. key, n - 1)
		ev:Fire(key)
		SHOP.toast(look.charge and "Jackpot Cast ready - cast away!" or (look.name .. " active for 10 min!"), "good")
		sound("Bubble", { volume = 0.8 })
		UI.punch(r.scale, 1.03, 0.25)
		SHOP.dirty()
	end)
end
-- Server Luck: a boost for everyone in the server. There is no server code for it yet, so it says so.
do
	local r = SHOP.row("boosts", "card", "ServerLuck", "teal", "clover")
	function r.refresh()
		SHOP.lines(r, "Server Luck (15 min)", "2x luck for everyone in the server")
		SHOP.setKey(r, "soon")
		return true
	end
	function r.onBuy() SHOP.toast("Server Luck - coming soon!", "info") end
end

---------------------------------------------------------------- the sea behind the rows (the stud baseplate's stand-in)
-- light rays and rising bubbles in the window's Ocean layer: only the gaps between rows show them. One loop, idle
-- while the shop is closed or Menu Animations are off (Set_MenuFX = false).
do
	local ocean = SHOP.win.ocean
	SHOP.rays = {}
	for i, x in ipairs({ 0.12, 0.34, 0.58, 0.83 }) do
		local ray = UI.new("Frame", {
			Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 46 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, ocean)
		UI.new("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(SHOP.rays, { f = ray, phase = i * 1.3 })
	end
	SHOP.bubbles = {}
	for i = 1, 22 do
		local s = 6 + (i * 7) % 13
		local b = UI.new("Frame", {
			Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = CENTRE,
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, ocean)
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		UI.new("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		table.insert(SHOP.bubbles, { f = b, x = ((i * 0.618) % 1), y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i })
	end
	RunService.RenderStepped:Connect(function(dt)
		if not gui.Enabled or player:GetAttribute("Set_MenuFX") == false then return end
		local t = os.clock()
		for _, b in ipairs(SHOP.bubbles) do
			b.y -= b.speed * dt
			if b.y < -0.05 then
				b.y = 1.05
				b.x = (b.x + 0.37) % 1
			end
			b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
		end
		for _, r in ipairs(SHOP.rays) do
			r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
		end
	end)
	for _, b in ipairs(SHOP.bubbles) do b.f.Position = UDim2.new(b.x, 0, b.y, 0) end
end

---------------------------------------------------------------- render, tabs, layout, open / close
-- the open tab's rows that show now, one under another (20 px apart: room for their drops and outlines)
function SHOP.render()
	if not SHOP.open then return end
	local y = 10
	for _, r in ipairs(SHOP.rows) do
		local show = false
		if r.tabId == SHOP.tab then
			local ok, res = pcall(r.refresh, r)
			if not ok then warn("[Shop] " .. r.button.Name .. ": " .. tostring(res)) end
			show = ok and res == true
		end
		r.button.Visible = show
		if show then
			r.button.Position = UDim2.fromOffset(8, y)
			y += r.h + 20
		end
	end
	SHOP.empty.Visible = y == 10
	local canvas = math.max(y - 8, 100)
	if SHOP.list.CanvasSize.Y.Offset ~= canvas then
		SHOP.list.CanvasSize = UDim2.fromOffset(0, canvas)
		SHOP.scrollTo(SHOP.listY)
	end
end
function SHOP.setTab(id)
	SHOP.tab = SHOP.tabs[id] and id or "passes"
	for tid, t in pairs(SHOP.tabs) do
		local lit = tid == SHOP.tab
		if t.lit ~= lit then
			t.lit = lit
			t.key.recolour(lit and "gold" or SHOP.TAB_OFF)
		end
	end
	SHOP.render()
end
-- Centred on the screen, as big as fits (never past MAX_SCALE). Its reach past its box: the big icon 44 px above the
-- top (none on a phone, where the cart is tucked into the header), the X 30 px past the right edge, the drop 9 px below.
-- A small screen (a phone) keeps the scale up and takes a shorter window instead (the list shows fewer rows). Returns
-- the scale.
function SHOP.layout()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or V2(1280, 720)
	local abs = gui.AbsoluteSize
	local cw = (abs.X > 100 and abs.X < vp.X) and abs.X or vp.X
	local ch = (abs.Y > 100 and abs.Y < vp.Y) and abs.Y or vp.Y
	if cw < 100 or ch < 100 then return SHOP.fit or 1 end
	local form = UI.form()
	local bar = GuiService.TopbarInset.Max.Y
	local top = (bar > 0 and bar or 58) + 4
	local room = ch - 8 - top
	local fitW = (cw - 16) / (SHOP.W + 66)
	-- 2026-10-11, the owner: "make the button uis centered to the phone screen" (and chose "centre, tuck the icon"). On a
	-- phone the cart no longer breaks out 44 px above the window - centred, that reach would cost the whole window 12-22%
	-- of its scale - it is TUCKED into the header's left end: 64 px at (10, 5), inside the 74 px header even turned -8
	-- degrees, its drop ending on the header's bottom edge, 38 px short of the title. Off a phone it goes back exactly
	-- where UI.window put it.
	local icon = SHOP.win.icon
	if icon then
		SHOP.iconAt = SHOP.iconAt or { icon.Size, icon.Position }
		icon.Size = form.phone and UDim2.fromOffset(64, 64) or SHOP.iconAt[1]
		icon.Position = form.phone and UDim2.fromOffset(10, 5) or SHOP.iconAt[2]
	end
	local h = SHOP.H
	if form.phone then
		-- as tall as fits CENTRED at the width's scale: the box under the top bar (nothing reaches above it), the drop
		-- 8 px off the bottom
		local s = math.min(fitW, SHOP.MAX_SCALE)
		h = math.clamp(math.floor(math.min(ch - 2 * top, ch - 16 - 18 * s) / s), SHOP.LIST_Y + 150, SHOP.H)
	end
	local fit = math.clamp(math.min(fitW, room / (h + 44 + 9), SHOP.MAX_SCALE), 0.35, SHOP.MAX_SCALE)
	-- Off a phone the window's BODY sits on the middle of the screen, like every other menu (MenuFit's
	-- fromScale(0.5, 0.5)). Centred in the band under the top bar instead, the cart's 44 px reach pushed it
	-- low - its drop ended 8 px off the bottom with ~100 px spare above (the owner, 2026-10-10: "center the
	-- shop more"). The reach is lopsided (44 above, 9 below), so at the centre the scale is also held to what
	-- keeps the cart under the top bar. A phone is centred the same way since 2026-10-11 ("centered to the phone
	-- screen"): its cart is tucked, so only the box itself is held under the top bar (the X rises into the bar's free
	-- region on the right, as on every other menu) and the drop 8 px off the bottom.
	local cy
	if form.phone then
		local mid = ch / 2
		fit = math.clamp(math.min(fitW, (mid - top) / (h / 2), (mid - 8) / (h / 2 + 9), SHOP.MAX_SCALE), 0.35, SHOP.MAX_SCALE)
		cy = mid
	else
		local mid = ch / 2
		fit = math.clamp(math.min(fit, (mid - top) / (h / 2 + 44), (mid - 8) / (h / 2 + 9)), 0.35, SHOP.MAX_SCALE)
		cy = mid
	end
	root.Size = UDim2.fromOffset(SHOP.W, h)
	local viewH = h - SHOP.LIST_Y - 16
	SHOP.list.Size = UDim2.fromOffset(SHOP.W - 28, viewH)
	SHOP.track.Size = UDim2.fromOffset(10, viewH)
	root.Position = UDim2.new(0.5, 0, 0, math.floor(cy + 0.5))
	SHOP.fit = fit
	return fit
end

local prevBackpack = true
local function setBackpackHidden(hidden)
	pcall(function()
		if hidden then
			prevBackpack = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		else
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, prevBackpack)
		end
	end)
end

function SHOP.onOpen()
	if SHOP.open then return end
	SHOP.open = true
	local fit = SHOP.layout()
	SHOP.scrim.BackgroundTransparency = 1
	TweenService:Create(SHOP.scrim, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
	SHOP.scale.Scale = 0.6 * fit
	TweenService:Create(SHOP.scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	SHOP.toastChip.block.root.Visible = false
	SHOP.setTab(SHOP.nextTab or "passes")
	SHOP.nextTab = nil
	SHOP.scrollTo(0)
	setBackpackHidden(true)
end
function SHOP.onClose()
	if not SHOP.open then return end
	SHOP.open = false
	setBackpackHidden(false)
end
function SHOP.close()
	gui.Enabled = false
end
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then SHOP.onOpen() else SHOP.onClose() end
end)
press(SHOP.scrim, SHOP.close)
press(SHOP.win.close.button, SHOP.close)

-- a new screen (a resized window, a different device): place it again
local function refit()
	if not SHOP.open then return end
	SHOP.scale.Scale = SHOP.layout()
	SHOP.scrollTo(SHOP.listY)
end
-- (a device switch or rotation passes through in-between sizes: wait for it to settle, then fit once more)
local refitToken = 0
local function refitSoon()
	refitToken += 1
	local t = refitToken
	task.delay(0.15, function() if t == refitToken then refit() end end)
	task.delay(0.6, function() if t == refitToken then refit() end end)
end
do
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refitSoon) end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local c = workspace.CurrentCamera
		if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(refitSoon) end
		refitSoon()
	end)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refitSoon)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitSoon)
end

-- live state: counts, ownership and prices on the open tab follow the attributes (and a 1 s tick)
player.AttributeChanged:Connect(function(a)
	if a:match("^Inv_") or a:match("^Pass_") or a == "StarterBought" then SHOP.dirty() end
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function() SHOP.dirty() end)
task.spawn(function()
	while gui.Parent do
		if SHOP.open then SHOP.render() end
		task.wait(1)
	end
end)

-- Studio lever (the house Dev* convention): DevShop:Fire("open", tab) / ("tab", tab) / ("close")
if RunService:IsStudio() then
	local lever = UI.new("BindableEvent", { Name = "DevShop" }, gui)
	lever.Event:Connect(function(verb, tab)
		if verb == "open" then
			if SHOP.open then
				SHOP.setTab(SHOP.tabId(tab) or SHOP.tab)
				SHOP.scrollTo(0)
			else
				SHOP.nextTab = SHOP.tabId(tab)
				gui.Enabled = true
			end
		elseif verb == "tab" and SHOP.open then
			SHOP.setTab(SHOP.tabId(tab) or "passes")
			SHOP.scrollTo(0)
		elseif verb == "close" then
			SHOP.close()
		end
	end)
end

print("[Shop] built - " .. #SHOP.rows .. " rows in 3 tabs (the +1 snowball design, sea theme)")
