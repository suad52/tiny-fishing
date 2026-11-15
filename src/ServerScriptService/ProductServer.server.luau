--[==[
	ProductServer - the Robux half of the inventory's buy buttons.

	There may only ever be ONE MarketplaceService.ProcessReceipt callback in a game; this is
	it. Nothing else in the place assigns it (checked). If you add another shop later, route
	it through here rather than assigning ProcessReceipt a second time - the second
	assignment silently wins and the first shop's purchases stop being granted.

	WHY IT HANDS OFF TO THE CLIENT. This game's economy is client-side by design: money is
	a client-created leaderstats.Money NumberValue and every item is a player attribute
	written by the client (see the Inventory / Currency notes). So the server cannot grant
	anything directly - it tells the buying client what was bought and the client applies
	it, exactly like a cash purchase does. That is no weaker than the rest of the game.

	THE RULE THAT MATTERS: return PurchaseGranted ONLY once the item is actually delivered.
	Returning it when the buyer has already left consumes the receipt forever and the player
	is simply out the Robux. So a missing player returns NotProcessedYet and Roblox re-fires
	the receipt next time they join.
]==]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")

local ShopProducts = require(ReplicatedStorage:WaitForChild("ShopProducts"))

-- ShopController already uses a ShopRemotes folder; reuse it rather than making a second.
local remotes = ReplicatedStorage:FindFirstChild("ShopRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "ShopRemotes"
	remotes.Parent = ReplicatedStorage
end
local granted = remotes:FindFirstChild("Granted")
if not granted then
	granted = Instance.new("RemoteEvent")
	granted.Name = "Granted"
	granted.Parent = remotes
end

-- The Shop window's own kinds (ShopProducts.SHOP_KINDS: cash packs, the Starter Pack) go on their own remote, which only
-- ShopController listens to - so a receipt resent at join can't be swallowed by InventoryController connecting first.
local shopGranted = remotes:FindFirstChild("ShopGranted")
if not shopGranted then
	shopGranted = Instance.new("RemoteEvent")
	shopGranted.Name = "ShopGranted"
	shopGranted.Parent = remotes
end
-- ...and zone purchases (ShopProducts.ZONE_KINDS) on theirs, which only ZonesController listens to, for the same reason.
local zoneGranted = remotes:FindFirstChild("ZoneGranted")
if not zoneGranted then
	zoneGranted = Instance.new("RemoteEvent")
	zoneGranted.Name = "ZoneGranted"
	zoneGranted.Parent = remotes
end

-- ZONES BOUGHT WITH ROBUX ARE KEPT (2026-10-10). Nothing else in this game saves progress, but a zone someone PAID for
-- must not vanish on rejoin: the receipt's zone id is written to ZonesBought_v1 BEFORE it is granted (a failed save
-- returns NotProcessedYet, so Roblox re-sends the receipt later instead of taking Robux for nothing), and every join
-- re-sends each saved zone on ZoneGranted with restore = true (ZonesController unlocks it quietly, and keeps paid zones
-- through a rebirth). Studio has no DataStore access, so there a zone is granted unsaved.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local zoneStore
do
	local okStore, res = pcall(function() return DataStoreService:GetDataStore("ZonesBought_v1") end)
	zoneStore = okStore and res or nil
end
local function saveZone(userId, zoneId)
	if not zoneStore then return false end
	for attempt = 1, 3 do
		local okSave = pcall(function()
			zoneStore:UpdateAsync("u" .. userId, function(old)
				old = type(old) == "table" and old or {}
				for _, z in ipairs(old) do if z == zoneId then return old end end
				table.insert(old, zoneId)
				return old
			end)
		end)
		if okSave then return true end
		task.wait(attempt)
	end
	return false
end
local function restoreZones(plr)
	if not zoneStore then return end
	local okLoad, list = pcall(function() return zoneStore:GetAsync("u" .. plr.UserId) end)
	if not (okLoad and type(list) == "table") then return end
	for _, z in ipairs(list) do
		if plr.Parent then pcall(function() zoneGranted:FireClient(plr, "zone", tostring(z), 0, true) end) end
	end
end
Players.PlayerAdded:Connect(restoreZones)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(restoreZones, p) end

-- Receipts Roblox has already told us about. ProcessReceipt can fire more than once for
-- the same purchase (that is why PurchaseId exists), and granting twice for one payment is
-- the mirror image of granting zero times.
local seen = {}
-- readyAt[player] = when its menus can take a grant: 4 s after its FIRST character (they start at that spawn)
local readyAt = {}
local function watchReady(p)
	if p.Character then readyAt[p] = os.clock() + 4 return end
	p.CharacterAdded:Once(function() readyAt[p] = os.clock() + 4 end)
end
Players.PlayerAdded:Connect(watchReady)
for _, p in ipairs(Players:GetPlayers()) do watchReady(p) end
Players.PlayerRemoving:Connect(function(p) readyAt[p] = nil end)

local function processReceipt(info)
	local key = tostring(info.PlayerId) .. ":" .. tostring(info.PurchaseId)
	if seen[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local plr = Players:GetPlayerByUserId(info.PlayerId)
	if not plr then
		-- they left mid-purchase; do NOT consume it
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- SAVES (SaveServer, 2026-10-11): a receipt already in this player's saved profile was granted on an earlier
	-- visit - Roblox re-sent it because that visit ended before it could say so. Don't grant it twice.
	local saveApi = game:GetService("ServerStorage"):FindFirstChild("SaveApi")
	if saveApi then
		local has = saveApi:Invoke("hasReceipt", plr, tostring(info.PurchaseId))
		if has == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet   -- their save hasn't loaded: can't know yet
		end
		if has then
			seen[key] = true
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	-- The menus that APPLY a grant only exist after the first spawn (SaveServer spawns once the save has loaded),
	-- and a RemoteEvent fired before ANY listener connects goes only to the FIRST script that connects. A receipt
	-- Roblox re-sends at join would otherwise race them. So wait until they are up.
	local t0 = os.clock()
	while plr.Parent and not (readyAt[plr] and os.clock() >= readyAt[plr]) and os.clock() - t0 < 90 do task.wait(0.25) end
	if not (readyAt[plr] and os.clock() >= readyAt[plr]) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local entry = ShopProducts.byProductId()[info.ProductId]
	if not entry then
		-- An id we do not recognise. Consuming it would take the money for nothing, so leave
		-- it unprocessed and make the misconfiguration loud.
		warn(string.format("[ProductServer] no catalog entry for product %d (bought by %s) - "
			.. "check ShopProducts.PRODUCTS", info.ProductId, plr.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local qty = 1
	if entry.kind == "bait" then
		-- pack size lives with the rarity, which the client knows; send the key and let the
		-- client resolve it the same way a cash buy does
		qty = 0
	elseif entry.kind == "boost" then
		qty = ShopProducts.packFor("boost", entry.key)
	end

	-- a zone is saved before it is granted (see ZONES BOUGHT WITH ROBUX ARE KEPT above)
	if entry.kind == "zone" and not saveZone(plr.UserId, tonumber(entry.key)) and not RunService:IsStudio() then
		warn(string.format("[ProductServer] couldn't save zone %s for %s - receipt left for a retry", tostring(entry.key), plr.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok = pcall(function()
		local ev = ((ShopProducts.SHOP_KINDS and ShopProducts.SHOP_KINDS[entry.kind]) and shopGranted)
			or ((ShopProducts.ZONE_KINDS and ShopProducts.ZONE_KINDS[entry.kind]) and zoneGranted) or granted
		-- 5th argument: the receipt id, which SaveClient acknowledges in its next snapshot
		ev:FireClient(plr, entry.kind, entry.key, qty, nil, tostring(info.PurchaseId))
	end)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- The item exists only on the client until a snapshot holding it is SAVED. Wait for that; if the player leaves
	-- first, NotProcessedYet makes Roblox re-send this receipt next visit, when it is granted again. (Zones are
	-- already saved above, before the grant.)
	if entry.kind ~= "zone" and saveApi and not saveApi:Invoke("commitReceipt", plr, tostring(info.PurchaseId), 45) then
		warn(string.format("[ProductServer] %s's grant of %s '%s' isn't saved yet - receipt left for a retry",
			plr.Name, entry.kind, tostring(entry.key)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	seen[key] = true
	-- the all-time Robux Spent board (LeaderboardServer) counts what this receipt actually cost
	local lb = game:GetService("ServerStorage"):FindFirstChild("LeaderboardRobux")
	if lb then lb:Fire(plr, info.CurrencySpent, info.PurchaseId) end
	print(string.format("[ProductServer] granted %s '%s' to %s (product %d)",
		entry.kind, tostring(entry.key), plr.Name, info.ProductId))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt

-- Studio-only test hook: ProcessReceipt is a callback Roblox won't let a script call, so tests run the same function
-- through this with a made-up receipt (no prompt, no Robux). Never exists in a live server.
if game:GetService("RunService"):IsStudio() then
	local devReceipt = Instance.new("BindableFunction")
	devReceipt.Name = "DevReceipt"
	devReceipt.Parent = script
	devReceipt.OnInvoke = processReceipt
end

Players.PlayerRemoving:Connect(function(p)
	for k in pairs(seen) do
		if k:sub(1, #tostring(p.UserId) + 1) == tostring(p.UserId) .. ":" then seen[k] = nil end
	end
end)

local live = 0
for _, id in pairs(ShopProducts.PRODUCTS) do
	if type(id) == "number" and id > 0 then live += 1 end
end
print(string.format("[ProductServer] online - %d of %d products have a real id",
	live, (function() local n = 0 for _ in pairs(ShopProducts.PRODUCTS) do n += 1 end return n end)()))
