// aac music (.m4a) through windows media foundation. the wavs were 108 MB of
// the download, aac at 192k is ~8x smaller and sounds the same, and windows
// already has the decoder so nothing gets bundled or downloaded. N editions of
// windows without the media feature pack dont have it, those can still use wavs
#pragma once
#include <initguid.h>
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace EmoteM4a
{
template <class T> static void Release(T *&p)
{
    if (p)
        p->Release();
    p = nullptr;
}

// media foundation drops the encoder's priming itself but not the padding at
// the end, out comes a multiple of 1024 frames and the mp4 header says the
// padded length too. a loop with that pad in it drifts off the beat by up to
// 20ms every loop, so Encode sticks the wav's real length on the end of the
// file in a "free" box (mp4 readers skip those):
//   be32 size 24, "free", "ceaikafr", le64 frames
static const int TrailerSize = 24;

static unsigned long long TrailerFrames(const wchar_t *path)
{
    FILE *f = _wfopen(path, L"rb");
    if (!f)
        return 0;
    unsigned char tail[TrailerSize]{};
    bool ok = !_fseeki64(f, -TrailerSize, SEEK_END) && fread(tail, 1, TrailerSize, f) == TrailerSize;
    fclose(f);
    if (!ok || tail[3] != TrailerSize || memcmp(tail + 4, "freeceaikafr", 12))
        return 0;
    unsigned long long frames = 0;
    memcpy(&frames, tail + 16, 8);
    return frames;
}

// a COM + media foundation session for the calling thread
struct Session
{
    HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    bool ok = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
    ~Session()
    {
        if (ok)
            MFShutdown();
        if (SUCCEEDED(co))
            CoUninitialize();
    }
};

static bool AudioType(IMFMediaType *&type, const GUID &format, unsigned rate)
{
    return SUCCEEDED(MFCreateMediaType(&type)) && SUCCEEDED(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio)) &&
           SUCCEEDED(type->SetGUID(MF_MT_SUBTYPE, format)) &&
           SUCCEEDED(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16)) &&
           (!rate || (SUCCEEDED(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate)) &&
                      SUCCEEDED(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2))));
}

// decodes a whole file to 16 bit stereo at the file's own rate, cut to the
// trailer's length
static bool Decode(const wchar_t *path, std::vector<short> &pcm, int &rate)
{
    pcm.clear();
    unsigned long long frames = TrailerFrames(path);
    if (!frames || frames > 16000000)
        return false;
    Session session;
    if (!session.ok)
        return false;
    IMFSourceReader *reader = nullptr;
    IMFMediaType *type = nullptr;
    const DWORD audio = DWORD(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
    bool ok = SUCCEEDED(MFCreateSourceReaderFromURL(path, nullptr, &reader)) &&
              SUCCEEDED(reader->SetStreamSelection(DWORD(MF_SOURCE_READER_ALL_STREAMS), FALSE)) &&
              SUCCEEDED(reader->SetStreamSelection(audio, TRUE)) && AudioType(type, MFAudioFormat_PCM, 0) &&
              SUCCEEDED(reader->SetCurrentMediaType(audio, nullptr, type));
    Release(type);
    UINT32 channels = 0, fileRate = 0;
    ok = ok && SUCCEEDED(reader->GetCurrentMediaType(audio, &type)) &&
         SUCCEEDED(type->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels)) &&
         SUCCEEDED(type->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &fileRate)) && channels == 2 &&
         fileRate >= 8000 && fileRate <= 96000;
    Release(type);
    pcm.reserve(size_t(frames + 1024) * 2);
    while (ok)
    {
        DWORD flags = 0;
        LONGLONG time = 0;
        IMFSample *sample = nullptr;
        IMFMediaBuffer *buffer = nullptr;
        if (FAILED(reader->ReadSample(audio, 0, nullptr, &flags, &time, &sample)))
        {
            ok = false;
            break;
        }
        if (sample)
        {
            BYTE *data = nullptr;
            DWORD bytes = 0;
            if (SUCCEEDED(sample->ConvertToContiguousBuffer(&buffer)) && SUCCEEDED(buffer->Lock(&data, nullptr, &bytes)))
            {
                const short *s = reinterpret_cast<const short *>(data);
                pcm.insert(pcm.end(), s, s + bytes / 4 * 2);
                buffer->Unlock();
            }
            else
                ok = false;
            Release(buffer);
            Release(sample);
        }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM)
            break;
        // the pad is under 1024 frames, way past that the trailer is lying
        if (pcm.size() > (frames + 4096) * 2)
            ok = false;
    }
    Release(reader);
    // shorter than the trailer says means the file got cut off somewhere
    ok = ok && pcm.size() >= frames * 2;
    if (ok)
    {
        pcm.resize(size_t(frames) * 2);
        rate = int(fileRate);
    }
    else
        pcm.clear();
    return ok;
}

// 16 bit stereo pcm to aac 192k + the length trailer. the encoder only does
// 44.1 and 48 kHz, anything else fails and stays a wav
static bool Encode(const wchar_t *path, const std::vector<short> &pcm, unsigned rate)
{
    Session session;
    IMFSinkWriter *writer = nullptr;
    IMFMediaType *out = nullptr, *in = nullptr;
    DWORD stream = 0;
    bool ok = session.ok && SUCCEEDED(MFCreateSinkWriterFromURL(path, nullptr, nullptr, &writer)) &&
              AudioType(out, MFAudioFormat_AAC, rate) &&
              SUCCEEDED(out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000)) && // 192 kbit
              SUCCEEDED(writer->AddStream(out, &stream)) && AudioType(in, MFAudioFormat_PCM, rate) &&
              SUCCEEDED(in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4)) &&
              SUCCEEDED(in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, rate * 4)) &&
              SUCCEEDED(writer->SetInputMediaType(stream, in, nullptr)) && SUCCEEDED(writer->BeginWriting());
    const size_t total = pcm.size() / 2, chunk = rate / 10;
    for (size_t at = 0; ok && at < total; at += chunk)
    {
        size_t frames = std::min(chunk, total - at);
        IMFMediaBuffer *buffer = nullptr;
        IMFSample *sample = nullptr;
        BYTE *data = nullptr;
        ok = SUCCEEDED(MFCreateMemoryBuffer(DWORD(frames * 4), &buffer)) && SUCCEEDED(buffer->Lock(&data, nullptr, nullptr));
        if (ok)
        {
            memcpy(data, pcm.data() + at * 2, frames * 4);
            buffer->Unlock();
        }
        ok = ok && SUCCEEDED(buffer->SetCurrentLength(DWORD(frames * 4))) && SUCCEEDED(MFCreateSample(&sample)) &&
             SUCCEEDED(sample->AddBuffer(buffer)) && SUCCEEDED(sample->SetSampleTime(LONGLONG(at * 10000000ull / rate))) &&
             SUCCEEDED(sample->SetSampleDuration(LONGLONG(frames * 10000000ull / rate))) &&
             SUCCEEDED(writer->WriteSample(stream, sample));
        Release(sample);
        Release(buffer);
    }
    ok = ok && SUCCEEDED(writer->Finalize());
    Release(in);
    Release(out);
    Release(writer);
    if (!ok)
        return false;
    unsigned char tail[TrailerSize] = {0, 0, 0, TrailerSize};
    unsigned long long frames = total;
    memcpy(tail + 4, "freeceaikafr", 12);
    memcpy(tail + 16, &frames, 8);
    FILE *f = _wfopen(path, L"ab");
    ok = f && fwrite(tail, 1, sizeof(tail), f) == sizeof(tail);
    if (f)
        fclose(f);
    return ok;
}

// how far back lines up with original (frames, + = late) and the snr in dB
// at that shift. the shift is found on a 0.1s piece a quarter of the way in
static void Compare(const std::vector<short> &original, const std::vector<short> &back, int &offset, double &snr)
{
    long long frames = original.size() / 2, got = back.size() / 2;
    auto at = [&](long long j) { return j >= 0 && j < got ? double(back[j * 2]) : 0.0; };
    double best = 1e300;
    offset = 0;
    for (int shift = -4096; shift <= 4096; shift++)
    {
        double error = 0;
        for (long long i = frames / 4; i < std::min(frames, frames / 4 + 4800); i++)
            error += (original[i * 2] - at(i + shift)) * (original[i * 2] - at(i + shift));
        if (error < best)
            best = error, offset = shift;
    }
    double signal = 0, noise = 0;
    for (long long i = 0; i < frames * 2; i++)
    {
        long long j = i + offset * 2;
        double b = j >= 0 && j < got * 2 ? back[j] : 0;
        signal += double(original[i]) * original[i];
        noise += (original[i] - b) * (original[i] - b);
    }
    snr = noise > 0 ? 10 * log10(signal / noise) : 99;
}
} // namespace EmoteM4a
