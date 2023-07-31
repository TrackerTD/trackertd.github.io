-- I was to lazy to store actual version (like 1.2) in table
local dub_version = 6

-- In case addon loaded multiple times (when bundled with character addons, for
-- instance)
--
-- On second thought, maybe bundling such addons with characters is a bad idea,
-- if you don't want dependency hell...
--
-- On third thought, loading this lua before all addons that may contain older
-- dub version will surely solve these problems :D
if dub_loaded then
    -- First 2 versions used boolean to indicate that dub is loaded, so
    -- i'll replace it with number so lua don't complain about "attempt to
    -- compare boolean with number"
    --
    -- ... And yes, i know that 'if bool == true' is stupid, but in this
    -- specific case that can be a number, so thats same as checking
    -- 'if type(dub_loaded) == "boolean"'
    if dub_loaded == true then rawset(_G, "dub_loaded", 1) end

    -- Not sure if i/someone else will update this addon that much that version
    -- missmatch would actually lead to problems, but its better to warn about
    -- that than just silently ignore
    if dub_loaded < dub_version then
        error("Older version of KL_CharDub loaded, this may lead to problems")
    end

    return
end

rawset(_G, "dub_loaded", dub_version)

local dub = {}

local SKINSOUNDS = {
    SKSKWIN,
	SKSKLOSE,
	SKSKPAN1,
	SKSKPAN2,
	SKSKATK1,
	SKSKATK2,
	SKSKBST1,
	SKSKBST2,
	SKSKSLOW,
	SKSKHITM,
	SKSKPOWR,
}

local KARTVOICES_NEVER = 0
local KARTVOICES_TASTEFUL = 1
local KARTVOICES_MEME = 2
local kartvoices_value = KARTVOICES_TASTEFUL

local config = "dub.cfg"
local config_loaded = false
local config_tosave = false

local dub_enabled = CV_RegisterVar({
    name = "dub_enabled",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
})

local function freeslotDubSfx(soundname, isgloat)
    local soundnum = _G[soundname] or freeslot(soundname)

    if isgloat then
        sfxinfo[soundnum].flags = sfxinfo[soundnum].flags | SF_X8AWAYSOUND | SF_NOINTERRUPT
    end

    return soundnum
end

local function freeslotDubEntry(entry, isgloat)
    if type(entry) == "string" then
        return freeslotDubSfx(entry, isgloat)
    elseif type(entry) == "number" then
        if isgloat then
            sfxinfo[entry].flags = sfxinfo[entry].flags | SF_X8AWAYSOUND | SF_NOINTERRUPT
        end

        return entry
    else
        local sounds = {}

        for _, soundname in ipairs(entry) do
            table.insert(sounds, freeslotDubSfx(soundname, isgloat))
        end

        return sounds
    end
end

local function pickDubEntry(entry, random)
    if type(entry) == "number" then
        return entry
    elseif #entry > 0 then
        return entry[random % #entry + 1]
    end
end

local function loadConfig()
    if config_loaded or not consoleplayer then return end

    local file = io.open(config, "r")

    -- No config :(
    if not file then
        config_loaded = true
        return
    end

    for line in file:lines() do
        COM_BufInsertText(consoleplayer, line)
    end

    config_loaded = true

    file:close()
end

local function saveConfig()
    if not consoleplayer then return end

    config_tosave = false

    local file = io.open(config, "w")

    if not file then return end

    file:write("dub_enabled "..dub_enabled.string..'\n')

    if consoleplayer.dub_choice ~= nil then
        for skin, choice in pairs(consoleplayer.dub_choice) do
            file:write("dub "..skin.." "..choice..'\n')
        end
    end

    file:close()
end

COM_AddCommand("dub", function(player, skin, choice)
    if player.dub_choice == nil then player.dub_choice = {} end

    if skin == nil then
        CONS_Printf(player, "Usage: \129dub\128 <\130skin\128> [\131dub\128]")
        CONS_Printf(player, "Check \129dub_list\128 for all available dubs")
    elseif choice == nil then
        if dub[skin] == nil then
            CONS_Printf(player, "\134This skin does not have any custom dub")
            return
        end

        local skin_dubs = {"default"}
        for dubname, _ in pairs(dub[skin]) do
            table.insert(skin_dubs, dubname)
        end

        CONS_Printf(player, "available dubs for skin \130"..skin.."\128: \131"..table.concat(skin_dubs, ", "))
    else
        if dub[skin] == nil then
            CONS_Printf(player, "\134This skin does not have any custom dub")
            return
        end

        if choice == "default" then
            player.dub_choice[skin] = nil
            CONS_Printf(player, "Custom dub for skin \130"..skin.." \133disabled")
            config_tosave = config_loaded -- To not cause config to be saved immideately after loading
            return
        end

        if dub[skin][choice] == nil then
            CONS_Printf(player, "Dub \131"..choice.." \133does not exist\128 for skin \130"..skin)
            return
        end

        player.dub_choice[skin] = choice
        CONS_Printf(player, "Set dub \131"..choice.."\128 for skin \130"..skin)
        config_tosave = config_loaded
    end
end)

COM_AddCommand("dub_list", function(player)
    local dubs = {"Skins with custom dubs:"}

    for skin, _ in pairs(dub) do
        local skin_dubs = {}

        for dubname, _ in pairs(dub[skin]) do
            table.insert(skin_dubs, dubname)
        end

        table.insert(dubs, "\130"..skin.."\128: \131"..table.concat(skin_dubs, ", "))
    end

    if #dubs == 1 then
        CONS_Printf(player, "\134There are no dubs yet...")
    else
        CONS_Printf(player, table.concat(dubs, "\n"))
    end
end)

-- Converts integer id for skin sound to string. If argument already is string,
-- it does nothing
local function DUB_GetSoundName(skinsound)
    if type(skinsound) == "string" then return skinsound end

    local NAMES = {
        [SKSKWIN] = "win",
        [SKSKLOSE] = "lose",
        [SKSKPAN1] = "pain",
        [SKSKPAN2] = "pain",
        [SKSKATK1] = "attack",
        [SKSKATK2] = "attack",
        [SKSKBST1] = "boost",
        [SKSKBST2] = "boost",
        [SKSKSLOW] = "overtake",
        [SKSKHITM] = "hitem",
        [SKSKPOWR] = "gloat",
    }

    return NAMES[skinsound] or error("Invalid skin sound id")
end

local defaultdub = {}
local function DUB_GetDefaultDub(skin)
    if defaultdub[skin] == nil then
        defaultdub[skin] = {}

        for _, soundid in ipairs(SKINSOUNDS) do
            local name = DUB_GetSoundName(soundid)

            defaultdub[skin][name] = defaultdub[skin][name] or {}

            table.insert(defaultdub[skin][name], skins[skin].soundsid[soundid])
        end
    end

    return defaultdub[skin]
end

local function DUB_GetSkinSound(player, skinsound)
    local soundname = DUB_GetSoundName(skinsound)

    if player.mo == nil then return end

    -- Used actual RNG here before, replaced with leveltime for less synch
    -- headache
    local random = leveltime

    local pdub = DUB_GetDefaultDub(player.mo.skin)

    local psounds = skins[player.mo.skin].soundsid

    if dub_enabled.value and player.dub_choice ~= nil and player.dub_choice[player.mo.skin] ~= nil then
        pdub = dub[player.mo.skin][player.dub_choice[player.mo.skin]]
    end

    local defsound

    if type(skinsound) == "string" then
        defsound = sfx_none
    else
        defsound = psounds[skinsound]
    end

    return pickDubEntry(pdub[soundname] or defsound, random)
end

local function DUB_GetWinSound(player)
    return DUB_GetSkinSound(player, SKSKWIN)
end

local function DUB_GetLoseSound(player)
    return DUB_GetSkinSound(player, SKSKLOSE)
end

local function DUB_GetBoostSound(player)
    local skinsound = SKSKBST1 + (leveltime % 2)

    return DUB_GetSkinSound(player, skinsound)
end

local function DUB_GetHurtSound(player)
    local skinsound = SKSKPAN1 + (leveltime % 2)

    return DUB_GetSkinSound(player, skinsound)
end

local function DUB_GetAttackSound(player)
    local skinsound = SKSKATK1 + (leveltime % 2)

    return DUB_GetSkinSound(player, skinsound)
end

local function DUB_GetHitEmSound(player)
    return DUB_GetSkinSound(player, SKSKHITM)
end

local function DUB_GetOvertakeSound(player)
    return DUB_GetSkinSound(player, SKSKSLOW)
end

local function DUB_GetGloatSound(player)
    return DUB_GetSkinSound(player, SKSKPOWR)
end

-- Will sound play or not depends on player's voice timer and kartvoices choice
local function DUB_PlaySound(player, sound, tasteful)
    if not player.mo then return end
    if not dub_enabled.value then return end
    if player.dub_sound_played then return end
    if kartvoices_value == KARTVOICES_NEVER then return end
    if not tasteful and kartvoices_value ~= KARTVOICES_MEME then return end

    S_StartSound(player.mo, sound)

    player.dub_sound_played = true
end

local function DUB_TauntVoiceTimers(player)
    if not (player and player.valid) then return end

    player.dub_tauntvoicetimer = 6*TICRATE
    player.dub_voicetimer = 4*TICRATE
end

local function DUB_RegularVoiceTimers(player)
    if not (player and player.valid) then return end

	player.dub_voicetimer = 4*TICRATE

	if player.dub_tauntvoicetimer == nil or player.dub_tauntvoicetimer < 4*TICRATE then
		player.dub_tauntvoicetimer = 4*TICRATE
    end
end

local function DUB_XRegisterDub(skin, dubname, dubvoices)
    if dubname == "default" then
        error("dub name 'default' is reserved")
    end

    skin = skin:lower()

    if dub[skin] == nil then
        dub[skin] = {}
    end

    dub[skin][dubname] = {}

    for name, entry in pairs(dubvoices) do
        dub[skin][dubname][name] = freeslotDubEntry(entry, name == "gloat")
    end
end

local function DUB_RegisterDub(skin, dubname, dubvoices)
    if dubname == "default" then
        error("dub name 'default' is reserved")
    end

    local new_dubvoices = {}

    for soundid, entry in pairs(dubvoices) do
        local name = DUB_GetSoundName(soundid)

        new_dubvoices[name] = new_dubvoices[name] or {}

        table.insert(new_dubvoices[name], entry)
    end

    DUB_XRegisterDub(skin, dubname, new_dubvoices)
end

local function DUB_GetDub(skin, dub_name)
    if dub[skin] == nil then return end

    return dub[skin][dub_name]
end

local function DUB_PlayAttackTaunt(pmo)
    if not pmo.player then return end

    local tasteful = not pmo.player.dub_tauntvoicetimer

    DUB_PlaySound(pmo.player, DUB_GetAttackSound(pmo.player), tasteful)

    if not tasteful then return end

    DUB_TauntVoiceTimers(pmo.player)
end

local function DUB_PlayBoostTaunt(pmo)
    if not pmo.player then return end

    local tasteful = not pmo.player.dub_tauntvoicetimer

    DUB_PlaySound(pmo.player, DUB_GetBoostSound(pmo.player), tasteful)

    if not tasteful then return end

    DUB_TauntVoiceTimers(pmo.player)
end

-- Expose some of functions
rawset(_G, "DUB_GetDefaultDub",     DUB_GetDefaultDub)
rawset(_G, "DUB_GetDub",            DUB_GetDub)
rawset(_G, "DUB_GetSkinSound",      DUB_GetSkinSound)
rawset(_G, "DUB_GetWinSound",       DUB_GetWinSound)
rawset(_G, "DUB_GetLoseSound",      DUB_GetLoseSound)
rawset(_G, "DUB_GetBoostSound",     DUB_GetBoostSound)
rawset(_G, "DUB_GetHurtSound",      DUB_GetHurtSound)
rawset(_G, "DUB_GetAttackSound",    DUB_GetAttackSound)
rawset(_G, "DUB_GetHitEmSound",     DUB_GetHitEmSound)
rawset(_G, "DUB_GetOvertakeSound",  DUB_GetOvertakeSound)
rawset(_G, "DUB_GetGloatSound",     DUB_GetGloatSound)
rawset(_G, "DUB_RegisterDub",       DUB_RegisterDub)
rawset(_G, "DUB_XRegisterDub",      DUB_XRegisterDub)

-- Replace global functions
local K_PlayAttackTaunt_Copy = K_PlayAttackTaunt
rawset(_G, "K_PlayAttackTaunt", function(pmo)
    K_PlayAttackTaunt_Copy(pmo)

    DUB_PlayAttackTaunt(pmo)
end)

local K_PlayBoostTaunt_Copy = K_PlayBoostTaunt
rawset(_G, "K_PlayBoostTaunt", function(pmo)
    K_PlayBoostTaunt_Copy(pmo)

    DUB_PlayBoostTaunt(pmo)
end)

-- Doesn't use P_Random so we can put condition there
local K_PlayPowerGloatSound_Copy = K_PlayPowerGloatSound
rawset(_G, "K_PlayPowerGloatSound", function(pmo)
    if dub_enabled.value then
        DUB_PlaySound(pmo.player, DUB_GetGloatSound(pmo.player), true)
        DUB_RegularVoiceTimers(pmo.player)
    else
        K_PlayPowerGloatSound_Copy(pmo)
    end
end)

-- Doesn't use P_Random so we can put condition there
local K_PlayOvertakeSound_Copy = K_PlayOvertakeSound
rawset(_G, "K_PlayOvertakeSound", function(pmo)
    if dub_enabled.value then
        if leveltime < 17*TICRATE then return end

        local tasteful = not pmo.player.dub_voicetimer

        DUB_PlaySound(pmo.player, DUB_GetOvertakeSound(pmo.player), tasteful)

        if not tasteful then return end

        DUB_RegularVoiceTimers(pmo.player)
    else
        K_PlayOvertakeSound_Copy(pmo)
    end
end)

-- Doesn't use P_Random so we can put condition there
local K_PlayLossSound_Copy = K_PlayLossSound
rawset(_G, "K_PlayLossSound", function(pmo)
    if dub_enabled.value then
        DUB_PlaySound(pmo.player, DUB_GetLoseSound(pmo.player), true)
    else
        K_PlayLossSound_Copy(pmo)
    end
end)

-- Doesn't use P_Random so we can put condition there
local K_PlayHitEmSound_Copy = K_PlayHitEmSound
rawset(_G, "K_PlayHitEmSound", function(pmo)
    if dub_enabled.value then
        pmo.player.dub_stophitemsfx = true
        DUB_PlaySound(pmo.player, DUB_GetHitEmSound(pmo.player), true)
        DUB_RegularVoiceTimers(pmo.player)
    else
        K_PlayHitEmSound_Copy(pmo)
    end
end)

-- Cvars think frame
local saved_dub_enabled = dub_enabled.value
local disabled_kartvoices = false
local cv_kartvoices
addHook("PreThinkFrame", function()
    if cv_kartvoices == nil then
        cv_kartvoices = CV_FindVar("kartvoices")
    end

    if not config_loaded then
        loadConfig()
    end

    if saved_dub_enabled ~= dub_enabled.value then config_tosave = true end

    saved_dub_enabled = dub_enabled.value

    if config_tosave then
        saveConfig()
    end

    if dub_enabled.value and cv_kartvoices.value then
        disabled_kartvoices = true
        kartvoices_value = cv_kartvoices.value
        CV_StealthSet(cv_kartvoices, 0)
    end

    if not dub_enabled.value then
        if disabled_kartvoices then
            disabled_kartvoices = false
            CV_StealthSet(cv_kartvoices, kartvoices_value)
        else
            kartvoices_value = cv_kartvoices.value
        end
    end
end)

-- Set old value for kartvoices. Cursed, but works, kinda
addHook("PostThinkFrame", function()
    if cv_kartvoices ~= nil then
        CV_StealthSet(cv_kartvoices, kartvoices_value)
    end
end)

addHook("MapLoad", function()
    for player in players.iterate do
        player.dub_init = false -- Reset all variables related to dub
    end
end)

-- Actual dub logic
addHook("MobjThinker", function(pmo)
    if not dub_enabled.value then return end

    local player = pmo.player
    local kst = player.kartstuff

    -- Setup player vars
    if not player.dub_init then
        player.dub_voicetimer = 0
        player.dub_tauntvoicetimer = 0
        player.dub_has_poweritem = false
        player.dub_has_sneaker = false
        player.dub_has_attackitem = false
        player.dub_rocketsneakertimer = 0
        player.dub_itemamount = nil
        player.dub_exiting = false
        player.dub_stolen = false
        player.dub_steal = false
        player.dub_position = 0
        player.dub_stopslipsfx = false
        player.dub_stophitemsfx = false
        player.dub_init = true
    end

    if player.dub_voicetimer > 0 then
        player.dub_voicetimer = player.dub_voicetimer - 1
    end

    if player.dub_tauntvoicetimer > 0 then
        player.dub_tauntvoicetimer = player.dub_tauntvoicetimer - 1
    end

    player.dub_sound_played = false -- To prevent multiple sounds playing at same frame

    if kst[k_position] < player.dub_position then
        DUB_PlaySound(player, DUB_GetOvertakeSound(player))
    end

    player.dub_position = kst[k_position]

    -- Win/lose line
    if player.exiting and not player.dub_exiting then
        if K_IsPlayerLosing(player) then
            K_PlayLossSound(pmo)
        else
            DUB_PlaySound(player, DUB_GetWinSound(player), true)
        end

        player.dub_exiting = true
    end

    -- Reaction to item being stolen
    if kst[k_stolentimer] then
        if not player.dub_stolen then
            player.dub_stolen = true

            DUB_PlaySound(player, DUB_GetSkinSound(player, "stolen"), true)
            DUB_RegularVoiceTimers(player)
        end
    else
        player.dub_stolen = false
    end

    -- Stealing item
    if kst[k_stealingtimer] and kst[k_itemamount] then
        if not player.dub_steal then
            player.dub_steal = true

            DUB_PlaySound(player, DUB_GetSkinSound(player, "steal"), true)
            DUB_RegularVoiceTimers(player)
        end
    else
        player.dub_steal = false
    end

    -- Gloat
    if kst[k_itemtype] == KITEM_INVINCIBILITY or kst[k_itemtype] == KITEM_GROW or kst[k_itemtype] == KITEM_SHRINK then
        player.dub_has_poweritem = true

        -- Player has multiple power items, and just have used one
        if player.dub_itemamount ~= nil and player.dub_itemamount > kst[k_itemamount] then
            K_PlayPowerGloatSound(pmo)
        end

        player.dub_itemamount = kst[k_itemamount]
    elseif player.dub_has_poweritem then
        if player.pflags & PF_ATTACKDOWN then
            K_PlayPowerGloatSound(pmo)
        end

        player.dub_has_poweritem = false
        player.dub_itemamount = nil
    end

    -- Using sneaker or pogo spring
    if kst[k_itemtype] == KITEM_SNEAKER or kst[k_itemtype] == KITEM_POGOSPRING then
        player.dub_has_sneaker = true

        -- Player has multiple boost items, and just have used one
        if player.dub_itemamount ~= nil and player.dub_itemamount > kst[k_itemamount] then
            DUB_PlayBoostTaunt(pmo)
        end

        player.dub_itemamount = kst[k_itemamount]
    elseif player.dub_has_sneaker then
        if player.pflags & PF_ATTACKDOWN then
            DUB_PlayBoostTaunt(pmo)
        end

        player.dub_has_sneaker = false
        player.dub_itemamount = nil
    end

    -- Using rocket sneaker
    if kst[k_rocketsneakertimer] then
        -- Rocket sneaker item just been used
        if player.dub_rocketsneakertimer < kst[k_rocketsneakertimer] then
            player.dub_rocketsneakertimer = kst[k_rocketsneakertimer] + 1
            DUB_PlayBoostTaunt(pmo)
        end

        -- Player have used part of rocket sneaker gauge
        if player.dub_rocketsneakertimer ~= kst[k_rocketsneakertimer] + 1 and player.pflags & PF_ATTACKDOWN then
            DUB_PlayBoostTaunt(pmo)
        end

        player.dub_rocketsneakertimer = kst[k_rocketsneakertimer]
    end

    -- Using attack items
    if kst[k_itemtype] == KITEM_ORBINAUT or kst[k_itemtype] == KITEM_BANANA
        or kst[k_itemtype] == KITEM_JAWZ or kst[k_itemtype] == KITEM_BALLHOG
        or kst[k_itemtype] == KITEM_SPB  or kst[k_itemtype] == KITEM_KITCHENSINK
        or kst[k_itemtype] == KITEM_THUNDERSHIELD then
        player.dub_has_attackitem = true

        -- Player has multiple attack items, and just have used one
        if player.dub_itemamount ~= nil and player.dub_itemamount > kst[k_itemamount] and player.pflags & PF_ATTACKDOWN then
            DUB_PlayAttackTaunt(pmo)
        end

        player.dub_itemamount = kst[k_itemamount]
    elseif player.dub_has_attackitem then
        if player.pflags & PF_ATTACKDOWN then
            DUB_PlayAttackTaunt(pmo)
        end

        player.dub_has_attackitem = false
        player.dub_itemamount = nil
    end
end, MT_PLAYER)

-- Remove annoying sounds
addHook("ThinkFrame", function()
    if not dub_enabled.value then return end

    for player in players.iterate do
        if player.dub_stopslipsfx then
            S_StopSoundByID(player.mo, sfx_slip)
            player.dub_stopslipsfx = false
        end

        if player.dub_stophitemsfx then
            S_StopSoundByID(player.mo, sfx_s1c9)
            player.dub_stophitemsfx = false
        end
    end
end)

addHook("PlayerSpin", function(player, source, inflictor)
    if source and (source.type == MT_ORBINAUT or source.type == MT_ORBINAUT_SHIELD or
        source.type == MT_JAWZ or source.type == MT_JAWZ_DUD or
        source.type == MT_JAWZ_SHIELD or source.type == MT_PLAYER) then

        player.dub_stopslipsfx = true
        DUB_PlaySound(player, DUB_GetHurtSound(player), true)
        DUB_RegularVoiceTimers(player)
    end

    if inflictor and inflictor.player and inflictor.player ~= player then
        K_PlayHitEmSound(inflictor)
    end
end)

addHook("PlayerExplode", function(player, _, inflictor)
    player.dub_stopslipsfx = true
    DUB_PlaySound(player, DUB_GetHurtSound(player), true)
    DUB_RegularVoiceTimers(player)

    if inflictor and inflictor.player and inflictor.player ~= player then
        K_PlayHitEmSound(inflictor)
    end
end)

addHook("PlayerSquish", function(player, _, inflictor)
    player.dub_stopslipsfx = true
    DUB_PlaySound(player, DUB_GetHurtSound(player), true)
    DUB_RegularVoiceTimers(player)
end)

addHook("MobjDeath", function(pmo, mo, pmo2)
    if not (mo and mo.type == MT_SINK) then return end

    if pmo2.player then
        DUB_PlaySound(pmo2.player, DUB_GetWinSound(pmo2.player), true)
        DUB_RegularVoiceTimers(player)
    end
end, MT_PLAYER)

-- Being chased by SPB
addHook("MobjThinker", function(mo)
    if mo.extravalue1 == 1 and mo.tracer and mo.tracer.valid and mo.tracer.player then
        if mo.tracer.player ~= mo.dub_chased then
            mo.dub_chased = mo.tracer.player
            DUB_PlaySound(mo.tracer.player, DUB_GetSkinSound(mo.tracer.player, "spb"), true)
            DUB_RegularVoiceTimers(mo.tracer.player)
        end
    end
end, MT_SPB)
