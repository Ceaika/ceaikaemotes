global function CeaikaEmotes_IsWheelOpen
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
    array<int> keys = CeaikaEmotes_BindableKeys()
    keys.append(BUTTON_DPAD_DOWN)
    foreach(int key in keys)
    RegisterButtonPressedCallback(key, void function(entity player) : (key)
    {
        CeaikaEmotes_WheelKey(key)
    })
}
void function CeaikaEmotes_WheelKey(int key)
{
    int bound = CeaikaEmotes_KeyCode(GetConVarString("em_wheel_bind"))
    bool keyboard = bound >= 0 && bound == key
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
    if(!IsValid(player) || !IsAlive(player) || clGlobal.isMenuOpen || file.wheelOpen) return
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
        if(!IsValid(player) || !IsAlive(player))
        {
            RunUIScript("CeaikaEmotes_CloseWheel")
            CeaikaEmotes_WheelClosed()
            return
        }
        wait 0.1
    }
}

bool function CeaikaEmotes_IsWheelOpen()
{
    return file.wheelOpen
}
