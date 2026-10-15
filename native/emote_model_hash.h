#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace EmoteModels
{
// SHA-256 identifies the exact published MDL payloads supported by the loader.
inline std::string ModelHash(const std::vector<uint8_t> &data)
{
    constexpr uint32_t constants[] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    };
    std::array<uint32_t, 8> hash = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    auto padded = data;
    const uint64_t bits = uint64_t(data.size()) * 8;
    padded.push_back(0x80);
    while (padded.size() % 64 != 56)
        padded.push_back(0);
    for (int shift = 56; shift >= 0; shift -= 8)
        padded.push_back(static_cast<uint8_t>(bits >> shift));
    const auto rotate = [](uint32_t value, int count) { return (value >> count) | (value << (32 - count)); };
    for (size_t block = 0; block < padded.size(); block += 64)
    {
        uint32_t words[64]{};
        for (int i = 0; i < 16; ++i)
            for (int j = 0; j < 4; ++j)
                words[i] = (words[i] << 8) | padded[block + i * 4 + j];
        for (int i = 16; i < 64; ++i)
        {
            const uint32_t a = rotate(words[i - 15], 7) ^ rotate(words[i - 15], 18) ^ (words[i - 15] >> 3);
            const uint32_t b = rotate(words[i - 2], 17) ^ rotate(words[i - 2], 19) ^ (words[i - 2] >> 10);
            words[i] = words[i - 16] + a + words[i - 7] + b;
        }
        auto state = hash;
        for (int i = 0; i < 64; ++i)
        {
            const uint32_t sum1 = rotate(state[4], 6) ^ rotate(state[4], 11) ^ rotate(state[4], 25);
            const uint32_t choose = (state[4] & state[5]) ^ (~state[4] & state[6]);
            const uint32_t first = state[7] + sum1 + choose + constants[i] + words[i];
            const uint32_t sum0 = rotate(state[0], 2) ^ rotate(state[0], 13) ^ rotate(state[0], 22);
            const uint32_t majority = (state[0] & state[1]) ^ (state[0] & state[2]) ^ (state[1] & state[2]);
            for (int j = 7; j > 0; --j)
                state[j] = state[j - 1];
            state[4] += first;
            state[0] = first + sum0 + majority;
        }
        for (size_t i = 0; i < hash.size(); ++i)
            hash[i] += state[i];
    }
    std::string result;
    for (const auto word : hash)
        for (int shift = 28; shift >= 0; shift -= 4)
            result += "0123456789abcdef"[(word >> shift) & 15];
    return result;
}
} // namespace EmoteModels
