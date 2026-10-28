untyped
global function CeaikaEmotes_GetSyncTarget
global function CeaikaEmotes_Sync
global function CeaikaEmotes_Init
global function CeaikaEmotes_Play
global function CeaikaEmotes_Stop
global function CeaikaEmotes_Status
global function CeaikaEmotes_Probe
global function CeaikaEmotes_List
global function CeaikaEmotes_PropDebug
global function CeaikaEmotes_PairTest
global function CeaikaEmotes_IsEmoting
struct
{
    array<entity> debugProps
    bool requestInFlight = false
    string requestNonce = ""
    bool started = false
    string emote = ""
    string syncUid = ""
    string syncNonce = ""
    float syncStartedAt = 0.0
    string nonce = "idle"
    int serial = 0
    float lastReplyTime = -100.0
    float lastError = -100.0
    bool traversal = false
    bool duckHeld = false
    bool drawIdle = true
    int culled = 0
    int pulse = 0
    int uidReads = 0
    table playerUIDs
    table peers
    table clocks
    table retryAfter
    table cancelledPlayback
    table dancers
    // our dancer's facing while it's locked (freelook, joined pair); shared
    // through the relay so other players see it hold still too
    bool yawLocked = false
    float lockedYaw = 0.0
    bool requestHadYaw = false
    bool noYaw = false // the relay predates the yaw field
    // em_pairtest: a local stand-in partner for testing paired emotes alone
    string pairTestEmote = ""
    float pairTestStart = 0.0
    entity pairTestModel
} relay

string function CeaikaEmotes_PlayerUID(entity player)
{
    if(!IsValid(player)) return ""
    if(!(player in relay.playerUIDs))
    {
        // slots get reused when someone leaves. cache the actual entity.
        array<entity> stale
        foreach(entity cachedPlayer, var entry in relay.playerUIDs)
            if(!IsValid(cachedPlayer)) stale.append(cachedPlayer)
        foreach(entity cachedPlayer in stale) delete relay.playerUIDs[cachedPlayer]
        relay.playerUIDs[player] <- {uid = "", nextRead = 0.0}
    }
    var entry = relay.playerUIDs[player]
    if(entry.uid != "" || Time() < expect float(entry.nextRead))
        return expect string(entry.uid)

    // some Ion builds spam the console on every GetUID call.
    entry.nextRead = Time() + 2.0
    string uid = GetUID(player)
    relay.uidReads++
    if(uid != "" && uid != "0") entry.uid = uid
    return expect string(entry.uid)
}

void function CeaikaEmotes_Init()
{
    AddDestroyCallback("player", void function(entity player)
    {
        if(player in relay.playerUIDs) delete relay.playerUIDs[player]
    })
    foreach (asset nativeModel, asset model in CeaikaEmotes_Models()) PrecacheModel(model)
    foreach (CeaikaEmoteDef emoteDef in CeaikaEmotes_Catalog())
    {
        foreach (CeaikaEmoteExtra extra in emoteDef.extras)
        {
            if (extra.model != $"") PrecacheModel(extra.model)
            if (extra.fx != $"") PrecacheParticleSystem(extra.fx)
        }
    }
    foreach (string variant, asset model in CeaikaEmotes_DebugProps()) PrecacheModel(model)
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
    if(!IsValid(player) || !IsAlive(player) || !player.IsOnGround()) return
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
    // a partner part only plays by joining someone (hold the sync key on them)
    if(!emoteDef.listed && args.find("join") < 0)
    {
        print("[EmoteRelay] "+emoteDef.title+" is played by joining someone doing its partner emote.")
        return
    }
    if(!CeaikaEmotes_SupportsEmote(player, emoteDef.id))
    {
        print("[EmoteRelay] This Titan can't play "+emoteDef.title+" yet.")
        return
    }
    bool traversal = args.len()>1 && args[1] == "traversal"
    if(traversal && !emoteDef.traversal)
    {
        print("[EmoteRelay] "+emoteDef.title+" has no traversal version.");
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

// em_propdebug <part>|off [static]
// em_propdebug all [copies]
// spawns props in front of u to look at, no relay needed. parts come from the
// sequence names, prop_<part>_<emote id> (red, bluea, blueb, sax...). "all"
// spawns every part a few times over (3 by default, 8 max) side by side and
// out of sync, cus a bunch of copies at once is what crashed the renderer
void function CeaikaEmotes_PropDebug(array<string> args = [])
{
    foreach(entity old in relay.debugProps) if(IsValid(old)) old.Destroy()
    relay.debugProps.clear()
    string variant = args.len() > 0 ? args[0] : "red"
    if(variant == "off") return
    table props = {}
    foreach(CeaikaEmoteDef emoteDef in CeaikaEmotes_Catalog())
        foreach(CeaikaEmoteExtra extra in emoteDef.extras)
            if(extra.model != $"" && extra.sequence.find("prop_") == 0)
                props[extra.sequence.slice(5, extra.sequence.len()-emoteDef.id.len()-1)] <- [extra.model, extra.sequence]
    entity player = GetLocalClientPlayer()
    if((variant != "all" && !(variant in props)) || !IsValid(player))
    {
        string names = ""
        foreach(part, entry in props) names += part + "|"
        print("[EmoteRelay] em_propdebug " + names + "off [static], or em_propdebug all [copies]")
        return
    }
    array<string> parts = [variant]
    int copies = 1
    if(variant == "all")
    {
        parts.clear()
        foreach(part, entry in props) parts.append(expect string(part))
        copies = 3
        if(args.len() > 1)
        {
            try { copies = args[1].tointeger() } catch(error) {}
        }
        copies = copies < 1 ? 1 : (copies > 8 ? 8 : copies)
    }
    bool animate = !(args.len() > 1 && args[1] == "static")
    float yaw = player.EyeAngles().y
    vector forward = AnglesToForward(<0, yaw, 0>)
    vector right = AnglesToRight(<0, yaw, 0>)
    int created = 0
    for(int copy = 0; copy < copies; copy++)
    {
        vector origin = player.GetOrigin()+forward*160+right*(float(copy)-float(copies-1)*0.5)*90
        foreach(string part in parts)
        {
            entity prop = CreateClientSidePropDynamic(origin, <0, yaw+180, 0>, expect asset(props[part][0]))
            if(!IsValid(prop))
            {
                // only the server can precache models, so a path it doesnt know just fails
                print("[EmoteRelay] "+part+" not created: the server has not precached its model path.")
                continue
            }
            relay.debugProps.append(prop)
            created++
            string sequence = expect string(props[part][1])
            // a model that failed to load has no sequences, -1 here
            int index = prop.LookupSequence(sequence)
            if(copies == 1)
                print("[EmoteRelay] debug prop "+part+": entity=true model="+string(prop.GetModelName())+" sequence="+index)
            if(index >= 0 && animate)
            {
                prop.Anim_Play(sequence)
                prop.Anim_SetStartTime(Time()-float(copy)*1.3)
            }
        }
    }
    if(copies > 1)
        print("[EmoteRelay] debug props: "+created+" models, "+copies+" sets of "+parts.len()+" parts")
}

void function CeaikaEmotes_List(array<string> args = [])
{
    foreach(emoteDef in CeaikaEmotes_Listed())
    print("[EmoteRelay] "+emoteDef.title+": em_play "+emoteDef.id+(emoteDef.traversal ? " [traversal]" : ""))
}

void function CeaikaEmotes_Stop(array<string> args = [])
{
    CeaikaEmotes_ReleaseDuck()
    relay.traversal = false
    relay.emote = ""
    relay.syncUid = ""
    relay.syncNonce = ""
    relay.syncStartedAt = 0.0
    relay.serial++
    relay.nonce = format("stop_%d", relay.serial)
}

bool function CeaikaEmotes_IsEmoting()
{
    return relay.emote != ""
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
    print("[EmoteRelay] identity=unverified UID")
    print("[EmoteRelay] idle="+relay.drawIdle+" audioSleeping="+GetConVarInt("em_audio_idle")+" audioDeviceOpen="+GetConVarInt("em_audio_device"))
    print("[EmoteRelay] audioReady="+GetConVarInt("em_audio_ready")+" voices="+GetConVarInt("em_audio_voices"))
    print("[EmoteRelay] enabled="+GetConVarBool("em_enabled")+" HTTP="+NSIsHttpEnabled()+" peers="+relay.peers.len()+" visuals="+relay.dancers.len()+" culled="+relay.culled+" native="+GetConVarInt("em_native_ready")+" hidden="+GetConVarInt("em_native_hidden")+" replyAge="+(Time()-relay.lastReplyTime))
    print("[EmoteRelay] uidCached="+relay.playerUIDs.len()+" uidReads="+relay.uidReads)
    if(IsValid(player)) print("[EmoteRelay] Local player UID available="+(CeaikaEmotes_PlayerUID(player) != ""))
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
                string playerId = CeaikaEmotes_PlayerUID(player)
                if(playerId != "0" && playerId != "")
                {
                    if(!IsAlive(player)) CeaikaEmotes_Stop()
                    HttpRequest request
                    request.method = HttpRequestMethod.POST
                    request.url = url+"/sync"
                    request.headers =
                    {
                        Authorization = ["Bearer "+key]
                    }
                    table payload = {
                        uid = playerId, map = GetMapName(), emote = relay.emote, nonce = relay.nonce, traversal = relay.traversal
                    }
                    if(relay.syncUid != "")
                    {
                        payload.sync_uid <- relay.syncUid
                        payload.sync_nonce <- relay.syncNonce
                    }
                    relay.requestHadYaw = relay.emote != "" && relay.yawLocked && !relay.noYaw
                    if(relay.requestHadYaw) payload.yaw <- relay.lockedYaw
                    request.body = EncodeJSON(payload)
                    request.timeout = 4
                    relay.requestInFlight = true
                    relay.requestNonce = relay.nonce
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
        // an older relay rejects the yaw field; keep emoting without it
        if(result.statusCode == 400 && relay.requestHadYaw)
        {
            relay.noYaw = true
            print("[EmoteRelay] The relay doesn't take locked facing yet; others see your dancer follow your view.")
            return
        }
        if(result.statusCode == 409 && relay.syncUid != "" && relay.requestNonce == relay.nonce)
        {
            CeaikaEmotes_Stop()
            CeaikaEmotes_Error("That player changed or stopped their emote. Release the sync key and try again.")
        }
        CeaikaEmotes_Error("Relay returned HTTP "+result.statusCode);
        return;
    }
    try
    {
        var data = DecodeJSON(result.body)
        table next
        table nextClocks
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
            string timeline = "timeline" in peer ? expect string(peer.timeline) : playerId+":"+nonce
            // everyone on one playback shares one clock here. a clock per player
            // keeps each one's own network delay and they slowly drift apart
            if(timeline in relay.clocks) startedAt = expect float(relay.clocks[timeline])
            if(timeline in nextClocks) startedAt = expect float(nextClocks[timeline])
            nextClocks[timeline] <- startedAt
            bool musicSource = !("music" in peer) || peer.music == true
            entity localPlayer = GetLocalClientPlayer()
            if(IsValid(localPlayer) && playerId == CeaikaEmotes_PlayerUID(localPlayer) &&
               nonce == relay.nonce && relay.syncUid != "")
            {
                // old 0.4.0 relays dont send timelines, so take the clock of the
                // dancer u were looking at when the hold finished
                if(!("timeline" in peer)) startedAt = relay.syncStartedAt
                musicSource = false
            }
            next[playerId] <-
            {
                nonce = nonce, startedAt = startedAt, musicSource = musicSource, timeline = timeline,
                yaw = CeaikaEmotes_JsonFloat("yaw" in peer ? peer.yaw : null, -999.0), emote = CeaikaEmotes_Catalog()[index].id, traversal = (CeaikaEmotes_Catalog()[index].traversal && "traversal" in peer && peer.traversal == true)
            }
        }
        array<string> expired
        foreach(string playerId, var entry in relay.cancelledPlayback)
        if(!(playerId in next) || next[playerId].nonce != entry.nonce) expired.append(playerId)
        foreach(string playerId in expired) delete relay.cancelledPlayback[playerId]
        relay.peers = next
        relay.clocks = nextClocks
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
    CeaikaEmotes_ClearExtras(expect array(relay.dancers[playerId].extras))
    if(IsValid(relay.dancers[playerId].model)) relay.dancers[playerId].model.Destroy()
    delete relay.dancers[playerId]
}

// does this dancer's music play. whoever started the playback has it, if they
// stop someone synced to them (same timeline, so not a paired part) keeps it
// going from the same spot. lowest uid wins so every client picks the same guy
// and nobody hears it twice
bool function CeaikaEmotes_CarriesMusic(string playerId, var state)
{
    if(state.musicSource) return true
    string timeline = expect string(state.timeline)
    string carrier = ""
    foreach(string uid, var peer in relay.peers)
    {
        if(expect string(peer.timeline) != timeline) continue
        if(peer.musicSource) return false
        if(carrier == "" || uid < carrier) carrier = uid
    }
    return carrier == playerId
}

// is listener on the same playback as player, synced or paired with them
// (the relay marks joins with "-j"/"-p" on the timeline)
bool function CeaikaEmotes_DancingWith(entity listener, entity player)
{
    if(relay.emote == "" || !IsValid(listener) || !IsValid(player)) return false
    string a = CeaikaEmotes_PlayerUID(listener)
    string b = CeaikaEmotes_PlayerUID(player)
    if(!(a in relay.peers) || !(b in relay.peers)) return false
    return CeaikaEmotes_BaseTimeline(expect string(relay.peers[a].timeline)) == CeaikaEmotes_BaseTimeline(expect string(relay.peers[b].timeline))
}

string function CeaikaEmotes_BaseTimeline(string timeline)
{
    if(timeline.len() < 3) return timeline
    string mark = timeline.slice(timeline.len()-2)
    return mark == "-j" || mark == "-p" ? timeline.slice(0, timeline.len()-2) : timeline
}

// DecodeJSON gives 90 as an int and 90.5 as a float, and float() on a float
// throws "cannot cast float to float". that one cancelled every emote after 6s
float function CeaikaEmotes_JsonFloat(var value, float fallback)
{
    if(value == null) return fallback
    if(typeof(value) == "float") return expect float(value)
    if(typeof(value) == "int") return float(expect int(value))
    return fallback
}

// whoever joined the playback on timeline hug style, or "". the relay gives a
// joiner the leader's timeline + "-j"
string function CeaikaEmotes_JoinerOf(string timeline)
{
    foreach(string uid, var peer in relay.peers)
        if(expect string(peer.timeline) == timeline+"-j") return uid
    return ""
}

// the leader a joiner joined, or "". hug style joins are "-j", last forever
// style ones (both start together) are "-p"
string function CeaikaEmotes_LeaderOf(string timeline)
{
    if(timeline.len() < 3) return ""
    string mark = timeline.slice(timeline.len()-2)
    if(mark != "-j" && mark != "-p") return ""
    string lead = timeline.slice(0, timeline.len()-2)
    foreach(string uid, var peer in relay.peers)
        if(expect string(peer.timeline) == lead) return uid
    return ""
}

// seconds into a playback, before looping. a leader that waits for a partner
// (joinAt) holds there till someone joins and then goes by the joiner's clock,
// so the paired part plays together and ends together
float function CeaikaEmotes_PlayTime(CeaikaEmoteDef emoteDef, var state)
{
    float elapsed = max(0.0, (Time()-expect float(state.startedAt))*emoteDef.playbackRate)
    // a joiner of a waiting leader starts once the leader's intro is done
    string lead = CeaikaEmotes_LeaderOf(expect string(state.timeline))
    if(lead != "")
    {
        float together = CeaikaEmotes_Together(expect float(state.startedAt), relay.peers[lead])
        if(together >= 0.0) return max(0.0, (Time()-together)*emoteDef.playbackRate)
    }
    if(emoteDef.joinAt < 0.0) return elapsed
    float joined = CeaikaEmotes_JoinStart(expect string(state.timeline))
    if(joined < 0.0) return min(elapsed, emoteDef.joinAt)
    float together = max(joined, expect float(state.startedAt)+emoteDef.joinAt/emoteDef.playbackRate)
    if(Time() < together) return min(elapsed, emoteDef.joinAt)
    return emoteDef.joinAt + (Time()-together)*emoteDef.playbackRate
}

// when a waiting leader and someone who joined at `joined` start the paired
// part: the join, or the end of the leader's intro if they joined during it.
// -1 if the leader doesnt wait for anyone
float function CeaikaEmotes_Together(float joined, var leader)
{
    int index = CeaikaEmotes_Index(expect string(leader.emote))
    if(index < 0 || CeaikaEmotes_Catalog()[index].joinAt < 0.0) return -1.0
    CeaikaEmoteDef leaderDef = CeaikaEmotes_Catalog()[index]
    return max(joined, expect float(leader.startedAt)+leaderDef.joinAt/leaderDef.playbackRate)
}

// when someone joined the playback on timeline (or em_pairtest's fake partner
// on ours), -1 if nobody did
float function CeaikaEmotes_JoinStart(string timeline)
{
    string joiner = CeaikaEmotes_JoinerOf(timeline)
    if(joiner != "") return expect float(relay.peers[joiner].startedAt)
    if(relay.pairTestEmote != "" && timeline == CeaikaEmotes_OwnTimeline()) return relay.pairTestStart
    return -1.0
}

string function CeaikaEmotes_OwnTimeline()
{
    entity localPlayer = GetLocalClientPlayer()
    string uid = IsValid(localPlayer) ? CeaikaEmotes_PlayerUID(localPlayer) : ""
    return uid in relay.peers ? expect string(relay.peers[uid].timeline) : ""
}

// two people dancing a paired emote together. facing locks so nobody spins
// away from their partner mid hug
bool function CeaikaEmotes_PairJoined(string playerId, var state)
{
    string timeline = expect string(state.timeline)
    if(CeaikaEmotes_LeaderOf(timeline) != "" || CeaikaEmotes_JoinStart(timeline) >= 0.0) return true
    if(relay.pairTestEmote != "" && timeline == CeaikaEmotes_OwnTimeline()) return true
    foreach(string uid, var peer in relay.peers)
        if(expect string(peer.timeline) == timeline+"-p") return true
    return false
}

// em_pairtest [off]: while doing a paired emote a fake partner joins u, only
// on ur screen. for checking spacing/timing without bugging a friend
void function CeaikaEmotes_PairTest(array<string> args = [])
{
    if(args.len() > 0 && args[0] == "off")
    {
        CeaikaEmotes_ClearPairTest()
        return
    }
    int index = relay.emote == "" ? -1 : CeaikaEmotes_Index(relay.emote)
    if(index < 0 || CeaikaEmotes_Catalog()[index].partner == "")
    {
        print("[EmoteRelay] Start a paired emote (Hug, Last Forever) first, then em_pairtest.")
        return
    }
    CeaikaEmotes_ClearPairTest()
    relay.pairTestEmote = CeaikaEmotes_Catalog()[index].partner
    relay.pairTestStart = Time()
    print("[EmoteRelay] Test partner joined as "+relay.pairTestEmote+"; em_pairtest off removes it.")
}

void function CeaikaEmotes_ClearPairTest()
{
    if(IsValid(relay.pairTestModel)) relay.pairTestModel.Destroy()
    relay.pairTestEmote = ""
}

// puts the fake partner where a real one would stand
void function CeaikaEmotes_UpdatePairTest(entity localPlayer)
{
    if(relay.pairTestEmote == "") return
    string uid = IsValid(localPlayer) ? CeaikaEmotes_PlayerUID(localPlayer) : ""
    int index = CeaikaEmotes_Index(relay.pairTestEmote)
    if(relay.emote == "" || !(uid in relay.dancers) || !(uid in relay.peers) || index < 0)
    {
        CeaikaEmotes_ClearPairTest()
        return
    }
    CeaikaEmoteDef partner = CeaikaEmotes_Catalog()[index]
    var leader = relay.peers[uid]
    int leaderIndex = CeaikaEmotes_Index(expect string(leader.emote))
    if(leaderIndex < 0) return
    entity dancer = expect entity(relay.dancers[uid].model)
    // a waiting leader's partner starts when it joined; others share the start
    float together = CeaikaEmotes_Together(relay.pairTestStart, leader)
    float start = together >= 0.0 ? together : expect float(leader.startedAt)
    float playTime = max(0.0, (Time()-start)*partner.playbackRate)
    if(!partner.loops && playTime >= partner.duration)
    {
        CeaikaEmotes_ClearPairTest()
        return
    }
    if(!IsValid(relay.pairTestModel))
    {
        relay.pairTestModel = CreateClientSidePropDynamic(dancer.GetOrigin(), dancer.GetAngles(), dancer.GetModelName())
        relay.pairTestModel.SetAlive(true)
        relay.pairTestModel.Anim_Play(partner.sequence)
        relay.pairTestModel.SetPlaybackRate(partner.playbackRate)
    }
    float yaw = dancer.GetAngles().y
    relay.pairTestModel.SetOrigin(CeaikaEmotes_PairSpot(dancer.GetOrigin(), yaw, partner))
    relay.pairTestModel.SetAngles(<0, yaw+partner.pairYaw, 0>)
    float clipTime = CeaikaEmotes_ClipTime(partner, playTime)
    relay.pairTestModel.Anim_SetStartTime(Time()-clipTime/partner.playbackRate)
    relay.pairTestModel.SetCycle(clipTime/partner.duration)
}

// where the joiner stands for a leader at origin facing yaw
vector function CeaikaEmotes_PairSpot(vector origin, float yaw, CeaikaEmoteDef emoteDef)
{
    vector angles = <0, yaw, 0>
    return origin+AnglesToForward(angles)*emoteDef.pairOffset.x+AnglesToRight(angles)*emoteDef.pairOffset.y
}

// moves the joiner's dancer next to the leader like fortnite does. the joiner's
// real body is hidden while dancing so only the copy moves, not the player
void function CeaikaEmotes_PlacePartner(entity model, CeaikaEmoteDef emoteDef, var state)
{
    string lead = CeaikaEmotes_LeaderOf(expect string(state.timeline))
    if(lead == "") return
    foreach(entity leader in GetPlayerArray())
    {
        if(!IsValid(leader) || CeaikaEmotes_PlayerUID(leader) != lead) continue
        float yaw = lead in relay.dancers ? expect float(relay.dancers[lead].yaw) : leader.EyeAngles().y
        model.SetOrigin(CeaikaEmotes_DancerOrigin(model, CeaikaEmotes_PairSpot(leader.GetOrigin(), yaw, emoteDef)))
        model.SetAngles(<0, yaw+emoteDef.pairYaw, 0>)
        return
    }
}

// seconds into the clip for a playback that started elapsed seconds ago.
// montage exports play the start once, then loop from loopStart. padded clips
// have loopPad seconds of the loop copied past the end and we wrap in the
// middle of that copy, so if the engine's clock is a bit ahead or behind it
// still lands on loop frames instead of the wind up. that was the jitter on
// swagger strut btw
float function CeaikaEmotes_ClipTime(CeaikaEmoteDef emoteDef, float elapsed)
{
    float half = emoteDef.loopPad*0.5
    float wrap = emoteDef.duration-half
    if(elapsed < wrap || !emoteDef.loops) return clamp(elapsed, 0.0, emoteDef.duration)
    float loop = emoteDef.duration-emoteDef.loopPad-emoteDef.loopStart
    float t = elapsed-emoteDef.loopStart-half
    return emoteDef.loopStart+half+t-loop*floor(t/loop)
}

void function CeaikaEmotes_ClearExtras(array extras)
{
    foreach(var state in extras)
    {
        if(IsValid(state.prop)) state.prop.Destroy()
        state.prop = null
        if(state.fx != -1 && EffectDoesExist(expect int(state.fx))) EffectStop(expect int(state.fx), false, true)
        state.fx = -1
    }
}

// props and effects ride the dancer, not the hidden player, and only exist
// during their bit of the loop
void function CeaikaEmotes_UpdateExtras(entity model, CeaikaEmoteDef emoteDef, array extras, float clipTime, bool titan)
{
    foreach(int i, CeaikaEmoteExtra extra in emoteDef.extras)
    {
        var state = extras[i]
        if(titan && !extra.titans) continue
        if(state.failed)
        {
            if(Time() < expect float(state.retryAt)) continue
            state.failed = false
        }
        // on a Titan, an animated prop plays the clip built for that Titan's rig
        string sequence = extra.sequence
        if(titan && sequence != "")
            sequence += "_"+CeaikaEmotes_TitanRig(model.GetModelName())
        bool active = clipTime >= extra.start && (extra.stop < 0.0 || clipTime < extra.stop)
        int attachment = extra.attachment == "" ? 0 : model.LookupAttachment(extra.attachment)
        string parentAttachment = attachment > 0 ? extra.attachment : ""
        try
        {
            if(extra.model != $"")
            {
                if(active && !IsValid(state.prop))
                {
                    entity prop = CreateClientSidePropDynamic(model.GetOrigin(), model.GetAngles(), extra.model)
                    state.prop = prop
                    prop.SetParent(model, parentAttachment)
                    prop.SetLocalOrigin(extra.offset)
                    prop.SetLocalAngles(extra.angles)
                    if(sequence != "")
                    {
                        if(prop.LookupSequence(sequence) < 0) throw "Missing sequence: "+sequence
                        prop.Anim_Play(sequence)
                    }
                }
                else if(!active && IsValid(state.prop))
                {
                    state.prop.Destroy()
                    state.prop = null
                }
                if(active && sequence != "" && IsValid(state.prop))
                {
                    // same clock as the dancer, loop point and all
                    state.prop.Anim_SetStartTime(Time()-clipTime/emoteDef.playbackRate)
                    state.prop.SetCycle(clipTime/emoteDef.duration)
                }
            }
            if(extra.fx != $"")
            {
                bool running = state.fx != -1 && EffectDoesExist(expect int(state.fx))
                if(active && !running)
                    state.fx = StartParticleEffectOnEntity(model, GetParticleSystemIndex(extra.fx), attachment > 0 ? FX_PATTACH_POINT_FOLLOW : FX_PATTACH_ABSORIGIN_FOLLOW, attachment)
                else if(!active && running)
                {
                    EffectStop(expect int(state.fx), false, true)
                    state.fx = -1
                }
            }
        }
        catch(error)
        {
            // a broken prop shouldnt kill the whole dance. printed straight away
            // (once per dancer) cus the throttled error log eats it if a relay
            // message just came in. and dont leave a half made prop on the
            // dancer, it used to sit there frozen off the hands. bin it, retry
            if(IsValid(state.prop)) state.prop.Destroy()
            state.prop = null
            state.failed = true
            state.retryAt = Time()+1.0
            state.tries++
            if(state.tries == 1) print("[EmoteRelay] "+emoteDef.id+" extra "+i+" ("+string(extra.model)+") failed: "+error)
        }
    }
}

void function CeaikaEmotes_ClearCamera()
{
    SetConVarString("em_camera_request", "0")
}

void function CeaikaEmotes_Camera(entity player, entity model)
{
    SetConVarString("em_camera_request", clGlobal.isMenuOpen ? "0" : (player.IsTitan() ? "2" : "1"))
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
// rough is it on screen check, a bit generous so arms flailing at the edge
// dont pop. fov is the engine's 4:3 one, wider screens just get more sideways
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

// voice 1 is a dancer's intro, kept apart from their music loop (voice 0).
string function CeaikaEmotes_BuildMusicRequest(entity player, entity listener, float age, int track, int voice = 0)
{
    float volume = clamp(GetConVarFloat("em_volume"), 0.0, 1.0)
    float gain = volume * clamp(GetConVarFloat("sound_volume"), 0.0, 1.0)
    float pan = 0.0
    // synced or paired with them: the shared music plays as your own does,
    // centred and at full volume, not from their direction
    bool ownEmote = player == listener || CeaikaEmotes_DancingWith(listener, player)

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

    return format("%d,%.4f,%.4f,%.4f,%d,%d", player.GetEntIndex()+voice*4096, age, gain, pan, ownEmote ? 1 : 0, track)
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
        foreach(string playerId, var entry in relay.dancers)
        {
            CeaikaEmotes_ClearExtras(expect array(entry.extras))
            if(IsValid(entry.model)) entry.model.Destroy()
        }
        CeaikaEmotes_ClearPairTest()
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
        (!IsAlive(localPlayer) || !localPlayer.IsOnGround() || localPlayer.IsInputCommandHeld(IN_JUMP) ||
        localPlayer.IsInputCommandHeld(IN_ATTACK) ||
        (localPlayer.IsTitan() && localPlayer.IsInputCommandHeld(IN_MELEE)) ||
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
                if(!IsValid(player) || !IsAlive(player)) continue
                string playerId = CeaikaEmotes_PlayerUID(player)
                if(!(playerId in relay.peers)) continue
                if(player == localPlayer && relay.emote == "") continue
                asset original = player.GetModelName()
                if(!(original in CeaikaEmotes_Models())) continue
                var state = relay.peers[playerId]
                if(!CeaikaEmotes_SupportsEmote(player, expect string(state.emote))) continue
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
                if(!emoteDef.loops && CeaikaEmotes_PlayTime(emoteDef, state) >= emoteDef.duration)
                {
                    // a one-shot emote has played through: end ours, and drop
                    // theirs until they start another (their client ends it too)
                    if(player == localPlayer) CeaikaEmotes_Stop()
                    else relay.cancelledPlayback[playerId] <-
                    {
                        nonce = state.nonce, source = player
                    }
                    continue
                }
                if(CeaikaEmotes_CarriesMusic(playerId, state) && GetConVarBool("em_music") && IsValid(localPlayer))
                {
                    // old dlls say 0 and only have the 16 built in tracks. asking for
                    // a track the dll doesnt have mutes everyone, not just that one
                    int tracks = GetConVarInt("em_audio_tracks") > 0 ? GetConVarInt("em_audio_tracks") : 16
                    float age = max(0.0, Time() - expect float(state.startedAt))
                    float musicAge = emoteDef.introTrack >= 0 && emoteDef.musicAfterIntro ? age-emoteDef.introDuration : age-emoteDef.musicDelay
                    array<int> voiceTracks = [emoteDef.track, emoteDef.introTrack]
                    array<float> voiceAges = [musicAge, age]
                    foreach(int voice, int track in voiceTracks)
                    {
                        // intros play once, the dll wont loop them
                        if(track < 0 || track >= tracks || voiceAges[voice] < 0.0 || musicCount >= 16) continue
                        if(voice == 1 && voiceAges[voice] >= emoteDef.introDuration) continue
                        string request = CeaikaEmotes_BuildMusicRequest(player, localPlayer, voiceAges[voice], track, voice)
                        if (request != "")
                        {
                            if (music != "") music += ";"
                            music += request
                            musicCount++
                        }
                    }
                }
                bool inView = player == localPlayer || player == viewer || !IsValid(viewer) ||
                CeaikaEmotes_InView(player.GetOrigin()+(player.IsTitan() ? <0, 0, 140> : <0, 0, 36>), viewOrigin, viewForward, viewRight, viewUp, tanX, tanY, player.IsTitan() ? 350.0 : (playerId in relay.dancers ? 128.0 : 112.0))
                if(!inView)
                {
                    // dont animate off-screen dancers. keep their music and hiding state.
                    // keep the dancer itself too: the engine doesnt draw or pose it
                    // off screen anyway, and rebuilding it (props and all) every time
                    // someone turned around was most of the cost
                    hidden = CeaikaEmotes_HideRequest(player, localPlayer, hidden)
                    if(playerId in relay.dancers) active[playerId] <- true
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
                    array extras
                    foreach(CeaikaEmoteExtra extra in emoteDef.extras) extras.append({prop = null, fx = -1, failed = false, retryAt = 0.0, tries = 0})
                    relay.dancers[playerId] <-
                    {
                        source = player, model = model, nonce = state.nonce, modelAsset = original, yaw = player.EyeAngles().y, extras = extras
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
                model.SetOrigin(CeaikaEmotes_DancerOrigin(model, player.GetOrigin()))
                float facing = player.EyeAngles().y
                if(player == localPlayer)
                {
                    // freelook or a joined pair: the camera orbits, the dancer holds
                    bool locked = CeaikaEmotes_FreelookHeld() || CeaikaEmotes_PairJoined(playerId, state)
                    if(locked && !relay.yawLocked) relay.lockedYaw = expect float(relay.dancers[playerId].yaw)
                    relay.yawLocked = locked
                    if(locked) facing = relay.lockedYaw
                }
                else if(expect float(state.yaw) > -900.0)
                    facing = expect float(state.yaw)
                float yaw = CeaikaEmotes_SmoothYaw(expect float(relay.dancers[playerId].yaw), facing, FrameTime())
                relay.dancers[playerId].yaw = yaw
                model.SetAngles(<0, yaw, 0>)
                if(emoteDef.pairOffset != <0, 0, 0>) CeaikaEmotes_PlacePartner(model, emoteDef, state)
                float clipTime = CeaikaEmotes_ClipTime(emoteDef, CeaikaEmotes_PlayTime(emoteDef, state))
                // Anim_Play runs its own clock and it overwrites SetCycle the
                // next time the engine ticks, so move the clock itself. letting
                // the engine wrap on its own replays a montage's wind up
                try
                {
                    model.Anim_SetStartTime(Time()-clipTime/emoteDef.playbackRate)
                }
                catch(error)
                {
                    // a clip ported with Loop off stops being a scripted
                    // animation once it reaches its end; start it again
                    model.Anim_Play(emoteDef.sequence)
                    model.SetPlaybackRate(emoteDef.playbackRate)
                    model.Anim_SetStartTime(Time()-clipTime/emoteDef.playbackRate)
                }
                model.SetCycle(clipTime/emoteDef.duration)
                if(emoteDef.extras.len() > 0)
                    CeaikaEmotes_UpdateExtras(model, emoteDef, expect array(relay.dancers[playerId].extras), clipTime, player.IsTitan())
                hidden = CeaikaEmotes_HideRequest(player, localPlayer, hidden)
                if(player == localPlayer) CeaikaEmotes_Camera(player, model)
            }
        }
        CeaikaEmotes_UpdatePairTest(localPlayer)
        if(relay.emote == "") relay.yawLocked = false
        array<string> removed
        foreach(string playerId, var entry in relay.dancers) if(!(playerId in active)) removed.append(playerId)
        foreach(string playerId in removed) CeaikaEmotes_Remove(playerId)
        relay.pulse++
        SetConVarString("em_native_request", hidden == "" ? "" : relay.pulse+":"+hidden)
        SetConVarString("em_audio_request", music == "" ? "" : relay.pulse+":"+music)
        WaitFrame()
    }
}

// what u get when u hold the sync key on someone doing emote: the same one,
// or the other half if its paired
string function CeaikaEmotes_JoinEmote(string emote)
{
    int index = CeaikaEmotes_Index(emote)
    if(index < 0 || CeaikaEmotes_Catalog()[index].partner == "") return emote
    return CeaikaEmotes_Catalog()[index].partner
}

// the player u could sync with rn: close, actually emoting, not cancelled
entity function CeaikaEmotes_SyncTarget()
{
    entity localPlayer = GetLocalClientPlayer()
    entity nearest
    if(!IsValid(localPlayer) || !IsAlive(localPlayer) || !localPlayer.IsOnGround() ||
       !GetConVarBool("em_enabled") || GetConVarInt("em_native_ready") != 1 ||
       Time()-relay.lastReplyTime >= 6.0) return nearest
    if(relay.emote != "" || clGlobal.isMenuOpen || CeaikaEmotes_IsWheelOpen()) return nearest
    // the nearest dancer within reach, no need to aim at them; still not
    // through walls
    vector eye = localPlayer.EyePosition()
    float best = 150.0
    foreach(entity player in GetPlayerArray())
    {
        if(player == localPlayer || !IsValid(player) || !IsAlive(player) || !player.IsOnGround()) continue
        string uid = CeaikaEmotes_PlayerUID(player)
        if(!(uid in relay.peers)) continue
        var state = relay.peers[uid]
        int index = CeaikaEmotes_Index(expect string(state.emote))
        if(index < 0) continue
        CeaikaEmoteDef emoteDef = CeaikaEmotes_Catalog()[index]
        if(!emoteDef.listed && emoteDef.partner == "") continue
        // a waiting leader can be joined straight away (the pair starts once
        // their intro is done), but only by one partner
        if(emoteDef.joinAt >= 0.0 && CeaikaEmotes_JoinerOf(expect string(state.timeline)) != "") continue
        if(!CeaikaEmotes_SupportsEmote(localPlayer, CeaikaEmotes_JoinEmote(expect string(state.emote))) ||
           !CeaikaEmotes_SupportsEmote(player, expect string(state.emote))) continue
        if(Length2D(player.GetVelocity()) > (state.traversal ? 260.0 : 80.0)) continue
        if(uid in relay.cancelledPlayback && relay.cancelledPlayback[uid].nonce == state.nonce &&
           relay.cancelledPlayback[uid].source == player) continue
        float distance = Distance(localPlayer.GetOrigin(), player.GetOrigin())
        if(distance > best) continue
        vector point = player.GetWorldSpaceCenter()
        // dancers and their props arent walls
        array<entity> ignored = [localPlayer, player]
        foreach(string dancerUid, var dancer in relay.dancers)
            if(IsValid(dancer.model)) ignored.append(expect entity(dancer.model))
        TraceResults sight = TraceLine(eye, point, ignored, TRACE_MASK_SOLID, TRACE_COLLISION_GROUP_NONE)
        if(sight.startSolid || sight.fraction < 0.99) continue
        best = distance
        nearest = player
    }
    return nearest
}
table function CeaikaEmotes_GetSyncTarget()
{
    entity target = CeaikaEmotes_SyncTarget()
    if(!IsValid(target)) return {}
    string uid = CeaikaEmotes_PlayerUID(target)
    string emote = expect string(relay.peers[uid].emote)
    return {uid = uid, nonce = relay.peers[uid].nonce, name = target.GetPlayerName(),
            paired = CeaikaEmotes_JoinEmote(emote) != emote}
}
void function CeaikaEmotes_Sync(string uid, string nonce)
{
    // check again, they mightve stopped or walked off during the hold
    entity target = CeaikaEmotes_SyncTarget()
    if(!IsValid(target) || CeaikaEmotes_PlayerUID(target) != uid || !(uid in relay.peers)) return
    var state = relay.peers[uid]
    if(state.nonce != nonce) return
    // the relay accepts the partner part on the target's timeline too
    array<string> args = [CeaikaEmotes_JoinEmote(expect string(state.emote))]
    if(state.traversal) args.append("traversal")
    args.append("join")
    string previousNonce = relay.nonce
    CeaikaEmotes_Play(args)
    if(relay.nonce == previousNonce) return
    relay.syncUid = uid
    relay.syncNonce = nonce
    relay.syncStartedAt = expect float(state.startedAt)
}
