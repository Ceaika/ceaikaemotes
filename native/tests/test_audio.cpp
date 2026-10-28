#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cassert>
static ULONGLONG testClock = 1000;
static ULONGLONG TestClock()
{
    return testClock;
}
#define GetTickCount64 TestClock
#include "emote_audio.h"
#undef GetTickCount64
using namespace EmoteAudio;
static double energy(short *p, int c)
{
    double e = 0;
    for (int i = 0; i < FramesPerBuffer; i++)
        e += double(p[i * 2 + c]) * p[i * 2 + c];
    return e;
}
int main()
{
    SubmitRequest("77:1,1,0.5,0,1");
    assert(pendingPlayback.count == 1);
    testClock += 751;
    SubmitRequest("77:1,1,0.5,0,1");
    assert(pendingPlayback.count == 0);
    testClock += 751;
    SubmitRequest("77:1,1,0.5,0,1");
    assert(pendingPlayback.count == 0);
    SubmitRequest("78:1,1,0.5,0,1");
    assert(pendingPlayback.count == 1);
    SubmitRequest("");
    assert(pendingPlayback.count == 0);
    PlaybackSnapshot s;
    assert(ParseRequest("1:1,12.0,0.5,1.0,0", s));
    assert(s.count == 1 && s.items[0].age == 12);
    for (const char *bad : {"x",
                            "1:0,0,.5,0,0",
                            "1:1,nan,.5,0,0",
                            "1:1,0,2,0,0",
                            "1:1,0,.5,2,0",
                            "1:1,0,.5,0,0;1,0,.5,0,0",
                            "1:1,0,.5,0,0garbage"})
    {
        PlaybackSnapshot n;
        assert(!ParseRequest(bad, n));
    }
    tracks[0].resize(OutputSampleRate * 2 * 3);
    for (int i = 0; i < OutputSampleRate * 3; i++)
        tracks[0][i * 2] = tracks[0][i * 2 + 1] = (i < OutputSampleRate ? 4000 : 12000);
    short out[FramesPerBuffer * 2];
    s.stamp = 1000;
    s.items[0].age = 1.5;
    MixBuffer(out, FramesPerBuffer, s, 1000);
    assert(energy(out, 0) == 0 && energy(out, 1) > 0);
    assert(voices[0].position > OutputSampleRate * 1.5);
    s.items[0].pan = -1;
    for (int i = 0; i < 20; i++)
        MixBuffer(out, FramesPerBuffer, s, 1000);
    assert(energy(out, 0) > energy(out, 1) * 1000);
    s.items[0].stereo = 1;
    for (int i = 0; i < 20; i++)
        MixBuffer(out, FramesPerBuffer, s, 1000);
    assert(fabs(energy(out, 0) - energy(out, 1)) < energy(out, 0) * .02);
    s.items[0].age = 2.999;
    voices[0].position = 2.999 * OutputSampleRate;
    MixBuffer(out, FramesPerBuffer, s, 1000);
    assert(voices[0].position < FramesPerBuffer);
    for (int i = 0; i < 25; i++)
        MixBuffer(out, FramesPerBuffer, s, 2000);
    assert(playing == 0 && energy(out, 0) == 0 && energy(out, 1) == 0);
    PlaybackSnapshot full;
    for (int i = 0; i < MaxMusicVoices; i++)
        full.items[i] = {i + 1, .5, 1, 0, 1};
    full.count = MaxMusicVoices;
    full.stamp = 3000;
    MixBuffer(out, FramesPerBuffer, full, 3000);
    assert(playing == 16); // Saturating output never wraps around.
    for (auto &v : voices)
        v = {};
    tracks[1].resize(OutputSampleRate * 2);
    for (auto &sample : tracks[1])
        sample = -8000;
    PlaybackSnapshot g;
    assert(ParseRequest("9:1,.5,.5,0,1,1", g));
    g.stamp = 4000;
    MixBuffer(out, FramesPerBuffer, g, 4000);
    assert(voices[0].track == 1 && out[FramesPerBuffer * 2 - 1] < 0);
    g.items[0].track = 0;
    MixBuffer(out, FramesPerBuffer, g, 4000);
    assert(voices[0].track == 0 && out[FramesPerBuffer * 2 - 1] > 0);
    PlaybackSnapshot badTrack;
    assert(!ParseRequest("10:1,.5,.5,0,1,16", badTrack));
    // Every catalog track routes independently, including 44.1kHz music.
    for (int track = 0; track < TrackCount; track++)
    {
        for (auto &v : voices)
            v = {};
        tracks[track].assign(TrackRates[track] * 2, short(1000 + track * 100));
        PlaybackSnapshot each;
        char request[128];
        snprintf(request, sizeof(request), "12:1,.25,.5,0,1,%d", track);
        assert(ParseRequest(request, each));
        each.stamp = 5000;
        MixBuffer(out, FramesPerBuffer, each, 5000);
        assert(voices[0].track == track && energy(out, 0) > 0);
        double expected =
            .25 * TrackRates[track] + FramesPerBuffer * double(TrackRates[track]) / OutputSampleRate;
        assert(fabs(voices[0].position - expected) < .001);
    }
    // tracks.txt: comments and blanks skipped, unsafe names keep their number.
    char names[8][64]{};
    bool once[8]{};
    int listed = ParseTrackList(
        "loop_a.wav\r\n# note\n\nintro_a.wav once\n..\\evil.wav\nloop_b.wav  # trailing\n", names, once, 8);
    assert(listed == 4 && !strcmp(names[0], "loop_a.wav") && !once[0]);
    assert(!strcmp(names[1], "intro_a.wav") && once[1]);
    assert(names[2][0] == 0 && !strcmp(names[3], "loop_b.wav"));
    // Requests are limited to the tracks this DLL actually has.
    PlaybackSnapshot extra;
    assert(!ParseRequest("20:1,.1,.5,0,1,16", extra));
    trackCount = TrackCount + 2;
    assert(ParseRequest("21:1,.1,.5,0,1,17", extra));
    assert(!ParseRequest("22:1,.1,.5,0,1,18", extra));
    // A one-shot plays, then stays silent instead of wrapping to its start.
    for (auto &v : voices)
        v = {};
    tracks[TrackCount].assign(OutputSampleRate / 4 * 2, short(9000));
    extraRates[TrackCount] = OutputSampleRate;
    trackOnce[TrackCount] = true;
    PlaybackSnapshot intro;
    char request[64];
    snprintf(request, sizeof(request), "30:1,.1,.5,0,1,%d", TrackCount);
    assert(ParseRequest(request, intro));
    intro.stamp = 6000;
    for (int i = 0; i < 3; i++)
        MixBuffer(out, FramesPerBuffer, intro, 6000);
    assert(voices[0].id == 1 && energy(out, 0) > 0);
    // 5 ms before the end: the voice finishes inside this buffer.
    for (auto &v : voices)
        v = {};
    intro.items[0].age = .245;
    MixBuffer(out, FramesPerBuffer, intro, 6000);
    assert(voices[0].id == 0);
    // Later frames of the same request are past the end and stay silent.
    for (int i = 1; i <= 5; i++)
    {
        MixBuffer(out, FramesPerBuffer, intro, 6000 + i * 100);
        assert(voices[0].id == 0 && energy(out, 0) == 0);
    }
    // Extra tracks keep their own sample rate.
    tracks[TrackCount + 1].assign(44100 * 2, short(2000));
    extraRates[TrackCount + 1] = 44100;
    PlaybackSnapshot loop;
    snprintf(request, sizeof(request), "31:1,.25,.5,0,1,%d", TrackCount + 1);
    assert(ParseRequest(request, loop));
    loop.stamp = 7000;
    MixBuffer(out, FramesPerBuffer, loop, 7000);
    assert(fabs(voices[0].position - (.25 * 44100 + FramesPerBuffer * 44100. / OutputSampleRate)) < .001);
    ClearRequests();
    puts("Audio tests passed: validation, phase, panning, stereo, looping, timeout, voice limit, track "
         "selection/switching, track list, one-shot intros, extra track rates.");
}
