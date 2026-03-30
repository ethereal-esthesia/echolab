#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>

static inline uint64_t xorshift64(uint64_t &s) {
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    return s;
}

int main(int argc, char **argv) {
    uint64_t steps = 50000000ULL;
    if (argc > 1) steps = std::strtoull(argv[1], nullptr, 10);

    std::array<uint8_t, 65536> mem{};
    uint8_t a = 0x12, x = 0x34, y = 0x56, p = 0x24;
    uint16_t pc = 0x4000;
    uint64_t state = 0x65022026ULL;

    for (size_t i = 0; i < mem.size(); ++i) mem[i] = static_cast<uint8_t>(i ^ (i >> 8));

    auto t0 = std::chrono::high_resolution_clock::now();
    for (uint64_t i = 0; i < steps; ++i) {
        uint8_t op = static_cast<uint8_t>(xorshift64(state) & 0xFF);
        uint16_t addr = static_cast<uint16_t>(pc + x + (y << 1));
        uint8_t m = mem[addr];

        switch (op & 0x0F) {
            case 0:
                a = static_cast<uint8_t>(a + m + (p & 1));
                p = (p & ~0x83) | (a == 0 ? 0x02 : 0) | (a & 0x80 ? 0x80 : 0);
                break;
            case 1:
                a ^= m;
                p = (p & ~0x82) | (a == 0 ? 0x02 : 0) | (a & 0x80 ? 0x80 : 0);
                break;
            case 2:
                a |= m;
                p = (p & ~0x82) | (a == 0 ? 0x02 : 0) | (a & 0x80 ? 0x80 : 0);
                break;
            case 3:
                a &= m;
                p = (p & ~0x82) | (a == 0 ? 0x02 : 0) | (a & 0x80 ? 0x80 : 0);
                break;
            case 4:
                mem[addr] = static_cast<uint8_t>(m + x);
                break;
            case 5:
                mem[addr] = static_cast<uint8_t>(m - y);
                break;
            case 6:
                x = static_cast<uint8_t>(x + 1);
                break;
            case 7:
                y = static_cast<uint8_t>(y - 1);
                break;
            case 8:
                pc = static_cast<uint16_t>((static_cast<int32_t>(pc) + static_cast<int8_t>(m)) & 0xFFFF);
                break;
            case 9:
                p ^= 0x41;
                break;
            case 10:
                a = static_cast<uint8_t>((a << 1) | (a >> 7));
                break;
            case 11:
                a = static_cast<uint8_t>((a >> 1) | (a << 7));
                break;
            case 12:
                mem[static_cast<uint16_t>(pc + x)] ^= a;
                break;
            case 13:
                mem[static_cast<uint16_t>(pc + y)] += p;
                break;
            case 14:
                x ^= y;
                break;
            default:
                y += a;
                break;
        }
        pc = static_cast<uint16_t>(pc + 1);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double secs = std::chrono::duration<double>(t1 - t0).count();
    double mops = (steps / 1e6) / secs;

    uint64_t checksum = static_cast<uint64_t>(a) | (static_cast<uint64_t>(x) << 8) |
                        (static_cast<uint64_t>(y) << 16) | (static_cast<uint64_t>(p) << 24) |
                        (static_cast<uint64_t>(pc) << 32) | (static_cast<uint64_t>(mem[0x1234]) << 48);

    std::cout << "lang=cpp steps=" << steps << " seconds=" << std::fixed << std::setprecision(6)
              << secs << " mops=" << std::setprecision(3) << mops << " checksum=0x" << std::hex
              << checksum << std::dec << "\n";
    return 0;
}
