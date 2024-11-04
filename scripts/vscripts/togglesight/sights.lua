if not IsServer() then
	return
end

-- Definitions for each weapon. 
-- Model = substring for the model to swap
-- group = the group index to change.
-- state = current state of the gun.
local weapons = {
	{
		classname = "hlvr_weapon_energygun",
		-- Added this new bodygroup
		model="attach_shroud",
		group=1,
		state=1,
	},
	{
		classname="hlvr_weapon_rapidfire",
		-- This bodygroup already exists by default.
		model="holosight",
		group=0,
		state=1,
	}
};
local was_held = false

-- Find the sight entity, then update its state.
local function UpdateSight(info, should_toggle)
	local gun = Entities:FindByClassname(nil, info.classname);
	while gun ~= nil do
		local child = gun:FirstMoveChild()
		while child do
			if child:GetModelName():find(info.model) then
				-- Found, toggle if required.
				if should_toggle then
					if info.state == 0 then
						info.state = 1
						-- These are defined in the regular weapons script, so they should already be loaded.
						gun:EmitSound("RapidFire.UpgradeSelectionEnabled");
					else
						info.state = 0
						gun:EmitSound("RapidFire.UpgradeSelectionDisabled");
					end
				end
				print("Set" .. info.classname .. " = " .. info.state);
				child:SetBodygroup(info.group, info.state)
			end
			child = child:NextMovePeer()
		end
		gun = Entities:FindByClassname(gun, info.classname);
	end
end

local function UpdateSights()
	for _, weapon in pairs(weapons) do
		UpdateSight(weapon, false);
	end
end

local function Toggle()
	-- Only toggle the gun which is currently out.
	local criteria = {};
	Entities:GetLocalPlayer():GatherCriteria(criteria);
	local current_gun = criteria.primaryhand_active_attachment;
	-- print('Toggle sight for "' .. current_gun .. '"')
	for _, weapon in pairs(weapons) do
		if weapon.classname == current_gun then
			UpdateSight(weapon, true);
		end
	end
end

local function Think()
	-- Is "toggle laser sight" held for this frame (but not the last one?)
	local player = Entities:GetLocalPlayer();
	local held = player:IsDigitalActionOnForHand(0, 13) or player:IsDigitalActionOnForHand(1, 13)

	if held and not was_held then
		Toggle()
	end

	was_held = held
	-- Need to run fairly quickly, to detect brief presses.
	-- Unfortunate, but this is a single short function.
	return 0.05
end

ListenToGameEvent("player_activate", function()
	local player = Entities:GetLocalPlayer()
	player:SetContextThink("tspen_toggle_sights", Think, 0.5)
	print("TS Toggle Reflex Sights active.")
end, nil);

-- Whenever weapons are switched, update in case they got out of sync.
ListenToGameEvent("weapon_switch", function() UpdateSights() end, nil)
