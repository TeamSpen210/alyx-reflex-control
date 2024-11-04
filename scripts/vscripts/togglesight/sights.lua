-- Definitions for each weapon. 
-- Model = substring for the model to swap
-- group = the group index to change.
-- on/off_state = states to use when turned on/off.
-- snd_pos = Offset from child model to play sound from.
local weapons = {
	{
		classname = "hlvr_weapon_energygun",
		-- Added this new bodygroup
		model="attach_shroud",
		group=1,
		on_state=1,
		off_state=0,
		snd_pos=Vector(0, 2.6875, 2.825),
	},
	{
		classname="hlvr_weapon_rapidfire",
		-- This bodygroup already exists by default.
		model="holosight",
		group=0,
		on_state=0,
		off_state=1,
		snd_pos=Vector(0, -1.0, 4.0),
	}
};
local CTX_ENABLED = "tspen_toggle_sight_enabled"
-- These are defined in the regular weapons script, so they should already be loaded.
-- But precache just in case.
local SND_ON = "RapidFire.UpgradeSelectionEnabled"
local SND_OFF = "RapidFire.UpgradeSelectionDisabled"
GlobalPrecache("sound", SND_ON)
GlobalPrecache("sound", SND_OFF)

-- Turn on Alyxlib's button tracking
Input.AutoStart = true

-- Find the sight entity, then update its state.
local function UpdateSight(gun, info, should_toggle)
	-- @type CBaseAnimating
	local child = gun:FirstMoveChild()
	while child do
		if child:GetModelName():find(info.model) then
			-- Found, toggle if required.
			local enabled = Storage.LoadBoolean(gun, CTX_ENABLED, true)
			if should_toggle then
				enabled = not enabled
				Storage.SaveBoolean(gun, CTX_ENABLED, enabled)
				local pos = RotatePosition(child:GetOrigin(), child:GetAngles(), info.snd_pos);
				StartSoundEventFromPosition(vlua.select(enabled, SND_ON, SND_OFF), pos);
			end
			local state = vlua.select(enabled, info.on_state, info.off_state);
			print("Set" .. info.classname .. " = " .. state);
			child:SetBodygroup(info.group, state)
		end
		child = child:NextMovePeer()
	end
end

local function UpdateSights(should_toggle)
	local gun = Player:GetWeapon()
	if gun == nil then
		return
	end
	local cls = gun:GetClassname()
	for _, info in pairs(weapons) do
		if info.classname == cls then
			UpdateSight(gun, info, should_toggle);
		end
	end
end

local function Init()
	Input:TrackButton(DIGITAL_INPUT_TOGGLE_LASER_SIGHT);
	Input:ListenToButton(
		"press", INPUT_HAND_BOTH, DIGITAL_INPUT_TOGGLE_LASER_SIGHT, 1,
		function() UpdateSights(true) end
	);
	print("TS Toggle Reflex Sights active.")
end
ListenToPlayerEvent("player_activate", Init);

-- Whenever weapons are switched, update in case they got out of sync.
ListenToPlayerEvent("weapon_switch", function(data) UpdateSights(false) end)
