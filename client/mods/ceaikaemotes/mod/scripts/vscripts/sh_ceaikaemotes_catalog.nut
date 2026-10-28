global function CeaikaEmotes_Catalog
global function CeaikaEmotes_Index
global function CeaikaEmotes_Listed
global function CeaikaEmotes_KeyCode
global function CeaikaEmotes_BindableKeys
global function CeaikaEmotes_PropModels
global function CeaikaEmotes_DebugProps
// a prop or particle effect the dancer carries. times are seconds into each
// loop of the clip, stop < 0 keeps it the whole loop
global struct CeaikaEmoteExtra
{
    asset model = $""
    asset fx = $""
    string attachment = ""
    vector offset = <0, 0, 0>
    vector angles = <0, 0, 0>
    float start = 0.0
    float stop = -1.0
    // animated prop from build_prop.py. its sequence is made in the dancer's
    // model space and runs on the emote's clock
    string sequence = ""
    // pilot-sized props look wrong on a Titan
    bool titans = true
}
global struct CeaikaEmoteDef
{
    string id
    string title
    string sequence
    float duration
    float playbackRate
    bool traversal
    // music loop: index into the DLL's built-in tracks (0-15), then the lines
    // of plugins/ceaikaemotes/tracks.txt (16+); -1 plays no music
    int track = -1
    // one-shot intro sound (a "once" line in tracks.txt), its length, and
    // whether the music loop waits for it to finish
    int introTrack = -1
    float introDuration = 0.0
    bool musicAfterIntro = true
    // when the music doesn't wait for the intro: seconds before it starts
    float musicDelay = 0.0
    // seconds into the clip where the loop begins; earlier frames play once
    float loopStart = 0.0
    // seconds of loop repeated after the clip's end (refine_clip.py); the
    // loop wraps in the middle of that copy, see CeaikaEmotes_ClipTime
    float loopPad = 0.0
    // false for a one-shot emote: it plays through once and ends itself
    bool loops = true
    // false when the clip is missing from the Titan libraries (pilot-only)
    bool titans = true
    // paired emotes: holding the sync key on someone playing this emote joins
    // them on their timing with the partner part instead of copying it
    string partner = ""
    // false for a part only reachable by joining (not on the wheel or em_play)
    bool listed = true
    // a leader that waits for a partner (Pat Pat): holds at this clip time
    // until someone joins, then both play the rest together; -1 never waits
    float joinAt = -1.0
    // where the joiner gets put, from the leader: units forward and to the
    // leader's right, and which way it faces compared to them (hug: 56 in
    // front turned 180 so the hands meet, 74 was way too far). zero = the
    // joiner just dances where they stand
    vector pairOffset = <0, 0, 0>
    float pairYaw = 0.0
    array<CeaikaEmoteExtra> extras
}
struct
{
    array<CeaikaEmoteDef> entries
    array<CeaikaEmoteDef> listed
    table<string, int> index
    bool ready = false
    table<string, int> keys
} file

// key names u can type into mod settings (em_wheel_bind, em_sync_bind,
// em_freelook_bind): letters, digits, F1-F12, KP0-9, SHIFT, CTRL, ALT, SPACE,
// MOUSE3 and the rest below. caps and spaces dont matter
table<string, int> function CeaikaEmotes_KeyNames()
{
    if (file.keys.len() == 0)
        file.keys =
        {
            ["A"] = KEY_A,
            ["B"] = KEY_B,
            ["C"] = KEY_C,
            ["D"] = KEY_D,
            ["E"] = KEY_E,
            ["F"] = KEY_F,
            ["G"] = KEY_G,
            ["H"] = KEY_H,
            ["I"] = KEY_I,
            ["J"] = KEY_J,
            ["K"] = KEY_K,
            ["L"] = KEY_L,
            ["M"] = KEY_M,
            ["N"] = KEY_N,
            ["O"] = KEY_O,
            ["P"] = KEY_P,
            ["Q"] = KEY_Q,
            ["R"] = KEY_R,
            ["S"] = KEY_S,
            ["T"] = KEY_T,
            ["U"] = KEY_U,
            ["V"] = KEY_V,
            ["W"] = KEY_W,
            ["X"] = KEY_X,
            ["Y"] = KEY_Y,
            ["Z"] = KEY_Z,
            ["0"] = KEY_0,
            ["1"] = KEY_1,
            ["2"] = KEY_2,
            ["3"] = KEY_3,
            ["4"] = KEY_4,
            ["5"] = KEY_5,
            ["6"] = KEY_6,
            ["7"] = KEY_7,
            ["8"] = KEY_8,
            ["9"] = KEY_9,
            ["F1"] = KEY_F1,
            ["F2"] = KEY_F2,
            ["F3"] = KEY_F3,
            ["F4"] = KEY_F4,
            ["F5"] = KEY_F5,
            ["F6"] = KEY_F6,
            ["F7"] = KEY_F7,
            ["F8"] = KEY_F8,
            ["F9"] = KEY_F9,
            ["F10"] = KEY_F10,
            ["F11"] = KEY_F11,
            ["F12"] = KEY_F12,
            ["KP0"] = KEY_PAD_0,
            ["KP1"] = KEY_PAD_1,
            ["KP2"] = KEY_PAD_2,
            ["KP3"] = KEY_PAD_3,
            ["KP4"] = KEY_PAD_4,
            ["KP5"] = KEY_PAD_5,
            ["KP6"] = KEY_PAD_6,
            ["KP7"] = KEY_PAD_7,
            ["KP8"] = KEY_PAD_8,
            ["KP9"] = KEY_PAD_9,
            ["SHIFT"] = KEY_LSHIFT,
            ["LSHIFT"] = KEY_LSHIFT,
            ["RSHIFT"] = KEY_RSHIFT,
            ["CTRL"] = KEY_LCONTROL,
            ["LCTRL"] = KEY_LCONTROL,
            ["RCTRL"] = KEY_RCONTROL,
            ["ALT"] = KEY_LALT,
            ["LALT"] = KEY_LALT,
            ["RALT"] = KEY_RALT,
            ["SPACE"] = KEY_SPACE,
            ["TAB"] = KEY_TAB,
            ["ENTER"] = KEY_ENTER,
            ["BACKSPACE"] = KEY_BACKSPACE,
            ["CAPSLOCK"] = KEY_CAPSLOCK,
            ["INSERT"] = KEY_INSERT,
            ["DELETE"] = KEY_DELETE,
            ["HOME"] = KEY_HOME,
            ["END"] = KEY_END,
            ["PAGEUP"] = KEY_PAGEUP,
            ["PAGEDOWN"] = KEY_PAGEDOWN,
            ["UP"] = KEY_UP,
            ["DOWN"] = KEY_DOWN,
            ["LEFT"] = KEY_LEFT,
            ["RIGHT"] = KEY_RIGHT,
            ["MINUS"] = KEY_MINUS,
            ["EQUAL"] = KEY_EQUAL,
            ["COMMA"] = KEY_COMMA,
            ["PERIOD"] = KEY_PERIOD,
            ["SLASH"] = KEY_SLASH,
            ["SEMICOLON"] = KEY_SEMICOLON,
            ["APOSTROPHE"] = KEY_APOSTROPHE,
            ["BACKSLASH"] = KEY_BACKSLASH,
            ["LBRACKET"] = KEY_LBRACKET,
            ["RBRACKET"] = KEY_RBRACKET,
            ["BACKQUOTE"] = KEY_BACKQUOTE,
            ["MOUSE3"] = MOUSE_MIDDLE,
            ["MMB"] = MOUSE_MIDDLE
        }
    return file.keys
}

// the game key for a typed name, -1 if its empty, NONE or not a key i know
int function CeaikaEmotes_KeyCode(string name)
{
    name = StringReplace(name.toupper(), " ", "", true)
    table<string, int> keys = CeaikaEmotes_KeyNames()
    return name in keys ? keys[name] : -1
}

array<int> function CeaikaEmotes_BindableKeys()
{
    array<int> codes
    foreach (string name, int code in CeaikaEmotes_KeyNames())
        if (!codes.contains(code)) codes.append(code)
    return codes
}

// what the wheel shows, a to z. partner parts arent on it, u get those by joining
array<CeaikaEmoteDef> function CeaikaEmotes_Listed()
{
    if (file.listed.len() == 0)
    {
        foreach (CeaikaEmoteDef def in CeaikaEmotes_Catalog())
            if (def.listed) file.listed.append(def)
        file.listed.sort(CeaikaEmotes_ByTitle)
    }
    return file.listed
}

int function CeaikaEmotes_ByTitle(CeaikaEmoteDef a, CeaikaEmoteDef b)
{
    string x = a.title.tolower()
    string y = b.title.tolower()
    if (x < y) return -1
    return x > y ? 1 : 0
}
array<CeaikaEmoteDef> function CeaikaEmotes_Catalog()
{
    if (file.ready) return file.entries
    file.ready = true
    {
        CeaikaEmoteDef def
        def.id = "bbd_traversal"
        def.title = "Billy Bounce"
        def.sequence = "emote_bbd_traversal"
        def.duration = 11.20009899011823
        def.playbackRate = 0.9970423776833528
        def.traversal = true
        def.track = 0
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_dancemoves"
        def.title = "Dance Moves"
        def.sequence = "emote_emote_dancemoves"
        def.duration = 6.8
        def.playbackRate = 0.9444444444444444
        def.traversal = false
        def.track = 2
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_electroshuffle"
        def.title = "Electro Shuffle"
        def.sequence = "emote_emote_electroshuffle"
        def.duration = 8.400131519552387
        def.playbackRate = 1.1114685533260733
        def.traversal = false
        def.track = 3
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "electroswing_auto"
        def.title = "Electro Swing"
        def.sequence = "emote_electroswing_auto"
        def.duration = 8.0
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 4
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_floss"
        def.title = "Floss"
        def.sequence = "emote_emote_floss"
        def.duration = 1.5673469387755101
        def.playbackRate = 0.9389620339830357
        def.traversal = false
        def.track = 5
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_freestylin"
        def.title = "Freestylin'"
        def.sequence = "emote_emote_freestylin"
        def.duration = 6.233510086007717
        def.playbackRate = 0.9877344948844279
        def.traversal = false
        def.track = 6
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "griddy_traversal"
        def.title = "Griddy"
        def.sequence = "emote_griddy_traversal"
        def.duration = 6.033515520427016
        def.playbackRate = 0.9891000604695411
        def.traversal = true
        def.track = 1
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_hype"
        def.title = "Hype"
        def.sequence = "emote_emote_hype"
        def.duration = 3.5003113933694374
        def.playbackRate = 1.042460651428652
        def.traversal = false
        def.track = 7
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_oj"
        def.title = "Orange Justice"
        def.sequence = "emote_emote_oj"
        def.duration = 6.46683660883151
        def.playbackRate = 1.024580113272692
        def.traversal = false
        def.track = 8
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_rambunctious"
        def.title = "Rambunctious"
        def.sequence = "emote_emote_rambunctious"
        def.duration = 3.633633779322057
        def.playbackRate = 0.9909910307241974
        def.traversal = false
        def.track = 10
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_technozombie"
        def.title = "Reanimated"
        def.sequence = "emote_emote_technozombie"
        def.duration = 4.800228425471233
        def.playbackRate = 1.0000475886398403
        def.traversal = false
        def.track = 11
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_smoothmoves"
        def.title = "Smooth Moves"
        def.sequence = "emote_emote_smoothmoves"
        def.duration = 9.566782208965414
        def.playbackRate = 0.9965398134338973
        def.traversal = false
        def.track = 12
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_squatkick"
        def.title = "Squat Kick"
        def.sequence = "emote_emote_squatkick"
        def.duration = 11.600095044234367
        def.playbackRate = 0.8101780138044147
        def.traversal = false
        def.track = 13
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_takethel"
        def.title = "Take The L"
        def.sequence = "emote_emote_takethel"
        def.duration = 0.768
        def.playbackRate = 0.9727996622223395
        def.traversal = false
        def.track = 14
        file.entries.append(def)
    }
    // new emotes go below, artifacts/emotes/tools/add_to_ceaikaemotes.py prints
    // the entries for u. one with a hand prop and an effect looks like this
    // (made up paths, and drop def.titans = false once the titan libs have it):
    // {
    //     CeaikaEmoteDef def
    //     def.id = "emote_example"
    //     def.title = "Example"
    //     def.sequence = "emote_emote_example"
    //     def.duration = 4.0
    //     def.playbackRate = 1.0
    //     def.titans = false
    //     CeaikaEmoteExtra prop
    //     prop.model = $"models/your/prop.mdl"
    //     prop.attachment = "l_hand"
    //     prop.start = 0.5
    //     prop.stop = 3.5
    //     def.extras.append(prop)
    //     CeaikaEmoteExtra effect
    //     effect.fx = $"P_your_effect"
    //     effect.attachment = "CHESTFOCUS"
    //     def.extras.append(effect)
    //     file.entries.append(def)
    // }
    {
        CeaikaEmoteDef def
        def.id = "emote_voidredemption"
        def.title = "I'm A Mystery"
        def.sequence = "emote_emote_voidredemption"
        def.duration = 7.6833691721936965
        def.playbackRate = 1.0
        // frames 0-21 are a wind-up; the last frame matches frame 22
        def.loopStart = 0.3658747224854141
        def.traversal = false
        def.track = 16
        def.introTrack = 17
        def.introDuration = 0.4
        // rings and orbs in 3 parts, the whole thing has too many bones for
        // the renderer. each one sits on a stock path every server precaches
        // but never shows, see build_prop.py
        foreach(string part, asset model in CeaikaEmotes_DebugProps())
        {
            CeaikaEmoteExtra prop
            prop.model = model
            prop.sequence = "prop_" + part + "_emote_voidredemption"
            def.extras.append(prop)
        }
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_epicsaxguy"
        def.title = "Phone It In"
        def.sequence = "emote_emote_epicsaxguy"
        def.duration = 7.333483630499354
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 18
        // the cymbal hits at the start; the sax loop comes in 0.25s later
        def.introTrack = 19
        def.introDuration = 1.099
        def.musicAfterIntro = false
        def.musicDelay = 0.25
        // the sax stays at the mouth (follows the head) with both hands IK'd
        // onto it, pilots and titans (build_prop.py --titans adds the titan
        // clips). textures are in ceaika_emote_epicsaxguy.rpak
        CeaikaEmoteExtra prop
        prop.model = $"models/test/brad/store_card_relic.mdl"
        prop.sequence = "prop_sax_emote_epicsaxguy"
        def.extras.append(prop)
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_sad_trombone"
        def.title = "Sad Trombone"
        def.sequence = "emote_emote_sad_trombone"
        def.duration = 6.733497151736163
        def.playbackRate = 1.0
        def.traversal = false
        def.loops = false
        // fortnite plays the wah wah once, so do we
        def.introTrack = 20
        def.introDuration = 6.177333333333333
        // trombone follows the head like the sax, slide animated, both hands
        // IK'd on. textures in ceaika_emote_sad_trombone.rpak
        CeaikaEmoteExtra prop
        prop.model = $"models/test/brad/store_card_angel_city.mdl"
        prop.sequence = "prop_trombone_emote_sad_trombone"
        def.extras.append(prop)
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_alors"
        def.title = "Alors On Dance"
        def.sequence = "emote_emote_alors"
        def.duration = 5.266875087900461
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 21
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_boogiedown"
        def.title = "Boogie Down"
        def.sequence = "emote_emote_boogiedown"
        def.duration = 5.425564034266973
        def.playbackRate = 1.0
        def.loopStart = 0.6616541505203626
        def.loopPad = 0.39699249031221756
        def.traversal = false
        def.track = 22
        def.introTrack = 23
        def.introDuration = 0.5555625
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_breakin"
        def.title = "Breakin'"
        def.sequence = "emote_emote_breakin"
        def.duration = 7.23348587212955
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 24
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_downward"
        def.title = "Downward"
        def.sequence = "emote_emote_downward"
        def.duration = 11.433429799986218
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 25
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_fireball"
        def.title = "Fireball"
        def.sequence = "emote_emote_fireball"
        def.duration = 9.231960181836953
        def.playbackRate = 1.0
        def.loopStart = 1.0626716756071313
        def.loopPad = 0.39850187835267425
        def.traversal = true
        def.track = 26
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_flamenco"
        def.title = "Flamenco"
        def.sequence = "emote_emote_flamenco"
        def.duration = 10.527675424944261
        def.playbackRate = 1.0
        def.loopStart = 1.162361639978073
        def.loopPad = 0.39852399084962503
        def.traversal = false
        def.track = 27
        def.introTrack = 28
        def.introDuration = 1.0310625
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_freeflow"
        def.title = "Free Flow"
        def.sequence = "emote_emote_freeflow"
        // the clip is a 1.96s intro section and a loop (refine_clip.py
        // --loop-frame 59, padded)
        def.duration = 10.232098958184494
        def.playbackRate = 1.0
        def.loopStart = 1.960044930301575
        def.loopPad = 0.39865320616303224
        def.traversal = false
        def.track = 29
        def.introTrack = 30
        def.introDuration = 3.2049583333333334
        // the intro's music is one bar (4 beats of the 121.7 BPM loop); the
        // rest of the file is its reverb tail, which the loop plays over
        def.musicAfterIntro = false
        def.musicDelay = 1.972
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_gangnam"
        def.title = "Gangnam Style"
        def.sequence = "emote_emote_gangnam"
        def.duration = 7.200152546119665
        def.playbackRate = 1.0
        def.traversal = true
        def.track = 31
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_macarena"
        def.title = "Macarena"
        def.sequence = "emote_emote_macarena"
        def.duration = 9.266785745848198
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 32
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_pompous"
        def.title = "Swagger Strut"
        def.sequence = "emote_emote_pompous"
        def.duration = 1.7581394724951642
        def.playbackRate = 1.0
        def.loopStart = 0.5860464908317214
        def.loopPad = 0.39069766055448096
        def.traversal = true
        def.track = 33
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_pumpernickel"
        def.title = "Pumpernickel"
        def.sequence = "emote_emote_pumpernickel"
        def.duration = 3.5003113933694374
        // the clip is 8 beats at 137 BPM but the music is 143 BPM (32 beats
        // in 13.427s); Fortnite plays it faster so 4 loops fill the music loop
        def.playbackRate = 1.042801
        def.traversal = true
        def.track = 34
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_robot"
        def.title = "Robot"
        def.sequence = "emote_emote_robot"
        def.duration = 9.800112254765853
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 35
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_rollie"
        def.title = "Rollie"
        def.sequence = "emote_emote_rollie"
        def.duration = 13.233417039998137
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 36
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_scenario"
        def.title = "Scenario"
        def.sequence = "emote_emote_scenario"
        def.duration = 8.100135869444774
        def.playbackRate = 1.0
        def.traversal = false
        def.track = 37
        file.entries.append(def)
    }
    {
        // last forever is a duo (ayo and teo), holding the sync key on one
        // joins them as the other half on the same timing
        CeaikaEmoteDef def
        def.id = "emote_lastforever"
        def.title = "Last Forever (paired)"
        def.sequence = "emote_emote_lastforever"
        def.duration = 12.630475979395587
        def.playbackRate = 1.0
        def.loopStart = 0.6315237989697793
        def.loopPad = 0.3988571361914396
        def.traversal = false
        def.track = 38
        def.partner = "emote_lastforever_b"
        // joined onto a teo: stand on their left
        def.pairOffset = <0, -64, 0>
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_lastforever_b"
        def.title = "Last Forever (partner)"
        def.sequence = "emote_emote_lastforever_b"
        def.duration = 12.630475979395587
        def.playbackRate = 1.0
        def.loopStart = 0.6315237989697793
        def.loopPad = 0.3988571361914396
        def.traversal = false
        def.partner = "emote_lastforever"
        def.listed = false
        // side by side with ayo on their right. fortnite's placement data
        // didnt come with the export so this is eyeballed, hands dont cross
        def.pairOffset = <0, 64, 0>
        file.entries.append(def)
    }
    {
        // hug (fortnite's pat pat): the leader puts their arms out and waits
        // (joinAt), whoever joins gets put in front facing them, both do the
        // pat and its over
        CeaikaEmoteDef def
        def.id = "emote_patpat"
        def.title = "Hug (paired)"
        def.sequence = "emote_emote_patpat"
        def.duration = 8.27205905555442
        def.playbackRate = 1.0
        def.traversal = false
        def.loops = false
        def.joinAt = 3.805147165555033
        def.partner = "emote_patpat_b"
        def.introTrack = 39
        def.introDuration = 2.3699375
        def.musicAfterIntro = false
        def.titans = false
        file.entries.append(def)
    }
    {
        CeaikaEmoteDef def
        def.id = "emote_patpat_b"
        def.title = "Hug (partner)"
        def.sequence = "emote_emote_patpat_b"
        def.duration = 4.466911889999387
        def.playbackRate = 1.0
        def.traversal = false
        def.loops = false
        def.listed = false
        // face to face, close enough that the torsos meet in the hug (bone
        // gap ~13 at the closest frame, measured on the retargeted clips)
        def.pairOffset = <56, 0, 0>
        def.pairYaw = 180.0
        def.titans = false
        file.entries.append(def)
    }
    return file.entries
}
// the i'm a mystery prop parts, em_propdebug uses these too. the whole 243 bone
// prop crashed the renderer and bones past 127 might draw wrong, so its 3
// parts: red rings (91 bones), blue A-C (67) and blue D-F (65). everything
// glows cyan anyway, red/blue is just what the rig calls them
table<string, asset> function CeaikaEmotes_DebugProps()
{
    return {
        red = $"models/test/brad/store_titan_warpaint_bundle.mdl",
        bluea = $"models/test/brad/store_weapon_warpaint_bundle.mdl",
        blueb = $"models/test/brad/store_card_prime_bundle.mdl"
    }
}

// every model the props use. clients can only spawn what the server precached,
// so props sit on stock paths every server loads anyway, same trick as the
// dances (the unused store card test models _mapspawn.gnut precaches)
array<asset> function CeaikaEmotes_PropModels()
{
    array<asset> models
    foreach(CeaikaEmoteDef emoteDef in CeaikaEmotes_Catalog())
        foreach(CeaikaEmoteExtra extra in emoteDef.extras)
            if(extra.model != $"" && !models.contains(extra.model)) models.append(extra.model)
    foreach(string variant, asset model in CeaikaEmotes_DebugProps())
        if(!models.contains(model)) models.append(model)
    return models
}

// this gets called a bunch every frame for every dancer, so ids and nicknames
// all go in one table the first time instead of rebuilding the nicknames and
// scanning the catalog on every call
int function CeaikaEmotes_Index(string name)
{
    if (file.index.len() == 0)
    {
        table<string, string> aliases =
        {
            ["billy"] = "bbd_traversal",
            ["bbd"] = "bbd_traversal",
            ["griddy"] = "griddy_traversal",
            ["billybounce"] = "bbd_traversal",
            ["bbdtraversal"] = "bbd_traversal",
            ["dancemoves"] = "emote_dancemoves",
            ["electroshuffle"] = "emote_electroshuffle",
            ["electroswing"] = "electroswing_auto",
            ["floss"] = "emote_floss",
            ["freestylin"] = "emote_freestylin",
            ["griddytraversal"] = "griddy_traversal",
            ["hype"] = "emote_hype",
            ["orangejustice"] = "emote_oj",
            ["oj"] = "emote_oj",
            ["rambunctious"] = "emote_rambunctious",
            ["reanimated"] = "emote_technozombie",
            ["technozombie"] = "emote_technozombie",
            ["smoothmoves"] = "emote_smoothmoves",
            ["squatkick"] = "emote_squatkick",
            ["takethel"] = "emote_takethel",
            ["voidredemption"] = "emote_voidredemption",
            ["mystery"] = "emote_voidredemption",
            ["phoneitin"] = "emote_epicsaxguy",
            ["sax"] = "emote_epicsaxguy",
            ["epicsaxguy"] = "emote_epicsaxguy",
            ["sadtrombone"] = "emote_sad_trombone",
            ["trombone"] = "emote_sad_trombone",
            ["alors"] = "emote_alors",
            ["alorsondance"] = "emote_alors",
            ["boogiedown"] = "emote_boogiedown",
            ["breakin"] = "emote_breakin",
            ["downward"] = "emote_downward",
            ["fireball"] = "emote_fireball",
            ["flamenco"] = "emote_flamenco",
            ["freeflow"] = "emote_freeflow",
            ["gangnam"] = "emote_gangnam",
            ["gangnamstyle"] = "emote_gangnam",
            ["macarena"] = "emote_macarena",
            ["pompous"] = "emote_pompous",
            ["swaggerstrut"] = "emote_pompous",
            ["pumpernickel"] = "emote_pumpernickel",
            ["robot"] = "emote_robot",
            ["rollie"] = "emote_rollie",
            ["scenario"] = "emote_scenario",
            ["lastforever"] = "emote_lastforever",
            ["patpat"] = "emote_patpat",
            ["hug"] = "emote_patpat"
        }
        foreach (int i, CeaikaEmoteDef def in CeaikaEmotes_Catalog())
            file.index[def.id] <- i
        foreach (string alias, string id in aliases)
            if (id in file.index) file.index[alias] <- file.index[id]
    }
    name = name.tolower()
    return name in file.index ? file.index[name] : -1
}
