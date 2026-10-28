// turns the emote wavs into .m4a (aac 192k) with windows' own encoder, then
// decodes it back the way the dll does and checks it lines up with the wav.
// music timing is the thing ppl notice first so a file that comes back shifted
// or the wrong length gets deleted and the wav stays
//
//   encode_music.exe in.wav out.m4a
//
// prints "<frames> offset <n> snr <db> decoded <frames>"
#include "../native/emote_m4a.h"

static bool ReadWav(const wchar_t *path, std::vector<short> &pcm, unsigned &rate)
{
    FILE *f = _wfopen(path, L"rb");
    if (!f)
        return false;
    unsigned char head[44]{};
    bool ok = fread(head, 1, 44, f) == 44;
    auto u16 = [&](int i) { return unsigned(head[i]) | (unsigned(head[i + 1]) << 8); };
    auto u32 = [&](int i) { return u16(i) | (u16(i + 2) << 16); };
    // same layout check as the dll's wav loader
    ok = ok && !memcmp(head, "RIFF", 4) && !memcmp(head + 8, "WAVEfmt ", 8) && !memcmp(head + 36, "data", 4) &&
         u32(16) == 16 && u16(20) == 1 && u16(22) == 2 && u16(34) == 16;
    rate = u32(24);
    if (ok)
    {
        pcm.resize(u32(40) / 2);
        ok = fread(pcm.data(), 2, pcm.size(), f) == pcm.size();
    }
    fclose(f);
    return ok;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "usage: encode_music in.wav out.m4a\n");
        return 2;
    }
    std::vector<short> wav, back;
    unsigned rate = 0;
    if (!ReadWav(argv[1], wav, rate))
    {
        fprintf(stderr, "cant read %ls (needs 16 bit stereo pcm)\n", argv[1]);
        return 1;
    }
    int backRate = 0;
    if (!EmoteM4a::Encode(argv[2], wav, rate) || !EmoteM4a::Decode(argv[2], back, backRate) || unsigned(backRate) != rate)
    {
        fprintf(stderr, "encoding %ls failed (aac only does 44.1/48 kHz), keeping the wav\n", argv[1]);
        _wremove(argv[2]);
        return 1;
    }
    int offset = 0;
    double snr = 0;
    EmoteM4a::Compare(wav, back, offset, snr);
    printf("%zu offset %d snr %.1f decoded %zu\n", wav.size() / 2, offset, snr, back.size() / 2);
    // snr is just a garbage check, aac on short punchy intros measures ~15 and
    // sounds fine, a broken file is ~0
    if (offset != 0 || snr < 10 || back.size() != wav.size())
    {
        fprintf(stderr, "%ls came back wrong, keeping the wav\n", argv[1]);
        _wremove(argv[2]);
        return 1;
    }
    return 0;
}
