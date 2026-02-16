#[cfg(not(feature = "sdl3"))]
fn main() {
    eprintln!("This example requires the 'sdl3' feature.");
    eprintln!("Run: cargo run --example sdl3_text40x24 --features sdl3 -- --screenshot");
}

#[cfg(feature = "sdl3")]
mod app {
    use echo_lab::capture::CaptureOptions;
    use echo_lab::config::EchoLabConfig;
    use echo_lab::rng::FastRng;
    use echo_lab::screen_buffer::ScreenBuffer;
    use echo_lab::video::{COLOR_BLACK, COLOR_WHITE, FRAME_HEIGHT, FRAME_WIDTH, TextVideoController};
    use std::ffi::{CStr, CString, c_char, c_int, c_void};
    use std::ptr;
    use std::thread;
    use std::time::{Duration, Instant};

    #[repr(C)]
    struct SDL_Window(c_void);
    #[repr(C)]
    struct SDL_Renderer(c_void);
    #[repr(C)]
    struct SDL_Texture(c_void);
    type SdlDisplayId = u32;

    #[repr(C)]
    struct SDL_DisplayMode {
        display_id: SdlDisplayId,
        format: u32,
        w: c_int,
        h: c_int,
        pixel_density: f32,
        refresh_rate: f32,
        refresh_rate_numerator: c_int,
        refresh_rate_denominator: c_int,
        internal: *mut c_void,
    }

    #[repr(C)]
    struct SDL_Event {
        event_type: u32,
        _pad: [u8; 56],
    }

    #[link(name = "SDL3")]
    unsafe extern "C" {
        fn SDL_Init(flags: u32) -> bool;
        fn SDL_Quit();
        fn SDL_GetError() -> *const c_char;

        fn SDL_CreateWindow(
            title: *const c_char,
            width: c_int,
            height: c_int,
            flags: u64,
        ) -> *mut SDL_Window;
        fn SDL_GetDisplayForWindow(window: *mut SDL_Window) -> SdlDisplayId;
        fn SDL_GetCurrentDisplayMode(display_id: SdlDisplayId) -> *const SDL_DisplayMode;
        fn SDL_GetDesktopDisplayMode(display_id: SdlDisplayId) -> *const SDL_DisplayMode;
        fn SDL_DestroyWindow(window: *mut SDL_Window);
        fn SDL_SetWindowFullscreen(window: *mut SDL_Window, fullscreen: bool) -> bool;

        fn SDL_CreateRenderer(window: *mut SDL_Window, name: *const c_char) -> *mut SDL_Renderer;
        fn SDL_DestroyRenderer(renderer: *mut SDL_Renderer);
        fn SDL_SetRenderVSync(renderer: *mut SDL_Renderer, vsync: c_int) -> bool;

        fn SDL_CreateTexture(
            renderer: *mut SDL_Renderer,
            format: u32,
            access: c_int,
            w: c_int,
            h: c_int,
        ) -> *mut SDL_Texture;
        fn SDL_DestroyTexture(texture: *mut SDL_Texture);

        fn SDL_UpdateTexture(
            texture: *mut SDL_Texture,
            rect: *const c_void,
            pixels: *const c_void,
            pitch: c_int,
        ) -> bool;

        fn SDL_RenderClear(renderer: *mut SDL_Renderer) -> bool;
        fn SDL_RenderTexture(
            renderer: *mut SDL_Renderer,
            texture: *mut SDL_Texture,
            srcrect: *const c_void,
            dstrect: *const c_void,
        ) -> bool;
        fn SDL_RenderPresent(renderer: *mut SDL_Renderer);

        fn SDL_PollEvent(event: *mut SDL_Event) -> bool;
        fn SDL_Delay(ms: u32);
    }

    const SDL_INIT_VIDEO: u32 = 0x0000_0020;
    const SDL_WINDOW_RESIZABLE: u64 = 0x0000_0020;
    const SDL_TEXTUREACCESS_STREAMING: c_int = 1;
    const SDL_PIXELFORMAT_ARGB8888: u32 = 372_645_892;
    const SDL_EVENT_QUIT: u32 = 0x100;
    const APPLE2E_NTSC_FPS: f64 = 59.92;
    const HOST_DISPLAY_FPS_FALLBACK: f64 = 60.0;
    const PREV_FRAME_BLEED_NUM: u16 = 196; // ~76.6% previous-frame persistence

    fn sdl_error() -> String {
        // SAFETY: SDL_GetError returns a valid null-terminated C string pointer or null.
        unsafe {
            let p = SDL_GetError();
            if p.is_null() {
                "unknown SDL error".to_owned()
            } else {
                CStr::from_ptr(p).to_string_lossy().to_string()
            }
        }
    }

    struct CliOptions {
        config_path: String,
        config_path_explicit: bool,
        capture: CaptureOptions,
        white: bool,
        flip_test: bool,
        fullscreen: bool,
        vsync_off: bool,
        crossfade_vsync_off: bool,
    }

    impl Default for CliOptions {
        fn default() -> Self {
            Self {
                config_path: "echolab.toml".to_owned(),
                config_path_explicit: false,
                capture: CaptureOptions::default(),
                white: false,
                flip_test: false,
                fullscreen: false,
                vsync_off: false,
                crossfade_vsync_off: false,
            }
        }
    }

    impl CliOptions {
        fn parse() -> Result<Self, String> {
            let mut options = Self::default();
            let args: Vec<String> = std::env::args().skip(1).collect();
            let mut i = 0usize;
            while i < args.len() {
                if options.capture.parse_arg(&args, &mut i)? {
                    continue;
                }

                match args[i].as_str() {
                    "--config" => {
                        if i + 1 >= args.len() {
                            return Err("missing value for --config".to_owned());
                        }
                        options.config_path = args[i + 1].clone();
                        options.config_path_explicit = true;
                        i += 2;
                    }
                    "--white" => {
                        options.white = true;
                        i += 1;
                    }
                    "--flip-test" => {
                        options.flip_test = true;
                        i += 1;
                    }
                    "--fullscreen" => {
                        options.fullscreen = true;
                        i += 1;
                    }
                    "--vsync-off" => {
                        options.vsync_off = true;
                        i += 1;
                    }
                    "--crossfade-vsync-off" => {
                        options.crossfade_vsync_off = true;
                        i += 1;
                    }
                    "-h" | "--help" => {
                        println!(
                            "Usage: cargo run --example sdl3_text40x24 --features sdl3 -- [--config <path>] [--white] [--flip-test] [--fullscreen] [--vsync-off] [--crossfade-vsync-off] [--screenshot [dir]]"
                        );
                        println!("Config default path: ./echolab.toml");
                        println!("Default text color is green; pass --white for white-on-black.");
                        println!("Pass --flip-test to randomize all cells with codes 0..15 every frame.");
                        println!("Pass --fullscreen to start in fullscreen mode.");
                        println!("Default sync uses 60Hz host crossover to 59.92Hz Apple IIe timing.");
                        println!("Pass --crossfade-vsync-off to disable renderer VSync while keeping crossover sync.");
                        println!("Pass --vsync-off for raw uncoupled timing.");
                        println!("Screenshots are always saved as screenshot_<timestamp>.ppm.");
                        println!("If --screenshot dir is omitted, default comes from config.");
                        std::process::exit(0);
                    }
                    other => return Err(format!("unknown argument: {other}")),
                }
            }
            Ok(options)
        }
    }

    pub fn run() -> Result<(), String> {
        let options = CliOptions::parse()?;
        let cfg =
            EchoLabConfig::load_from_path(&options.config_path, options.config_path_explicit)?;

        let title = CString::new("Echo Lab SDL3 Text 40x24").map_err(|e| e.to_string())?;

        // SAFETY: SDL lifecycle calls are serialized in this function.
        unsafe {
            if !SDL_Init(SDL_INIT_VIDEO) {
                return Err(format!("SDL_Init failed: {}", sdl_error()));
            }

            let window = SDL_CreateWindow(
                title.as_ptr(),
                (FRAME_WIDTH as i32) * 3 / 2,
                (FRAME_HEIGHT as i32) * 3 / 2,
                SDL_WINDOW_RESIZABLE,
            );
            if window.is_null() {
                SDL_Quit();
                return Err(format!("SDL_CreateWindow failed: {}", sdl_error()));
            }
            if options.fullscreen && !SDL_SetWindowFullscreen(window, true) {
                SDL_DestroyWindow(window);
                SDL_Quit();
                return Err(format!("SDL_SetWindowFullscreen failed: {}", sdl_error()));
            }

            let renderer = SDL_CreateRenderer(window, ptr::null());
            if renderer.is_null() {
                SDL_DestroyWindow(window);
                SDL_Quit();
                return Err(format!("SDL_CreateRenderer failed: {}", sdl_error()));
            }
            let use_crossover_sync = !options.vsync_off;
            let crossover_vsync_off = options.crossfade_vsync_off;
            let vsync_value: c_int = if options.vsync_off || crossover_vsync_off {
                0
            } else {
                1
            };
            if !SDL_SetRenderVSync(renderer, vsync_value) {
                SDL_DestroyRenderer(renderer);
                SDL_DestroyWindow(window);
                SDL_Quit();
                return Err(format!("SDL_SetRenderVSync failed: {}", sdl_error()));
            }

            let texture = SDL_CreateTexture(
                renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_STREAMING,
                FRAME_WIDTH as i32,
                FRAME_HEIGHT as i32,
            );
            if texture.is_null() {
                SDL_DestroyRenderer(renderer);
                SDL_DestroyWindow(window);
                SDL_Quit();
                return Err(format!("SDL_CreateTexture failed: {}", sdl_error()));
            }

            let mut ram = [b' '; 65536];
            fill_text_page_demo_layout(&mut ram, 0x0400);

            let mut video = TextVideoController::default();
            if options.white {
                video = video.with_foreground_color(COLOR_WHITE);
            }
            let mut frame = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
            let mut blended_frame = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
            blended_frame.clear(COLOR_BLACK);
            let mut rng = FastRng::new(0x4543_484f_4c41_42u64);
            let start = Instant::now();
            let (host_display_fps, mode_fps_known) =
                query_host_display_fps(window).unwrap_or((HOST_DISPLAY_FPS_FALLBACK, false));
            let mut host_frame_period_secs = 1.0 / host_display_fps;
            let mut guest_frames_per_host = APPLE2E_NTSC_FPS * host_frame_period_secs;
            let mut next_host_deadline = Instant::now();
            let mut guest_step_accumulator = 1.0f64;
            let mut last_present_instant: Option<Instant> = None;

            'running: loop {
                let mut event = SDL_Event {
                    event_type: 0,
                    _pad: [0; 56],
                };
                while SDL_PollEvent(&mut event) {
                    if event.event_type == SDL_EVENT_QUIT {
                        break 'running;
                    }
                }

                if options.flip_test {
                    if use_crossover_sync {
                        guest_step_accumulator += guest_frames_per_host;
                        let guest_steps = guest_step_accumulator.floor() as usize;
                        guest_step_accumulator -= guest_steps as f64;
                        for _ in 0..guest_steps {
                            fill_text_page_random_0_to_15(&mut ram, 0x0400, &mut rng);
                        }
                    } else {
                        fill_text_page_random_0_to_15(&mut ram, 0x0400, &mut rng);
                    }
                }

                video.render_frame(&ram, &mut frame);
                apply_persistence_blend(frame.pixels(), blended_frame.pixels_mut());

                let pitch = (FRAME_WIDTH * std::mem::size_of::<u32>()) as i32;
                if !SDL_UpdateTexture(
                    texture,
                    ptr::null(),
                    blended_frame.pixels().as_ptr() as *const c_void,
                    pitch,
                ) {
                    break 'running;
                }

                if !SDL_RenderClear(renderer) {
                    break 'running;
                }
                if !SDL_RenderTexture(renderer, texture, ptr::null(), ptr::null()) {
                    break 'running;
                }
                SDL_RenderPresent(renderer);
                let presented_at = Instant::now();
                if use_crossover_sync && !crossover_vsync_off && !mode_fps_known {
                    if let Some(prev) = last_present_instant {
                        let dt = presented_at.duration_since(prev).as_secs_f64();
                        if dt > (1.0 / 240.0) && dt < (1.0 / 20.0) {
                            // Exponential smoothing on present intervals for stable fallback.
                            host_frame_period_secs = host_frame_period_secs * 0.9 + dt * 0.1;
                            guest_frames_per_host = APPLE2E_NTSC_FPS * host_frame_period_secs;
                        }
                    }
                    last_present_instant = Some(presented_at);
                }
                if start.elapsed() >= Duration::from_secs(cfg.sdl3_text40x24.auto_exit_seconds) {
                    break 'running;
                }
                if use_crossover_sync && crossover_vsync_off {
                    pace_to_next_frame(
                        &mut next_host_deadline,
                        Duration::from_secs_f64(host_frame_period_secs),
                    );
                } else if options.vsync_off {
                    SDL_Delay(16);
                }
            }

            if let Some(path) = options
                .capture
                .capture_frame_if_requested(
                    &blended_frame,
                    &cfg.sdl3_text40x24.default_screenshot_dir,
                )?
            {
                println!("Saved screenshot to {}", path.display());
            }

            SDL_DestroyTexture(texture);
            SDL_DestroyRenderer(renderer);
            SDL_DestroyWindow(window);
            SDL_Quit();
        }

        Ok(())
    }

    fn fill_text_page_demo_layout(ram: &mut [u8; 65536], text_base: usize) {
        const COLS: usize = 40;
        const ROWS: usize = 24;
        const HELLO: &[u8] = b"HELLO WORLD";

        for i in 0..(COLS * ROWS) {
            ram[text_base + i] = b' ';
        }

        for (i, ch) in HELLO.iter().enumerate() {
            ram[text_base + i] = *ch;
        }

        for code in 0u16..=255u16 {
            let idx = code as usize;
            let row = 2 + idx / 32;
            let col = idx % 32;
            if row < ROWS {
                ram[text_base + row * COLS + col] = code as u8;
            }
        }
    }

    fn fill_text_page_random_0_to_15(ram: &mut [u8; 65536], text_base: usize, rng: &mut FastRng) {
        const COLS: usize = 40;
        const ROWS: usize = 24;
        for i in 0..(COLS * ROWS) {
            ram[text_base + i] = rng.next_u8() & 0x0f;
        }
    }

    fn pace_to_next_frame(next_frame_deadline: &mut Instant, frame_period: Duration) {
        *next_frame_deadline += frame_period;
        let now = Instant::now();
        if now + Duration::from_millis(1) < *next_frame_deadline {
            thread::sleep(*next_frame_deadline - now - Duration::from_millis(1));
        }
        while Instant::now() < *next_frame_deadline {
            std::hint::spin_loop();
        }
        let now = Instant::now();
        if now.duration_since(*next_frame_deadline) > frame_period.saturating_mul(2) {
            *next_frame_deadline = now;
        }
    }

    fn apply_persistence_blend(src: &[u32], dst: &mut [u32]) {
        for (current, displayed) in src.iter().zip(dst.iter_mut()) {
            let decayed_prev = scale_rgb(*displayed, PREV_FRAME_BLEED_NUM);
            *displayed = max_rgb(*current, decayed_prev);
        }
    }

    fn scale_rgb(pixel: u32, scale_num: u16) -> u32 {
        let r = (((pixel >> 16) & 0xff) as u16 * scale_num / 256) as u32;
        let g = (((pixel >> 8) & 0xff) as u16 * scale_num / 256) as u32;
        let b = ((pixel & 0xff) as u16 * scale_num / 256) as u32;
        0xff00_0000 | (r << 16) | (g << 8) | b
    }

    fn max_rgb(a: u32, b: u32) -> u32 {
        let ar = (a >> 16) & 0xff;
        let ag = (a >> 8) & 0xff;
        let ab = a & 0xff;
        let br = (b >> 16) & 0xff;
        let bg = (b >> 8) & 0xff;
        let bb = b & 0xff;

        let r = ar.max(br);
        let g = ag.max(bg);
        let bl = ab.max(bb);
        0xff00_0000 | (r << 16) | (g << 8) | bl
    }

    fn query_host_display_fps(window: *mut SDL_Window) -> Option<(f64, bool)> {
        // SAFETY: Called after SDL video init with a valid window pointer.
        unsafe {
            let display_id = SDL_GetDisplayForWindow(window);
            if display_id == 0 {
                return None;
            }

            let mode = {
                let current = SDL_GetCurrentDisplayMode(display_id);
                if current.is_null() {
                    SDL_GetDesktopDisplayMode(display_id)
                } else {
                    current
                }
            };
            if mode.is_null() {
                return None;
            }

            let m = &*mode;
            if m.refresh_rate_numerator > 0 && m.refresh_rate_denominator > 0 {
                let fps = (m.refresh_rate_numerator as f64) / (m.refresh_rate_denominator as f64);
                if fps.is_finite() && fps > 1.0 {
                    return Some((fps, true));
                }
            }
            let fps = m.refresh_rate as f64;
            if fps.is_finite() && fps > 1.0 {
                return Some((fps, true));
            }

            None
        }
    }
}

#[cfg(feature = "sdl3")]
fn main() {
    if let Err(err) = app::run() {
        eprintln!("{}", err);
        std::process::exit(1);
    }
}
