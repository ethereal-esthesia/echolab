#[cfg(not(feature = "sdl3"))]
fn main() {
    eprintln!("This example requires the 'sdl3' feature.");
    eprintln!("Run: cargo run --example sdl3_text40x24 --features sdl3 -- --screenshot");
}

#[cfg(feature = "sdl3")]
mod app {
    use echo_lab::capture::CaptureOptions;
    use echo_lab::config::EchoLabConfig;
    use echo_lab::screen_buffer::ScreenBuffer;
    use echo_lab::video::{FRAME_HEIGHT, FRAME_WIDTH, TextVideoController};
    use std::ffi::{CStr, CString, c_char, c_int, c_void};
    use std::ptr;
    use std::time::{Duration, Instant};

    #[repr(C)]
    struct SDL_Window(c_void);
    #[repr(C)]
    struct SDL_Renderer(c_void);
    #[repr(C)]
    struct SDL_Texture(c_void);

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
        fn SDL_DestroyWindow(window: *mut SDL_Window);

        fn SDL_CreateRenderer(window: *mut SDL_Window, name: *const c_char) -> *mut SDL_Renderer;
        fn SDL_DestroyRenderer(renderer: *mut SDL_Renderer);

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
    }

    impl Default for CliOptions {
        fn default() -> Self {
            Self {
                config_path: "echolab.toml".to_owned(),
                config_path_explicit: false,
                capture: CaptureOptions::default(),
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
                    "-h" | "--help" => {
                        println!(
                            "Usage: cargo run --example sdl3_text40x24 --features sdl3 -- [--config <path>] [--screenshot [dir]]"
                        );
                        println!("Config default path: ./echolab.toml");
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
                (FRAME_WIDTH as i32) * 3,
                (FRAME_HEIGHT as i32) * 3,
                SDL_WINDOW_RESIZABLE,
            );
            if window.is_null() {
                SDL_Quit();
                return Err(format!("SDL_CreateWindow failed: {}", sdl_error()));
            }

            let renderer = SDL_CreateRenderer(window, ptr::null());
            if renderer.is_null() {
                SDL_DestroyWindow(window);
                SDL_Quit();
                return Err(format!("SDL_CreateRenderer failed: {}", sdl_error()));
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
            let msg = b"HELLO WORLD FROM SDL3";
            for (idx, b) in msg.iter().enumerate() {
                ram[0x0400 + idx] = *b;
            }

            let video = TextVideoController::default();
            let mut frame = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
            let start = Instant::now();

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

                video.render_frame(&ram, &mut frame);

                let pitch = (FRAME_WIDTH * std::mem::size_of::<u32>()) as i32;
                if !SDL_UpdateTexture(
                    texture,
                    ptr::null(),
                    frame.pixels().as_ptr() as *const c_void,
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
                if start.elapsed() >= Duration::from_secs(cfg.sdl3_text40x24.auto_exit_seconds) {
                    break 'running;
                }
                SDL_Delay(16);
            }

            if let Some(path) = options
                .capture
                .capture_frame_if_requested(&frame, &cfg.sdl3_text40x24.default_screenshot_dir)?
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
}

#[cfg(feature = "sdl3")]
fn main() {
    if let Err(err) = app::run() {
        eprintln!("{}", err);
        std::process::exit(1);
    }
}
