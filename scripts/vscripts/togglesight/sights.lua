
-- These are defined in the regular weapons script, so they should already be loaded.
-- But precache just in case.

-- Turning on/off the hologram
local SND_HOLO_ON = "RapidFire.UpgradeSelectionEnabled"
local SND_HOLO_OFF = "RapidFire.UpgradeSelectionDisabled"
-- "Detaching" and re-attaching a physical prop.
local SND_REMOVE = "Shotgun.SlidebackEmpty"
local SND_ATTACH = "RapidFire.UpgradeSelectionChanged"


local enabled_addons = {};

for addon in Convars:GetStr("default_enabled_addons_list"):gmatch("[^,]+") do
	enabled_addons[addon] = true;
end


-- Definitions for each weapon. 
-- snd_pos = Offset from child model to play sound from.
-- snd_on, snd_off = Sounds to use.
-- replace_lhand, replace_rhand: If set, override the model to this.
-- group = the bodygroup index to change, if set.
--    on/off_state = states to use when turned on/off.
-- disable_draw = If set, hide when disabled.
local weapons = {
	{
		name="RapidFire",
		classname="hlvr_weapon_rapidfire",
		-- This bodygroup already exists by default.
		model="holosight",
		group=0,
		on_state=0,
		off_state=1,
		snd_on=SND_HOLO_ON,
		snd_off=SND_HOLO_OFF,
		snd_pos=Vector(0, -1.0, 4.0),
	}
};

if enabled_addons["2482808860"] then
	print("togglesight: Shooter Pistol mod enabled, cannot toggle.")
	-- TODO: Include modified version, swap model?
elseif enabled_addons["2406708838"] then
	-- It's a scope on top, not something that can be disabled.
	print("togglesight: DL-44 Blaster detected.")
	table.insert(weapons, {
		name="DL-44",
		classname="hlvr_weapon_energygun",
		disable_draw=true,
		snd_on=SND_ATTACH,
		snd_off=SND_REMOVE,
		snd_pos=Vector(0, 0, 0),
	});
else
	print("togglesight: No known pistol mods detected.")
	-- Original pistol.
	table.insert(weapons, {
		name="Alyxgun",
		classname="hlvr_weapon_energygun",
		group=1,
		on_state=1,
		off_state=0,
		snd_pos=Vector(0, 2.6875, 2.825),
		snd_on=SND_HOLO_ON,
		snd_off=SND_HOLO_OFF,
		replace="alyxgun",
	});
end

local CTX_ENABLED = "tspen_toggle_sight_enabled"
local REPLACE_PREFIX = "models/weapons/ts_togglesight/"

GlobalPrecache("sound", SND_HOLO_ON)
GlobalPrecache("sound", SND_HOLO_OFF)
GlobalPrecache("sound", SND_REMOVE)
GlobalPrecache("sound", SND_ATTACH)

for _,info in pairs(weapons) do
	if info.replace then
		info.replace_lhand = REPLACE_PREFIX .. info.replace .. "_lhand.vmdl"
		info.replace_rhand = REPLACE_PREFIX .. info.replace .. "_rhand.vmdl"
		GlobalPrecache("model", info.replace_lhand);
		GlobalPrecache("model", info.replace_rhand);
	end
end

-- Turn on Alyxlib's button tracking
Input.AutoStart = true

-- Find the sight entity, then update its state.
local function UpdateSight(gun, info, should_toggle)
	-- @type CBaseAnimating
	local child = gun:FirstMoveChild()
	while child do
		if child:GetClassname() == "reflex_sights" then
			-- Found, toggle if required.
			local enabled = Storage.LoadBoolean(gun, CTX_ENABLED, true)
			if should_toggle then
				enabled = not enabled
				Storage.SaveBoolean(gun, CTX_ENABLED, enabled)
				-- local pos = RotatePosition(child:GetAbsOrigin(), child:GetAngles(), info.snd_pos);
				-- print("Snd pos: " .. tostring(pos - gun:GetOrigin()))
				gun:EmitSound(vlua.select(enabled, info.snd_on, info.snd_off));
			end
			if info.replace then
				local mdl = child:GetModelName();
				local desired = vlua.select(Player.IsLeftHanded, info.replace_lhand, info.replace_rhand)
				-- After a reload the model gets set to null, we need to always set the first time.
				if mdl ~= desired or not info.replaced then
					print(string.format("Togglesight: Override model \"%s\" -> \"%s\"", mdl, desired));
					child:SetModel(desired);
					info.replaced = true;
				end
			end
			if info.disable_draw then
				local alpha = vlua.select(enabled, 255, 0)
				print(string.format("Set sight for %s, alpha=%i", info.name, alpha))
				child:SetRenderAlpha(alpha);
			end
			if info.group ~= nil then
				local state = vlua.select(enabled, info.on_state, info.off_state);
				print(string.format("Set sight for %s, body %i = %i", info.name, info.group, state));
				child:SetBodygroup(info.group, state)
			end
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
		"press", -1, DIGITAL_INPUT_TOGGLE_LASER_SIGHT, 1,
		function() UpdateSights(true) end
	);
	print("TS Toggle Reflex Sights active.")
end
ListenToPlayerEvent("player_activate", Init);

-- Whenever weapons are switched or the hand swaps, update in case they got out of sync.
ListenToPlayerEvent("weapon_switch", function(data) UpdateSights(false) end)
ListenToPlayerEvent("primary_hand_changed", function(data) UpdateSights(false) end)
