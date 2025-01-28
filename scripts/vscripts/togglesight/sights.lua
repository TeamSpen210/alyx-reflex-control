
-- We have 4 sounds - on/off, via button and auto.
-- When automatic it's much quieter.

---@class WeaponSounds
---@field auto_off string
---@field auto_on string
---@field btn_off string
---@field btn_on string

-- Turning on/off the hologram. 
---@type WeaponSounds
local SND_HOLO = {
	auto_off="TSpen.ToggleSight.HoloAutoOff",
	auto_on="TSpen.ToggleSight.HoloAutoOn",
	btn_off="TSpen.ToggleSight.HoloBtnOff",
	btn_on="TSpen.ToggleSight.HoloBtnOn",
};

-- "Detaching" and re-attaching a physical prop.
---@type WeaponSounds
local SND_PROP = {
	auto_off="TSpen.ToggleSight.AttachAutoOff",
	auto_on="TSpen.ToggleSight.AttachAutoOn",
	btn_off="TSpen.ToggleSight.AttachBtnOff",
	btn_on="TSpen.ToggleSight.AttachBtnOn",
}

-- On all reflex_sights entities, where the dot is. Direction is inconsistent.
local ATTACH_REFLEX = "reticule_attach"

local enabled_addons = {};

for addon in Convars:GetStr("default_enabled_addons_list"):gmatch("[^,]+") do
	enabled_addons[addon] = true;
end


-- Definitions for each weapon. 
---@class WeaponInfo
---@field name string Debug name for the weapon.
---@field snd_pos Vector = Offset from child model to play sound from.
---@field sounds WeaponSounds The sounds to use.
---@field auto_range_sqr number Squared radius for auto-swapping.
---@field replace? string If set, override the model using this name.
---@field group? integer The bodygroup index to change, if set.
---@field on_state? integer States to use when turned on/off.
---@field off_state? integer
---@field disable_draw? boolean If set, hide when disabled.
-- Later set:
---@field replace_lhand string? Full model path for left hand.
---@field replace_rhand string? Full model path for right hand.
---@field replaced boolean? If the model has been replaced during this session.
---@field cached_attach integer? Cached reflex attachment index.

---@type table<string, WeaponInfo>
local weapons = {
	hlvr_weapon_rapidfire={
		name="RapidFire",
		-- This bodygroup already exists by default.
		model="holosight",
		group=0,
		on_state=0,
		off_state=1,
		auto_range_sqr=4^2,
		sounds=SND_HOLO,
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
		auto_range_sqr=2^2,
		sounds=SND_PROP,
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
		auto_range_sqr=2^2,
		snd_pos=Vector(0, 2.6875, 2.825),
		sounds=SND_HOLO,
		replace="alyxgun",
	};
end

local CTX_ENABLED = "tspen_toggle_sight_enabled"
local REPLACE_PREFIX = "models/weapons/ts_togglesight/"
local CVAR_AUTO = "tspen_reflex_control_auto"


for _,info in pairs(weapons) do
	if info.replace then
		info.replace_lhand = REPLACE_PREFIX .. info.replace .. "_lhand.vmdl"
		info.replace_rhand = REPLACE_PREFIX .. info.replace .. "_rhand.vmdl"
		GlobalPrecache("model", info.replace_lhand);
		GlobalPrecache("model", info.replace_rhand);
		GlobalPrecache("sound", info.sounds.auto_off)
		GlobalPrecache("sound", info.sounds.auto_on)
		GlobalPrecache("sound", info.sounds.btn_off)
		GlobalPrecache("sound", info.sounds.btn_on)
	end
end

---@param x boolean
local function identity(x) return x end
---@param x boolean
local function toggle(x) return not x end

-- Turn on Alyxlib's button tracking
Input.AutoStart = true

-- Find the sight entity, then update its state.
---@param gun CBaseAnimating
---@param info WeaponInfo
---@param state_func fun(old: boolean, info: WeaponInfo, sights: CBaseAnimating): boolean
local function UpdateSight(gun, info, state_func)
	-- @type CBaseAnimating
	local child = gun:FirstMoveChild() --[[@as CBaseAnimating]]
	while child do
		if child:GetClassname() == "reflex_sights" then
			-- Found, toggle if required.
			local prev_enabled = Storage.LoadBoolean(gun, CTX_ENABLED, true)
			local enabled = state_func(prev_enabled, info, child)
			if enabled ~= prev_enabled then
				Storage.SaveBoolean(gun, CTX_ENABLED, enabled)
				-- local pos = RotatePosition(child:GetAbsOrigin(), child:GetAngles(), info.snd_pos);
				-- print("Snd pos: " .. tostring(pos - gun:GetOrigin()))
				if EasyConvars:GetBool(CVAR_AUTO) then
					gun:EmitSound(vlua.select(enabled, info.sounds.auto_on, info.sounds.auto_off));
				else
					gun:EmitSound(vlua.select(enabled, info.sounds.btn_on, info.sounds.btn_off));
				end
			end
			if info.replace then
				local mdl = child:GetModelName();
				local desired = vlua.select(Player.IsLeftHanded, info.replace_lhand, info.replace_rhand)
				-- After a reload the model gets set to null, we need to always set the first time.
				if mdl ~= desired or not info.replaced then
					--print(string.format("Togglesight: Override model \"%s\" -> \"%s\"", mdl, desired));
					child:SetModel(desired);
					info.replaced = true;
					info.cached_attach = nil; -- Invalidated.
				end
			end
			if info.disable_draw then
				local alpha = vlua.select(enabled, 255, 0)
				--print(string.format("Set sight for %s, alpha=%i", info.name, alpha))
				child:SetRenderAlpha(alpha);
			end
			if info.group ~= nil then
				local state = vlua.select(enabled, info.on_state, info.off_state);
				--print(string.format("Set sight for %s, body %i = %i", info.name, info.group, state));
				child:SetBodygroup(info.group, state)
			end
		end
		child = child:NextMovePeer()
	end
end

-- Update the held weapon.
---@param state_func fun(old: boolean, info: WeaponInfo, sights: CBaseAnimating): boolean
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

-- Calculate whether the eye is close to the sights.
---@param old_state boolean
---@param info WeaponInfo
---@param sights CBaseAnimating
---@returns boolean
local function IsEyeClose(old_state, info, sights)
	if info.cached_attach == nil then
		info.cached_attach = sights:ScriptLookupAttachment(ATTACH_REFLEX);
	end
	-- Simple check, if looking at the front always disable.
	if sights:GetForwardVector():Dot(Player.HMDAvatar:GetForwardVector()) < 0 then
		return false
	end

	-- Distance between eyes, seems to be in cm. 6.285 is about the average IPD.
	local eye_dist = (Convars:GetFloat("r_stereo_eye_separation") or 6.285) / 2.54;
	-- Location of reflex sight back, and local vectors.
	local reflex_pos = sights:GetAttachmentOrigin(info.cached_attach);
	local sight_up = sights:GetUpVector();
	local sight_right = sights:GetRightVector();

	-- Offset from player eye center to reflex
	local eye_off = Player:EyePosition() - reflex_pos;
	-- Local camera right.
	local player_right = Player.HMDAvatar:GetRightVector();
	-- Left/right eye offset
	local eye_left = eye_off + (player_right * -eye_dist);
	local eye_right = eye_off + (player_right * eye_dist);

	-- Finally, calc 2D distance in sight plane = check if eye is within cylinder
	-- extending out of the sights.
	local dist_left = eye_left:Dot(sight_up)^2 + eye_left:Dot(sight_right)^2;
	local dist_right = eye_right:Dot(sight_up)^2 + eye_right:Dot(sight_right)^2;
	-- Add some hysteresis - if in range, need to pull further out to detach.
	local range = info.auto_range_sqr;
	if old_state then
		range = range + 3*3;
	end
	return dist_left < range or dist_right < range;
end

local EVT_BUTTON_CTX = "tspen_toggle_sight";

local function AutoThink()
	if not EasyConvars:GetBool(CVAR_AUTO) then
		return; -- Non-auto, stop thinking.
	end
	-- Automatically toggle.
	if not Player:HasWeaponEquipped() then
		return 0.25; -- Wait for a weapon.
	end
	UpdateHeldSight(IsEyeClose);
	return 0.05;
end

local function SetupCallbacks(auto)
	-- Avoid double-registering.
	Input:StopListeningByContext(EVT_BUTTON_CTX);

	if auto then
		-- Auto mode.
		Player:SetContextThink("TSpen_ToggleSight_AutoThink", AutoThink, 0.0);
	else
		-- Button mode.
		Input:ListenToButton(
			"press", -1, DIGITAL_INPUT_TOGGLE_LASER_SIGHT, 1,
			function() UpdateHeldSight(toggle) end,
			EVT_BUTTON_CTX
		);
	end
end

EasyConvars:RegisterToggle(
	CVAR_AUTO, true,
	"If set the sight will enable automatically when aligned with the eye. " ..
	"Otherwise, the Toggle Laser Sight button will be used.",
	nil, function(value)
		SetupCallbacks(truthy(value))
	end
);
EasyConvars:SetPersistent(CVAR_AUTO, true);

local function Init()
	Input:TrackButton(DIGITAL_INPUT_TOGGLE_LASER_SIGHT);
	SetupCallbacks(EasyConvars:GetBool(CVAR_AUTO));
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
ListenToPlayerEvent("vr_player_ready", Init);

-- Whenever weapons are switched or the hand swaps, update in case they got out of sync.
ListenToPlayerEvent("weapon_switch", function() UpdateHeldSight(identity) end)
ListenToPlayerEvent("primary_hand_changed", function() UpdateHeldSight(identity) end)
