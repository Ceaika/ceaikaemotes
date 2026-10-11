global function CeaikaEmotes_AuthUIInit
global function CeaikaEmotes_ShowAuthDialog
global function CeaikaEmotes_ForgetRelay

struct
{
    string promptedUrl = ""
} file

void function CeaikaEmotes_AuthUIInit()
{
    thread CeaikaEmotes_WatchAuthPermission()
}

void function CeaikaEmotes_WatchAuthPermission()
{
    while(true)
    {
        wait 1.0
        if(!GetConVarBool("em_enabled"))
        {
            file.promptedUrl = ""
            continue
        }
        if(!IsFullyConnected() || !IsMultiplayer() || !CanRunClientScript()) continue

        string url = GetConVarString("em_url")
        if(url == "" || url == GetConVarString("em_auth_allowed_url") || url == file.promptedUrl) continue
        // ordinary lobby menus are fine. dont interrupt another dialog or the wheel.
        var activeMenu = GetActiveMenu()
        if(activeMenu != null && IsDialog(activeMenu)) continue
        if(activeMenu == GetMenu("CeaikaEmoteWheel")) continue
        CeaikaEmotes_ShowAuthDialog()
    }
}

void function CeaikaEmotes_ShowAuthDialog()
{
    string url = GetConVarString("em_url")
    file.promptedUrl = url
    DialogData dialog
    dialog.header = "ceaikaemotes - online emotes"
    dialog.message = "To show your emotes to other players, this relay needs to verify your EA account.\n\n"
        + url + "\n\n"
        + "It receives a fresh, short-lived EA login code and checks it with Respawn. "
        + "Only allow a relay you trust. This choice is remembered for this address. "
        + "You can remove it in Mod Settings."
    AddDialogButton(dialog, "Allow and remember", void function() : (url)
    {
        // only approve the address the player actually saw.
        if(GetConVarString("em_url") != url || url.find("https://") != 0) return
        SetConVarString("em_auth_allowed_url", url)
        SetConVarBool("em_enabled", true)
    })
    AddDialogButton(dialog, "Not now", void function()
    {
        SetConVarBool("em_enabled", false)
    })
    OpenDialog(dialog)
}

void function CeaikaEmotes_ForgetRelay()
{
    SetConVarString("em_auth_allowed_url", "")
    SetConVarString("em_auth_request", "")
    SetConVarBool("em_enabled", false)
    if(CanRunClientScript()) RunClientScript("CeaikaEmotes_AuthRevoke")
}
