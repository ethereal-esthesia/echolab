#include <SDL2/SDL.h>

#include <array>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static inline uint64_t xorshift64(uint64_t &x) {
  x ^= x << 13;
  x ^= x >> 7;
  x ^= x << 17;
  return x;
}

static inline uint64_t mix64(uint64_t z) {
  z = (z ^ (z >> 33)) * 0xff51afd7ed558ccdULL;
  z = (z ^ (z >> 33)) * 0xc4ceb9fe1a85ec53ULL;
  return z ^ (z >> 33);
}

struct FastRng {
  uint64_t state = 0;

  explicit FastRng(uint64_t seed) { setSeed(seed); }

  void setSeed(uint64_t seed) {
    uint64_t mixed = mix64(seed);
    state = (mixed == 0ULL) ? 0x9E3779B97F4A7C15ULL : mixed;
  }

  uint64_t nextRaw() { return xorshift64(state); }

  uint8_t nextU8() { return static_cast<uint8_t>(nextRaw() >> 56); }

  uint16_t nextU16() { return static_cast<uint16_t>(nextRaw() >> 48); }
};

struct Kernel {
  std::array<uint8_t, 65536> mem{};
  uint8_t a = 0x12;
  uint8_t x = 0x34;
  uint8_t y = 0x56;
  uint8_t p = 0x24;
  uint16_t pc = 0x200;
  FastRng rng;

  explicit Kernel(uint64_t seed) : rng(seed) {}

  void step() {
    uint16_t addr = rng.nextU16();
    uint8_t op = rng.nextU8();

    switch (op & 0x0F) {
      case 0: a = static_cast<uint8_t>(a + mem[addr]); p = (p & 0x3C) | (a == 0 ? 2 : 0) | (a & 0x80); break;
      case 1: a ^= mem[addr]; p = (p & 0x3C) | (a == 0 ? 2 : 0) | (a & 0x80); break;
      case 2: x = static_cast<uint8_t>(x + 1); p = (p & 0x3C) | (x == 0 ? 2 : 0) | (x & 0x80); break;
      case 3: y = static_cast<uint8_t>(y - 1); p = (p & 0x3C) | (y == 0 ? 2 : 0) | (y & 0x80); break;
      case 4: mem[addr] = static_cast<uint8_t>(a + x + y); break;
      case 5: pc = static_cast<uint16_t>(pc + static_cast<uint16_t>(static_cast<int8_t>(op))); break;
      case 6: pc = static_cast<uint16_t>((pc << 1) | (pc >> 15)); break;
      case 7: p ^= 0x41; break;
      case 8: mem[addr] ^= static_cast<uint8_t>(pc); break;
      case 9: a = static_cast<uint8_t>((a << 1) | (a >> 7)); break;
      case 10: x = static_cast<uint8_t>((x >> 1) | (x << 7)); break;
      case 11: y ^= static_cast<uint8_t>(a + x); break;
      case 12: mem[static_cast<uint16_t>(addr + x)] = static_cast<uint8_t>(mem[addr] + y); break;
      case 13: a = mem[static_cast<uint16_t>(addr + y)]; break;
      case 14: p = static_cast<uint8_t>((p & 0xC3) | ((a ^ x ^ y) & 0x3C)); break;
      case 15: pc ^= static_cast<uint16_t>(addr); break;
    }

    pc = static_cast<uint16_t>(pc + 1);
  }
};

int main(int argc, char **argv) {
  int seconds = 10;
  bool fullscreen = false;
  bool static_frame = false;
  bool vsync = true;
  uint64_t seed = 0x65022026ULL ^
      static_cast<uint64_t>(std::chrono::steady_clock::now().time_since_epoch().count());
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--fullscreen") == 0) {
      fullscreen = true;
    } else if (std::strcmp(argv[i], "--static") == 0) {
      static_frame = true;
    } else if (std::strcmp(argv[i], "--no-vsync") == 0) {
      vsync = false;
    } else if (std::strcmp(argv[i], "--seed") == 0 && (i + 1) < argc) {
      seed = static_cast<uint64_t>(std::strtoull(argv[++i], nullptr, 0));
    } else {
      int parsed = std::atoi(argv[i]);
      if (parsed > 0) seconds = parsed;
    }
  }
  if (seconds <= 0) seconds = 10;

  if (SDL_Init(SDL_INIT_VIDEO) != 0) {
    std::fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
    return 1;
  }

  uint32_t window_flags = SDL_WINDOW_SHOWN;
  if (fullscreen) window_flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
  SDL_Window *window = SDL_CreateWindow("C++ 60fps benchmark", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 900, 220, window_flags);
  if (!window) {
    std::fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
    SDL_Quit();
    return 1;
  }

  uint32_t renderer_flags = SDL_RENDERER_ACCELERATED | (vsync ? SDL_RENDERER_PRESENTVSYNC : 0);
  SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, renderer_flags);
  if (!renderer) {
    std::fprintf(stderr, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }

  constexpr int ops_per_frame = 17050;
  constexpr double frame_sec = 1.0 / 60.0;

  Kernel k(seed);
  FastRng visRng(seed);
  int outW = 0;
  int outH = 0;
  SDL_GetRendererOutputSize(renderer, &outW, &outH);
  SDL_Texture *staticTexture = nullptr;
  if (static_frame) {
    staticTexture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, outW, outH);
    if (!staticTexture) {
      std::fprintf(stderr, "SDL_CreateTexture failed: %s\n", SDL_GetError());
      SDL_DestroyRenderer(renderer);
      SDL_DestroyWindow(window);
      SDL_Quit();
      return 1;
    }
  }
  auto start = std::chrono::steady_clock::now();
  auto frame_start = start;
  auto next_title = start;
  uint64_t frames = 0;
  double emu_sec_sum = 0.0;

  bool running = true;
  while (running) {
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
      if (ev.type == SDL_QUIT) running = false;
    }

    auto f0 = std::chrono::steady_clock::now();
    for (int i = 0; i < ops_per_frame; ++i) k.step();
    auto f1 = std::chrono::steady_clock::now();

    double emu_sec = std::chrono::duration<double>(f1 - f0).count();
    emu_sec_sum += emu_sec;
    frames++;

    SDL_SetRenderDrawColor(renderer, 16, 16, 16, 255);
    SDL_RenderClear(renderer);
    if (static_frame) {
      void *pixels = nullptr;
      int pitch = 0;
      if (SDL_LockTexture(staticTexture, nullptr, &pixels, &pitch) == 0) {
        for (int y = 0; y < outH; ++y) {
          uint32_t *row = reinterpret_cast<uint32_t *>(reinterpret_cast<uint8_t *>(pixels) + (y * pitch));
          int x = 0;
          while (x < outW) {
            uint64_t bits = visRng.nextRaw();
            for (int b = 0; b < 64 && x < outW; ++b, ++x) {
              row[x] = ((bits >> (63 - b)) & 1ULL) ? 0xFF000000U : 0xFFFFFFFFU;
            }
          }
        }
        SDL_UnlockTexture(staticTexture);
        SDL_RenderCopy(renderer, staticTexture, nullptr, nullptr);
      }
    } else {
      uint8_t bar = static_cast<uint8_t>((k.a + k.x + k.y + (k.pc & 0xFF)) & 0xFF);
      SDL_Rect r{20, 80, 860 * bar / 255, 60};
      SDL_SetRenderDrawColor(renderer, 64, 192, 96, 255);
      SDL_RenderFillRect(renderer, &r);
    }
    SDL_RenderPresent(renderer);

    auto now = std::chrono::steady_clock::now();
    double elapsed_total = std::chrono::duration<double>(now - start).count();
    if (elapsed_total >= seconds) running = false;

    if (now >= next_title) {
      double avg_emu_ms = (emu_sec_sum / static_cast<double>(frames)) * 1000.0;
      double free_ms = 16.6666667 - avg_emu_ms;
      double fps = static_cast<double>(frames) / elapsed_total;
      uint64_t expected_frames = static_cast<uint64_t>(elapsed_total * 60.0);
      uint64_t dropped = (expected_frames > frames) ? (expected_frames - frames) : 0;
      char title[256];
      std::snprintf(title, sizeof(title), "C++ | fps=%.2f | drop=%llu | emu=%.4f ms | free=%.4f ms | %s %s | seed=%llx", fps,
                    static_cast<unsigned long long>(dropped), avg_emu_ms, free_ms,
                    static_frame ? "static" : "dynamic", vsync ? "vsync" : "no-vsync",
                    static_cast<unsigned long long>(seed));
      SDL_SetWindowTitle(window, title);
      next_title = now + std::chrono::seconds(1);
    }

    if (!vsync) {
      double frame_elapsed = std::chrono::duration<double>(now - frame_start).count();
      if (frame_elapsed < frame_sec) {
        uint32_t delay_ms = static_cast<uint32_t>((frame_sec - frame_elapsed) * 1000.0);
        if (delay_ms > 0) SDL_Delay(delay_ms);
      }
    }
    frame_start = std::chrono::steady_clock::now();
  }

  double total_sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
  double avg_emu_ms = (emu_sec_sum / static_cast<double>(frames)) * 1000.0;
  uint64_t expected_frames = static_cast<uint64_t>(total_sec * 60.0);
  uint64_t dropped = (expected_frames > frames) ? (expected_frames - frames) : 0;
  std::printf("lang=cpp_window frames=%llu expected=%llu dropped=%llu seconds=%.3f fps=%.2f avg_emu_ms=%.4f free_ms=%.4f seed=0x%llx\n",
              static_cast<unsigned long long>(frames), static_cast<unsigned long long>(expected_frames),
              static_cast<unsigned long long>(dropped), total_sec, static_cast<double>(frames) / total_sec,
              avg_emu_ms, 16.6666667 - avg_emu_ms, static_cast<unsigned long long>(seed));

  if (staticTexture) SDL_DestroyTexture(staticTexture);
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();
  return 0;
}
