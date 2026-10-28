#include <cassert>
#include "emote_m4a.h"
using namespace EmoteM4a;
// a few seconds of something music-ish: two tones over some hiss, at a length
// that isnt a multiple of 1024 so the end padding has to get cut. pure tones
// alone line up at every period so Compare cant tell the offset, hence hiss
static std::vector<short> Song(unsigned rate, size_t frames)
{
    std::vector<short> pcm(frames * 2);
    unsigned noise = 12345;
    for (size_t i = 0; i < frames; i++)
    {
        double t = double(i) / rate;
        noise = noise * 1103515245 + 12345;
        double hiss = int(noise >> 16 & 0x7fff) / 32768.0 - 0.5;
        pcm[i * 2] = short(8000 * (sin(t * 2 * 3.14159265 * 440) + hiss));
        pcm[i * 2 + 1] = short(8000 * (sin(t * 2 * 3.14159265 * 660) - hiss));
    }
    return pcm;
}
int main()
{
    wchar_t dir[MAX_PATH], path[MAX_PATH];
    GetTempPathW(MAX_PATH, dir);
    swprintf(path, MAX_PATH, L"%lsceaika_test_m4a_%lu.m4a", dir, GetCurrentProcessId());
    for (unsigned rate : {48000u, 44100u})
    {
        std::vector<short> song = Song(rate, rate * 3 + 337), back;
        int got = 0, offset = 99;
        double snr = 0;
        assert(Encode(path, song, rate));
        assert(TrailerFrames(path) == song.size() / 2);
        ULONGLONG start = GetTickCount64();
        assert(Decode(path, back, got));
        fprintf(stderr, "%u Hz: decoded %zu frames in %llu ms\n", rate, back.size() / 2, GetTickCount64() - start);
        assert(got == int(rate) && back.size() == song.size());
        Compare(song, back, offset, snr);
        fprintf(stderr, "  offset %d snr %.1f dB\n", offset, snr);
        // hiss is the worst thing to throw at aac, ~14 dB. a broken file is ~0
        assert(offset == 0 && snr > 10);
    }
    // the encoder cant do 24 kHz, that one has to stay a wav
    assert(!Encode(path, Song(24000, 24000), 24000));
    // no trailer (an aac file from anywhere else) doesnt load, wrong length is worse than none
    std::vector<short> song = Song(48000, 50000), back;
    int got = 0;
    assert(Encode(path, song, 48000));
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
    LARGE_INTEGER size;
    GetFileSizeEx(f, &size);
    size.QuadPart -= TrailerSize;
    SetFilePointerEx(f, size, nullptr, FILE_BEGIN);
    SetEndOfFile(f);
    CloseHandle(f);
    assert(TrailerFrames(path) == 0 && !Decode(path, back, got) && back.empty());
    assert(!Decode(L"Z:\\definitely\\not\\here.m4a", back, got));
    _wremove(path);
    puts("m4a tests passed");
    return 0;
}
