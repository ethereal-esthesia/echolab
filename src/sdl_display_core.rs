use crate::capture::CaptureOptions;
use crate::config::EchoLabConfig;
use crate::postfx::PersistenceBlend;
use crate::screen_buffer::ScreenBuffer;
use crate::timing::{pace_to_next_frame, CrossoverSync};
use crate::video::{
    COLOR_BLACK, COLOR_PHOSPHOR_GREEN, FRAME_HEIGHT, FRAME_WIDTH, TextVideoController,
};
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;
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

#[derive(Debug, Clone)]
pub struct SdlDisplayCoreOptions {
    pub title: String,
    pub config_path: String,
    pub config_path_explicit: bool,
    pub capture: CaptureOptions,
    pub fullscreen: bool,
    pub vsync_off: bool,
    pub crossover_vsync_off: bool,
    pub text_base: u16,
    pub foreground_color: u32,
}

impl Default for SdlDisplayCoreOptions {
    fn default() -> Self {
        Self {
            title: "Echo Lab SDL3 Display".to_owned(),
            config_path: "echolab.toml".to_owned(),
            config_path_explicit: false,
            capture: CaptureOptions::default(),
            fullscreen: false,
            vsync_off: false,
            crossover_vsync_off: false,
            text_base: 0x0400,
            foreground_color: COLOR_PHOSPHOR_GREEN,
        }
    }
}

pub fn run_text_display<Init, Update>(
    options: SdlDisplayCoreOptions,
    init_ram: Init,
    mut update_ram: Update,
) -> Result<(), String>
where
    Init: FnOnce(&mut [u8; 65536]),
    Update: FnMut(&mut [u8; 65536], usize) -> Option<u32>,
{
    let cfg = EchoLabConfig::load_from_path(&options.config_path, options.config_path_explicit)?;
    let title = CString::new(options.title).map_err(|e| e.to_string())?;
    let persistence = PersistenceBlend::default();

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
        let crossover_vsync_off = options.crossover_vsync_off;
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
        init_ram(&mut ram);

        let video = TextVideoController::new(options.text_base).with_foreground_color(options.foreground_color);
        let mut frame = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
        let mut blended_frame = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
        blended_frame.clear(COLOR_BLACK);
        let start = Instant::now();
        let (host_display_fps, mode_fps_known) =
            query_host_display_fps(window).unwrap_or((HOST_DISPLAY_FPS_FALLBACK, false));
        let mut crossover = CrossoverSync::new(APPLE2E_NTSC_FPS, host_display_fps);
        let mut next_host_deadline = Instant::now();
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

            let guest_steps = if use_crossover_sync {
                crossover.on_host_tick()
            } else {
                1
            };
            let frame_override_color = update_ram(&mut ram, guest_steps);

            if let Some(color) = frame_override_color {
                frame.clear(color);
                frame.publish_frame();
            } else {
                video.render_frame(&ram, &mut frame);
            }
            persistence.apply(frame.pixels(), blended_frame.pixels_mut());

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
                    crossover.update_host_period_from_measurement(dt);
                }
                last_present_instant = Some(presented_at);
            }

            if start.elapsed() >= Duration::from_secs(cfg.sdl3_text40x24.auto_exit_seconds) {
                break 'running;
            }
            if use_crossover_sync && crossover_vsync_off {
                pace_to_next_frame(&mut next_host_deadline, crossover.host_period());
            } else if options.vsync_off {
                SDL_Delay(16);
            }
        }

        if let Some(path) = options
            .capture
            .capture_frame_if_requested(&blended_frame, &cfg.sdl3_text40x24.default_screenshot_dir)?
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
