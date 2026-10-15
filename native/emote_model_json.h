#pragma once
#include <cctype>
#include <cstdlib>
#include <map>
#include <stdexcept>
#include <string>

namespace EmoteModels
{
// Read Northstar's descriptors and enabledmods.json, including its supported
// comments/trailing commas. Arrays are parsed but need not be retained.
struct Json
{
    char type = 'n';
    std::string text;
    bool boolean = false;
    std::map<std::string, Json> members;
    const Json *Find(const std::string &key) const
    {
        const auto i = members.find(key);
        return i == members.end() ? nullptr : &i->second;
    }
};
class JsonReader
{
    const std::string &source;
    size_t at = 0;
    void Space()
    {
        while (at < source.size())
        {
            if (std::isspace(static_cast<unsigned char>(source[at])))
            {
                ++at;
                continue;
            }
            if (source.compare(at, 2, "//") == 0)
            {
                at = source.find('\n', at + 2);
                if (at == std::string::npos)
                    at = source.size();
                continue;
            }
            if (source.compare(at, 2, "/*") == 0)
            {
                const auto end = source.find("*/", at + 2);
                if (end == std::string::npos)
                    throw std::runtime_error("Unclosed JSON comment");
                at = end + 2;
                continue;
            }
            break;
        }
    }
    char Take()
    {
        if (at >= source.size())
            throw std::runtime_error("Truncated JSON");
        return source[at++];
    }
    unsigned Hex()
    {
        unsigned value = 0;
        for (int i = 0; i < 4; ++i)
        {
            const char c = Take();
            const auto pos = std::string("0123456789abcdef")
                                 .find(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
            if (pos == std::string::npos)
                throw std::runtime_error("Invalid JSON escape");
            value = value * 16 + static_cast<unsigned>(pos);
        }
        return value;
    }
    std::string String()
    {
        if (Take() != '"')
            throw std::runtime_error("Expected JSON string");
        std::string result;
        while (true)
        {
            char c = Take();
            if (c == '"')
                return result;
            if (static_cast<unsigned char>(c) < 32)
                throw std::runtime_error("Invalid JSON string");
            if (c != '\\')
            {
                result += c;
                continue;
            }
            c = Take();
            switch (c)
            {
            case '"':
            case '\\':
            case '/':
                result += c;
                break;
            case 'b':
                result += '\b';
                break;
            case 'f':
                result += '\f';
                break;
            case 'n':
                result += '\n';
                break;
            case 'r':
                result += '\r';
                break;
            case 't':
                result += '\t';
                break;
            case 'u':
            {
                unsigned cp = Hex();
                if (cp >= 0xd800 && cp <= 0xdbff)
                {
                    if (Take() != '\\' || Take() != 'u')
                        throw std::runtime_error("Invalid JSON surrogate");
                    const auto low = Hex();
                    if (low < 0xdc00 || low > 0xdfff)
                        throw std::runtime_error("Invalid JSON surrogate");
                    cp = 0x10000 + ((cp - 0xd800) << 10) + low - 0xdc00;
                }
                else if (cp >= 0xdc00 && cp <= 0xdfff)
                    throw std::runtime_error("Invalid JSON surrogate");
                if (cp < 0x80)
                    result += static_cast<char>(cp);
                else
                {
                    if (cp < 0x800)
                        result += static_cast<char>(0xc0 | (cp >> 6));
                    else
                    {
                        if (cp < 0x10000)
                            result += static_cast<char>(0xe0 | (cp >> 12));
                        else
                        {
                            result += static_cast<char>(0xf0 | (cp >> 18));
                            result += static_cast<char>(0x80 | ((cp >> 12) & 63));
                        }
                        result += static_cast<char>(0x80 | ((cp >> 6) & 63));
                    }
                    result += static_cast<char>(0x80 | (cp & 63));
                }
                break;
            }
            default:
                throw std::runtime_error("Invalid JSON escape");
            }
        }
    }
    Json Value(int depth)
    {
        if (depth > 32)
            throw std::runtime_error("JSON nesting limit");
        Space();
        Json value;
        if (at >= source.size())
            throw std::runtime_error("Truncated JSON");
        const char first = source[at];
        if (first == '{' || first == '[')
        {
            value.type = Take();
            const char end = first == '{' ? '}' : ']';
            Space();
            while (at < source.size() && source[at] != end)
            {
                std::string key;
                if (first == '{')
                {
                    key = String();
                    Space();
                    if (Take() != ':')
                        throw std::runtime_error("Expected JSON colon");
                }
                auto child = Value(depth + 1);
                if (first == '{')
                    value.members[key] = std::move(child);
                Space();
                if (at < source.size() && source[at] == end)
                    break;
                if (Take() != ',')
                    throw std::runtime_error("Expected JSON comma");
                Space();
            }
            if (Take() != end)
                throw std::runtime_error("Unclosed JSON container");
        }
        else if (first == '"')
        {
            value.type = 's';
            value.text = String();
        }
        else if (source.compare(at, 4, "true") == 0)
        {
            at += 4;
            value.type = 'b';
            value.boolean = true;
        }
        else if (source.compare(at, 5, "false") == 0)
        {
            at += 5;
            value.type = 'b';
        }
        else if (source.compare(at, 4, "null") == 0)
        {
            at += 4;
        }
        else
        {
            const auto begin = at;
            if (source[at] == '-')
                ++at;
            if (at >= source.size() || !std::isdigit(static_cast<unsigned char>(source[at])))
                throw std::runtime_error("Invalid JSON number");
            if (source[at++] != '0')
                while (at < source.size() && std::isdigit(static_cast<unsigned char>(source[at])))
                    ++at;
            if (at < source.size() && source[at] == '.')
            {
                ++at;
                const auto digits = at;
                while (at < source.size() && std::isdigit(static_cast<unsigned char>(source[at])))
                    ++at;
                if (digits == at)
                    throw std::runtime_error("Invalid JSON number");
            }
            if (at < source.size() && (source[at] == 'e' || source[at] == 'E'))
            {
                ++at;
                if (at < source.size() && (source[at] == '+' || source[at] == '-'))
                    ++at;
                const auto digits = at;
                while (at < source.size() && std::isdigit(static_cast<unsigned char>(source[at])))
                    ++at;
                if (digits == at)
                    throw std::runtime_error("Invalid JSON exponent");
            }
            value.type = 'd';
            value.text = source.substr(begin, at - begin);
        }
        return value;
    }

  public:
    explicit JsonReader(const std::string &s) : source(s)
    {
    }
    Json Read()
    {
        auto result = Value(0);
        Space();
        if (at != source.size())
            throw std::runtime_error("Trailing JSON content");
        return result;
    }
};
} // namespace EmoteModels
