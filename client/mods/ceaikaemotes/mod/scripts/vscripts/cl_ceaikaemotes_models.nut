global function CeaikaEmotes_SupportsEmote
global function CeaikaEmotes_Models
global function CeaikaEmotes_TitanRig
global function CeaikaEmotes_DancerOrigin

// both tables get asked every frame per dancer, so build them once
struct
{
    table<asset, asset> models
    table<asset, string> rigs
    table<asset, float> drops
} file

// the models a dancer can be. the mod overrides every one of these to include
// the emote clips, so the dancer just uses the player's own model
table<asset, asset> function CeaikaEmotes_Models()
{
    if(file.models.len() > 0) return file.models
    array<asset> pilots = [
        $"models/humans/pilots/pilot_heavy_drex_f.mdl",
        $"models/humans/pilots/pilot_heavy_drex_m.mdl",
        $"models/humans/pilots/pilot_heavy_roog_f.mdl",
        $"models/humans/pilots/pilot_heavy_roog_m.mdl",
        $"models/humans/pilots/pilot_light_ged_f.mdl",
        $"models/humans/pilots/pilot_light_ged_m.mdl",
        $"models/humans/pilots/pilot_light_jester_f.mdl",
        $"models/humans/pilots/pilot_light_jester_m.mdl",
        $"models/humans/pilots/pilot_medium_geist_f.mdl",
        $"models/humans/pilots/pilot_medium_geist_m.mdl",
        $"models/humans/pilots/pilot_medium_reaper_f.mdl",
        $"models/humans/pilots/pilot_medium_reaper_m.mdl",
        $"models/humans/pilots/pilot_medium_stalker_f.mdl",
        $"models/humans/pilots/pilot_medium_stalker_m.mdl"
    ]
    foreach(asset model in pilots)
        file.models[model] <- model
    foreach(asset model, string rig in CeaikaEmotes_TitanRigs())
        file.models[model] <- model
    return file.models
}

// which titan this is in build-titans terms. props built with build_prop.py
// --titans have a "<sequence>_<rig>" clip for each (the non chassis ones just
// reuse their chassis clip's frames, share_titan_clips.py)
string function CeaikaEmotes_TitanRig(asset model)
{
    table<asset, string> rigs = CeaikaEmotes_TitanRigs()
    return model in rigs ? rigs[model] : ""
}

table<asset, string> function CeaikaEmotes_TitanRigs()
{
    if(file.rigs.len() == 0)
        file.rigs = {
            [$"models/titans/medium/titan_medium_ajax.mdl"] = "ion",
            [$"models/titans/medium/titan_medium_wraith.mdl"] = "tone",
            [$"models/titans/medium/titan_medium_vanguard.mdl"] = "monarch",
            [$"models/titans/light/titan_light_raptor.mdl"] = "northstar",
            [$"models/titans/light/titan_light_locust.mdl"] = "ronin",
            [$"models/titans/heavy/titan_heavy_ogre.mdl"] = "scorch",
            [$"models/titans/heavy/titan_heavy_deadbolt.mdl"] = "legion",
            [$"models/titans/medium/titan_medium_ion_prime.mdl"] = "ion_prime",
            [$"models/titans/medium/titan_medium_tone_prime.mdl"] = "tone_prime",
            [$"models/titans/light/titan_light_northstar_prime.mdl"] = "northstar_prime",
            [$"models/titans/light/titan_light_ronin_prime.mdl"] = "ronin_prime",
            [$"models/titans/heavy/titan_heavy_scorch_prime.mdl"] = "scorch_prime",
            [$"models/titans/heavy/titan_heavy_legion_prime.mdl"] = "legion_prime"
        }
    return file.rigs
}

// every titan of a chassis plays one library (ion, northstar or scorch, see the
// titan overrides) since their skeletons are the same. the clips were grounded
// on that titans own feet tho, so the others float or sink a bit. measured with
// em_selftest against each titans own library, steady per titan
float function CeaikaEmotes_TitanDrop(asset model)
{
    if(file.drops.len() == 0)
        file.drops = {
            [$"models/titans/medium/titan_medium_vanguard.mdl"] = -6.7,
            [$"models/titans/medium/titan_medium_wraith.mdl"] = -2.8,
            [$"models/titans/medium/titan_medium_ion_prime.mdl"] = -0.7,
            [$"models/titans/medium/titan_medium_tone_prime.mdl"] = 2.0,
            [$"models/titans/light/titan_light_locust.mdl"] = 1.7,
            [$"models/titans/light/titan_light_northstar_prime.mdl"] = -2.0,
            [$"models/titans/light/titan_light_ronin_prime.mdl"] = 2.4,
            [$"models/titans/heavy/titan_heavy_deadbolt.mdl"] = 1.7,
            [$"models/titans/heavy/titan_heavy_legion_prime.mdl"] = 0.4,
            [$"models/titans/heavy/titan_heavy_scorch_prime.mdl"] = 1.8
        }
    return model in file.drops ? file.drops[model] : 0.0
}

// where a dancer stands for a player standing at `origin`
vector function CeaikaEmotes_DancerOrigin(entity model, vector origin)
{
    float drop = CeaikaEmotes_TitanDrop(model.GetModelName())
    return origin+<0, 0, drop>
}

// titans dance too, except emotes marked titans = false (pilot only, like hug)
bool function CeaikaEmotes_SupportsEmote(entity player, string emote)
{
    if(!player.IsTitan()) return true
    int index = CeaikaEmotes_Index(emote)
    if(index < 0 || !CeaikaEmotes_Catalog()[index].titans) return false
    return player.GetModelName() in CeaikaEmotes_Models()
}
