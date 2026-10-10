global function CeaikaEmotes_AddMenu
global function CeaikaEmotes_Settings
global function CeaikaEmotes_OpenWheel
global function CeaikaEmotes_CloseWheel
struct
{
    var menu
    int page = 0
    int selected = -1
    int holdKey = -1
    int generation = 0
    array<var> labels
    array<var> hits
} file
void function CeaikaEmotes_AddMenu()
{
    AddMenu("CeaikaEmoteWheel", $"resource/ui/menus/ceaikaemotes.menu", CeaikaEmotes_InitWheel)
}
void function CeaikaEmotes_Settings()
{
    ModSettings_AddModTitle("ceaikaemotes")
    ModSettings_AddModCategory("Emote wheel controls")
    ModSettings_AddEnumSetting("em_wheel_key", "Hold to open emote wheel", ["Unbound", "B", "G", "H", "J"])
    ModSettings_AddEnumSetting("em_wheel_pad", "Hold controller emote wheel", ["Unbound", "D-pad Down"])
    ModSettings_AddEnumSetting("em_traversal", "Billy Bounce / Griddy movement", ["Stationary", "Traversal"])
}
int function CeaikaEmotes_Sector(float x, float y)
{
    if ( x*x+y*y < 0.15) return -1
    float angle = atan2(y, x)+1.570796327+0.392699082
    if ( angle < 0.0) angle += 6.283185307
    return int(angle/0.785398163)%8
}
void function CeaikaEmotes_InitWheel()
{
    file.menu = GetMenu("CeaikaEmoteWheel")
    for ( int i = 0; i<8; i++) file.labels.append(Hud_GetChild(file.menu, "Emote"+i))
    for ( int i = 0; i<576; i++)
    {
        var hit = Hud_GetChild(file.menu, "Hit"+i)
        file.hits.append(hit)
        Hud_SetText(hit, "")
        Hud_SetAlpha(hit, 0)
        int slot = CeaikaEmotes_Sector((float(i%24)+0.5-12.0)/12.0, (float(i/24)+0.5-12.0)/12.0)
        AddButtonEventHandler(hit, UIE_GET_FOCUS, void function(var b) : (slot)
        {
            CeaikaEmotes_Hover(slot)
        })
        AddButtonEventHandler(hit, UIE_CLICK, void function(var b)
        {
            if (file.holdKey < 0) CeaikaEmotes_Choose()
        })
    }
    AddMenuEventHandler(file.menu, eUIEvent.MENU_OPEN, CeaikaEmotes_DrawWheel)
    AddMenuEventHandler(file.menu, eUIEvent.MENU_CLOSE, CeaikaEmotes_Closed)
    AddMenuFooterOption(file.menu, BUTTON_B, "#B_BUTTON_BACK", "#BACK")
    var ring = Hud_GetRui(Hud_GetChild(file.menu, "Ring"))
    RuiSetImage(ring, "basicImage", $"rui/ceaika_emotes/ring")
    RuiSetFloat3(ring, "basicImageColor", <1, 1, 1>)
    RuiSetFloat(ring, "basicImageAlpha", 1.0)
    var highlight = Hud_GetRui(Hud_GetChild(file.menu, "Highlight"))
    RuiSetFloat3(highlight, "basicImageColor", <0.08, 0.55, 1.0>)
    RuiSetFloat(highlight, "basicImageAlpha", 0.0)
}
void function CeaikaEmotes_OpenWheel(int holdKey = -1)
{
    if ( !CanRunClientScript() || CeaikaEmotes_Catalog().len() == 0) return
    if ( GetTopNonDialogMenu() == file.menu) return
    file.page = 0
    file.holdKey = holdKey
    file.selected = -1
    AdvanceMenu(file.menu)
    file.generation++
    thread CeaikaEmotes_Hold(file.generation)
    print("[EmoteRelay] radial wheel opened with "+CeaikaEmotes_Catalog().len()+" names")
}
void function CeaikaEmotes_CloseWheel()
{
    if ( GetTopNonDialogMenu() == file.menu) CloseActiveMenu()
}
void function CeaikaEmotes_Closed()
{
    file.generation++
    if ( CanRunClientScript()) RunClientScript("CeaikaEmotes_WheelClosed")
}
void function CeaikaEmotes_Hold(int generation)
{
    bool previousQ = false
    bool previousE = false
    WaitFrame()
    while ( generation == file.generation && GetTopNonDialogMenu() == file.menu)
    {
        if ( file.holdKey >= 0 && !InputIsButtonDown(file.holdKey))
        {
            CeaikaEmotes_Choose()
            return
        }
        bool q = InputIsButtonDown(KEY_Q)
        bool e = InputIsButtonDown(KEY_E)
        int pages = (CeaikaEmotes_Catalog().len()+7)/8
        if ( pages>1 && ((q && !previousQ) || (e && !previousE)))
        {
            file.page = (file.page+pages+(q ? -1 : 1))%pages
            file.selected = -1
            CeaikaEmotes_DrawWheel()
        }
        previousQ = q
        previousE = e
        float stickX = InputGetAxis(ANALOG_RIGHT_X)
        float stickY = InputGetAxis(ANALOG_RIGHT_Y)
        if ( stickX*stickX+stickY*stickY > 0.15) CeaikaEmotes_Hover(CeaikaEmotes_Sector(stickX, stickY))
        WaitFrame()
    }
}
void function CeaikaEmotes_DrawWheel()
{
    float width = float(Hud_GetWidth(file.menu))
    float height = float(Hud_GetHeight(file.menu))
    float size = min(width*0.66, height*0.74)
    float left = (width-size)*0.5
    float top = (height-size)*0.5
    foreach ( string name in ["Ring", "Highlight"])
    {
        var panel = Hud_GetChild(file.menu, name)
        Hud_SetText(panel, "")
        Hud_SetSize(panel, int(size), int(size))
        Hud_SetPos(panel, int(left), int(top))
    }
    for (int i = 0; i<576; i++)
    {
        float x = left+size*float(i%24)/24.0
        float y = top+size*float(i/24)/24.0
        Hud_SetPos(file.hits[i], int(x), int(y))
        Hud_SetSize(file.hits[i], int(size/24.0)+1, int(size/24.0)+1)
    }
    for (int i = 0; i<8; i++)
    {
        int index = file.page*8+i
        float angle = -1.570796327+float(i)*0.785398163
        var label = file.labels[i]
        Hud_SetPos(label, int(width*0.5+cos(angle)*size*0.34-Hud_GetWidth(label)*0.5), int(height*0.5+sin(angle)*size*0.34-Hud_GetHeight(label)*0.5))
        Hud_SetEnabled(label, true)
        Hud_SetColor(label, 255, 255, 255, 255)
        Hud_SetText(label, index<CeaikaEmotes_Catalog().len() ? CeaikaEmotes_Catalog()[index].title : "")
    }
    foreach(string name in ["Selected", "Page"])
    {
        var label = Hud_GetChild(file.menu, name)
        Hud_SetEnabled(label, true)
        Hud_SetColor(label, 255, 255, 255, 255)
    }
    Hud_SetText(Hud_GetChild(file.menu, "Title"), "EMOTES")
    Hud_SetText(Hud_GetChild(file.menu, "Page"), (file.page+1)+" / "+((CeaikaEmotes_Catalog().len()+7)/8))
    string help = file.holdKey < 0 ? "Aim at a name and click" : "Aim at a name, then release the held key"
    Hud_SetText(Hud_GetChild(file.menu, "Hint"), help+"     Q / E: pages     Esc: cancel")
    CeaikaEmotes_Hover(-1)
}
void function CeaikaEmotes_Hover(int slot)
{
    if ( GetTopNonDialogMenu() != file.menu) return
    file.selected = slot >= 0 && file.page*8+slot<CeaikaEmotes_Catalog().len() ? slot : -1
    var highlight = Hud_GetRui(Hud_GetChild(file.menu, "Highlight"))
    RuiSetFloat(highlight, "basicImageAlpha", file.selected >= 0 ? 1.0 : 0.0)
    array<asset> sectors = [$"rui/ceaika_emotes/sector_0", $"rui/ceaika_emotes/sector_1", $"rui/ceaika_emotes/sector_2", $"rui/ceaika_emotes/sector_3", $"rui/ceaika_emotes/sector_4", $"rui/ceaika_emotes/sector_5", $"rui/ceaika_emotes/sector_6", $"rui/ceaika_emotes/sector_7"]
    if ( file.selected >= 0) RuiSetImage(highlight, "basicImage", sectors[file.selected])
    Hud_SetText(Hud_GetChild(file.menu, "Selected"), file.selected >= 0 ? CeaikaEmotes_Catalog()[file.page*8+file.selected].title : "EMOTES")
}
void function CeaikaEmotes_Choose()
{
    int index = file.selected<0 ? -1 : file.page*8+file.selected
    CeaikaEmotes_CloseWheel()
    if ( index >= 0 && index<CeaikaEmotes_Catalog().len() && CanRunClientScript())
    RunClientScript("CeaikaEmotes_Select", CeaikaEmotes_Catalog()[index].id)
}

