#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cassert>
#include "emote_audio.h"
using namespace EmoteAudio;
int main()
{
    tracks[0].resize(OutputSampleRate * 2);
    wakeEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    worker = CreateThread(nullptr, 0, AudioWorker, nullptr, 0, nullptr);
    for (int i = 0; i < 100 && !sleeping; i++)
        Sleep(10);
    assert(ready == 1 && sleeping == 1 && buffersWritten == 0 && deviceOpens == 0 && deviceOpen == 0);
    Sleep(200);
    assert(buffersWritten == 0);
    SubmitRequest("1:1,0,0.00001,0,1");
    Sleep(100);
    assert(!sleeping && buffersWritten > 0 && deviceOpen == 1 && deviceOpens == 1);
    ClearRequests();
    for (int i = 0; i < 100 && !sleeping; i++)
        Sleep(10);
    assert(sleeping && deviceOpen == 0 && deviceCloses == 1);
    LONG saved = buffersWritten;
    Sleep(200);
    assert(saved == buffersWritten);
    SubmitRequest("2:1,0,0.00001,0,1");
    Sleep(150);
    assert(buffersWritten > saved && deviceOpen == 1 && deviceOpens == 2);
    Sleep(1000);
    assert(sleeping && deviceOpen == 0 && deviceCloses == 2);
    saved = buffersWritten;
    Sleep(200);
    assert(saved == buffersWritten);
    puts("Idle worker passed: no buffers when idle, request wake, fade/drain then sleep, second wake, "
         "watchdog sleep, device unopened at startup, close/reopen lifecycle.");
}
