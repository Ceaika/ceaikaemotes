global function CeaikaEmotes_SelfTestInit

// start the game with +em_selftest 1 (or +em_selftest quit to close it after)
// on a local map. it poses every emote on every dancer model and every prop
// clip and writes where things end up to the log. run it before and after
// changing how the models get built and diff the numbers, cus i cant see the
// screen from where i build this stuff

void function CeaikaEmotes_SelfTestInit()
{
    if(IsMenuLevel()) return
    AddCallback_EntitiesDidLoad(void function()
    {
        if(GetConVarString("em_selftest") != "") thread CeaikaEmotes_SelfTest()
    })
}

void function CeaikaEmotes_SelfTest()
{
    // Anim_SetStartTime wants a positive time and right after a map loads
    // Time() is like 3, so wait out the longest clip first
    while(Time() < 30.0) wait 1.0
    print("[EmoteSelfTest] start")
    // +em_selftest "scan emote_x" samples just that emote at 21 points, for
    // when one emote is off and the 3 usual samples dont say how
    array<string> words = split(GetConVarString("em_selftest"), " ")
    if(words.len() == 2 && words[0] == "scan")
    {
        CeaikaEmotes_TestScan(words[1])
        print("[EmoteSelfTest] done failures=0")
        wait 1.0
        GetLocalClientPlayer().ClientCommand("quit")
        return
    }
    int failures = CeaikaEmotes_TestDancers()+CeaikaEmotes_TestProps()
    CeaikaEmotes_TestMouse()
    print("[EmoteSelfTest] done failures="+failures)
    if(GetConVarString("em_selftest") == "quit")
    {
        wait 1.0
        GetLocalClientPlayer().ClientCommand("quit")
    }
}

// one dancer per model, all of them posed together so a whole emote is one frame
int function CeaikaEmotes_TestDancers()
{
    int failures = 0
    table<asset, entity> dancers
    foreach(asset model, asset unused in CeaikaEmotes_Models())
    {
        dancers[model] <- CreateClientSidePropDynamic(<0, 0, -2000>, <0, 0, 0>, model)
        // placed the way the mod places dancers (titan height fix and all)
        dancers[model].SetOrigin(CeaikaEmotes_DancerOrigin(dancers[model], <0, 0, -2000>))
    }
    foreach(CeaikaEmoteDef def in CeaikaEmotes_Catalog())
    {
        table<asset, string> lines
        foreach(asset model, entity dancer in dancers)
        {
            bool titan = CeaikaEmotes_TitanRig(model) != ""
            if(titan && !def.titans) continue
            if(dancer.LookupSequence(def.sequence) < 0)
            {
                print("[EmoteSelfTest] MISSING "+def.id+" on "+model)
                failures++
                continue
            }
            dancer.Anim_Play(def.sequence)
            lines[model] <- ""
        }
        foreach(float at in [0.25, 0.5, 0.75])
        {
            foreach(asset model, string line in lines)
            {
                entity dancer = dancers[model]
                dancer.SetCycle(at)
                dancer.Anim_SetStartTime(Time()-at*def.duration/def.playbackRate)
            }
            // bones are cached per frame, a new cycle only shows up next frame
            WaitFrame()
            foreach(asset model, string line in lines)
                lines[model] = line+" "+CeaikaEmotes_TestPoints(dancers[model])
        }
        foreach(asset model, string line in lines)
            print("[EmoteSelfTest] pose "+def.id+" "+model+line)
    }
    foreach(asset model, entity dancer in dancers)
        if(IsValid(dancer)) dancer.Destroy()
    return failures
}

void function CeaikaEmotes_TestScan(string id)
{
    int index = CeaikaEmotes_Index(id)
    if(index < 0) return
    CeaikaEmoteDef def = CeaikaEmotes_Catalog()[index]
    foreach(asset model in [$"models/humans/pilots/pilot_medium_reaper_m.mdl", $"models/titans/medium/titan_medium_ajax.mdl"])
    {
        entity dancer = CreateClientSidePropDynamic(<0, 0, -2000>, <0, 0, 0>, model)
        dancer.Anim_Play(def.sequence)
        for(int i = 0; i <= 20; i++)
        {
            float at = i/20.0
            dancer.SetCycle(at)
            dancer.Anim_SetStartTime(Time()-at*def.duration/def.playbackRate)
            WaitFrame()
            print(format("[EmoteSelfTest] scan %s %.2f %s", def.id, at, CeaikaEmotes_TestPoints(dancer)))
        }
        dancer.Destroy()
    }
}

// head and chest, relative to the model. titans name them differently
string function CeaikaEmotes_TestPoints(entity model)
{
    string out = ""
    int found = 0
    foreach(string name in ["HEADFOCUS", "CHESTFOCUS", "HEADSHOT", "HATCH_HEAD"])
    {
        int id = model.LookupAttachment(name)
        if(id <= 0 || found >= 2) continue
        vector p = model.GetAttachmentOrigin(id)-<0, 0, -2000>
        out += format("%s=%.1f,%.1f,%.1f;", name, p.x, p.y, p.z)
        found++
    }
    return out
}

// every prop clip, pilot and titan ones, has to play without an error and
// keep REF at the prop's origin
int function CeaikaEmotes_TestProps()
{
    int failures = 0
    array<string> rigs = ["ion", "tone", "monarch", "northstar", "ronin", "scorch", "legion",
        "ion_prime", "tone_prime", "northstar_prime", "ronin_prime", "scorch_prime", "legion_prime"]
    foreach(CeaikaEmoteDef def in CeaikaEmotes_Catalog())
    {
        foreach(int i, CeaikaEmoteExtra extra in def.extras)
        {
            if(extra.model == $"" || extra.sequence == "") continue
            array<string> sequences = [extra.sequence]
            if(extra.titans)
                foreach(string rig in rigs) sequences.append(extra.sequence+"_"+rig)
            entity prop = CreateClientSidePropDynamic(<0, 0, -2000>, <0, 0, 0>, extra.model)
            foreach(string sequence in sequences)
            {
                try
                {
                    if(prop.LookupSequence(sequence) < 0) throw "missing sequence"
                    prop.Anim_Play(sequence)
                    prop.SetCycle(0.5)
                    WaitFrame()
                    int ref = prop.LookupAttachment("REF")
                    vector at = ref > 0 ? prop.GetAttachmentOrigin(ref)-prop.GetOrigin() : <999, 999, 999>
                    print(format("[EmoteSelfTest] prop %s %s ref=%.2f,%.2f,%.2f", def.id, sequence, at.x, at.y, at.z))
                    if(ref <= 0 || Length(at) > 0.5) failures++
                }
                catch(error)
                {
                    print("[EmoteSelfTest] PROP FAILED "+def.id+" "+sequence+": "+error)
                    failures++
                }
            }
            prop.Destroy()
        }
    }
    return failures
}

// scripts cant read mouse convars ("ConVar m_pitch is not valid"), so this
// just runs console commands and the values show up in the log next to these
// markers. checks what freelook invert can use
void function CeaikaEmotes_TestMouse()
{
    entity player = GetLocalClientPlayer()
    foreach(string command in ["m_pitch", "m_yaw", "m_invert_pitch", "toggle m_invert_pitch", "m_invert_pitch",
        "toggle m_invert_pitch", "m_invert_pitch", "toggle m_yaw 0.022 -0.022", "m_yaw", "toggle m_yaw 0.022 -0.022", "m_yaw"])
    {
        print("[EmoteSelfTest] mouse > "+command)
        player.ClientCommand(command)
        wait 0.3
    }
}
