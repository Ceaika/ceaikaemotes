#include <windows.h>
static ULONGLONG testClock = 1000;
static ULONGLONG TestClock()
{
    return testClock;
}
#define GetTickCount64 TestClock
#include "emote_visibility.cpp"
#include <cassert>
struct FakeVar
{
    alignas(8) unsigned char memory[0x90]{};
    char text[2048]{};
} request, ready, hidden;
static void InitVar(FakeVar &v, const char *text)
{
    *reinterpret_cast<void **>(v.memory + 0x38) = v.memory;
    *reinterpret_cast<char **>(v.memory + 0x48) = v.text;
    *reinterpret_cast<int64_t *>(v.memory + 0x50) = sizeof(v.text);
    strcpy(v.text, text);
}
static void *Find(void *, const char *s)
{
    return !strcmp(s, "em_native_request")  ? request.memory
           : !strcmp(s, "em_native_ready")  ? ready.memory
           : !strcmp(s, "em_native_hidden") ? hidden.memory
                                            : nullptr;
}
struct FakeRenderable
{
    void **table;
};
struct FakeEntity
{
    void **table;
    uint32_t handle;
    uint32_t pad = 0;
    FakeRenderable renderable;
    char data[0x800]{};
};
static void *fakeRenderTable[33]{};
static void *fakeEntityTable[104]{};
static FakeEntity actor{fakeEntityTable, 101, 0, {fakeRenderTable + 1}};
static FakeEntity weapon{fakeEntityTable, 65538, 0, {fakeRenderTable + 1}};
static void *GetEntity(void *, int index)
{
    return index == 1 ? &actor : index == 2 ? &weapon : nullptr;
}
static bool thirdPerson = false;
static void CameraOffset(void *, float *v)
{
    v[0] = v[1] = 0;
    v[2] = 30;
}
static void CameraData(void *p, void *data, const float *)
{
    *reinterpret_cast<void **>(static_cast<char *>(p) + 0x110) = data;
}
static bool IsThird(void *, int)
{
    return thirdPerson;
}
static void Third(void *)
{
    thirdPerson = true;
}
static void First(void *)
{
    thirdPerson = false;
}
static void *Renderable(void *entity)
{
    return &static_cast<FakeEntity *>(entity)->renderable;
}
static bool cachedVisible = true;
static int visibilityRefreshes = 0;
static bool actorDrawable = true; // false: dead, mid-embark
static bool OriginalShouldDraw(void *)
{
    return actorDrawable;
}
static void RefreshVisibility(void *entity)
{
    ++visibilityRefreshes;
    cachedVisible = GetVirtualFunction<bool (*)(void *)>(Renderable(entity), 3)(Renderable(entity));
}
static int Count()
{
    return *reinterpret_cast<int *>(hidden.memory + 0x5c);
}
int main()
{
    // Validate bounds/guard checks and ensure cached regions expire after scope.
    void *page = VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    assert(page);
    {
        FrameMemoryChecks scope;
        assert(IsMemoryReadable(page, 4096));
        assert(IsMemoryReadable(static_cast<char *>(page) + 4, 8));
        assert(!IsMemoryReadable(reinterpret_cast<void *>(UINTPTR_MAX - 1), 16));
    }
    assert(!readCacheActive && checkedRegionCount == 0);
    DWORD oldProtect;
    VirtualProtect(page, 4096, PAGE_NOACCESS, &oldProtect);
    {
        FrameMemoryChecks scope;
        assert(!IsMemoryReadable(page, 1));
    }
    VirtualFree(page, 0, MEM_RELEASE);

    void *entityVt[9]{};
    entityVt[3] = reinterpret_cast<void *>(&GetEntity);
    void **ev = entityVt;
    entityList = &ev;
    void *cvarVt[42]{};
    cvarVt[15] = reinterpret_cast<void *>(&Find);
    void **cv = cvarVt;
    consoleVariables = &cv;
    fakeEntityTable[4] = reinterpret_cast<void *>(&Renderable);
    fakeEntityTable[103] = reinterpret_cast<void *>(&RefreshVisibility);
    fakeRenderTable[4] = reinterpret_cast<void *>(&OriginalShouldDraw);
    fakeRenderTable[0] = reinterpret_cast<void *>(0x12345678); // RTTI slot must survive.
    supportedClient = true;
    InitVar(request, "");
    InitVar(ready, "0");
    InitVar(hidden, "0");
    strcpy(request.text, "1:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    assert(actor.renderable.table != fakeRenderTable + 1);
    assert(actor.renderable.table[-1] == fakeRenderTable[0]);
    assert(!GetVirtualFunction<bool (*)(void *)>(&actor.renderable, 3)(&actor.renderable));
    // Simulate an engine visibility update during crouch/jump while hooked.
    RefreshVisibility(&actor);
    assert(!cachedVisible);
    const int beforeRestore = visibilityRefreshes;
    testClock += 751;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0);
    assert(actor.renderable.table == fakeRenderTable + 1);
    assert(cachedVisible && visibilityRefreshes == beforeRestore + 1);
    testClock += 751;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0); // Frozen request must never re-hide.
    strcpy(request.text, "2:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    strcpy(request.text, "3:1,999999");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0); // Malformed request restores.
    strcpy(request.text, "4:1,1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1); // Duplicates consume one slot.
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0);
    strcpy(request.text, "5:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    actor.handle = 202;
    actor.renderable.table = fakeRenderTable + 1;
    strcpy(request.text, "6:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0);
    assert(actor.renderable.table == fakeRenderTable + 1);
    // A changed handle does not necessarily reset the renderable's vtable.
    // Re-hiding must not capture our previous hidden table as the original.
    strcpy(request.text, "61:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    actor.handle += 65536;
    strcpy(request.text, "62:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0 && actor.renderable.table == fakeRenderTable + 1);
    assert(GetVirtualFunction<bool (*)(void *)>(&actor.renderable, 3)(&actor.renderable));
    strcpy(request.text, "7:1");
    testClock += 100;
    plugin.RunFrame();
    plugin.OnSqvmDestroying(nullptr);
    assert(Count() == 0);
    attachmentsEnabled = true;
    auto field = [](FakeEntity &e, int at) -> uint32_t &
    { return *reinterpret_cast<uint32_t *>(reinterpret_cast<char *>(&e) + at); };
    field(actor, 0x7a0) = weapon.handle;
    field(weapon, 0xf8) = actor.handle;
    field(weapon, 0x7a0) = field(weapon, 0x7a4) = 0xffffffff;
    strcpy(request.text, "8:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 2);
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0 && weapon.renderable.table == fakeRenderTable + 1);
    field(weapon, 0xf8) = 999;
    strcpy(request.text, "9:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    field(weapon, 0xf8) = actor.handle;
    field(weapon, 0x7a4) = weapon.handle;
    strcpy(request.text, "10:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 2); // Cyclic sibling is bounded.
    weapon.handle += 65536;
    strcpy(request.text, "11:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    void *cameraVt[50]{};
    cameraVt[33] = reinterpret_cast<void *>(&CameraOffset);
    cameraVt[49] = reinterpret_cast<void *>(&CameraData);
    cameraVt[32] = reinterpret_cast<void *>(&IsThird);
    cameraVt[34] = reinterpret_cast<void *>(&Third);
    cameraVt[35] = reinterpret_cast<void *>(&First);
    alignas(8) char cameraObject[0x118]{};
    *reinterpret_cast<void ***>(cameraObject) = cameraVt;
    cameraInput = cameraObject;
    SetEmoteCamera(true);
    assert(thirdPerson && ownsThirdPerson);
    assert(*reinterpret_cast<void **>(cameraObject + 0x110) == &emoteCamera);
    SetEmoteCamera(false);
    assert(!thirdPerson && !*reinterpret_cast<void **>(cameraObject + 0x110));
    thirdPerson = true;
    SetEmoteCamera(true);
    SetEmoteCamera(false);
    assert(thirdPerson && !ownsThirdPerson);
    thirdPerson = false;
    SetEmoteCamera(true);
    RestoreAllEntities();
    assert(!thirdPerson);
    nextIdlePollTime = 0;
    request.text[0] = 0;
    plugin.RunFrame();
    const ULONGLONG poll = nextIdlePollTime;
    strcpy(request.text, "12:1");
    testClock += 99;
    plugin.RunFrame();
    assert(Count() == 0 && nextIdlePollTime == poll);
    testClock += 1;
    plugin.RunFrame();
    assert(Count() == 1 && nextIdlePollTime == 0);
    request.text[0] = 0;
    plugin.RunFrame();
    assert(Count() == 0);

    // A pilot who stops emoting by dying: their restore can't refresh
    // visibility while they can't be drawn (the engine would drop them from
    // the render list and never add them back on respawn); it refreshes once
    // they can be drawn again, once.
    strcpy(request.text, "13:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    RefreshVisibility(&actor); // the engine re-checked while hidden
    assert(!cachedVisible);
    actorDrawable = false;
    const int beforeDeath = visibilityRefreshes;
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0 && actor.renderable.table == fakeRenderTable + 1);
    assert(visibilityRefreshes == beforeDeath);
    testClock += 100;
    plugin.RunFrame();
    assert(visibilityRefreshes == beforeDeath && !cachedVisible);
    actorDrawable = true; // respawned
    testClock += 100;
    plugin.RunFrame();
    assert(visibilityRefreshes == beforeDeath + 1 && cachedVisible);
    testClock += 100;
    plugin.RunFrame();
    assert(visibilityRefreshes == beforeDeath + 1);
    // Hidden again before it could be drawn: that restore refreshes instead.
    strcpy(request.text, "14:1");
    testClock += 100;
    plugin.RunFrame();
    actorDrawable = false;
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    strcpy(request.text, "15:1");
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 1);
    actorDrawable = true;
    const int beforeRehide = visibilityRefreshes;
    testClock += 100;
    plugin.RunFrame();
    assert(visibilityRefreshes == beforeRehide); // still hidden: no refresh
    request.text[0] = 0;
    testClock += 100;
    plugin.RunFrame();
    assert(Count() == 0 && visibilityRefreshes == beforeRehide + 1 && cachedVisible);
    puts("Visibility tests passed: cached crouch/jump visibility refresh, deferred refresh after an "
         "undrawable restore, idle polling and wake, hide, restore, RTTI, timeout, frozen request, malformed "
         "input, duplicate IDs, recycled handle, VM teardown.");
}
