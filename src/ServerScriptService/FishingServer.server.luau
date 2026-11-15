--[==[
	FishingServer — the 2.5D stage's only server-side job (for now): put the
	player in the boat and keep them there. Sitting must be server-side to
	replicate; the camera / casting / fish all live in GameClient.
]==]

local Players = game:GetService("Players")

local boat = workspace:WaitForChild("Rowboat")
local seat = boat:WaitForChild("RowSeat")

local function seatPlayer(char)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not hum then return end
	char:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.35)                       -- let the rig finish assembling
	if not char.Parent then return end
	pcall(function()
		char:PivotTo(seat.CFrame * CFrame.new(0, 3.2, 0))
	end)
	task.wait(0.15)
	pcall(function() seat:Sit(hum) end)

	-- Equipping is deliberately NOT done here any more. This used to grab
	-- pack:FindFirstChildOfClass("Tool") - i.e. whatever rod happened to be first in the
	-- Backpack - which was fine when there was only ever one. Once a second rod is bought
	-- that pick is arbitrary, so the character could hold one rod while the Inventory said
	-- another was equipped. InventoryController owns the choice (it holds EquippedRod, a
	-- client attribute the server cannot see) and re-equips it on spawn.

	-- if they ever pop out, put them back
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if hum.SeatPart == nil and char.Parent then
			task.wait(0.4)
			if hum.Health > 0 and hum.SeatPart == nil then
				pcall(function()
					char:PivotTo(seat.CFrame * CFrame.new(0, 3.2, 0))
					seat:Sit(hum)
				end)
			end
		end
	end)
end

local function hook(p)
	p.CharacterAdded:Connect(seatPlayer)
	if p.Character then task.spawn(seatPlayer, p.Character) end
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end

print("[FishingServer] online — seating players on " .. seat:GetFullName())
