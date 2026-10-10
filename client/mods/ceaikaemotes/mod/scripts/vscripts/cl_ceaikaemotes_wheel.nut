global function CeaikaEmotes_WheelInit
global function CeaikaEmotes_OpenCommand
global function CeaikaEmotes_Select
global function CeaikaEmotes_WheelClosed
struct
{
    bool wheelOpen = false
    int generation = 0
} file
void function CeaikaEmotes_WheelInit()
{
    if(IsMenuLevel()) return
    foreach(int key in [KEY_B, KEY_G, KEY_H, KEY_J, BUTTON_DPAD_DOWN])
    RegisterButtonPressedCallback(key, void function(entity player) : (key)
    {
        CeaikaEmotes_WheelKey(key)
    })
}
void function CeaikaEmotes_WheelKey(int key)
{
    array<int> keys = [-1, KEY_B, KEY_G, KEY_H, KEY_J]
    int binding = GetConVarInt("em_wheel_key")
    bool keyboard = binding >= 0 && binding<keys.len() && keys[binding] == key
    bool pad = GetConVarBool("em_wheel_pad") && key == BUTTON_DPAD_DOWN
    if(keyboard || pad) CeaikaEmotes_Open(key)
}
void function CeaikaEmotes_OpenCommand(array<string> args = [])
{
    CeaikaEmotes_Open(-1)
}
void function CeaikaEmotes_Open(int holdKey)
{
    entity player = GetLocalClientPlayer()
    if(!IsValid(player) || !IsAlive(player) || player.IsTitan() || clGlobal.isMenuOpen || file.wheelOpen) return
    file.wheelOpen = true
    file.generation++
    RunUIScript("CeaikaEmotes_OpenWheel", holdKey)
    thread CeaikaEmotes_WheelWatch(file.generation)
}
void function CeaikaEmotes_WheelClosed()
{
    file.wheelOpen = false;
    file.generation++;
}
void function CeaikaEmotes_Select(string id)
{
    int index = CeaikaEmotes_Index(id)
    if(index<0) return
    CeaikaEmoteDef emoteDef = CeaikaEmotes_Catalog()[index]
    array<string> args = [emoteDef.id]
    if(emoteDef.traversal && GetConVarBool("em_traversal")) args.append("traversal")
    CeaikaEmotes_Play(args)
}
void function CeaikaEmotes_WheelWatch(int generation)
{
    while(file.wheelOpen && generation == file.generation)
    {
        entity player = GetLocalClientPlayer()
        if(!IsValid(player) || !IsAlive(player) || player.IsTitan())
        {
            RunUIScript("CeaikaEmotes_CloseWheel")
            CeaikaEmotes_WheelClosed()
            return
        }
        wait 0.1
    }
}
