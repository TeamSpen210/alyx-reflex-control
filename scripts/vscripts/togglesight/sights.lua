require "alyxlib.helpers.easyconvars"
require "alyxlib.controls.input"
require "alyxlib.extensions.entity"
require "alyxlib.extensions.entities"
require "alyxlib.globals"

local version = "v1.0.0"

local ADDON_ID = RegisterAlyxLibAddon("Reflex Control", version, "???", "ts_togglesight", "v2.0.0")
local MENU_ID = "ts_togglesight"
local CLS_PISTOL = "hlvr_weapon_energygun"
local CLS_SMG = "hlvr_weapon_rapidfire"

-- For testing both sights:
-- hlvr_setall 31 48 258 100 10 30 1 0 10 30 2 0


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
local SND_ATTACH = {
	auto_off="TSpen.ToggleSight.AttachAutoOff",
	auto_on="TSpen.ToggleSight.AttachAutoOn",
	btn_off="TSpen.ToggleSight.AttachBtnOff",
	btn_on="TSpen.ToggleSight.AttachBtnOn",
}

-- Flipping down a part while turning on/off the hologram.
---@type WeaponSounds
local SND_FLIP = {
	auto_off="TSpen.ToggleSight.FlipAutoOff",
	auto_on="TSpen.ToggleSight.FlipAutoOn",
	btn_off="TSpen.ToggleSight.FlipBtnOff",
	btn_on="TSpen.ToggleSight.FlipBtnOn",
}

-- On default and most modded reflex_sights entities, where the screen is. 
-- Direction is inconsistent, many modded sights omit. All our replacements have
-- it though.
local ATTACH_REFLEX = "reticule_attach"

local CTX_ENABLED = "tspen_reflex_control_enabled" -- Think function context
-- Context on guns, whether offhand is holding the gun.
local CTX_IS_HELD = "tspen_reflex_control_held"
local EVT_BUTTON_CTX = "tspen_reflex_control" -- Context for Alyxlib buttons
--- Folder replacement models are found in.
local REPLACE_PREFIX = "models/weapons/ts_togglesight/"
local CVAR_MODE = "tspen_reflex_control_mode"
local CVAR_AUTO_RANGE = {
	[CLS_PISTOL]="tspen_reflex_control_pistol_auto_range",
	[CLS_SMG]="tspen_reflex_control_smg_auto_range",
}
local CVAR_DISABLE = {
	[CLS_PISTOL]="tspen_reflex_control_disable_pistol",
	[CLS_SMG]="tspen_reflex_control_disable_smg",
}
local CTRL_PISTOL_AUTO_RANGE = "ts_togglesight_pistol_auto_range";
local CTRL_SMG_AUTO_RANGE = "ts_togglesight_smg_auto_range";
local DEBUG = false;
-- So we know what to swap back to 
local ORIG_MODELS = {
	[CLS_PISTOL]="models/weapons/vr_alyxgun/vr_alyxgun_attach_shroud",
	[CLS_SMG]="models/weapons/vr_ipistol/ipistol_holosight",
}

-- Definitions for each weapon. 
---@class WeaponInfo
---@field name string Debug name for the weapon.
---@field snd_pos Vector = Offset from child model to play sound from.
---@field sounds WeaponSounds The sounds to use.
---@field auto_range number Radius for auto-swapping.
---@field replace? string If set, auto-define replace_lhand/rhand.
---@field replace_lhand? string If set, full model path to replace for this hand.
---@field replace_rhand? string If set, full model path to replace for this hand.
---@field group? integer The bodygroup index to change, if set.
---@field on_state? integer States to use when turned on/off.
---@field off_state? integer
---@field disable_draw? boolean If set, hide when disabled.
---@field sight_pos_lhand? Vector The offset to the reflex sights, for auto mode. 
---       If unset, use the `reticule_attach` attachment point to locate.
---@field sight_pos_rhand? Vector The offset to the reflex sights, for auto mode. 
---       If unset, use the `reticule_attach` attachment point to locate.
-- Later set:
---@field replaced boolean? If the model has been replaced during this session.
---@field cls? string Classname for weapon.
---@field entity? CBaseAnimating? The entity for the weapon.
---@field errors? string[] Errors that occurred during parsing.

---@type table<string, WeaponInfo>
local weapons = {
	-- Doesn't seem to be any SMG mods, we can unconditionally do this one.
	[CLS_SMG]={
		name="RapidFire",
		-- This bodygroup already exists by default.
		model="holosight",
		group=0,
		on_state=0,
		off_state=1,
		auto_range=2.5,
		sounds=SND_HOLO,
		snd_pos=Vector(0, -1.0, 4.0),
	}
};

---@alias StateFunc fun(old: boolean, gun: CBaseAnimating, sights: CBaseAnimating, info: WeaponInfo): boolean

-- Name + sight offsets, when inheriting.
---@class SightInfo
---@field name string Debug name for the weapon.
---@field pos_lhand? Vector
---@field pos_rhand? Vector

-- Wrap so we can discard all this data once evaulated. Mods can't change
-- within any given session.
(function ()

-- Pistols which have a physical sight with the view inside it.
-- To toggle those would logically need to be added/removed.
---@type table<string, SightInfo>
local phys_sight = {
	["2971436118"] = {name="Desert Eagle"},
	["2804426219"] = {name="Apex Legends Pistol"},
	["2503412081"] = {
		name="OTS-14 Groza",
		pos_lhand=Vector(0.4, 0, 8.35),
		pos_rhand=Vector(0.4, 0, 8.35),
	},
	["2386620896"] = {
		name="Fallout 4 Pistol",
		pos_lhand=Vector(-0.7, -0.03, 4.35),
		pos_rhand=Vector(-0.7, 0.03, 4.35),
	},
	["2281728283"] = {
		name="COD 50 GS",
		pos_lhand=Vector(5.8, 0, 3.8),
		pos_rhand=Vector(5.8, 0, 3.8),
	},
	["2406708838"] = {
		name="DL-44 Blaster",
		pos_lhand=Vector(-5.4, 14.5, 2.3),
		pos_rhand=Vector(-5.4, -14.5, 2.3),
	},
};

-- Pistols that don't have their own attachments, just use the default sight model.
-- No custom sight offsets necessary, the default model has the attachment.
local default_sight = {
	["2778816428"] = "Gunman Pistol",
	["2595135995"] = "Cyberpunk liberty",
	["2290585929"] = "CSGO Five-SeveN",
	["2282845209"] = "Goldeneye PP7",
	["2263486326"] = "Boneworks M1911",
	["2258990046"] = "Silenced Pistol",
	["2248623741"] = "AJM-9",
	["2243234414"] = "MMod Pistol",
}

-- Sight is composed only of the holo part, so we can disable-draw to hide.
---@type table<string, SightInfo>
local invis_sight = {
	["2352925224"] = {
		name="Deus Ex HR Zenith",
		pos_lhand=Vector(5, 0, 4),
		pos_rhand=Vector(5, 0, 4),
	},
	["2291028898"] = {name="Doom EMG Pistol"},
	 -- Default model, with frame materials set invisible.
	["2251436253"] = {name="TF2 Pistol"},
}

-- Config for standard Alyxgun.
--- @type WeaponInfo
local standard_pistol = {
	name="Alyx Gun",
	group=1,
	on_state=1,
	off_state=0,
	auto_range=2,
	snd_pos=Vector(0, 2.6875, 2.825),
	sounds=SND_HOLO,
	replace="alyxgun",
};

for addon in Convars:GetStr("default_enabled_addons_list"):gmatch("[^,]+") do
	if addon == "2482808860" then
		print("togglesight: Shooter Pistol mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="Shooter Pistol",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(0, 2.6875, 4.0),
			sounds=SND_HOLO,
			replace="shooterpistol",
		};
		return;
	end

	if addon == "2122819116" then
		print("togglesight: Luger P08 mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="Luger P08",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(4.7, 0, 4.0),
			sounds=SND_ATTACH,
			-- Both are identical.
			replace_lhand=REPLACE_PREFIX .. "luger_ambi.vmdl",
			replace_rhand=REPLACE_PREFIX .. "luger_ambi.vmdl",
		};
		return;
	end

	if addon == "2353427612" then
		print("togglesight: Modern Warfare Renetti mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="Modern Warfare Renetti",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=1.0,
			snd_pos=Vector(3.55, 0.0, 3.6),
			sounds=SND_ATTACH,
			replace="cod_renetti",
		};
		return;
	end

	-- These two are both made by MCMessenger, and share a sight.
	if addon == "2126368719" then
		print("togglesight: Halo M6C mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="Halo M6C",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(4.8, 0, 4.0),
			sounds=SND_FLIP,
			replace="mcmessenger",
		};
		return;
	end
	if addon == "2168778468" then
		print("togglesight: Walther PPK mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="Walther PPK",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(4.8, 0, 4.0),
			sounds=SND_FLIP,
			replace="mcmessenger"
		};
		return;
	end

	if addon == "2257869330" then
		print("togglesight: SoggyMicrowaveNugget's USP Match mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="USP Match",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=1.5,
			snd_pos=Vector(4.8, 0, 4.0),
			sounds=SND_ATTACH,
			replace="soggy_usp"
		};
		return;
	end

	if addon == "2260861413" then
		print("togglesight: Anticitizen USP Match mod detected, toggling sights.")
		weapons[CLS_PISTOL] = {
			name="USP Match",
			group=1,
			on_state=1,
			off_state=0,
			auto_range=2,
			snd_pos=Vector(3, 0, 3),
			sounds=SND_HOLO,
			replace="anticitizen_usp",
		};
		return;
	end

	if default_sight[addon] ~= nil then
		-- Just uses the regular one, copy the config.
		print("togglesight: " .. default_sight[addon] .. " detected, uses standard sights.")
		standard_pistol.name = default_sight[addon];
		weapons[CLS_PISTOL] = standard_pistol;
		return;
	end

	local sight = phys_sight[addon]
	if sight ~= nil then
		-- It's not disableable, it'll be "removed" when not used.
		print("togglesight: " .. sight.name .. " detected, hiding/showing physical sight.")
		weapons[CLS_PISTOL] = {
			name=sight.name,
			disable_draw=true,
			auto_range=2,
			sounds=SND_ATTACH,
			sight_pos_lhand=sight.pos_lhand,
			sight_pos_rhand=sight.pos_rhand,
			snd_pos=Vector(0, 0, 0),
		};
		return;
	end

	sight = invis_sight[addon]
	if sight ~= nil then
		print("togglesight: " .. sight.name .. " detected, hiding/showing holo sight.")
		weapons[CLS_PISTOL] = {
			name=sight.name,
			disable_draw=true,
			auto_range=2,
			sounds=SND_HOLO,
			sight_pos_lhand=sight.pos_lhand,
			sight_pos_rhand=sight.pos_rhand,
			snd_pos=Vector(0, 0, 0),
		};
		return;
	end
end
print("togglesight: No known pistol mods detected.")
weapons[CLS_PISTOL] = standard_pistol;

end)()


for cls, info in pairs(weapons) do
	-- Allow specifying replace lhand/rhand standalone, for ambidexterous etc
	-- sights.
	info.cls = cls;
	info.errors = {};
	if info.replace or info.replace_lhand or info.replace_rhand then
		if not info.replace_lhand then
			info.replace_lhand = REPLACE_PREFIX .. info.replace .. "_lhand.vmdl"
		end
		if not info.replace_rhand then
			info.replace_rhand = REPLACE_PREFIX .. info.replace .. "_rhand.vmdl"
		end
		GlobalPrecache("model", info.replace_lhand);
		GlobalPrecache("model", info.replace_rhand);
		GlobalPrecache("sound", info.sounds.auto_off)
		GlobalPrecache("sound", info.sounds.auto_on)
		GlobalPrecache("sound", info.sounds.btn_off)
		GlobalPrecache("sound", info.sounds.btn_on)
	end
end

--- Calculate the distance between the eyes.
local function EyeDist()
	-- Distance between eyes, seems to be in cm. 6.285 is about the average IPD.
	return (Convars:GetFloat("r_stereo_eye_separation") or 6.285) / 2.54;
end

RegisterAlyxLibDiagnostic(ADDON_ID, function ()
	local diag = {"Running"};
	local modes = {
		[0] = "Auto",
		[1] = "Manual",
	}
	local mode_int = EasyConvars:GetInt(CVAR_MODE);
	table.insert(diag, "Mode: " .. (modes[mode_int] or ("Invalid = %i"):format(mode_int)));
	table.insert(diag, ("Eye Distance (Hammer Units): %f"):format(EyeDist()))
	for cls, weapon in pairs(weapons) do
		table.insert(diag, ("Registered weapon for %s = %s:"):format(cls, weapon.name))
		if weapon.replace_lhand or weapon.replace_rhand then
			table.insert(diag, "- Left-hand model: " .. (weapon.replace_lhand or "N/A"))
			table.insert(diag, "- Right-hand model: " .. (weapon.replace_rhand or "N/A"))
			if not weapon.replaced then
				table.insert(diag, "- Not yet overridden.")
			end
		end
		table.insert(diag, "- Left-hand sights offset: " .. (weapon.sight_pos_lhand or "Not calculated"))
		table.insert(diag, "- Right-hand sights offset: " .. (weapon.sight_pos_rhand or "Not calculated"))
		if weapon.disable_draw then
			table.insert(diag, "- Disables draw to hide.")
		end
		table.insert(diag, ("- Auto range: %i"):format(weapon.auto_range))
		if weapon.group then
			table.insert(diag, ("- Bodygroups: group %i, on=%q, off=%q"):format(weapon.group, weapon.on_state, weapon.off_state))
		end
		if weapon.errors and #weapon.errors > 0 then
			table.insert(diag, ("- Errors: %s"):format(table.concat(weapon.errors, ",")));
		end
	end

    return true, table.concat(diag, "\n")
end)

--- Default state function, apply held-changes, or leave unchanged.
---@param prev boolean
---@param gun CBaseAnimating
---@param sight CBaseAnimating
---@param info WeaponInfo
local function StateUnchanged(prev, gun, sight, info) 
	if EasyConvars:GetInt(CVAR_MODE) == 2 then
		return Storage.LoadBoolean(gun, CTX_IS_HELD, prev)
	else
		return prev;
	end
end

--- Just toggle the gun.
---@param x boolean
local function StateToggle(x) return not x end

-- Update the state of a sight entity.
---@param gun CBaseAnimating
---@param sight CBaseAnimating
---@param info WeaponInfo
---@param state_func StateFunc
local function UpdateSight(gun, sight, info, state_func)
	if EasyConvars:GetBool(CVAR_DISABLE[info.cls]) then
		-- Disabled, revert changes.
		if info.disable_draw then
			sight:SetRenderingEnabled(true);
		end
		if info.group ~= nil then
			sight:SetBodygroup(info.group, info.on_state);
		end
		local orig = ORIG_MODELS[info.cls] .. vlua.select(Player.IsLeftHanded, "_lhand.mdl", ".mdl");
		if sight:GetModelName() ~= orig or info.replaced then
			local prev_skin = sight:GetMaterialGroupHash();
			sight:SetModel(orig);
			sight:SetMaterialGroupHash(prev_skin);
			info.replaced = false;
		end
	else
		-- Toggle the sight if ncessary.
		local prev_enabled = Storage.LoadBoolean(gun, CTX_ENABLED, true)
		local enabled = state_func(prev_enabled, gun, sight, info)
		if enabled ~= prev_enabled then
			Storage.SaveBoolean(gun, CTX_ENABLED, enabled)
			-- local pos = RotatePosition(sight:GetAbsOrigin(), sight:GetAngles(), info.snd_pos);
			-- print("Snd pos: " .. tostring(pos - gun:GetOrigin()))
			-- In auto mode, reduce volume since it's going to swap occasionally.
			if EasyConvars:GetInt(CVAR_MODE) == 0 then
				gun:EmitSound(vlua.select(enabled, info.sounds.auto_on, info.sounds.auto_off));
			else
				gun:EmitSound(vlua.select(enabled, info.sounds.btn_on, info.sounds.btn_off));
			end
		end
		local replace = vlua.select(Player.IsLeftHanded, info.replace_lhand, info.replace_rhand);
		if replace then
			local mdl = sight:GetModelName();
			-- After a reload the model ends up null/invisible, we need to always set the first time.
			if mdl ~= replace or not info.replaced then
				print(string.format("Togglesight: Override model \"%s\" -> \"%s\"", mdl, replace));
				-- Save/restore the skin, for the Shooter Pistol. Harmless otherwise.
				local prev_skin = sight:GetMaterialGroupHash();
				sight:SetModel(replace);
				sight:SetMaterialGroupHash(prev_skin);
				info.replaced = true;
			end
		end
		if info.disable_draw then
			--print(string.format("Set sight for %s, alpha=%i", info.name, alpha))
			sight:SetRenderingEnabled(enabled);
		end
		if info.group ~= nil then
			local state = vlua.select(enabled, info.on_state, info.off_state);
			--print(string.format("Set sight for %s, body %i = %i", info.name, info.group, state));
			if state ~= nil then
				sight:SetBodygroup(info.group, state)
			end
		end
	end
end

-- Find a sight, then update it.
---@param gun CBaseAnimating
---@param info WeaponInfo
---@param state_func StateFunc
local function FindAndUpdateSight(gun, info, state_func)
	local child = gun:FirstMoveChild()
	while child do
		if child:GetClassname() == "reflex_sights" then
			local sight = child --[[@as CBaseAnimating]]
			UpdateSight(gun, sight, info, state_func)
		end
		child = child:NextMovePeer()
	end
end

-- Update the held weapon.
---@param state_func StateFunc
local function UpdateHeldSight(state_func)
	local gun = Player:GetWeapon() --[[@as CBaseAnimating]]
	if gun == nil then
		return
	end
	local info = weapons[gun:GetClassname()]
	if info ~= nil then
		-- Reset, in case it was replaced etc.
		info.entity = gun;
		FindAndUpdateSight(gun, info, state_func);
	end
end

-- Update disabled state on the held weapon, if it matches.
---@param cls string the weapon that changed.
local function UpdateDisabled(cls)
	local gun = Player:GetWeapon() --[[@as CBaseAnimating]]
	if gun == nil or gun:GetClassname() ~= cls then
		return
	end
	local info = weapons[gun:GetClassname()]
	if info ~= nil then
		info.entity = gun;
		FindAndUpdateSight(gun, info, StateUnchanged);
	end
end

-- Calculate whether the eye is close to the sights.
---@param old_state boolean
---@param gun CBaseAnimating
---@param sights CBaseAnimating
---@param info WeaponInfo
---@returns boolean
---@diagnostic disable-next-line: unused-local
local function IsEyeClose(old_state, gun, sights, info)
	-- Location of the reflex sight screen, in world.
	local reflex_pos;
	local reflex_off = vlua.select(Player.IsLeftHanded, info.sight_pos_lhand, info.sight_pos_rhand);
	if reflex_off == nil then
		-- Try and grab from the attachment point.
		local attach_ind = sights:ScriptLookupAttachment(ATTACH_REFLEX);
		reflex_pos = sights:GetAttachmentOrigin(attach_ind);
		reflex_off = sights:TransformPointWorldToEntity(reflex_pos);
		if reflex_off:LengthSquared() < 0.1 then
			-- It's right at the origin, probably not valid.
			print("togglesight: ERROR, no sight position for gun " .. info.name .. "!");
			info.errors[#info.errors+1] = "No sight position!";
			-- Roughly where most sights are.
			reflex_off = Vector(4, 0, 4);
			reflex_pos = sights:TransformPointEntityToWorld(reflex_off);
		end
		if Player.IsLeftHanded then
			info.sight_pos_lhand = reflex_off;
		else
			info.sight_pos_rhand = reflex_off;
		end
		print("Offset for gun " .. info.name .. " = " .. tostring(reflex_off));
	else
		reflex_pos = sights:TransformPointEntityToWorld(reflex_off);
	end
	-- Simple check, if looking backwards at the gun, always disable.
	if sights:GetForwardVector():Dot(Player.HMDAvatar:GetForwardVector()) < 0 then
		return false
	end

	-- Offset from player eye center to reflex
	local eye_off = Player:EyePosition() - reflex_pos;
	-- Local camera right.
	local player_right = Player.HMDAvatar:GetRightVector();
	-- Left/right eye offset
	local eye_dist = EyeDist();
	local eye_left = eye_off + (player_right * -eye_dist);
	local eye_right = eye_off + (player_right * eye_dist);

	-- Local axes.
	local sight_up = sights:GetUpVector();
	local sight_right = sights:GetRightVector();
	-- Finally, calc 2D distance in sight plane = check if eye is within cylinder
	-- extending out of the sights.
	local dist_left = eye_left:Dot(sight_up)^2 + eye_left:Dot(sight_right)^2;
	local dist_right = eye_right:Dot(sight_up)^2 + eye_right:Dot(sight_right)^2;

	-- Increase by the eye distance, to get a cone.
	local range = EasyConvars:GetFloat(CVAR_AUTO_RANGE[info.cls]);
	if range == nil then
		range = info.auto_range;
	end
	if old_state then
		-- Add some hysteresis - if in range, need to pull further out to detach.
		range = range + 2;
	end

	if DEBUG then
		local sight_back = reflex_pos + sights:GetForwardVector() * -32.0;
		DebugDrawSphere(reflex_pos, Vector(255, 0, 255), 32, range, false, 0.1);
		-- Aligned edges to show the cylinder.
		DebugDrawLine(reflex_pos + sight_up * range, sight_back + sight_up * range, 255, 255, 0, false, 0.1);
		DebugDrawLine(reflex_pos - sight_up * range, sight_back - sight_up * range, 255, 255, 0, false, 0.1);
		DebugDrawLine(reflex_pos + sight_right * range, sight_back + sight_right * range, 255, 255, 0, false, 0.1);
		DebugDrawLine(reflex_pos - sight_right * range, sight_back - sight_right * range, 255, 255, 0, false, 0.1);
	end
	range = range * range;
	return dist_left < range or dist_right < range;
end

--- Record whenever a two-hand grab occurs, upate the sight if necessary.
local function TwoHandGrab(cls, grabbed)
	local gun = Player:GetWeapon();
	-- Msg(("Grab %s = %s"):format(cls, tostring(grabbed)))
	if gun ~= nil and gun:GetClassname() == cls then
		Storage.SaveBoolean(gun, CTX_IS_HELD, grabbed);
		if EasyConvars:GetInt(CVAR_MODE) == 2 then
			UpdateHeldSight(StateUnchanged)
		end
	else
		-- Gun is not yet fully equipped. Weapon switch event will then apply
		-- this change.
		local info = weapons[cls];
		if info ~= nil and info.entity ~= nil then
			Storage.SaveBoolean(info.entity, CTX_IS_HELD, grabbed);
			FindAndUpdateSight(info.entity, info, function() return grabbed end);
		end
	end
end

local function AutoThink()
	-- Automatically toggle.
	if Player:HasWeaponEquipped() then
		UpdateHeldSight(IsEyeClose);
		return 0.05;
	else
		return 0.25; -- Wait for a weapon.
	end
end

-- When the mode changes, configure the correct callbacks.
--- @param mode 0|1|2
local function ModeChanged(mode)
	-- Avoid double-registering.
	Input:StopListeningByContext(EVT_BUTTON_CTX);

	Msg(("ModeChange: type=%s, value=%s"):format(type(mode), tostring(mode)))

	if mode == 0 then -- Auto mode.
		Player:SetContextThink("TSpen_ToggleSight_AutoThink", AutoThink, 0.0);
	elseif mode == 1 then -- Button mode.
		Player:SetContextThink("TSpen_ToggleSight_AutoThink", nil, 0.0);
		Input:ListenToButton(
			"press", -1, DIGITAL_INPUT_TOGGLE_LASER_SIGHT, 1,
			function() UpdateHeldSight(StateToggle) end,
			EVT_BUTTON_CTX
		);
	elseif mode == 2 then -- Offhand mode
		Player:SetContextThink("TSpen_ToggleSight_AutoThink", nil, 0.0);
		-- Refresh, this checks the state.
		UpdateHeldSight(StateUnchanged)
	else
		Warning("Invalid Reflex Control mode " .. mode .. "!");
		EasyConvars:SetInt(CVAR_MODE, 0);
	end
end

EasyConvars:RegisterConvar(
	CVAR_MODE, 0,
	"Sets the behaviour. 0: The sight will enable automatically when aligned with the eye. " ..
	"1: Use the Toggle Laser Sight button. " .. "2: Enable when gripped with the offhand.",
	nil, function(value)
		ModeChanged(tonumber(value) or 0)
	end
);
EasyConvars:SetPersistent(CVAR_MODE, true);
EasyConvars:RegisterConvar(CVAR_AUTO_RANGE[CLS_PISTOL], weapons[CLS_PISTOL].auto_range, "Determines how close you need to be to trigger the pistol's sight.")
EasyConvars:RegisterConvar(CVAR_AUTO_RANGE[CLS_SMG], weapons[CLS_SMG].auto_range, "Determines how close you need to be to trigger the SMG's sight.")
EasyConvars:RegisterToggle(CVAR_DISABLE[CLS_PISTOL], false, "Disable modifying the pistol.", nil, function() UpdateDisabled(CLS_PISTOL) end)
EasyConvars:RegisterToggle(CVAR_DISABLE[CLS_SMG], false, "Disable modifying the SMG.", nil, function() UpdateDisabled(CLS_SMG) end)

local function Init()
	ModeChanged(EasyConvars:GetInt(CVAR_MODE) or 0);
	-- Look for already-equipped weapons, toggle them in case we loaded from save.
	local hand_pos = Player.PrimaryHand:GetAbsOrigin();
	for info_cls, info in pairs(weapons) do
		local gun = Entities:FindByClassnameNearest(info_cls, hand_pos, 128) --[[@as CBaseAnimating?]]
		if gun ~= nil then
			FindAndUpdateSight(gun, info, StateUnchanged)
		end
	end

	Player:GetPublicScriptScope()["ToggleSight"] = function()
		FireGameEvent("player_pistol_toggle_lasersight", {userid=Player:entindex()});
	end
	print("TS Toggle Reflex Sights active.")
end
ListenToPlayerEvent("vr_player_ready", Init);

-- Whenever weapons are switched or the hand swaps, update in case they got out of sync.
ListenToPlayerEvent("weapon_switch", function()	UpdateHeldSight(StateUnchanged) end)
ListenToPlayerEvent("primary_hand_changed", function() UpdateHeldSight(StateUnchanged) end)

-- Always listen, in case the player swaps mode while holding (console command?)
ListenToGameEvent("two_hand_pistol_grab_start", function() TwoHandGrab(CLS_PISTOL, true) end, weapons);
ListenToGameEvent("two_hand_pistol_grab_end", function() TwoHandGrab(CLS_PISTOL, false) end, weapons);
ListenToGameEvent("two_hand_rapidfire_grab_start", function() TwoHandGrab(CLS_SMG, true) end, weapons);
ListenToGameEvent("two_hand_rapidfire_grab_end", function() TwoHandGrab(CLS_SMG, false) end, weapons);


local function makeMenu()
	DebugMenu:AddCategory(MENU_ID, "Reflex Control")

	-- TODO: Enable/disable menu options?
	DebugMenu:AddCycle(MENU_ID, CVAR_MODE, {
		{value=0, text="Toggle Automatically"},
		{value=1, text="Use Toggle Laser Sights button"},
		{value=2, text="Enable from Offhand"},
	}, CVAR_MODE)
	DebugMenu:AddToggle(MENU_ID, "tspen_reflex_control_debug", "Visualise Range", function(value) DEBUG = value end, false)

	DebugMenu:AddSeparator(MENU_ID, "tspen_reflex_control_pistol", "Pistol (" .. weapons[CLS_PISTOL].name .. ")")
	DebugMenu:AddToggle(MENU_ID, "tspen_reflex_control_pistol_disable", "Disable Changes", CVAR_DISABLE[CLS_PISTOL])
	DebugMenu:AddSlider(MENU_ID, CTRL_PISTOL_AUTO_RANGE, "Auto Range", 0.1, 10, false, CVAR_AUTO_RANGE[CLS_PISTOL], 1, 0.1, nil)

	DebugMenu:AddSeparator(MENU_ID, "tspen_reflex_control_smg", "SMG (RapidFire)")
	DebugMenu:AddToggle(MENU_ID, "tspen_reflex_control_smg_disable", "Disable Changes", CVAR_DISABLE[CLS_SMG])
	DebugMenu:AddSlider(MENU_ID, CTRL_SMG_AUTO_RANGE, "Auto Range", 0.1, 10, false, CVAR_AUTO_RANGE[CLS_SMG], 1, 0.1, nil)

end

makeMenu()
