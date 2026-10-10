untyped
global function CeaikaEmotes_Init
global function CeaikaEmotes_Play
global function CeaikaEmotes_Stop
global function CeaikaEmotes_Status
global function CeaikaEmotes_Probe
global function CeaikaEmotes_List
struct
{
    bool requestInFlight = false
    bool started = false
    string emote = ""
    string nonce = "idle"
    int serial = 0
    float lastReplyTime = -100.0
    float lastError = -100.0
    bool traversal = false
    bool duckHeld = false
    bool drawIdle = true
    int culled = 0
    int pulse = 0
    table peers
    table retryAfter
    table cancelledPlayback
    table dancers
} relay
void function CeaikaEmotes_Init()
{
    foreach (asset nativeModel, asset model in CeaikaEmotes_Models()) PrecacheModel(model)
    SetConVarString("em_native_request", "")
    SetConVarString("em_audio_request", "")
    SetConVarString("em_camera_request", "0")
    AddCallback_EntitiesDidLoad(void function()
    {
        thread CeaikaEmotes_PollRelay()
    })
}

void function CeaikaEmotes_Play(array<string> args = [])
{
    entity player = GetLocalClientPlayer()
    if(!IsValid(player) || !IsAlive(player) || player.IsTitan() || !player.IsOnGround()) return
    if(GetConVarString("em_url") == "" || GetConVarString("emkey") == "")
    {
        print("[EmoteRelay] Set em_url and emkey first.");
        return;
    }
    if(GetConVarInt("em_native_ready") != 1)
    {
        print("[EmoteRelay] Visibility plugin unavailable. Install plugins/ceaikaemotes.dll and restart Ion.");
        return;
    }
    string name = args.len()>0 ? args[0].tolower() : "billy"
    int index = CeaikaEmotes_Index(name)
    if(index<0)
    {
        print("[EmoteRelay] Unknown emote. Use em_list for names.");
        return;
    }
    CeaikaEmoteDef emoteDef = CeaikaEmotes_Catalog()[index]
    bool traversal = args.len()>1 && args[1] == "traversal"
    if(traversal && !emoteDef.traversal)
    {
        print("[EmoteRelay] Traversal is available only for Billy Bounce and Griddy.");
        return;
    }
    CeaikaEmotes_Stop()
    relay.traversal = traversal
    if(traversal)
    {
        player.ClientCommand("+duck 9876");
        relay.duckHeld = true;
    }
    SetConVarBool("em_enabled", true)
    relay.serial++
    relay.nonce = format("%d_%d", int(Time()*1000), relay.serial)
    relay.emote = emoteDef.id
    print("[EmoteRelay] "+relay.emote+" requested; traversal="+relay.traversal)
}

void function CeaikaEmotes_List(array<string> args = [])
{
    foreach(emoteDef in CeaikaEmotes_Catalog())
    print("[EmoteRelay] "+emoteDef.title+": em_play "+emoteDef.id+(emoteDef.traversal ? " [traversal]" : ""))
}

void function CeaikaEmotes_Stop(array<string> args = [])
{
    CeaikaEmotes_ReleaseDuck()
    relay.traversal = false
    relay.emote = ""
    relay.serial++
    relay.nonce = format("stop_%d", relay.serial)
}

void function CeaikaEmotes_ReleaseDuck()
{
    if(!relay.duckHeld) return
    entity player = GetLocalClientPlayer()
    if(IsValid(player)) player.ClientCommand("-duck 9876")
    relay.duckHeld = false
}

void function CeaikaEmotes_Status(array<string> args = [])
{
    entity player = GetLocalClientPlayer()
    print("[EmoteRelay] idle="+relay.drawIdle+" audioSleeping="+GetConVarInt("em_audio_idle")+" audioDeviceOpen="+GetConVarInt("em_audio_device"))
    print("[EmoteRelay] audioReady="+GetConVarInt("em_audio_ready")+" voices="+GetConVarInt("em_audio_voices"))
    print("[EmoteRelay] enabled="+GetConVarBool("em_enabled")+" HTTP="+NSIsHttpEnabled()+" peers="+relay.peers.len()+" visuals="+relay.dancers.len()+" culled="+relay.culled+" native="+GetConVarInt("em_native_ready")+" hidden="+GetConVarInt("em_native_hidden")+" replyAge="+(Time()-relay.lastReplyTime))
    if(IsValid(player)) print("[EmoteRelay] Local player UID available="+(GetUID(player) != "0"))
}

void function CeaikaEmotes_Probe(array<string> args = [])
{
    entity player = GetLocalClientPlayer()
    if(!IsValid(player)) return
    print("[EmoteRelay] Weapon entities: main="+player.GetMainWeapons().len()+" offhand="+player.GetOffhandWeapons().len())
}

void function CeaikaEmotes_PollRelay()
{
    if(relay.started) return
    relay.started = true
    entity initial
    while(!IsValid(initial))
    {
        initial = GetLocalClientPlayer();
        wait 0.1;
    }
    initial.ClientCommand("-duck 9876")
    thread CeaikaEmotes_UpdateDancers()
    while(true)
    {
        entity player = GetLocalClientPlayer()
        if(IsValid(player) && GetConVarBool("em_enabled") && NSIsHttpEnabled() && !relay.requestInFlight)
        {
            string url = GetConVarString("em_url")
            string key = GetConVarString("emkey")
            if(url != "" && key != "" && GetMapName().find("mp_") == 0)
            {
                string playerId = GetUID(player)
                if(playerId != "0" && playerId != "")
                {
                    if(!IsAlive(player) || player.IsTitan()) CeaikaEmotes_Stop()
                    HttpRequest request
                    request.method = HttpRequestMethod.POST
                    request.url = url+"/sync"
                    request.headers =
                    {
                        Authorization = ["Bearer "+key]
                    }
                    request.body = EncodeJSON(
                    {
                        uid = playerId, map = GetMapName(), emote = relay.emote, nonce = relay.nonce, traversal = relay.traversal
                    })
                    request.timeout = 4
                    relay.requestInFlight = true
                    if(!NSHttpRequest(request, CeaikaEmotes_OnRelayReply, CeaikaEmotes_OnRelayFailure)) relay.requestInFlight = false
                }
            }
        }
        wait 0.5
    }
}

void function CeaikaEmotes_Error(string message)
{
    if(Time()-relay.lastError<10.0) return
    relay.lastError = Time()
    print("[EmoteRelay] "+message)
}

void function CeaikaEmotes_OnRelayFailure(HttpRequestFailure result)
{
    relay.requestInFlight = false
    CeaikaEmotes_Error("HTTP request failed (code "+result.errorCode+")")
}

void function CeaikaEmotes_OnRelayReply(HttpRequestResponse result)
{
    relay.requestInFlight = false
    if(result.statusCode != 200)
    {
        CeaikaEmotes_Error("Relay returned HTTP "+result.statusCode);
        return;
    }
    try
    {
        var data = DecodeJSON(result.body)
        table next
        foreach(var peer in data.peers)
        {
            string emote = expect string(peer.emote)
            int index = CeaikaEmotes_Index(emote)
            if(index<0) continue
            string playerId = expect string(peer.uid)
            string nonce = expect string(peer.nonce)
            float age = expect float(peer.age)
            if(age<0.0 || age>3600.0) continue
            float startedAt = Time()-age
            if(playerId in relay.peers && relay.peers[playerId].nonce == nonce) startedAt = expect float(relay.peers[playerId].startedAt)
            next[playerId] <-
            {
                nonce = nonce, startedAt = startedAt, emote = CeaikaEmotes_Catalog()[index].id, traversal = (CeaikaEmotes_Catalog()[index].traversal && "traversal" in peer && peer.traversal == true)
            }
        }
        array<string> expired
        foreach(string playerId, var entry in relay.cancelledPlayback)
        if(!(playerId in next) || next[playerId].nonce != entry.nonce) expired.append(playerId)
        foreach(string playerId in expired) delete relay.cancelledPlayback[playerId]
        relay.peers = next
        relay.lastReplyTime = Time()
    }
    catch(error)
    {
        CeaikaEmotes_Error("Invalid relay response: "+error);
    }
}

void function CeaikaEmotes_Remove(string playerId)
{
    if(!(playerId in relay.dancers)) return
    if(relay.dancers[playerId].source == GetLocalClientPlayer()) CeaikaEmotes_ClearCamera()
    if(IsValid(relay.dancers[playerId].model)) relay.dancers[playerId].model.Destroy()
    delete relay.dancers[playerId]
}

void function CeaikaEmotes_ClearCamera()
{
    SetConVarString("em_camera_request", "0")
}

void function CeaikaEmotes_Camera(entity player, entity model)
{
    SetConVarString("em_camera_request", clGlobal.isMenuOpen ? "0" : "1")
}

float function CeaikaEmotes_SmoothYaw(float current, float target, float dt)
{
    // take the short turn, dont spin all the way around.
    // 35 ms half-life keeps it responsive at different frame rates.
    float delta = target-current
    delta -= 360.0*floor((delta+180.0)/360.0)
    float yaw = current+delta*(1.0-pow(0.5, max(0.0, dt)/0.035))
    return yaw-360.0*floor((yaw+180.0)/360.0)
}
// Conservative sphere/frustum intersection: allow dancing limbs at the edges.
// FOV is the engine's 4:3 horizontal base; wider screens expand horizontally.
bool function CeaikaEmotes_InView(vector center, vector camera, vector forward, vector right, vector up, float tanX, float tanY, float radius)
{
    vector delta = center-camera
    float depth = DotProduct(delta, forward)
    if(depth < -radius) return false
    if(fabs(DotProduct(delta, right)) > depth*tanX+radius*sqrt(1.0+tanX*tanX)) return false
    if(fabs(DotProduct(delta, up)) > depth*tanY+radius*sqrt(1.0+tanY*tanY)) return false
    return true
}

string function CeaikaEmotes_HideRequest(entity player, entity localPlayer, string hidden)
{
    if(hidden != "") hidden += ","
    hidden += string(player.GetEntIndex())
    foreach(entity weapon in player.GetMainWeapons()) if(IsValid(weapon)) hidden += ","+weapon.GetEntIndex()
    foreach(entity weapon in player.GetOffhandWeapons()) if(IsValid(weapon)) hidden += ","+weapon.GetEntIndex()
    if(player == localPlayer)
    {
        entity viewModel = player.GetViewModelEntity()
        if(IsValid(viewModel)) hidden += ","+viewModel.GetEntIndex()
    }
    return hidden
}

string function CeaikaEmotes_BuildMusicRequest(entity player, entity listener, float age, int track)
{
    float volume = clamp(GetConVarFloat("em_volume"), 0.0, 1.0)
    float gain = volume * clamp(GetConVarFloat("sound_volume"), 0.0, 1.0)
    float pan = 0.0
    bool ownEmote = player == listener

    if (!ownEmote)
    {
        vector direction = player.GetOrigin() - listener.GetOrigin()
        float distance = Length(direction)
        float fade = 1.0 - clamp((distance - 96.0) / 1004.0, 0.0, 1.0)
        gain *= 0.65 * fade * fade

        if (distance > 1.0)
        {
            vector cameraRight = AnglesToRight(<0, listener.EyeAngles().y, 0>)
            pan = clamp(DotProduct(direction / distance, cameraRight), -1.0, 1.0)
        }
    }

    if (gain <= 0.0001)
        return ""

    return format("%d,%.4f,%.4f,%.4f,%d,%d", player.GetEntIndex(), age, gain, pan, ownEmote ? 1 : 0, track)
}

void function CeaikaEmotes_UpdateDancers()
{
    OnThreadEnd(void function()
    {
        SetConVarString("em_native_request", "")
        SetConVarString("em_audio_request", "")
        SetConVarString("em_camera_request", "0")
        CeaikaEmotes_ClearCamera()
        CeaikaEmotes_ReleaseDuck()
        foreach(string playerId, var entry in relay.dancers) if(IsValid(entry.model)) entry.model.Destroy()
        relay.dancers.clear()
    })
    while(true)
    {
        if(relay.emote == "" && relay.dancers.len() == 0 &&
        (!GetConVarBool("em_enabled") || relay.peers.len() == 0 || Time()-relay.lastReplyTime >= 6.0))
        {
            if(!relay.drawIdle)
            {
                SetConVarString("em_native_request", "")
                SetConVarString("em_audio_request", "")
                relay.drawIdle = true
            }
            relay.culled = 0
            wait 0.1
            continue
        }
        relay.drawIdle = false
        entity localPlayer = GetLocalClientPlayer()
        if(IsValid(localPlayer) && relay.emote != "" &&
        (!IsAlive(localPlayer) || localPlayer.IsTitan() || !localPlayer.IsOnGround() || localPlayer.IsInputCommandHeld(IN_JUMP) ||
        localPlayer.IsInputCommandHeld(IN_ATTACK) ||
        (!relay.traversal && (fabs(localPlayer.GetInputAxisForward())>0.1 || fabs(localPlayer.GetInputAxisRight())>0.1)) ||
        Length2D(localPlayer.GetVelocity())>(relay.traversal?260.0:80.0) || !GetConVarBool("em_enabled")))
        CeaikaEmotes_Stop()
        relay.culled = 0
        entity viewer = GetLocalViewPlayer()
        if(!IsValid(viewer)) viewer = localPlayer
        vector viewOrigin = <0, 0, 0>
        vector viewForward = <1, 0, 0>
        vector viewRight = <0, -1, 0>
        vector viewUp = <0, 0, 1>
        float tanX = 1.0
        float tanY = 1.0
        if(IsValid(viewer))
        {
            viewOrigin = viewer.CameraPosition()
            vector viewAngles = viewer.CameraAngles()
            viewForward = AnglesToForward(viewAngles)
            viewRight = AnglesToRight(viewAngles)
            viewUp = AnglesToUp(viewAngles)
            float[2] screenSize = GetScreenSize()
            float aspect = screenSize[0]/max(1.0, screenSize[1])
            float halfFov = clamp(viewer.GetFOV(), 1.0, 170.0)*0.00872664626
            tanX = tan(halfFov)*max(1.0, aspect/(4.0/3.0))
            tanY = tanX/aspect
        }
        table active
        string hidden = ""
        string music = ""
        int musicCount = 0
        if(GetConVarBool("em_enabled") && GetConVarInt("em_native_ready") == 1 && Time()-relay.lastReplyTime<6.0)
        {
            foreach(entity player in GetPlayerArray())
            {
                if(!IsValid(player) || !IsAlive(player) || player.IsTitan()) continue
                string playerId = GetUID(player)
                if(!(playerId in relay.peers)) continue
                if(player == localPlayer && relay.emote == "") continue
                asset original = player.GetModelName()
                if(!(original in CeaikaEmotes_Models())) continue
                var state = relay.peers[playerId]
                // old relay reply, dont hide the player again after they land.
                if(playerId in relay.cancelledPlayback && relay.cancelledPlayback[playerId].nonce == state.nonce && relay.cancelledPlayback[playerId].source == player) continue
                if(!player.IsOnGround() || Length2D(player.GetVelocity())>(state.traversal?260.0:80.0))
                {
                    relay.cancelledPlayback[playerId] <-
                    {
                        nonce = state.nonce, source = player
                    }
                    continue
                }
                int index = CeaikaEmotes_Index(expect string(state.emote))
                if(index<0) continue
                CeaikaEmoteDef emoteDef = CeaikaEmotes_Catalog()[index]
                if(GetConVarBool("em_music") && musicCount<16 && IsValid(localPlayer))
                {
                    float age = max(0.0, Time() - expect float(state.startedAt))
                    string request = CeaikaEmotes_BuildMusicRequest(player, localPlayer, age, emoteDef.track)
                    if (request != "")
                    {
                        if (music != "") music += ";"
                        music += request
                        musicCount++
                    }
                }
                bool inView = player == localPlayer || player == viewer || !IsValid(viewer) ||
                CeaikaEmotes_InView(player.GetOrigin()+<0, 0, 36>, viewOrigin, viewForward, viewRight, viewUp, tanX, tanY, playerId in relay.dancers ? 128.0 : 112.0)
                if(!inView)
                {
                    // dont animate off-screen dancers. keep their music and hiding state.
                    hidden = CeaikaEmotes_HideRequest(player, localPlayer, hidden)
                    relay.culled++
                    continue
                }
                if(playerId in relay.dancers && (relay.dancers[playerId].source != player || relay.dancers[playerId].nonce != state.nonce || relay.dancers[playerId].modelAsset != original)) CeaikaEmotes_Remove(playerId)
                if(!(playerId in relay.dancers))
                {
                    if(playerId in relay.retryAfter && Time()<expect float(relay.retryAfter[playerId])) continue
                    entity model
                    try
                    {
                        model = CreateClientSidePropDynamic(player.GetOrigin(), player.GetAngles(), CeaikaEmotes_Models()[original])
                        if(!IsValid(model)) continue
                        model.SetAlive(true)
                        SetTeam(model, player.GetTeam())
                        model.SetSkin(player.GetSkin())
                        model.SetCamo(player.GetCamo())
                        foreach(string groupName in ["mri", "body", "head", "torso", "legs"])
                        {
                            int group = player.FindBodyGroup(groupName)
                            if(group >= 0) model.SetBodygroup(group, player.GetBodyGroupState(group))
                        }
                        if(model.LookupSequence(emoteDef.sequence)<0) throw "Missing sequence: "+emoteDef.sequence
                        model.Anim_Play(emoteDef.sequence)
                        model.SetPlaybackRate(emoteDef.playbackRate)
                    }
                    catch(error)
                    {
                        if(IsValid(model)) model.Destroy()
                        relay.retryAfter[playerId] <- Time()+10.0
                        CeaikaEmotes_Error("Model creation failed: "+error)
                        continue
                    }
                    relay.dancers[playerId] <-
                    {
                        source = player, model = model, nonce = state.nonce, modelAsset = original, yaw = player.EyeAngles().y
                    }
                    print("[EmoteRelay] Rendering received emote in place for "+player.GetPlayerName())
                }
                entity model = expect entity(relay.dancers[playerId].model)
                if(!IsValid(model))
                {
                    CeaikaEmotes_Remove(playerId);
                    continue;
                }
                active[playerId] <- true
                SetTeam(model, player.GetTeam())
                model.SetOrigin(player.GetOrigin())
                float yaw = CeaikaEmotes_SmoothYaw(expect float(relay.dancers[playerId].yaw), player.EyeAngles().y, FrameTime())
                relay.dancers[playerId].yaw = yaw
                model.SetAngles(<0, yaw, 0>)
                float cycles = (Time()-expect float(state.startedAt))*emoteDef.playbackRate/emoteDef.duration
                model.SetCycle(cycles-floor(cycles))
                hidden = CeaikaEmotes_HideRequest(player, localPlayer, hidden)
                if(player == localPlayer) CeaikaEmotes_Camera(player, model)
            }
        }
        array<string> removed
        foreach(string playerId, var entry in relay.dancers) if(!(playerId in active)) removed.append(playerId)
        foreach(string playerId in removed) CeaikaEmotes_Remove(playerId)
        relay.pulse++
        SetConVarString("em_native_request", hidden == "" ? "" : relay.pulse+":"+hidden)
        SetConVarString("em_audio_request", music == "" ? "" : relay.pulse+":"+music)
        WaitFrame()
    }
}
