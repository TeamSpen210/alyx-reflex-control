
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
---@class WeaponInfo
---@field name string Debug name for the weapon.
---@field snd_pos Vector = Offset from child model to play sound from.
---@field snd_on string Sound to use when turned on.
---@field snd_off string
---@field replace? string If set, override the model using this name.
---@field group? integer The bodygroup index to change, if set.
---@field on_state? integer States to use when turned on/off.
---@field off_state? integer
---@field disable_draw? boolean If set, hide when disabled.
-- Later set:
---@field replace_lhand string? Full model path for left hand.
---@field replace_rhand string? Full model path for right hand.
---@field replaced boolean? If the model has been replaced during this session.

---@type table<string, WeaponInfo>
local weapons = {
	hlvr_weapon_rapidfire={
		name="RapidFire",
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
	weapons.hlvr_weapon_energygun = {
		name="DL-44",
		disable_draw=true,
		snd_on=SND_ATTACH,
		snd_off=SND_REMOVE,
		snd_pos=Vector(0, 0, 0),
	};
else
	print("togglesight: No known pistol mods detected.")
	-- Original pistol.
	weapons.hlvr_weapon_energygun = {
		name="Alyxgun",
		group=1,
		on_state=1,
		off_state=0,
		snd_pos=Vector(0, 2.6875, 2.825),
		snd_on=SND_HOLO_ON,
		snd_off=SND_HOLO_OFF,
		replace="alyxgun",
	};
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

local function identity(x) return x end
local function toggle(x) return not x end

-- Turn on Alyxlib's button tracking
Input.AutoStart = true

-- Find the sight entity, then update its state.
---@param gun CBaseAnimating
---@param info WeaponInfo
---@param state_func fun(old: boolean): boolean
local function UpdateSight(gun, info, state_func)
	-- @type CBaseAnimating
	local child = gun:FirstMoveChild() --[[@as CBaseAnimating]]
	while child do
		if child:GetClassname() == "reflex_sights" then
			-- Found, toggle if required.
			local prev_enabled = Storage.LoadBoolean(gun, CTX_ENABLED, true)
			local enabled = state_func(prev_enabled)
			if enabled ~= prev_enabled then
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

-- Update the held weapon.
---@param state_func fun(old: boolean): boolean
local function UpdateHeldSight(state_func)
	local gun = Player:GetWeapon() --[[@as CBaseAnimating]]
	if gun == nil then
		return
	end
	local info = weapons[gun:GetClassname()]
	if info ~= nil then
		UpdateSight(gun, info, state_func);
	end
end

local function Init()
	Input:TrackButton(DIGITAL_INPUT_TOGGLE_LASER_SIGHT);
	Input:ListenToButton(
		"press", -1, DIGITAL_INPUT_TOGGLE_LASER_SIGHT, 1,
		function() UpdateHeldSight(toggle) end
	);
	-- Look for already-equipped weapons, toggle them in case we loaded from save.
	local hand_pos = Player.PrimaryHand:GetAbsOrigin();
	for info_cls, info in pairs(weapons) do
		local gun = Entities:FindByClassnameNearest(info_cls, hand_pos, 128) --[[@as CBaseAnimating?]]
		if gun ~= nil then
			UpdateSight(gun, info, identity)
		end
	end
	print("TS Toggle Reflex Sights active.")
end
ListenToPlayerEvent("player_activate", Init);

-- Whenever weapons are switched or the hand swaps, update in case they got out of sync.
ListenToPlayerEvent("weapon_switch", function() UpdateHeldSight(identity) end)
ListenToPlayerEvent("primary_hand_changed", function() UpdateHeldSight(identity) end)
