#pragma once
#ifdef _WIN32
#include <windows.h>
#endif
#include <cstdint>
#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <regex>
#include <string>
#include <vector>
#include "emote_model_json.h"
#include "emote_model_hash.h"

namespace EmoteModels
{
using Bytes = std::vector<uint8_t>;
using Logger = void (*)(const char *);
struct Report
{
    int prepared = 0;
    int catEars = 0;
    int failed = 0;
};
namespace fs = std::filesystem;
struct Pilot
{
    const char *name;
    const char *mod;
    size_t archiveOffset;
    const char *sourceHash;
};
inline constexpr char FemaleHash[] = "59fa9c87f9228597701236d7054fa22e2f86604206587e8fd04c8017ca386b9c";
inline constexpr char MaleHash[] = "92e82d045cd765260e99f216c07061d42684fd75cd4ad1180bdd909f921d9c58";
inline constexpr Pilot Pilots[] = {
    {"pilot_medium_geist_f.mdl", "CAT.EARS.Tech.Test.Pulse.Blade.Female.Grapple.Replace", 0, FemaleHash},
    {"pilot_medium_geist_m.mdl", "CAT.EARS.Tech.Test.Pulse.Blade.Male.Grapple.Replace", 0, MaleHash},
    {"pilot_medium_reaper_f.mdl", "CAT.EARS.Tech.Test.Pulse.Blade.Female", 223, FemaleHash},
    {"pilot_medium_reaper_m.mdl", "CAT.EARS.Tech.Test.Pulse.Blade.Male", 223, MaleHash},
};
inline constexpr const char *Animations[] = {
    "models/emotes/bbd_traversal/anim.mdl",
    "models/emotes/emote_dancemoves/anim.mdl",
    "models/emotes/emote_electroshuffle/anim.mdl",
    "models/emotes/electroswing_auto/anim.mdl",
    "models/emotes/emote_floss/anim.mdl",
    "models/emotes/emote_freestylin/anim.mdl",
    "models/emotes/griddy_traversal/anim.mdl",
    "models/emotes/emote_hype/anim.mdl",
    "models/emotes/emote_oj/anim.mdl",
    "models/emotes/emote_laugh/anim.mdl",
    "models/emotes/emote_rambunctious/anim.mdl",
    "models/emotes/emote_technozombie/anim.mdl",
    "models/emotes/emote_smoothmoves/anim.mdl",
    "models/emotes/emote_squatkick/anim.mdl",
    "models/emotes/emote_takethel/anim.mdl",
    "models/emotes/emote_worm/anim.mdl",
};
inline uint32_t U32(const Bytes &b, size_t offset)
{
    uint32_t value;
    std::memcpy(&value, b.data() + offset, sizeof(value));
    return value;
}
inline void U32(Bytes &b, size_t offset, uint32_t value)
{
    std::memcpy(b.data() + offset, &value, sizeof(value));
}
inline bool ModelString(const Bytes &b, int64_t offset, std::string &out)
{
    if (offset <= 0 || static_cast<uint64_t>(offset) >= b.size())
        return false;
    const auto begin = b.begin() + offset, end = std::find(begin, b.end(), 0);
    if (end == b.end())
        return false;
    out.assign(begin, end);
    return true;
}
inline bool PrepareModel(const Bytes &source, const std::string &name, Bytes &result)
{
    bool supported = false;
    for (const auto &pilot : Pilots)
        if (name == std::string("humans/pilots/") + pilot.name)
            supported = true;
    if (!supported || source.size() < 0x2CC || source.size() > 64 * 1024 * 1024 ||
        std::memcmp(source.data(), "IDST\x35\0\0\0", 8) || U32(source, 0x50) != source.size())
        return false;
    size_t studioEnd = source.size();
    for (size_t field = 0x1AC; field <= 0x1B8; field += 4)
    {
        const auto offset = U32(source, field), size = U32(source, field + 16);
        if (!offset && !size)
            continue;
        if (offset < 0x2CC || offset > source.size() || uint64_t(offset) + size > source.size())
            return false;
        studioEnd = std::min(studioEnd, size_t(offset));
    }
    const auto count = U32(source, 0x154), table = U32(source, 0x158);
    if (count > 4096 || table > studioEnd || uint64_t(table) + uint64_t(count) * 8 > studioEnd)
        return false;
    Bytes studio(source.begin(), source.begin() + studioEnd);
    std::vector<std::pair<std::string, std::string>> includes;
    for (uint32_t i = 0; i < count; ++i)
    {
        const auto entry = table + i * 8;
        const int32_t labelOffset = static_cast<int32_t>(U32(source, entry));
        const int32_t nameOffset = static_cast<int32_t>(U32(source, entry + 4));
        std::string label, path;
        if ((labelOffset && !ModelString(studio, int64_t(entry) + labelOffset, label)) ||
            !ModelString(studio, int64_t(entry) + nameOffset, path) || path.empty())
            return false;
        includes.emplace_back(label, path);
    }
    for (const char *animation : Animations)
        if (std::none_of(includes.begin(),
                         includes.end(),
                         [animation](const auto &p) { return p.second == animation; }))
            includes.emplace_back("", animation);
    // The cache loads studio metadata separately from the packed PHY/VTX/VVD/VVC
    // payloads. Includes and names appended after those payloads are not resident.
    result = std::move(studio);
    while (result.size() % 4)
        result.push_back(0);
    const auto newTable = result.size();
    result.resize(newTable + includes.size() * 8, 0);
    for (size_t i = 0; i < includes.size(); ++i)
    {
        const auto entry = newTable + i * 8;
        if (!includes[i].first.empty())
        {
            U32(result, entry, static_cast<uint32_t>(result.size() - entry));
            result.insert(result.end(), includes[i].first.begin(), includes[i].first.end());
            result.push_back(0);
        }
        U32(result, entry + 4, static_cast<uint32_t>(result.size() - entry));
        result.insert(result.end(), includes[i].second.begin(), includes[i].second.end());
        result.push_back(0);
    }
    U32(result, 0x154, static_cast<uint32_t>(includes.size()));
    U32(result, 0x158, static_cast<uint32_t>(newTable));
    U32(result, 0x0C, static_cast<uint32_t>(result.size()));
    result.insert(result.end(), name.begin(), name.end());
    result.push_back(0);
    std::fill(result.begin() + 0x10, result.begin() + 0x50, 0);
    std::copy(name.begin(), name.end(), result.begin() + 0x10);
    // Preserve each payload's alignment and contents, changing only its file offset.
    while ((result.size() - studioEnd) % 16)
        result.push_back(0);
    const auto added = static_cast<uint32_t>(result.size() - studioEnd);
    for (const size_t field :
         {size_t(0x1AC), size_t(0x1B0), size_t(0x1B4), size_t(0x1B8), size_t(0x1CC), size_t(0x1D8)})
    {
        const auto offset = U32(source, field);
        if (offset && offset >= studioEnd)
            U32(result, field, offset + added);
    }
    result.insert(result.end(), source.begin() + studioEnd, source.end());
    U32(result, 0x50, static_cast<uint32_t>(result.size()));
    return true;
}
inline bool ReadFile(const fs::path &path, Bytes &data, size_t limit = 64 * 1024 * 1024)
{
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file)
        return false;
    const auto length = file.tellg();
    if (length < 0 || static_cast<uint64_t>(length) > limit)
        return false;
    data.resize(static_cast<size_t>(length));
    file.seekg(0);
    if (!data.empty())
        file.read(reinterpret_cast<char *>(data.data()), data.size());
    return file.good();
}
inline bool ReadJson(const fs::path &path, Json &value)
{
    Bytes data;
    if (!ReadFile(path, data, 1024 * 1024))
        return false;
    try
    {
        const std::string text(data.begin(), data.end());
        value = JsonReader(text).Read();
        return value.type == '{';
    }
    catch (const std::exception &)
    {
        return false;
    }
}
inline bool Enabled(const Json &config, const std::string &name, const std::string &version)
{
    const auto entry = config.Find(name);
    if (!entry)
        return true;
    // Northstar migrates the old {"Mod.Name":false} format on startup.
    const auto format = config.Find("Version");
    if (!format || (format->type == 'd' && format->text == "0"))
        return entry->type != 'b' || entry->boolean;
    if (format->type != 'd' || format->text.find_first_of(".eE") != std::string::npos)
        return true;
    const auto formatNumber = std::strtoll(format->text.c_str(), nullptr, 10);
    if (formatNumber < INT32_MIN || formatNumber > INT32_MAX)
        return true;
    const auto state = entry->Find(version);
    return !state || (state->type == 'b' && state->boolean);
}
inline std::vector<fs::path> ModDirectories(const fs::path &profile)
{
    std::vector<fs::path> dirs;
    const auto addChildren = [&dirs](const fs::path &root)
    {
        std::error_code error;
        for (fs::directory_iterator it(root, error), end; !error && it != end; it.increment(error))
        {
            std::error_code probe;
            if (fs::is_regular_file(it->path() / "mod.json", probe))
                dirs.push_back(it->path());
        }
    };
    addChildren(profile / "mods");
    std::error_code error;
    const std::regex packageName("[a-zA-Z0-9_]+-[a-zA-Z0-9_]+-[0-9]+\\.[0-9]+\\.[0-9]+");
    for (fs::directory_iterator it(profile / "packages", error), end; !error && it != end;
         it.increment(error))
        if (std::regex_match(it->path().filename().string(), packageName))
            addChildren(it->path() / "mods");
    // Northstar deliberately disables remote/runtime mods on initial startup.
    return dirs;
}
inline fs::path FindOwnMod(const fs::path &profile, const fs::path &package = {})
{
    auto directories = ModDirectories(profile);
    if (!package.empty())
    {
        // Prefer the mod shipped beside this DLL, rather than a duplicate install.
        const auto root = package / "mods";
        std::error_code error;
        for (fs::directory_iterator it(root, error), end; !error && it != end; it.increment(error))
            directories.insert(directories.begin(), it->path());
    }
    for (const auto &path : directories)
    {
        Json mod;
        if (!ReadJson(path / "mod.json", mod))
            continue;
        const auto name = mod.Find("Name");
        if (name && name->type == 's' && name->text == "ceaikaemotes" &&
            fs::is_directory(path / "pilot-defaults"))
            return path;
    }
    return {};
}
inline bool ArchiveModel(const fs::path &path, size_t offset, Bytes &model)
{
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file)
        return false;
    const auto total = file.tellg();
    if (total < 0 || static_cast<uint64_t>(total) < offset + 0x1D8)
        return false;
    model.resize(0x1D8);
    file.seekg(offset);
    file.read(reinterpret_cast<char *>(model.data()), model.size());
    const auto length = U32(model, 0x50);
    if (!file || std::memcmp(model.data(), "IDST\x35\0\0\0", 8) || length < model.size() ||
        length > 64 * 1024 * 1024 || uint64_t(offset) + length > static_cast<uint64_t>(total))
        return false;
    model.resize(length);
    file.seekg(offset);
    file.read(reinterpret_cast<char *>(model.data()), model.size());
    return file.good();
}
inline bool WriteModel(const fs::path &path, const Bytes &data)
{
    Bytes previous;
    if (ReadFile(path, previous) && previous == data)
        return true;
    fs::create_directories(path.parent_path());
    auto temp = path;
    temp += ".ceaika.tmp";
    {
        std::ofstream file(temp, std::ios::binary | std::ios::trunc);
        if (!file)
            return false;
        file.write(reinterpret_cast<const char *>(data.data()), data.size());
        file.close();
        if (!file)
        {
            fs::remove(temp);
            return false;
        }
    }
#ifdef _WIN32
    if (!MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    {
        fs::remove(temp);
        return false;
    }
#else
    std::error_code error;
    fs::rename(temp, path, error);
    if (error)
    {
        fs::remove(temp);
        return false;
    }
#endif
    return true;
}
inline Report PrepareInstalledModels(const fs::path &profile, const fs::path &own, Logger log = nullptr)
{
    Report report;
    const auto note = [log](const std::string &s)
    {
        if (log)
            log(s.c_str());
    };
    Json config;
    ReadJson(profile / "enabledmods.json", config);
    std::map<std::string, std::vector<fs::path>> enabled;
    for (const auto &path : ModDirectories(profile))
    {
        Json descriptor;
        if (!ReadJson(path / "mod.json", descriptor))
            continue;
        const auto name = descriptor.Find("Name"), version = descriptor.Find("Version");
        if (!name || name->type != 's')
            continue;
        if (!Enabled(config, name->text, version && version->type == 's' ? version->text : "0.0.0"))
            continue;
        enabled[name->text].push_back(path);
    }
    for (const auto &pilot : Pilots)
    {
        try
        {
            Bytes output;
            if (!ReadFile(own / "pilot-defaults" / pilot.name, output))
            {
                ++report.failed;
                note(std::string("Missing pristine pilot default: ") + pilot.name);
                continue;
            }
            bool selected = false;
            const auto matches = enabled.find(pilot.mod);
            if (matches != enabled.end() && matches->second.size() == 1)
            {
                Bytes source, prepared;
                const auto vpk = matches->second.front() / "vpk/client_mp_common.bsp.pak000_000.vpk";
                if (ArchiveModel(vpk, pilot.archiveOffset, source) && ModelHash(source) == pilot.sourceHash &&
                    PrepareModel(source, std::string("humans/pilots/") + pilot.name, prepared))
                {
                    output = std::move(prepared);
                    selected = true;
                }
                else
                {
                    ++report.failed;
                    note(std::string("Cannot prepare Cat Ears VPK; using stock pilot: ") + vpk.string());
                }
            }
            if (!WriteModel(own / "mod/models/humans/pilots" / pilot.name, output))
            {
                ++report.failed;
                note(std::string("Cannot write pilot override: ") + pilot.name);
                continue;
            }
            ++report.prepared;
            if (selected)
            {
                ++report.catEars;
                note(std::string("Cat Ears dance model ready: ") + pilot.name);
            }
        }
        catch (const std::exception &e)
        {
            ++report.failed;
            note(std::string("Pilot preparation failed: ") + e.what());
        }
    }
    return report;
}
} // namespace EmoteModels
