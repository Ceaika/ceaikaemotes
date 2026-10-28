// hide the normal pilot locally; the server still owns the actual player.
// ABI references: local IonLauncher include/client/iclientrenderable.h,
// icliententitylist.h, iclientunknown.h, tier1/cvar.h and convar.h.
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "emote_audio.h"

using InterfaceFactory = void *(*)(const char *, int *);
template <class F> F GetVirtualFunction(void *p, int i)
{
    return reinterpret_cast<F>((*reinterpret_cast<void ***>(p))[i]);
}
struct NorthstarData
{
    HMODULE handle;
    uint64_t size;
};
struct PluginLogger
{
    virtual void Log(int64_t, int, char *) = 0;
    virtual void Unload(int64_t) = 0;
    virtual void Reload(int64_t) = 0;
};
struct PluginIdentity
{
    virtual const char *GetString(int) = 0;
    virtual int64_t GetField(int) = 0;
};
struct PluginCallbacks
{
    virtual void Init(HMODULE, const NorthstarData *, bool) = 0;
    virtual void Finalize() = 0;
    virtual bool Unload() = 0;
    virtual void OnSqvmCreated(void *) = 0;
    virtual void OnSqvmDestroying(void *) = 0;
    virtual void OnLibraryLoaded(HMODULE, const char *) = 0;
    virtual void RunFrame() = 0;
};
static PluginLogger *logger = nullptr;
static volatile LONG logCount = 0;
static void Log(const char *s)
{
    if (logger)
        logger->Log(0, 0, const_cast<char *>(s));
    InterlockedIncrement(&logCount);
}
static void *entityList = nullptr, *consoleVariables = nullptr;
static bool supportedClient = false;
static ULONGLONG nextIdlePollTime = 0;
static bool attachmentsEnabled = false;
static void *cameraInput = nullptr;
static bool ownsThirdPerson = false;
struct CameraThirdData
{
    float pitch = 0, yaw = 0, distance = 180, lag = 1;
    float minimum[3]{-8, -8, -8}, maximum[3]{8, 8, 8};
};
static_assert(sizeof(CameraThirdData) == 40);
static CameraThirdData emoteCamera;
static void *previousCameraData = nullptr;
static float previousCameraOffset[3]{};

// already checked this memory, dont tank the fps checking it again.
// throw the results away after this callback.
struct ReadableRegion
{
    uintptr_t begin = 0, end = 0;
};
static thread_local ReadableRegion checkedRegions[64];
static thread_local int checkedRegionCount = 0;
static thread_local bool readCacheActive = false;
struct FrameMemoryChecks
{
    FrameMemoryChecks()
    {
        checkedRegionCount = 0;
        readCacheActive = true;
    }
    ~FrameMemoryChecks()
    {
        readCacheActive = false;
        checkedRegionCount = 0;
    }
};
static bool IsMemoryReadable(const void *, size_t);
static void SetEmoteCamera(bool enabled)
{
    if (!cameraInput)
        return;
    if (enabled && !ownsThirdPerson)
    {
        if (!GetVirtualFunction<bool (*)(void *, int)>(cameraInput, 32)(cameraInput, -1))
        {
            if (!IsMemoryReadable(cameraInput, 0x118))
                return;
            // Per-user camera data at CInput + 18 + F8, as in Ion input.h.
            previousCameraData = *reinterpret_cast<void **>(static_cast<char *>(cameraInput) + 0x110);
            GetVirtualFunction<void (*)(void *, float *)>(cameraInput, 33)(cameraInput, previousCameraOffset);
            GetVirtualFunction<void (*)(void *)>(cameraInput, 34)(cameraInput);
            float offset[3];
            GetVirtualFunction<void (*)(void *, float *)>(cameraInput, 33)(cameraInput, offset);
            offset[2] = emoteCamera.distance;
            // Game-supported custom third-person data uses CAM_CameraThirdThink, including
            // its collision hull trace, rather than the developer-console camera path.
            GetVirtualFunction<void (*)(void *, void *, const float *)>(cameraInput, 49)(
                cameraInput, &emoteCamera, offset);
            ownsThirdPerson = true;
        }
    }
    else if (!enabled && ownsThirdPerson)
    {
        GetVirtualFunction<void (*)(void *, void *, const float *)>(cameraInput, 49)(
            cameraInput, previousCameraData, previousCameraOffset);
        GetVirtualFunction<void (*)(void *)>(cameraInput, 35)(cameraInput);
        ownsThirdPerson = false;
    }
}
static void *GetEngineInterface(HMODULE h, const char *name)
{
    auto f = reinterpret_cast<InterfaceFactory>(h ? GetProcAddress(h, "CreateInterface") : nullptr);
    return f ? f(name, nullptr) : nullptr;
}
static bool IsMemoryReadable(const void *p, size_t bytes)
{
    if (!p)
        return false;
    uintptr_t begin = reinterpret_cast<uintptr_t>(p), end = begin + bytes;
    if (end < begin)
        return false;
    if (readCacheActive)
        for (int i = 0; i < checkedRegionCount; i++)
            if (begin >= checkedRegions[i].begin && end <= checkedRegions[i].end)
                return true;
    MEMORY_BASIC_INFORMATION m{};
    if (!VirtualQuery(p, &m, sizeof(m)) || m.State != MEM_COMMIT ||
        (m.Protect & (PAGE_GUARD | PAGE_NOACCESS)))
        return false;
    uintptr_t regionBegin = reinterpret_cast<uintptr_t>(m.BaseAddress),
              regionEnd = regionBegin + m.RegionSize;
    if (end > regionEnd)
        return false;
    if (readCacheActive && checkedRegionCount < 64)
        checkedRegions[checkedRegionCount++] = {regionBegin, regionEnd};
    return true;
}
static void *FindConVar(const char *name)
{
    return consoleVariables ? GetVirtualFunction<void *(*)(void *, const char *)>(consoleVariables,
                                                                                  15)(consoleVariables, name)
                            : nullptr;
}
static char *ReadConVarString(void *v)
{
    if (!IsMemoryReadable(v, 0x40))
        return nullptr;
    void *parent = *reinterpret_cast<void **>(static_cast<char *>(v) + 0x38);
    return IsMemoryReadable(parent, 0x60) ? *reinterpret_cast<char **>(static_cast<char *>(parent) + 0x48)
                                          : nullptr;
}
static void SetDiagnosticValue(const char *name, int value)
{
    void *v = FindConVar(name);
    if (!v)
        return;
    void *parent = *reinterpret_cast<void **>(static_cast<char *>(v) + 0x38);
    if (!IsMemoryReadable(parent, 0x60) ||
        *reinterpret_cast<int *>(static_cast<char *>(parent) + 0x5c) == value)
        return;
    // only our status counters go through here, not gameplay settings.
    // the engine overloads dont line up reliably across compilers.
    *reinterpret_cast<float *>(static_cast<char *>(parent) + 0x58) = static_cast<float>(value);
    *reinterpret_cast<int *>(static_cast<char *>(parent) + 0x5c) = value;
    char *text = *reinterpret_cast<char **>(static_cast<char *>(parent) + 0x48);
    auto capacity = *reinterpret_cast<int64_t *>(static_cast<char *>(parent) + 0x50);
    char formatted[16];
    int length = snprintf(formatted, sizeof(formatted), "%d", value);
    if (capacity > length && IsMemoryReadable(text, length + 1))
        memcpy(text, formatted, length + 1);
}

static void *FindEntity(int index)
{
    return entityList ? GetVirtualFunction<void *(*)(void *, int)>(entityList, 3)(entityList, index)
                      : nullptr;
}
static uint32_t EntityHandle(void *p)
{
    return *reinterpret_cast<uint32_t *>(static_cast<char *>(p) + 8);
}
static void CollectAttachedModels(int parentIndex, int *wanted, int &count)
{
    if (!attachmentsEnabled)
        return;
    void *parent = FindEntity(parentIndex);
    if (!IsMemoryReadable(parent, 0x7a8))
        return;
    // Ion SDK baseentity.h: LerpData ends at F8 (move parent).
    // Four 32-bit child handles precede flags + model name, then particles at 7C0.
    uint32_t handle = *reinterpret_cast<uint32_t *>(static_cast<char *>(parent) + 0x7a0);
    for (int guard = 0; guard < 32 && count < 128 && handle != 0xffffffffu; guard++)
    {
        int index = handle & 0xffff;
        if (index < 1 || index > 8191 || index == parentIndex)
            break;
        void *child = FindEntity(index);
        if (!IsMemoryReadable(child, 0x7a8) || EntityHandle(child) != handle ||
            *reinterpret_cast<uint32_t *>(static_cast<char *>(child) + 0xf8) != EntityHandle(parent))
            break;
        bool duplicate = false;
        for (int i = 0; i < count; i++)
            if (wanted[i] == index)
                duplicate = true;
        if (!duplicate)
            wanted[count++] = index;
        uint32_t next = *reinterpret_cast<uint32_t *>(static_cast<char *>(child) + 0x7a4);
        if (next == handle)
            break;
        handle = next;
    }
}
static bool HiddenShouldDraw(void *)
{
    return false;
}
static int HiddenDrawModel(void *, const void *, uint32_t, const void *)
{
    return 0;
}
struct HiddenEntity
{
    int index = 0;
    uint32_t handle = 0;
    void *entity = nullptr;
    void *renderable = nullptr;
    void **original = nullptr;
    void *shadow[33]{};
    bool active = false;
};
static HiddenEntity hiddenEntities[128];
static char lastRenderRequest[2048]{};
static ULONGLONG lastRenderHeartbeat = 0;
static bool IsHiddenTable(void **table)
{
    for (auto &s : hiddenEntities)
        if (s.active && table == s.shadow + 1)
            return true;
    return false;
}
// putting the functions back isnt enough after a crouch-jump: the engine may
// have dropped the model from its render list while it was hidden, so it is
// told to check visibility again. That check only keeps a model it can draw
// right now. A pilot who stopped emoting by dying (or mid-embark) can't be
// drawn at that moment, so the check removed them and nothing in the game
// added them back on respawn: invisible until their next emote. Wait until
// the model says it can be drawn, then check.
struct PendingRefresh
{
    int index = 0;
    void *entity = nullptr;
    void *renderable = nullptr;
    ULONGLONG until = 0;
    bool active = false;
};
static PendingRefresh pendingRefreshes[128];
static bool CanDraw(void *renderable)
{
    // Supported Ion IClientRenderable::ShouldDraw, the entry the hook replaces.
    return GetVirtualFunction<bool (*)(void *)>(renderable, 3)(renderable);
}
static void UpdateEntityVisibility(void *entity)
{
    GetVirtualFunction<void (*)(void *)>(entity, 103)(entity); // Supported Ion C_BaseEntity::UpdateVisibility.
}
static void RefreshWhenDrawable(int index, void *entity, void *renderable)
{
    if (CanDraw(renderable))
    {
        UpdateEntityVisibility(entity);
        return;
    }
    PendingRefresh *slot = nullptr;
    for (auto &p : pendingRefreshes)
        if (p.active && p.entity == entity)
            slot = &p;
    for (auto &p : pendingRefreshes)
        if (!slot && !p.active)
            slot = &p;
    if (slot)
        *slot = {index, entity, renderable, GetTickCount64() + 300000, true};
}
static void ServicePendingRefreshes()
{
    ULONGLONG now = GetTickCount64();
    for (auto &p : pendingRefreshes)
    {
        if (!p.active)
            continue;
        // Same object, same renderable, not hidden again (that restore will
        // schedule its own refresh). Respawning keeps the object; a replaced
        // object is set up by the engine itself.
        void *current = FindEntity(p.index);
        if (now > p.until || current != p.entity || !IsMemoryReadable(current, 16) ||
            GetVirtualFunction<void *(*)(void *)>(current, 4)(current) != p.renderable ||
            !IsMemoryReadable(p.renderable, 8) || IsHiddenTable(*reinterpret_cast<void ***>(p.renderable)))
        {
            p.active = false;
            continue;
        }
        if (CanDraw(p.renderable))
        {
            UpdateEntityVisibility(current);
            p.active = false;
        }
    }
}
static void ClearPendingRefreshes()
{
    for (auto &p : pendingRefreshes)
        p.active = false;
}
static void RestoreEntity(HiddenEntity &s)
{
    if (!s.active)
        return;
    void *now = FindEntity(s.index);
    // A live entity can receive a new handle without resetting its renderable.
    // Remove our own hook even in that case, or the next hide can copy the
    // hidden table as its "original" and leave the model permanently hidden.
    // Resolve the renderable from the live entity; never dereference an old one.
    if (now == s.entity && IsMemoryReadable(now, 16) &&
        GetVirtualFunction<void *(*)(void *)>(now, 4)(now) == s.renderable &&
        IsMemoryReadable(s.renderable, 8))
    {
        InterlockedCompareExchangePointer(reinterpret_cast<PVOID volatile *>(s.renderable), s.original, s.shadow + 1);
        s.active = false;
        // also when the engine had already reset the table: its cached
        // visibility may still be from while the model was hidden
        if (!IsHiddenTable(*reinterpret_cast<void ***>(s.renderable)))
            RefreshWhenDrawable(s.index, now, s.renderable);
    }
    s.active = false;
}
static void RestoreAllEntities()
{
    SetEmoteCamera(false);
    for (auto &s : hiddenEntities)
        RestoreEntity(s);
    SetDiagnosticValue("em_native_hidden", 0);
}
static bool HideEntity(int index)
{
    void *entity = FindEntity(index);
    if (!IsMemoryReadable(entity, 16))
        return false;
    for (auto &s : hiddenEntities)
        if (s.active && s.index == index)
            return true;
    void *renderable = GetVirtualFunction<void *(*)(void *)>(entity, 4)(entity);
    if (!IsMemoryReadable(renderable, 8))
        return false;
    void **table = *reinterpret_cast<void ***>(renderable);
    if (!IsMemoryReadable(table - 1, 33 * sizeof(void *)))
        return false;
    for (auto &s : hiddenEntities)
        if (!s.active)
        {
            s.index = index;
            s.entity = entity;
            s.handle = EntityHandle(entity);
            s.renderable = renderable;
            s.original = table;
            memcpy(s.shadow, table - 1, sizeof(s.shadow));
            s.shadow[4] = reinterpret_cast<void *>(&HiddenShouldDraw);
            s.shadow[10] = reinterpret_cast<void *>(&HiddenDrawModel);
            // change this renderable only, not every pilot using the same model.
            s.active = InterlockedCompareExchangePointer(
                           reinterpret_cast<PVOID volatile *>(renderable), s.shadow + 1, table) == table;
            return s.active;
        }
    return false;
}
struct PluginId final : PluginIdentity
{
    const char *GetString(int p) override
    {
        return p == 0 ? "ceaikaemotes" : p == 1 ? "CEA_EMOTES" : "ceaikaemotes";
    }
    int64_t GetField(int p) override
    {
        return p == 0 ? 2 : 0x66ccff;
    }
} id;
static bool ParseRenderRequest(const char *raw, size_t n, int (&wanted)[128], int &count)
{
    // changing counter:entity indices, up to 128 entries.
    char copy[2048];
    memcpy(copy, raw, n + 1);
    char *rest = nullptr;
    strtoul(copy, &rest, 10);
    if (rest == copy || *rest != ':')
    {
        return false;
    }
    ++rest;
    while (*rest && count < 128)
    {
        char *end = nullptr;
        long index = strtol(rest, &end, 10);
        if (end == rest || index < 1 || index > 8191 || (*end && *end != ','))
        {
            return false;
        }
        bool duplicate = false;
        for (int i = 0; i < count; ++i)
            if (wanted[i] == index)
                duplicate = true;
        if (!duplicate)
            wanted[count++] = static_cast<int>(index);
        rest = *end ? end + 1 : end;
    }
    if (*rest)
    {
        return false;
    }
    return true;
}

struct Plugin final : PluginCallbacks
{
    void Init(HMODULE northstar, const NorthstarData *, bool) override
    {
        logger = static_cast<PluginLogger *>(GetEngineInterface(northstar, "NSSys001"));
        Log("Visibility helper loaded; waiting for supported client and emote heartbeat.");
        HMODULE self = nullptr;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(&EmoteAudio::StartWorker),
                           &self);
        Log(EmoteAudio::StartWorker(self) ? "Proximity music worker started."
                                          : "Music file missing or invalid; proximity music disabled.");
        char tracks[96];
        snprintf(tracks,
                 sizeof(tracks),
                 "%ld music tracks (%ld from tracks.txt, %ld failed to load).",
                 EmoteAudio::trackCount,
                 EmoteAudio::trackCount - EmoteAudio::TrackCount,
                 EmoteAudio::extraFailed);
        Log(tracks);
    }
    void Finalize() override
    {
    }
    bool Unload() override
    {
        EmoteAudio::ClearRequests();
        RestoreAllEntities();
        ClearPendingRefreshes();
        Log("Restart Ion to unload visibility helper safely.");
        return false;
    }
    void OnSqvmCreated(void *) override
    {
        nextIdlePollTime = 0;
    }
    void OnSqvmDestroying(void *) override
    {
        nextIdlePollTime = 0;
        EmoteAudio::ClearRequests();
        RestoreAllEntities();
        // the level's entities are going away with this VM
        ClearPendingRefreshes();
    }
    void OnLibraryLoaded(HMODULE module, const char *name) override
    {
        if (_stricmp(name, "vstdlib.dll") == 0)
            consoleVariables = GetEngineInterface(module, "VEngineCvar007");
        if (_stricmp(name, "client.dll") == 0)
        {
            auto dos = reinterpret_cast<IMAGE_DOS_HEADER *>(module);
            auto nt =
                reinterpret_cast<IMAGE_NT_HEADERS64 *>(reinterpret_cast<char *>(module) + dos->e_lfanew);
            supportedClient =
                nt->FileHeader.TimeDateStamp == 0x5a271254 && nt->OptionalHeader.SizeOfImage == 0x3d4c000;
            if (supportedClient)
                entityList = GetEngineInterface(module, "VClientEntityList003");
            // Supported Ion SDK src/client/input.cpp: CInput at client + B1D380.
            if (supportedClient)
                cameraInput = reinterpret_cast<char *>(module) + 0xB1D380;
            attachmentsEnabled = supportedClient;
            Log(supportedClient && entityList ? "Supported client entity/render interfaces ready."
                                              : "Unsupported client build; body hiding disabled.");
        }
    }
    void RunFrame() override
    {
        ULONGLONG now = GetTickCount64();
        if (now < nextIdlePollTime)
            return;
        nextIdlePollTime = now + 100;
        FrameMemoryChecks readFrameScope;
        if (!consoleVariables)
            consoleVariables = GetEngineInterface(GetModuleHandleA("vstdlib.dll"), "VEngineCvar007");
        SetDiagnosticValue("em_native_ready", supportedClient && entityList ? 1 : 0);
        SetDiagnosticValue("em_audio_ready", EmoteAudio::ready);
        SetDiagnosticValue("em_audio_voices", EmoteAudio::playing);
        SetDiagnosticValue("em_audio_idle", EmoteAudio::sleeping);
        SetDiagnosticValue("em_audio_device", EmoteAudio::deviceOpen);
        // scripts only request tracks this DLL has; older DLLs leave it at 0.
        SetDiagnosticValue("em_audio_tracks", EmoteAudio::trackCount);
        if (!supportedClient || !entityList || !consoleVariables)
        {
            EmoteAudio::ClearRequests();
            return;
        }
        // before the early returns below: restores happen when nobody emotes too
        ServicePendingRefreshes();
        const char *audio = ReadConVarString(FindConVar("em_audio_request"));
        if (audio && *audio)
            nextIdlePollTime = 0;
        EmoteAudio::SubmitRequest(audio);
        char *raw = ReadConVarString(FindConVar("em_native_request"));
        if (!raw || !IsMemoryReadable(raw, 1))
        {
            RestoreAllEntities();
            return;
        }
        size_t n = strnlen(raw, sizeof(lastRenderRequest));
        if (n == 0 || n >= sizeof(lastRenderRequest))
        {
            RestoreAllEntities();
            return;
        }
        nextIdlePollTime = 0;
        if (strcmp(raw, lastRenderRequest) != 0)
        {
            memcpy(lastRenderRequest, raw, n + 1);
            lastRenderHeartbeat = now;
        }
        if (now - lastRenderHeartbeat > 750)
        {
            RestoreAllEntities();
            return;
        }
        const char *camera = ReadConVarString(FindConVar("em_camera_request"));
        emoteCamera.distance = camera && strcmp(camera, "2") == 0 ? 520.0f : 180.0f;
        SetEmoteCamera(camera && (strcmp(camera, "1") == 0 || strcmp(camera, "2") == 0));
        int wanted[128]{};
        int count = 0;
        if (!ParseRenderRequest(raw, n, wanted, count))
        {
            RestoreAllEntities();
            return;
        }
        for (int i = 0; i < count && count < 128; i++)
            CollectAttachedModels(wanted[i], wanted, count);
        for (auto &s : hiddenEntities)
            if (s.active)
            {
                bool keep = false;
                for (int i = 0; i < count; ++i)
                    if (wanted[i] == s.index)
                        keep = true;
                void *current = FindEntity(s.index);
                if (!keep || current != s.entity || !IsMemoryReadable(current, 16) ||
                    EntityHandle(current) != s.handle)
                    RestoreEntity(s);
            }
        for (int i = 0; i < count; ++i)
            HideEntity(wanted[i]);
        int hidden = 0;
        for (auto &s : hiddenEntities)
            if (s.active)
                ++hidden;
        SetDiagnosticValue("em_native_hidden", hidden);
    }
} plugin;
extern "C" __declspec(dllexport) void *CreateInterface(const char *name, int *status)
{
    void *p = strcmp(name, "PluginId001") == 0 ? static_cast<void *>(static_cast<PluginIdentity *>(&id))
              : strcmp(name, "PluginCallbacks001") == 0
                  ? static_cast<void *>(static_cast<PluginCallbacks *>(&plugin))
                  : nullptr;
    if (status)
        *status = p ? 0 : 1;
    return p;
}
