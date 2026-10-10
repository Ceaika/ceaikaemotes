global function CeaikaEmotes_ModelsInit
global function CeaikaEmotes_Models
global function CeaikaEmotes_SupportsEmote

struct
{
    table<asset, asset> models
} file

void function CeaikaEmotes_ModelsInit()
{
    // These copies carry the animations without overriding normal pilot models.
    file.models = {
        [$"models/humans/pilots/pilot_heavy_drex_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_heavy_drex_f.mdl",
        [$"models/humans/pilots/pilot_heavy_drex_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_heavy_drex_m.mdl",
        [$"models/humans/pilots/pilot_heavy_roog_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_heavy_roog_f.mdl",
        [$"models/humans/pilots/pilot_heavy_roog_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_heavy_roog_m.mdl",
        [$"models/humans/pilots/pilot_light_ged_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_light_ged_f.mdl",
        [$"models/humans/pilots/pilot_light_ged_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_light_ged_m.mdl",
        [$"models/humans/pilots/pilot_light_jester_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_light_jester_f.mdl",
        [$"models/humans/pilots/pilot_light_jester_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_light_jester_m.mdl",
        [$"models/humans/pilots/pilot_medium_geist_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_medium_geist_f.mdl",
        [$"models/humans/pilots/pilot_medium_geist_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_medium_geist_m.mdl",
        [$"models/humans/pilots/pilot_medium_reaper_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_medium_reaper_f.mdl",
        [$"models/humans/pilots/pilot_medium_reaper_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_medium_reaper_m.mdl",
        [$"models/humans/pilots/pilot_medium_stalker_f.mdl"] = $"models/ceaikaemotes/pilots/pilot_medium_stalker_f.mdl",
        [$"models/humans/pilots/pilot_medium_stalker_m.mdl"] = $"models/ceaikaemotes/pilots/pilot_medium_stalker_m.mdl",

        [$"models/titans/light/titan_light_raptor.mdl"] = $"models/titans/light/titan_light_raptor.mdl",
        [$"models/titans/light/titan_light_locust.mdl"] = $"models/titans/light/titan_light_locust.mdl",
        [$"models/titans/light/titan_light_northstar_prime.mdl"] = $"models/titans/light/titan_light_northstar_prime.mdl",
        [$"models/titans/light/titan_light_ronin_prime.mdl"] = $"models/titans/light/titan_light_ronin_prime.mdl",
        [$"models/titans/medium/titan_medium_ajax.mdl"] = $"models/titans/medium/titan_medium_ajax.mdl",
        [$"models/titans/medium/titan_medium_wraith.mdl"] = $"models/titans/medium/titan_medium_wraith.mdl",
        [$"models/titans/medium/titan_medium_vanguard.mdl"] = $"models/titans/medium/titan_medium_vanguard.mdl",
        [$"models/titans/medium/titan_medium_ion_prime.mdl"] = $"models/titans/medium/titan_medium_ion_prime.mdl",
        [$"models/titans/medium/titan_medium_tone_prime.mdl"] = $"models/titans/medium/titan_medium_tone_prime.mdl",
        [$"models/titans/heavy/titan_heavy_ogre.mdl"] = $"models/titans/heavy/titan_heavy_ogre.mdl",
        [$"models/titans/heavy/titan_heavy_deadbolt.mdl"] = $"models/titans/heavy/titan_heavy_deadbolt.mdl",
        [$"models/titans/heavy/titan_heavy_scorch_prime.mdl"] = $"models/titans/heavy/titan_heavy_scorch_prime.mdl",
        [$"models/titans/heavy/titan_heavy_legion_prime.mdl"] = $"models/titans/heavy/titan_heavy_legion_prime.mdl"
    }

    // Northstar_Archive's Grapple and Pulse packages share the same two meshes.
    // Check enabled mods once per map, before precaching the selected copies.
    foreach (ModInfo mod in NSGetModsInformation())
    {
        if (!mod.enabled) continue
        switch (mod.name)
        {
            case "CAT.EARS.Tech.Test.Pulse.Blade.Female.Grapple.Replace":
                file.models[$"models/humans/pilots/pilot_medium_geist_f.mdl"] = $"models/ceaikaemotes/pilots/cat_ears_f.mdl"
                break
            case "CAT.EARS.Tech.Test.Pulse.Blade.Male.Grapple.Replace":
                file.models[$"models/humans/pilots/pilot_medium_geist_m.mdl"] = $"models/ceaikaemotes/pilots/cat_ears_m.mdl"
                break
            case "CAT.EARS.Tech.Test.Pulse.Blade.Female":
                file.models[$"models/humans/pilots/pilot_medium_reaper_f.mdl"] = $"models/ceaikaemotes/pilots/cat_ears_f.mdl"
                break
            case "CAT.EARS.Tech.Test.Pulse.Blade.Male":
                file.models[$"models/humans/pilots/pilot_medium_reaper_m.mdl"] = $"models/ceaikaemotes/pilots/cat_ears_m.mdl"
                break
        }
    }
}

table<asset, asset> function CeaikaEmotes_Models()
{
    return file.models
}

// Each supported Titan keeps its own skeleton and all sixteen dance clips.
bool function CeaikaEmotes_SupportsEmote(entity player, string emote)
{
    if(!player.IsTitan()) return true
    return player.GetModelName() in CeaikaEmotes_Models()
}
