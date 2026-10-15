// Portable tests of the actual startup preparation, without an engine or Windows.
#include "emote_models.h"
#include <cassert>
#include <chrono>
#include <cstring>
#include <fstream>
#include <cstdio>
#include <iterator>
#include <set>

namespace fs = std::filesystem;
using EmoteModels::Bytes;
static uint32_t Read32(const Bytes &b, size_t at)
{
    uint32_t v;
    memcpy(&v, b.data() + at, 4);
    return v;
}
static void Put32(Bytes &b, size_t at, uint32_t v)
{
    memcpy(b.data() + at, &v, 4);
}
static std::string Text(const Bytes &b, size_t at)
{
    return reinterpret_cast<const char *>(b.data() + at);
}
static Bytes Fixture(const std::string &mesh)
{
    Bytes b(0x340, 0);
    memcpy(b.data(), "IDST\x35\0\0\0", 8);
    strcpy(reinterpret_cast<char *>(b.data() + 0x10), "humans/pilots/pilot_medium_reaper_f.mdl");
    memcpy(b.data() + 0x2D0, mesh.data(), mesh.size());
    Put32(b, 0x0C, 0x10);
    Put32(b, 0x154, 1);
    Put32(b, 0x158, 0x300);
    Put32(b, 0x304, 8);
    const char shared[] = "models/humans/pete/pilot_shared.mdl";
    memcpy(b.data() + 0x308, shared, sizeof(shared));
    // v53 packs the studio metadata before PHY, VTX, VVD and optional VVC data.
    for (const size_t field : {size_t(0x1AC), size_t(0x1B0), size_t(0x1B4), size_t(0x1B8)})
    {
        Put32(b, field, static_cast<uint32_t>(b.size()));
        Put32(b, field + 16, 32);
        b.insert(b.end(), 32, static_cast<uint8_t>(field));
    }
    Put32(b, 0x1CC, 0x3C0);
    Put32(b, 0x1D8, 0x3C0);
    Put32(b, 0x50, static_cast<uint32_t>(b.size()));
    return b;
}
static void Write(const fs::path &p, const Bytes &b)
{
    fs::create_directories(p.parent_path());
    std::ofstream f(p, std::ios::binary);
    f.write(reinterpret_cast<const char *>(b.data()), b.size());
    assert(f.good());
}
static void Write(const fs::path &p, const std::string &s)
{
    Write(p, Bytes(s.begin(), s.end()));
}
static Bytes Read(const fs::path &p)
{
    std::ifstream f(p, std::ios::binary);
    assert(f.good());
    return Bytes(std::istreambuf_iterator<char>(f), {});
}
static std::set<std::string> Includes(const Bytes &b)
{
    std::set<std::string> result;
    const auto count = Read32(b, 0x154), offset = Read32(b, 0x158);
    assert(offset + count * 8 <= b.size());
    for (uint32_t i = 0; i < count; ++i)
    {
        const size_t entry = offset + i * 8;
        result.insert(Text(b, entry + Read32(b, entry + 4)));
    }
    return result;
}
static const char *pilots[] = {"pilot_medium_geist_f.mdl",
                               "pilot_medium_geist_m.mdl",
                               "pilot_medium_reaper_f.mdl",
                               "pilot_medium_reaper_m.mdl"};
static const char *grapple = "CAT.EARS.Tech.Test.Pulse.Blade.Female.Grapple.Replace";
static const char *pulse = "CAT.EARS.Tech.Test.Pulse.Blade.Male";

int main()
{
    assert(EmoteModels::ModelHash({}) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    assert(EmoteModels::ModelHash({'a', 'b', 'c'}) ==
           "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    const Bytes source = Fixture("CAT_EARS_MESH");
    Bytes result;
    assert(EmoteModels::PrepareModel(source, "humans/pilots/pilot_medium_geist_f.mdl", result));
    assert(Text(result, 0x10) == "humans/pilots/pilot_medium_geist_f.mdl");
    assert(Text(result, Read32(result, 0x0C)) == "humans/pilots/pilot_medium_geist_f.mdl");
    assert(Read32(result, 0x50) == result.size());
    const size_t studioEnd = Read32(result, 0x1AC);
    // A cached studio header must be sufficient to resolve every include and
    // its name; the separately loaded mesh payload cannot carry these strings.
    const Bytes studio(result.begin(), result.begin() + studioEnd);
    const auto includes = Includes(studio);
    assert(Text(studio, Read32(studio, 0x0C)) == "humans/pilots/pilot_medium_geist_f.mdl");
    assert(std::equal(source.begin() + 0x54, source.begin() + 0x154, result.begin() + 0x54));
    assert(std::equal(source.begin() + 0x15C, source.begin() + 0x1AC, result.begin() + 0x15C));
    assert(std::equal(source.begin() + 0x1DC, source.begin() + 0x340, result.begin() + 0x1DC));
    for (const size_t field : {size_t(0x1AC), size_t(0x1B0), size_t(0x1B4), size_t(0x1B8)})
    {
        const auto before = Read32(source, field), after = Read32(result, field);
        assert(Read32(result, field + 16) == 32);
        assert(std::equal(source.begin() + before, source.begin() + before + 32, result.begin() + after));
    }
    assert(Read32(result, 0x1CC) == result.size());
    assert(Read32(result, 0x1D8) == result.size());
    assert(includes.size() == 17);
    assert(includes.count("models/humans/pete/pilot_shared.mdl"));
    assert(includes.count("models/emotes/emote_oj/anim.mdl"));
    assert(includes.count("models/emotes/griddy_traversal/anim.mdl"));
    Bytes again;
    assert(EmoteModels::PrepareModel(result, "humans/pilots/pilot_medium_geist_f.mdl", again));
    assert(Includes(again) == includes);
    for (const size_t field :
         {size_t(4), size_t(0x50), size_t(0x154), size_t(0x158), size_t(0x1AC), size_t(0x1BC), size_t(0x304)})
    {
        Bytes broken = source;
        Put32(broken, field, 0xFFFFFFFF);
        assert(!EmoteModels::PrepareModel(broken, "humans/pilots/pilot_medium_geist_f.mdl", again));
    }
    Bytes broken = source;
    Put32(broken, 0x304, 0x40);
    assert(!EmoteModels::PrepareModel(broken, "humans/pilots/pilot_medium_geist_f.mdl", again));
    Bytes withoutPhysics = source;
    Put32(withoutPhysics, 0x1B8, 0);
    Put32(withoutPhysics, 0x1C8, 0);
    assert(EmoteModels::PrepareModel(withoutPhysics, "humans/pilots/pilot_medium_geist_f.mdl", again));
    assert(Read32(again, 0x1B8) == 0 && Read32(again, 0x1C8) == 0);
    assert(!EmoteModels::PrepareModel(source, "../../outside.mdl", again));

    const fs::path root =
        fs::temp_directory_path() /
        ("ceaika-models-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    struct Cleanup
    {
        fs::path p;
        ~Cleanup()
        {
            fs::remove_all(p);
        }
    } cleanup{root};
    const auto own = root / "mods/ceaikaemotes";
    Write(own / "mod.json", std::string("{\"Name\":\"ceaikaemotes\",\"Version\":\"0.3.0\"}"));
    for (const auto name : pilots)
    {
        Write(own / "pilot-defaults" / name, Fixture("STOCK_MESH"));
        Write(own / "mod/models/humans/pilots" / name, Fixture("STALE_CAT_MESH"));
    }
    auto report = EmoteModels::PrepareInstalledModels(root, own);
    assert(report.prepared == 4 && report.catEars == 0 && report.failed == 0);
    for (const auto name : pilots)
        assert(Read(own / "mod/models/humans/pilots" / name) == Fixture("STOCK_MESH"));

    // A renamed classic folder and a Thunderstore package must both be resolved
    // by descriptor name, not by the originally published folder names.
    const auto female = root / "mods/renamed-female";
    const auto male = root / "packages/Author-CatEars-1.0.0/mods/renamed-male";
    Write(female / "mod.json",
          std::string("{ /* comment */ \"Name\":\"") + grapple + "\",\"Version\":\"1.0.0\",}");
    Write(male / "mod.json", std::string("{\"Name\":\"") + pulse + "\",\"Version\":\"1.0.0\"}");
    Write(female / "vpk/client_mp_common.bsp.pak000_000.vpk", source);
    Bytes archive(223, '!');
    archive.insert(archive.end(), source.begin(), source.end());
    Write(male / "vpk/client_mp_common.bsp.pak000_000.vpk", archive);
    Write(root / "packages/not-a-package/mods/duplicate/mod.json",
          std::string("{\"Name\":\"") + grapple + "\",\"Version\":\"2.0.0\"}");
    // New mods with no config entry default to enabled, as in Northstar.
    report = EmoteModels::PrepareInstalledModels(root, own);
    assert(report.prepared == 4 && report.catEars == 0 && report.failed == 2);
    assert(Text(Read(own / "mod/models/humans/pilots" / pilots[0]), 0x2D0) == "STOCK_MESH");
    assert(Text(Read(own / "mod/models/humans/pilots" / pilots[3]), 0x2D0) == "STOCK_MESH");
    assert(Read(female / "vpk/client_mp_common.bsp.pak000_000.vpk") == source);
    assert(Read(male / "vpk/client_mp_common.bsp.pak000_000.vpk") == archive);

    // Unknown source hashes fall back even when the descriptor matches.
    // Disabling one version restores byte-identical main assets on next start.
    Write(root / "enabledmods.json",
          std::string("{\"Version\":1,\"") + grapple + "\":{\"1.0.0\":false},\"" + pulse +
              "\":{\"1.0.0\":true}}");
    report = EmoteModels::PrepareInstalledModels(root, own);
    assert(report.catEars == 0 && report.failed == 1);
    assert(Read(own / "mod/models/humans/pilots" / pilots[0]) == Fixture("STOCK_MESH"));
    Write(male / "vpk/client_mp_common.bsp.pak000_000.vpk", std::string("truncated"));
    report = EmoteModels::PrepareInstalledModels(root, own);
    assert(report.catEars == 0 && report.prepared == 4 && report.failed == 1);
    assert(Read(own / "mod/models/humans/pilots" / pilots[3]) == Fixture("STOCK_MESH"));

    // An invalid manifest version is reset by Northstar to default-enabled.
    Write(root / "enabledmods.json",
          std::string("{\"Version\":\"invalid\",\"") + grapple + "\":{\"1.0.0\":false}}");
    report = EmoteModels::PrepareInstalledModels(root, own);
    assert(report.catEars == 0 && report.failed == 2);

    // Duplicate enabled versions are all disabled, matching Northstar.
    Write(root / "enabledmods.json", std::string("{\"Version\":1}"));
    Write(root / "mods/duplicate/mod.json",
          std::string("{\"Name\":\"") + grapple + "\",\"Version\":\"2.0.0\"}");
    report = EmoteModels::PrepareInstalledModels(root, own);
    assert(report.catEars == 0);
    assert(Read(own / "mod/models/humans/pilots" / pilots[0]) == Fixture("STOCK_MESH"));

    puts("Model native tests passed: stock fallback, Cat Ears selection, disabling, duplicate versions, "
         "invalid models, cached studio metadata, packed payloads and animation includes.");
}
