// track numbers match def.track in sh_ceaikaemotes_catalog.nut. keep these in sync.
// newer songs go in tracks.txt instead, that way nobody has to rebuild the dll
// laugh (9) and the worm (15) got cut, their slots stay empty so every number
// after them still points at the same song
constexpr int TrackCount = 16;
static const wchar_t *TrackFiles[TrackCount] = {L"ceaikaemotes\\billy_bounce.wav",
                                                L"ceaikaemotes\\griddy.wav",
                                                L"ceaikaemotes\\emote_dancemoves.wav",
                                                L"ceaikaemotes\\emote_electroshuffle.wav",
                                                L"ceaikaemotes\\electroswing_auto.wav",
                                                L"ceaikaemotes\\emote_floss.wav",
                                                L"ceaikaemotes\\emote_freestylin.wav",
                                                L"ceaikaemotes\\emote_hype.wav",
                                                L"ceaikaemotes\\emote_oj.wav",
                                                nullptr,
                                                L"ceaikaemotes\\emote_rambunctious.wav",
                                                L"ceaikaemotes\\emote_technozombie.wav",
                                                L"ceaikaemotes\\emote_smoothmoves.wav",
                                                L"ceaikaemotes\\emote_squatkick.wav",
                                                L"ceaikaemotes\\emote_takethel.wav",
                                                nullptr};
static const int TrackRates[TrackCount] = {48000,
                                           48000,
                                           48000,
                                           44100,
                                           48000,
                                           44100,
                                           48000,
                                           48000,
                                           48000,
                                           48000,
                                           48000,
                                           44100,
                                           48000,
                                           48000,
                                           48000,
                                           44100};
