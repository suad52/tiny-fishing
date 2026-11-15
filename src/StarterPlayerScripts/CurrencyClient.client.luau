--[[
	CurrencyClient — ONE shared money balance for the whole client.

	Every system already agrees on the convention "leaderstats.Money (or .Cash) if it
	exists, else the Coins attribute": GameClient earns into it, InventoryController's
	SELL ALL adds to it, and ShopMenu / ZonesMenu / RebirthMenu / UpgradesMenu spend from
	it. But NOTHING was creating leaderstats.Money, so each menu fell back to its own
	private demo balance and money you fished vanished into a Coins attribute nobody spent.

	This creates it, ONCE, on the client — earning happens client-side, so the value has
	to be client-writable (a server-owned IntValue can't be changed from the client). It
	is seeded from any Coins already earned and mirrored back to the Coins attribute so any
	straggler still reading the attribute stays in agreement.

	NumberValue (not IntValue): balances run well past 2.1B — zone 6 costs 900M, rebirths
	push higher — and IntValue overflows there.
--]]

local Players = game:GetService("Players")
local plr = Players.LocalPlayer

-- Reuse a real leaderstats if a server ever adds one; otherwise make the client copy.
local stats = plr:FindFirstChild("leaderstats")
local madeStats = false
if not stats then
	stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	madeStats = true
end

local money = stats:FindFirstChild("Money") or stats:FindFirstChild("Cash")
if not money then
	money = Instance.new("NumberValue")
	money.Name = "Money"
	money.Value = plr:GetAttribute("Coins") or 0
	money.Parent = stats
end

-- Parent the folder LAST (with Money already inside) so every menu's
-- "leaderstats added" listener finds Money immediately when it fires.
if madeStats then stats.Parent = plr end

-- Keep the Coins attribute mirrored to the balance both ways at start, then follow it.
plr:SetAttribute("Coins", money.Value)
money.Changed:Connect(function(v)
	plr:SetAttribute("Coins", v)
end)

-- SAVED BALANCE (SaveServer, 2026-10-11): the server writes SavedCoins once, when your save loads - a name this
-- client never writes. This script starts at join, usually BEFORE that, so it follows the attribute instead of
-- reading Coins once at line 35. Setting Money fires Money.Changed, which updates Coins and every menu.
local function applySaved()
	local c = tonumber(plr:GetAttribute("SavedCoins"))
	if c and c == c and c >= 0 then money.Value = c end
end
applySaved()
plr:GetAttributeChangedSignal("SavedCoins"):Connect(applySaved)
