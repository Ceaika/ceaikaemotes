// play the local wav/m4a files; nothing here downloads or streams music.
#include "emote_m4a.h"
#include <mmsystem.h>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <vector>
#include <cmath>
#include <algorithm>
namespace EmoteAudio
{
constexpr int OutputSampleRate = 48000, MaxMusicVoices = 16, FramesPerBuffer = 512, OutputBufferCount = 4;
struct MusicRequest
{
    int id = 0;
    double age = 0;
    float gain = 0, pan = 0;
    int stereo = 0, track = 0;
};
struct PlaybackSnapshot
{
    MusicRequest items[MaxMusicVoices]{};
    int count = 0;
    ULONGLONG stamp = 0;
};
struct ActiveVoice
{
    int id = 0;
    double position = 0;
    float left = 0, right = 0;
    bool stereo = false;
    int track = 0;
};
static SRWLOCK playbackLock = SRWLOCK_INIT;
static PlaybackSnapshot pendingPlayback;
#include "emote_catalog.h"
// Built-in tracks come first. Emotes added later list their WAVs in
// ceaikaemotes\tracks.txt, numbered from TrackCount in file order, so new
// music doesn't need a DLL rebuild. "once" marks a one-shot intro.
constexpr int MaxTracks = 64;
static std::vector<short> tracks[MaxTracks];
static int extraRates[MaxTracks]{};
static bool trackOnce[MaxTracks]{};
static volatile LONG trackCount = TrackCount, extraFailed = 0;
static const std::vector<short> &GetTrackSamples(int id)
{
    return tracks[id];
}
static int TrackRate(int id)
{
    return id < TrackCount ? TrackRates[id] : extraRates[id];
}
static ActiveVoice voices[MaxMusicVoices];
static HANDLE worker = nullptr;
static HANDLE wakeEvent = nullptr;
static volatile LONG sleeping = 0, buffersWritten = 0;
static volatile LONG ready = 0, playing = 0;
static volatile LONG deviceOpen = 0, deviceOpens = 0, deviceCloses = 0;
static char lastAudioRequest[4096]{};
static ULONGLONG lastAudioHeartbeat = 0;
static float Clamp(float x, float a, float b)
{
    return std::max(a, std::min(b, x));
}
static void ClearRequests()
{
    AcquireSRWLockExclusive(&playbackLock);
    pendingPlayback = {};
    ReleaseSRWLockExclusive(&playbackLock);
}
static bool ParseRequest(const char *raw, PlaybackSnapshot &out)
{
    if (!raw || !*raw)
        return true;
    char *end = nullptr;
    strtoul(raw, &end, 10);
    if (end == raw || *end != ':')
        return false;
    const char *cursor = end + 1;
    while (*cursor)
    {
        if (out.count >= MaxMusicVoices)
            return false;
        MusicRequest r;
        int used = 0;
        if (sscanf(cursor, "%d,%lf,%f,%f,%d%n", &r.id, &r.age, &r.gain, &r.pan, &r.stereo, &used) != 5 ||
            used <= 0)
            return false;
        if (cursor[used] == ',')
        {
            int extra = 0;
            if (sscanf(cursor + used, ",%d%n", &r.track, &extra) != 1 || extra <= 0)
                return false;
            used += extra;
        }
        if (r.track < 0 || r.track >= trackCount)
            return false;
        if (r.id < 1 || r.id > 8191 || !std::isfinite(r.age) || r.age < 0 || r.age > 3600 ||
            !std::isfinite(r.gain) || !std::isfinite(r.pan) || r.gain < 0 || r.gain > 1 || r.pan < -1 ||
            r.pan > 1 || r.stereo < 0 || r.stereo > 1)
            return false;
        for (int i = 0; i < out.count; i++)
            if (out.items[i].id == r.id)
                return false;
        out.items[out.count++] = r;
        cursor += used;
        if (*cursor == ';')
            ++cursor;
        else if (*cursor)
            return false;
    }
    return true;
}
static void SubmitRequest(const char *raw)
{
    PlaybackSnapshot next;
    size_t length = raw ? strnlen(raw, sizeof(lastAudioRequest)) : 0;
    if (length >= sizeof(lastAudioRequest) || !ParseRequest(raw, next))
    {
        ClearRequests();
        return;
    }
    ULONGLONG now = GetTickCount64();
    if (length && strcmp(raw, lastAudioRequest) != 0)
    {
        memcpy(lastAudioRequest, raw, length + 1);
        lastAudioHeartbeat = now;
    }
    if (!length || now - lastAudioHeartbeat > 750)
    {
        ClearRequests();
        return;
    }
    next.stamp = now;
    AcquireSRWLockExclusive(&playbackLock);
    pendingPlayback = next;
    ReleaseSRWLockExclusive(&playbackLock);
    if (next.count && wakeEvent && InterlockedCompareExchange(&sleeping, 0, 0))
        SetEvent(wakeEvent);
}
// no wav? releases ship the music as .m4a with the same name (emote_m4a.h),
// wavs still win so a freshly ported emote works before anyone encodes it
static bool LoadM4a(wchar_t *path, std::vector<short> &pcm, int &rate)
{
    size_t n = wcslen(path);
    if (n < 4 || _wcsicmp(path + n - 4, L".wav"))
        return false;
    wcscpy(path + n - 4, L".m4a");
    int fileRate = 0;
    // same 32 MB cap as a wav
    if (!EmoteM4a::Decode(path, pcm, fileRate) || (rate && fileRate != rate) || pcm.size() >= 16000000)
    {
        pcm.clear();
        return false;
    }
    rate = fileRate;
    return true;
}
// rate 0 accepts the file's own rate and returns it.
static bool LoadTrack(HMODULE self, const wchar_t *name, std::vector<short> &pcm, int &rate)
{
    wchar_t path[32768];
    DWORD n = GetModuleFileNameW(self, path, 32768);
    if (!n || n >= 32700)
        return false;
    wchar_t *slash = wcsrchr(path, L'\\');
    if (!slash)
        return false;
    wcscpy(slash + 1, name);
    FILE *f = _wfopen(path, L"rb");
    if (!f)
        return LoadM4a(path, pcm, rate);
    unsigned char head[44]{};
    bool ok = fread(head, 1, 44, f) == 44;
    auto u16 = [&](int i) { return unsigned(head[i]) | (unsigned(head[i + 1]) << 8); };
    auto u32 = [&](int i) { return u16(i) | (u16(i + 2) << 16); };
    unsigned bytes = u32(40);
    unsigned fileRate = u32(24);
    ok = ok && !memcmp(head, "RIFF", 4) && !memcmp(head + 8, "WAVEfmt ", 8) &&
         !memcmp(head + 36, "data", 4) && u32(16) == 16 && u16(20) == 1 && u16(22) == 2 &&
         (rate ? fileRate == unsigned(rate) : fileRate >= 8000 && fileRate <= 96000) && u16(34) == 16 &&
         bytes > 4 && bytes < 32000000 && bytes % 4 == 0;
    if (ok)
        rate = int(fileRate);
    if (ok)
    {
        pcm.resize(bytes / 2);
        ok = fread(pcm.data(), 1, bytes, f) == bytes;
    }
    fclose(f);
    if (!ok)
        pcm.clear();
    return ok;
}
// One "<file>.wav [once]" per line; '#' starts a comment. Names are plain
// files inside the ceaikaemotes folder. A line that fails to load still keeps
// its number, so later tracks stay where the catalog expects them.
static int ParseTrackList(const char *text, char names[][64], bool *once, int max)
{
    int count = 0;
    while (*text && count < max)
    {
        const char *end = strchr(text, '\n');
        size_t length = end ? size_t(end - text) : strlen(text);
        char line[128]{};
        memcpy(line, text, std::min(length, sizeof(line) - 1));
        text += length + (end ? 1 : 0);
        if (char *hash = strchr(line, '#'))
            *hash = 0;
        char name[96]{}, flag[16]{};
        int fields = sscanf(line, "%95s %15s", name, flag);
        if (fields < 1)
            continue;
        size_t n = strlen(name);
        bool valid = n > 4 && n < 64 && !_stricmp(name + n - 4, ".wav");
        for (size_t i = 0; valid && i < n; i++)
            valid = isalnum(static_cast<unsigned char>(name[i])) || strchr("_-.", name[i]);
        strcpy(names[count], valid ? name : "");
        once[count] = fields == 2 && !strcmp(flag, "once");
        ++count;
    }
    return count;
}
// every track to load, built-in and tracks.txt ones
struct LoadJob
{
    int id = 0, rate = 0;
    wchar_t file[96]{};
    bool loaded = false;
};
static LoadJob loadJobs[MaxTracks];
static int loadJobCount = 0;
static volatile LONG nextLoadJob = 0;
static HMODULE loadModule = nullptr;
static void AddLoadJob(int id, const wchar_t *file, int rate)
{
    LoadJob &job = loadJobs[loadJobCount++];
    job.id = id;
    job.rate = rate;
    wcsncpy(job.file, file, 95);
}
static DWORD WINAPI RunLoadJobs(void *)
{
    for (LONG i; (i = InterlockedIncrement(&nextLoadJob) - 1) < loadJobCount;)
    {
        LoadJob &job = loadJobs[i];
        job.loaded = LoadTrack(loadModule, job.file, tracks[job.id], job.rate);
    }
    return 0;
}
static int QueueExtraTracks(HMODULE self)
{
    wchar_t path[32768];
    DWORD n = GetModuleFileNameW(self, path, 32768);
    wchar_t *slash = n && n < 32700 ? wcsrchr(path, L'\\') : nullptr;
    if (!slash)
        return 0;
    wcscpy(slash + 1, L"ceaikaemotes\\tracks.txt");
    FILE *f = _wfopen(path, L"rb");
    if (!f)
        return 0;
    char text[8192]{};
    fread(text, 1, sizeof(text) - 1, f);
    fclose(f);
    char names[MaxTracks - TrackCount][64]{};
    bool once[MaxTracks - TrackCount]{};
    int count = ParseTrackList(text, names, once, MaxTracks - TrackCount);
    for (int i = 0; i < count; i++)
    {
        int id = TrackCount + i;
        trackOnce[id] = once[i];
        if (!names[i][0])
        {
            InterlockedIncrement(&extraFailed);
            continue;
        }
        wchar_t file[96] = L"ceaikaemotes\\";
        size_t prefix = wcslen(file);
        for (size_t k = 0; names[i][k]; k++)
            file[prefix + k] = wchar_t(names[i][k]);
        AddLoadJob(id, file, 0);
    }
    return count;
}
// decoding all the m4a music is ~1.3s on one core, so 4 threads split it.
// also keeps COM/media foundation setup on threads we own instead of northstar's
static bool LoadMusicFiles(HMODULE self)
{
    loadJobCount = 0;
    nextLoadJob = 0;
    loadModule = self;
    for (int i = 0; i < TrackCount; i++)
        if (TrackFiles[i])
            AddLoadJob(i, TrackFiles[i], TrackRates[i]);
    int builtIn = loadJobCount;
    int extras = QueueExtraTracks(self);
    HANDLE threads[4]{};
    DWORD started = 0;
    for (HANDLE &thread : threads)
        if ((thread = CreateThread(nullptr, 0, RunLoadJobs, nullptr, 0, nullptr)))
            started++;
        else
            break;
    if (started)
        WaitForMultipleObjects(started, threads, TRUE, INFINITE);
    else
        RunLoadJobs(nullptr);
    for (DWORD i = 0; i < started; i++)
        CloseHandle(threads[i]);
    for (int i = 0; i < loadJobCount; i++)
    {
        if (i < builtIn && !loadJobs[i].loaded)
            return false; // the original music not loading means the install is broken
        if (i >= builtIn && loadJobs[i].loaded)
            extraRates[loadJobs[i].id] = loadJobs[i].rate;
        else if (i >= builtIn)
            InterlockedIncrement(&extraFailed);
    }
    InterlockedExchange(&trackCount, TrackCount + extras);
    return true;
}
static void MixBuffer(
    short *output, int frames, const PlaybackSnapshot &state, ULONGLONG now, double queued = 0)
{

    int count = now - state.stamp <= 750 ? state.count : 0;
    bool used[MaxMusicVoices]{};
    float targetL[MaxMusicVoices]{}, targetR[MaxMusicVoices]{};
    int audible = 0;
    float totalGain = 0;
    for (int r = 0; r < count; r++)
    {
        const MusicRequest &req = state.items[r];
        if (GetTrackSamples(req.track).empty())
            continue;
        double trackFrames = GetTrackSamples(req.track).size() / 2;
        double elapsed = (req.age + double(now - state.stamp) / 1000. + queued) * TrackRate(req.track);
        // A finished one-shot stays silent instead of starting over.
        if (trackOnce[req.track] && elapsed >= trackFrames)
            continue;
        int slot = -1;
        for (int i = 0; i < MaxMusicVoices; i++)
            if (voices[i].id == req.id)
            {
                slot = i;
                break;
            }
        bool fresh = slot < 0;
        if (fresh)
            for (int i = 0; i < MaxMusicVoices; i++)
                if (!voices[i].id)
                {
                    slot = i;
                    break;
                }
        if (slot < 0)
            continue;
        ActiveVoice &v = voices[slot];
        double desired = fmod(elapsed, trackFrames);
        double error = fabs(v.position - desired);
        error = std::min(error, trackFrames - error);
        if (fresh || v.track != req.track || error > TrackRate(req.track) * .18)
        {
            v.position = desired;
            v.left = v.right = 0;
        }
        v.id = req.id;
        v.track = req.track;
        v.stereo = req.stereo != 0;
        used[slot] = true;
        targetL[slot] = req.gain * (v.stereo ? 1.f : float(sqrt((1. - req.pan) * .5)));
        targetR[slot] = req.gain * (v.stereo ? 1.f : float(sqrt((1. + req.pan) * .5)));
        if (req.gain > .0001)
        {
            ++audible;
            totalGain += req.gain;
        }
    }
    InterlockedExchange(&playing, audible);
    float normalization = 1.f / std::max(1.f, totalGain);
    for (int f = 0; f < frames; f++)
    {
        float l = 0, r = 0;
        for (int i = 0; i < MaxMusicVoices; i++)
            if (voices[i].id)
            {
                ActiveVoice &v = voices[i];
                v.left += (targetL[i] - v.left) * .002f;
                v.right += (targetR[i] - v.right) * .002f;
                const auto &samples = GetTrackSamples(v.track);
                double trackFrames = samples.size() / 2;
                if (samples.empty())
                {
                    v = {};
                    continue;
                }
                size_t at = size_t(v.position), next = (at + 1) % size_t(trackFrames);
                float fraction = float(v.position - double(at));
                float left = samples[at * 2] + (samples[next * 2] - samples[at * 2]) * fraction;
                float right = samples[at * 2 + 1] + (samples[next * 2 + 1] - samples[at * 2 + 1]) * fraction;
                if (!v.stereo)
                    left = right = (left + right) * .5f;
                // fade the loop edges a bit so they dont click.
                float edge = Clamp(
                    float(std::min(v.position, trackFrames - 1 - v.position) / (TrackRate(v.track) * .005)),
                    0,
                    1);
                l += left * v.left * edge;
                r += right * v.right * edge;
                v.position += double(TrackRate(v.track)) / OutputSampleRate;
                if (v.position >= trackFrames)
                {
                    if (trackOnce[v.track])
                    {
                        v = {};
                        continue;
                    }
                    v.position -= trackFrames;
                }
            }
        output[f * 2] = short(Clamp(l * normalization, -32767, 32767));
        output[f * 2 + 1] = short(Clamp(r * normalization, -32767, 32767));
    }
    for (int i = 0; i < MaxMusicVoices; i++)
        if (!used[i] && fabs(voices[i].left) + fabs(voices[i].right) < .00001)
            voices[i] = {};
}
static bool HasActiveRequest(const PlaybackSnapshot &s, ULONGLONG now)
{
    return s.count > 0 && now - s.stamp <= 750;
}
static bool HasFadingVoices()
{
    for (auto &v : voices)
        if (v.id)
            return true;
    return false;
}
static PlaybackSnapshot ReadSnapshot()
{
    PlaybackSnapshot s;
    AcquireSRWLockShared(&playbackLock);
    s = pendingPlayback;
    ReleaseSRWLockShared(&playbackLock);
    return s;
}
static void CloseDevice(HWAVEOUT &device, WAVEHDR *headers, bool reset = false)
{
    if (!device)
        return;
    if (reset)
        waveOutReset(device);
    for (int i = 0; i < OutputBufferCount; i++)
        if (headers[i].dwFlags & WHDR_PREPARED)
            waveOutUnprepareHeader(device, &headers[i], sizeof(WAVEHDR));
    waveOutClose(device);
    device = nullptr;
    InterlockedExchange(&deviceOpen, 0);
    InterlockedIncrement(&deviceCloses);
}
static DWORD WINAPI AudioWorker(void *)
{
    HWAVEOUT device = nullptr;
    WAVEFORMATEX format{WAVE_FORMAT_PCM, 2, OutputSampleRate, OutputSampleRate * 4, 4, 16, 0};
    short data[OutputBufferCount][FramesPerBuffer * 2]{};
    WAVEHDR headers[OutputBufferCount]{};
    // dont open the audio device until theres actually music to play.
    InterlockedExchange(&ready, 1);
    for (;;)
    {
        int queued = 0;
        for (auto &h : headers)
            if (h.dwFlags & WHDR_INQUEUE)
                queued++;
        if (!HasActiveRequest(ReadSnapshot(), GetTickCount64()) && !HasFadingVoices())
        {
            if (queued)
            {
                Sleep(3);
                continue;
            }
            CloseDevice(device, headers);
            InterlockedExchange(&sleeping, 1);
            // check again so a request arriving right now doesnt get missed.
            if (!HasActiveRequest(ReadSnapshot(), GetTickCount64()))
                WaitForSingleObject(wakeEvent, INFINITE);
            InterlockedExchange(&sleeping, 0);
            continue;
        }
        if (!device)
        {
            if (waveOutOpen(&device, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR)
            {
                InterlockedExchange(&ready, -1);
                return 0;
            }
            InterlockedIncrement(&deviceOpens);
            memset(headers, 0, sizeof(headers));
            for (int i = 0; i < OutputBufferCount; i++)
            {
                headers[i].lpData = reinterpret_cast<char *>(data[i]);
                headers[i].dwBufferLength = sizeof(data[i]);
                if (waveOutPrepareHeader(device, &headers[i], sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
                {
                    CloseDevice(device, headers);
                    InterlockedExchange(&ready, -1);
                    return 0;
                }
            }
            InterlockedExchange(&deviceOpen, 1);
        }
        for (int i = 0; i < OutputBufferCount; i++)
            if (!(headers[i].dwFlags & WHDR_INQUEUE))
            {
                PlaybackSnapshot state = ReadSnapshot();
                MixBuffer(data[i],
                          FramesPerBuffer,
                          state,
                          GetTickCount64(),
                          double(queued * FramesPerBuffer) / OutputSampleRate);
                if (waveOutWrite(device, &headers[i], sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
                {
                    CloseDevice(device, headers, true);
                    InterlockedExchange(&ready, -1);
                    return 0;
                }
                InterlockedIncrement(&buffersWritten);
                queued++;
            }
        Sleep(3);
    }
}
static bool StartWorker(HMODULE self)
{
    if (worker)
        return true;
    if (!LoadMusicFiles(self))
        return false;
    wakeEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!wakeEvent)
        return false;
    worker = CreateThread(nullptr, 0, AudioWorker, nullptr, 0, nullptr);
    return worker != nullptr;
}
} // namespace EmoteAudio
