untyped
global function CeaikaEmotes_InteractInit
global function CeaikaEmotes_FreelookHeld

const float EMOTE_HOLD_SECONDS = 0.8

struct
{
    table<int, bool> held
    bool inverted = false
    var label = null
    string prompt = ""
} interaction

// keys get typed into mod settings by name (em_sync_bind, em_freelook_bind),
// CeaikaEmotes_KeyCode turns that into the actual key or -1 if its unbound
bool function CeaikaEmotes_BindHeld(string convar)
{
    int key = CeaikaEmotes_KeyCode(GetConVarString(convar))
    return key >= 0 && key in interaction.held
}

// held while emoting = the camera orbits and the dancer keeps facing the same way
bool function CeaikaEmotes_FreelookHeld()
{
    return CeaikaEmotes_BindHeld("em_freelook_bind")
}

void function CeaikaEmotes_InteractInit()
{
    if(IsMenuLevel()) return
    // any key can be bound so just listen to all of them
    foreach(int key in CeaikaEmotes_BindableKeys())
    {
        RegisterButtonPressedCallback(key, void function(entity player) : (key)
        {
            interaction.held[key] <- true
            // space cancels, titans too. a titan's jump is a dash and that
            // doesnt always move it enough to cancel by itself
            if(key == KEY_SPACE && CeaikaEmotes_IsEmoting()) CeaikaEmotes_Stop()
        })
        RegisterButtonReleasedCallback(key, void function(entity player) : (key)
        {
            if(key in interaction.held) delete interaction.held[key]
        })
    }
    // a crash or alt+f4 mid freelook would leave the mouse flipped forever
    CeaikaEmotes_RestoreMouse()
    AddCallback_EntitiesDidLoad(void function()
    {
        thread CeaikaEmotes_InteractThink()
    })
}

void function CeaikaEmotes_InteractThink()
{
    CeaikaEmotes_RestoreMouse()
    OnThreadEnd(void function()
    {
        CeaikaEmotes_InteractionDestroy()
        CeaikaEmotes_RestoreMouse()
    })
    string holdingUid = ""
    string holdingNonce = ""
    float holdStart = -1.0
    bool wasDown = false
    while(true)
    {
        string bind = GetConVarString("em_sync_bind")
        bool enabled = CeaikaEmotes_KeyCode(bind) >= 0
        bool down = enabled && CeaikaEmotes_BindHeld("em_sync_bind")
        table target = enabled ? CeaikaEmotes_GetSyncTarget() : {}
        bool available = "uid" in target
        if(!down || !available || (holdStart >= 0.0 &&
           (target.uid != holdingUid || target.nonce != holdingNonce)))
            holdStart = -1.0

        // needs a fresh press on someone u can join. walking into range or
        // switching dancers with the key already held shouldnt start it
        if(down && !wasDown && available)
        {
            holdingUid = expect string(target.uid)
            holdingNonce = expect string(target.nonce)
            holdStart = Time()
        }
        float progress = holdStart < 0.0 ? 0.0 : clamp((Time()-holdStart)/EMOTE_HOLD_SECONDS, 0.0, 1.0)
        if(available)
            CeaikaEmotes_InteractionDraw(bind.toupper(), progress, expect bool(target.paired))
        else
            CeaikaEmotes_InteractionDestroy()

        if(progress >= 1.0)
        {
            // the relay checks the nonce again before it takes the shared start
            CeaikaEmotes_Sync(holdingUid, holdingNonce)
            holdStart = -1.0
            CeaikaEmotes_InteractionDestroy()
        }
        wasDown = down
        CeaikaEmotes_InvertWhileLooking()
        WaitFrame()
    }
}

// freelook invert flips the games own invert look while freelook is held.
// scripts cant read or set mouse convars at all (m_pitch doesnt even exist on
// the client, it just gets sent to the server lol) but "toggle m_invert_pitch"
// works blind. em_saved_mouse remembers we flipped it so a crash mid freelook
// gets flipped back next time instead of leaving u inverted forever
void function CeaikaEmotes_InvertWhileLooking()
{
    bool want = GetConVarInt("em_freelook_invert") > 0 && CeaikaEmotes_IsEmoting() && CeaikaEmotes_FreelookHeld()
    if(want == interaction.inverted) return
    if(!want)
    {
        CeaikaEmotes_RestoreMouse()
        return
    }
    entity player = GetLocalClientPlayer()
    if(!IsValid(player)) return
    player.ClientCommand("toggle m_invert_pitch")
    SetConVarString("em_saved_mouse", "flipped")
    interaction.inverted = true
}

void function CeaikaEmotes_RestoreMouse()
{
    interaction.inverted = false
    entity player = GetLocalClientPlayer()
    if(GetConVarString("em_saved_mouse") != "flipped" || !IsValid(player)) return
    player.ClientCommand("toggle m_invert_pitch")
    SetConVarString("em_saved_mouse", "")
}

void function CeaikaEmotes_InteractionDraw(string key, float progress, bool paired = false)
{
    // the game's own hint (same one executions use) with the key and how far
    // the hold is under it. paired emotes get joined as the partner, not copied
    string prompt = paired ? "Hold to join emote" : "Hold to sync emote"
    if(interaction.prompt != prompt)
    {
        if(interaction.prompt != "") HidePlayerHint(interaction.prompt)
        interaction.prompt = prompt
        AddPlayerHint(3600.0, 0.1, $"", interaction.prompt)
    }
    if(interaction.label == null)
    {
        interaction.label = RuiCreate($"ui/cockpit_console_text_center.rpak", clGlobal.topoCockpitHudPermanent, RUI_DRAW_COCKPIT, -1)
        RuiSetInt(interaction.label, "maxLines", 1)
        RuiSetInt(interaction.label, "lineNum", 1)
        RuiSetFloat(interaction.label, "msgAlpha", 1.0)
        RuiSetFloat(interaction.label, "thicken", 0.0)
        RuiSetFloat(interaction.label, "msgFontSize", 24.0)
        RuiSetFloat3(interaction.label, "msgColor", <1, 1, 1>)
        RuiSetFloat2(interaction.label, "msgPos", <0, 0.12, 0>)
    }
    RuiSetString(interaction.label, "msgText", progress > 0.0 ? key+"  "+int(progress*100.0)+"%" : key)
}

void function CeaikaEmotes_InteractionDestroy()
{
    if(interaction.prompt != "") HidePlayerHint(interaction.prompt)
    interaction.prompt = ""
    if(interaction.label != null) RuiDestroyIfAlive(interaction.label)
    interaction.label = null
}
