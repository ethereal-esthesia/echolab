use std::ffi::{c_char, c_int, c_uint, c_void, CString};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[repr(C)]
struct SDL_Window(c_void);
#[repr(C)]
struct SDL_Renderer(c_void);
#[repr(C)]
struct SDL_Texture(c_void);

#[repr(C)]
struct SDL_Rect {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
}

#[repr(C)]
struct SDL_Event {
    bytes: [u8; 56],
}

unsafe extern "C" {
    fn SDL_Init(flags: c_uint) -> c_int;
    fn SDL_Quit();
    fn SDL_GetError() -> *const c_char;
    fn SDL_CreateWindow(
        title: *const c_char,
        x: c_int,
        y: c_int,
        w: c_int,
        h: c_int,
        flags: c_uint,
    ) -> *mut SDL_Window;
    fn SDL_DestroyWindow(window: *mut SDL_Window);
    fn SDL_CreateRenderer(window: *mut SDL_Window, index: c_int, flags: c_uint) -> *mut SDL_Renderer;
    fn SDL_DestroyRenderer(renderer: *mut SDL_Renderer);
    fn SDL_GetRendererOutputSize(renderer: *mut SDL_Renderer, w: *mut c_int, h: *mut c_int) -> c_int;
    fn SDL_CreateTexture(
        renderer: *mut SDL_Renderer,
        format: c_uint,
        access: c_int,
        w: c_int,
        h: c_int,
    ) -> *mut SDL_Texture;
    fn SDL_DestroyTexture(texture: *mut SDL_Texture);
    fn SDL_LockTexture(
        texture: *mut SDL_Texture,
        rect: *const SDL_Rect,
        pixels: *mut *mut c_void,
        pitch: *mut c_int,
    ) -> c_int;
    fn SDL_UnlockTexture(texture: *mut SDL_Texture);
    fn SDL_SetRenderDrawColor(renderer: *mut SDL_Renderer, r: u8, g: u8, b: u8, a: u8) -> c_int;
    fn SDL_RenderClear(renderer: *mut SDL_Renderer) -> c_int;
    fn SDL_RenderFillRect(renderer: *mut SDL_Renderer, rect: *const SDL_Rect) -> c_int;
    fn SDL_RenderCopy(
        renderer: *mut SDL_Renderer,
        texture: *mut SDL_Texture,
        src: *const SDL_Rect,
        dst: *const SDL_Rect,
    ) -> c_int;
    fn SDL_RenderPresent(renderer: *mut SDL_Renderer);
    fn SDL_SetWindowTitle(window: *mut SDL_Window, title: *const c_char);
    fn SDL_PollEvent(event: *mut SDL_Event) -> c_int;
    fn SDL_Delay(ms: c_uint);
}

const SDL_INIT_VIDEO: c_uint = 0x0000_0020;
const SDL_WINDOWPOS_CENTERED: c_int = 0x2FFF_0000u32 as c_int;
const SDL_WINDOW_SHOWN: c_uint = 0x0000_0004;
const SDL_WINDOW_FULLSCREEN_DESKTOP: c_uint = 0x0000_1001;
const SDL_RENDERER_ACCELERATED: c_uint = 0x0000_0002;
const SDL_RENDERER_PRESENTVSYNC: c_uint = 0x0000_0004;
const SDL_TEXTUREACCESS_STREAMING: c_int = 1;
const SDL_PIXELFORMAT_ARGB8888: c_uint = 372645892;
const SDL_QUIT: u32 = 0x100;

#[inline]
fn xorshift64(x: &mut u64) -> u64 {
    *x ^= *x << 13;
    *x ^= *x >> 7;
    *x ^= *x << 17;
    *x
}

#[inline]
fn mix64(mut z: u64) -> u64 {
    z = (z ^ (z >> 33)).wrapping_mul(0xff51_afd7_ed55_8ccd);
    z = (z ^ (z >> 33)).wrapping_mul(0xc4ce_b9fe_1a85_ec53);
    z ^ (z >> 33)
}

struct FastRng {
    state: u64,
}

impl FastRng {
    fn new(seed: u64) -> Self {
        let mixed = mix64(seed);
        let state = if mixed == 0 { 0x9E37_79B9_7F4A_7C15 } else { mixed };
        Self { state }
    }

    #[inline]
    fn next_raw(&mut self) -> u64 {
        xorshift64(&mut self.state)
    }

    #[inline]
    fn next_u8(&mut self) -> u8 {
        (self.next_raw() >> 56) as u8
    }

    #[inline]
    fn next_u16(&mut self) -> u16 {
        (self.next_raw() >> 48) as u16
    }
}

struct Kernel {
    mem: [u8; 65536],
    a: u8,
    x: u8,
    y: u8,
    p: u8,
    pc: u16,
    rng: FastRng,
}

impl Kernel {
    fn new(seed: u64) -> Self {
        Self {
            mem: [0; 65536],
            a: 0x12,
            x: 0x34,
            y: 0x56,
            p: 0x24,
            pc: 0x0200,
            rng: FastRng::new(seed),
        }
    }

    #[inline]
    fn step(&mut self) {
        let addr = self.rng.next_u16();
        let op = self.rng.next_u8();
        match op & 0x0F {
            0 => {
                self.a = self.a.wrapping_add(self.mem[addr as usize]);
                self.p = (self.p & 0x3C) | if self.a == 0 { 2 } else { 0 } | (self.a & 0x80);
            }
            1 => {
                self.a ^= self.mem[addr as usize];
                self.p = (self.p & 0x3C) | if self.a == 0 { 2 } else { 0 } | (self.a & 0x80);
            }
            2 => {
                self.x = self.x.wrapping_add(1);
                self.p = (self.p & 0x3C) | if self.x == 0 { 2 } else { 0 } | (self.x & 0x80);
            }
            3 => {
                self.y = self.y.wrapping_sub(1);
                self.p = (self.p & 0x3C) | if self.y == 0 { 2 } else { 0 } | (self.y & 0x80);
            }
            4 => self.mem[addr as usize] = self.a.wrapping_add(self.x).wrapping_add(self.y),
            5 => self.pc = self.pc.wrapping_add((op as i8) as i16 as u16),
            6 => self.pc = self.pc.rotate_left(1),
            7 => self.p ^= 0x41,
            8 => self.mem[addr as usize] ^= self.pc as u8,
            9 => self.a = self.a.rotate_left(1),
            10 => self.x = self.x.rotate_right(1),
            11 => self.y ^= self.a.wrapping_add(self.x),
            12 => {
                let i = addr.wrapping_add(self.x as u16) as usize;
                self.mem[i] = self.mem[addr as usize].wrapping_add(self.y);
            }
            13 => {
                let i = addr.wrapping_add(self.y as u16) as usize;
                self.a = self.mem[i];
            }
            14 => self.p = (self.p & 0xC3) | ((self.a ^ self.x ^ self.y) & 0x3C),
            _ => self.pc ^= addr,
        }
        self.pc = self.pc.wrapping_add(1);
    }
}

fn sdl_err() -> String {
    unsafe {
        let p = SDL_GetError();
        if p.is_null() {
            "unknown SDL error".to_string()
        } else {
            std::ffi::CStr::from_ptr(p).to_string_lossy().to_string()
        }
    }
}

fn main() {
    let mut seconds: u64 = 10;
    let mut fullscreen = false;
    let mut static_frame = false;
    let mut vsync = true;
    let time_xor = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0);
    let mut seed = 0x6502_2026u64 ^ time_xor;
    let argv: Vec<String> = std::env::args().collect();
    let mut i = 1usize;
    while i < argv.len() {
        match argv[i].as_str() {
            "--fullscreen" => fullscreen = true,
            "--static" => static_frame = true,
            "--no-vsync" => vsync = false,
            "--seed" => {
                if i + 1 < argv.len() {
                    let s = argv[i + 1].as_str();
                    if let Some(hex) = s.strip_prefix("0x") {
                        if let Ok(v) = u64::from_str_radix(hex, 16) {
                            seed = v;
                        }
                    } else if let Ok(v) = s.parse::<u64>() {
                        seed = v;
                    }
                    i += 1;
                }
            }
            _ => {
                if let Ok(v) = argv[i].parse::<u64>() {
                    if v > 1_000_000 {
                        seed = v;
                    } else if v > 0 {
                        seconds = v;
                    }
                }
            }
        }
        i += 1;
    }

    unsafe {
        if SDL_Init(SDL_INIT_VIDEO) != 0 {
            eprintln!("SDL_Init failed: {}", sdl_err());
            std::process::exit(1);
        }
    }

    let title = CString::new("Rust 60fps benchmark").expect("title");
    let mut window_flags = SDL_WINDOW_SHOWN;
    if fullscreen {
        window_flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    }
    let window = unsafe {
        SDL_CreateWindow(
            title.as_ptr(),
            SDL_WINDOWPOS_CENTERED,
            SDL_WINDOWPOS_CENTERED,
            900,
            220,
            window_flags,
        )
    };
    if window.is_null() {
        eprintln!("SDL_CreateWindow failed: {}", sdl_err());
        unsafe { SDL_Quit() };
        std::process::exit(1);
    }

    let renderer_flags = SDL_RENDERER_ACCELERATED | if vsync { SDL_RENDERER_PRESENTVSYNC } else { 0 };
    let renderer = unsafe { SDL_CreateRenderer(window, -1, renderer_flags) };
    if renderer.is_null() {
        eprintln!("SDL_CreateRenderer failed: {}", sdl_err());
        unsafe {
            SDL_DestroyWindow(window);
            SDL_Quit();
        }
        std::process::exit(1);
    }

    let ops_per_frame = 17_050usize;
    let frame_target = Duration::from_nanos(16_666_667);

    let mut k = Kernel::new(seed);
    let mut vis_rng = FastRng::new(seed);
    let mut out_w: c_int = 0;
    let mut out_h: c_int = 0;
    unsafe {
        SDL_GetRendererOutputSize(renderer, &mut out_w, &mut out_h);
    }
    let static_texture = if static_frame {
        let t = unsafe {
            SDL_CreateTexture(
                renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_STREAMING,
                out_w,
                out_h,
            )
        };
        if t.is_null() {
            eprintln!("SDL_CreateTexture failed: {}", sdl_err());
            unsafe {
                SDL_DestroyRenderer(renderer);
                SDL_DestroyWindow(window);
                SDL_Quit();
            }
            std::process::exit(1);
        }
        t
    } else {
        std::ptr::null_mut()
    };
    let start = Instant::now();
    let mut frame_start = Instant::now();
    let mut last_title = Instant::now();
    let mut frames: u64 = 0;
    let mut emu_sec_sum: f64 = 0.0;
    let mut running = true;

    while running {
        let mut event = SDL_Event { bytes: [0; 56] };
        while unsafe { SDL_PollEvent(&mut event) } != 0 {
            let t = u32::from_ne_bytes([event.bytes[0], event.bytes[1], event.bytes[2], event.bytes[3]]);
            if t == SDL_QUIT {
                running = false;
            }
        }

        let e0 = Instant::now();
        for _ in 0..ops_per_frame {
            k.step();
        }
        let e1 = Instant::now();

        let emu = (e1 - e0).as_secs_f64();
        emu_sec_sum += emu;
        frames += 1;

        unsafe {
            SDL_SetRenderDrawColor(renderer, 16, 16, 16, 255);
            SDL_RenderClear(renderer);
            if static_frame {
                let mut pixels: *mut c_void = std::ptr::null_mut();
                let mut pitch: c_int = 0;
                if SDL_LockTexture(static_texture, std::ptr::null(), &mut pixels, &mut pitch) == 0 {
                    for y in 0..out_h {
                        let row = (pixels as *mut u8).add((y * pitch) as usize) as *mut u32;
                        let mut x = 0;
                        while x < out_w {
                            let bits = vis_rng.next_raw();
                            for b in 0..64 {
                                if x >= out_w {
                                    break;
                                }
                                let bit = (bits >> (63 - b)) & 1;
                                *row.add(x as usize) = if bit == 1 { 0xFF000000 } else { 0xFFFFFFFF };
                                x += 1;
                            }
                        }
                    }
                    SDL_UnlockTexture(static_texture);
                    SDL_RenderCopy(renderer, static_texture, std::ptr::null(), std::ptr::null());
                }
            } else {
                let bar = k.a.wrapping_add(k.x).wrapping_add(k.y).wrapping_add((k.pc & 0xFF) as u8);
                let rect = SDL_Rect {
                    x: 20,
                    y: 80,
                    w: (860 * bar as i32) / 255,
                    h: 60,
                };
                SDL_SetRenderDrawColor(renderer, 64, 96, 224, 255);
                SDL_RenderFillRect(renderer, &rect);
            }
            SDL_RenderPresent(renderer);
        }

        let now = Instant::now();
        let elapsed = now - start;
        if elapsed.as_secs() >= seconds {
            running = false;
        }

        if now.duration_since(last_title) >= Duration::from_secs(1) {
            let avg_emu_ms = (emu_sec_sum / frames as f64) * 1000.0;
            let free_ms = 16.666_666_7 - avg_emu_ms;
            let fps = frames as f64 / elapsed.as_secs_f64();
            let expected_frames = (elapsed.as_secs_f64() * 60.0) as u64;
            let dropped = expected_frames.saturating_sub(frames);
            let msg = CString::new(format!(
                "Rust | fps={:.2} | drop={} | emu={:.4} ms | free={:.4} ms | {} {} | seed={:x}",
                fps,
                dropped,
                avg_emu_ms,
                free_ms,
                if static_frame { "static" } else { "dynamic" },
                if vsync { "vsync" } else { "no-vsync" },
                seed
            ))
            .expect("title msg");
            unsafe { SDL_SetWindowTitle(window, msg.as_ptr()) };
            last_title = now;
        }

        if !vsync {
            let frame_elapsed = now - frame_start;
            if frame_elapsed < frame_target {
                let ms = (frame_target - frame_elapsed).as_millis() as u32;
                if ms > 0 {
                    unsafe { SDL_Delay(ms) };
                }
            }
        }
        frame_start = Instant::now();
    }

    let total = start.elapsed().as_secs_f64();
    let avg_emu_ms = (emu_sec_sum / frames as f64) * 1000.0;
    let expected_frames = (total * 60.0) as u64;
    let dropped = expected_frames.saturating_sub(frames);
    println!(
        "lang=rust_window frames={} expected={} dropped={} seconds={:.3} fps={:.2} avg_emu_ms={:.4} free_ms={:.4} seed=0x{:x}",
        frames,
        expected_frames,
        dropped,
        total,
        frames as f64 / total,
        avg_emu_ms,
        16.666_666_7 - avg_emu_ms,
        seed
    );

    unsafe {
        if !static_texture.is_null() {
            SDL_DestroyTexture(static_texture);
        }
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        SDL_Quit();
    }
}
