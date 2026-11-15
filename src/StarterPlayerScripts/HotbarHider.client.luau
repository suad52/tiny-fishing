--[[
	HotbarHider — the Roblox Backpack hotbar is never shown in this game.

	Rods are chosen in the Inventory menu (which calls Humanoid:EquipTool directly), so the
	default hotbar is redundant and clutters the bottom of a deliberately framed 2.5D shot.

	Every full-screen menu already hides the Backpack while it is open and restores whatever
	it saw beforehand. Because this runs first and pins it to false, those menus capture
	false and restore false - they cannot resurrect it. The CharacterAdded re-assert covers
	the case where the CoreGui state is rebuilt on respawn.
]]

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local plr = Players.LocalPlayer

local function hide()
	-- SetCoreGuiEnabled throws if the CoreGui is not ready yet, so keep trying briefly
	for _ = 1, 12 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then return end
		task.wait(0.25)
	end
end

hide()
plr.CharacterAdded:Connect(function() task.wait(0.5); hide() end)

print("[HotbarHider] online — Backpack hotbar disabled")
