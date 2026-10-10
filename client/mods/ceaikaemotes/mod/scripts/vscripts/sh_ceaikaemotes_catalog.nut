global function CeaikaEmotes_Catalog
global function CeaikaEmotes_Index
global struct CeaikaEmoteDef
{
    string id
    string title
    string sequence
    float duration
    float playbackRate
    bool traversal
    int track
}
struct
{
    array<CeaikaEmoteDef> entries
    bool ready = false
} file
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
        def.id = "emote_laugh"
        def.title = "Laugh"
        def.sequence = "emote_emote_laugh"
        def.duration = 9.100121094303297
        def.playbackRate = 0.9963636234638648
        def.traversal = false
        def.track = 9
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
    {
        CeaikaEmoteDef def
        def.id = "emote_worm"
        def.title = "Worm"
        def.sequence = "emote_emote_worm"
        def.duration = 4.133597654163148
        def.playbackRate = 1.2056326491309182
        def.traversal = false
        def.track = 15
        file.entries.append(def)
    }
    return file.entries
}
int function CeaikaEmotes_Index(string name)
{
    name = name.tolower()
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
        ["laugh"] = "emote_laugh",
        ["rambunctious"] = "emote_rambunctious",
        ["reanimated"] = "emote_technozombie",
        ["technozombie"] = "emote_technozombie",
        ["smoothmoves"] = "emote_smoothmoves",
        ["squatkick"] = "emote_squatkick",
        ["takethel"] = "emote_takethel",
        ["worm"] = "emote_worm"
    }
    if (name in aliases) name = aliases[name]
    foreach (int i, def in CeaikaEmotes_Catalog()) if (def.id == name) return i
    return -1
}
