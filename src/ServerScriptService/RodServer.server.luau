--[[
	RodServer — hands over a fishing rod Tool once it has been unlocked.

	The 10 rods live in ServerStorage.FishingRods, which the client cannot reach, so the
	actual handover has to happen here. InventoryController owns the PURCHASE (it spends
	the client-side money and sets Rod_<tier>) and then asks this script for the Tool —
	same split as DailyServer/WheelServer: client owns the economy, server owns the thing
	the client can't touch.

	Backpacks are emptied on respawn, so the client re-requests everything it owns on each
	CharacterAdded; Grant is therefore idempotent and simply no-ops if the rod is present.

	TRUST: ownership is client-asserted, consistent with the rest of this place. If the
	economy ever moves server-side, validate Rod_<tier> here before cloning.
]]

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SOURCE = ServerStorage:WaitForChild("FishingRods", 20)

local remotes = ReplicatedStorage:FindFirstChild("RodRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "RodRemotes"
	remotes.Parent = ReplicatedStorage
end
local grant = remotes:FindFirstChild("Grant")
if not grant then
	grant = Instance.new("RemoteEvent")
	grant.Name = "Grant"
	grant.Parent = remotes
end

-- rods are named "07 · Emerald Rod", so the tier is just the zero-padded prefix
local function toolForTier(tier)
	if not SOURCE then return nil end
	local prefix = string.format("%02d", tier)
	for _, t in ipairs(SOURCE:GetChildren()) do
		if t:IsA("Tool") and t.Name:sub(1, 2) == prefix then return t end
	end
	return nil
end

-- Clients cannot see ServerStorage, so the Inventory has no way to PREVIEW a rod it does
-- not own yet - the card would show a price beside an empty tank. Publish inert copies for
-- display only. Scripts are stripped: a display copy must never be able to run anything.
do
	local previews = ReplicatedStorage:FindFirstChild("RodPreviews")
	if not previews then
		previews = Instance.new("Folder")
		previews.Name = "RodPreviews"
		previews.Parent = ReplicatedStorage
	end
	if SOURCE then
		for _, t in ipairs(SOURCE:GetChildren()) do
			if t:IsA("Tool") and not previews:FindFirstChild(t.Name) then
				local c = t:Clone()
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then d:Destroy() end
				end
				c.Parent = previews
			end
		end
	end
end

grant.OnServerEvent:Connect(function(plr, tier)
	tier = tonumber(tier)
	if not tier or tier ~= math.floor(tier) or tier < 1 or tier > 10 then return end
	local tool = toolForTier(tier)
	if not tool then return end
	local bp = plr:FindFirstChildOfClass("Backpack")
	if not bp then return end
	-- idempotent: already in the pack (or currently held) means nothing to do
	if bp:FindFirstChild(tool.Name) then return end
	local char = plr.Character
	if char and char:FindFirstChild(tool.Name) then return end
	tool:Clone().Parent = bp
end)

print("[RodServer] online — " .. (SOURCE and #SOURCE:GetChildren() or 0) .. " rods available to grant")
