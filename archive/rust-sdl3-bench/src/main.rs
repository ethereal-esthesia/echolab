use sdl3::event::Event;
use sdl3::mouse::MouseButton;
use sdl3::pixels::Color;
use sdl3::render::FRect;
use sdl3::render::Texture;
use sdl3::render::TextureCreator;
use sdl3::video::WindowContext;
use std::thread;
use std::time::{Duration, Instant};

fn fill_pattern_texture(
    texture: &mut Texture<'_>,
    pattern_w: usize,
    pattern_h: usize,
    scale_x: usize,
    scale_y: usize,
    phase: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    texture
        .with_lock(None, |buf: &mut [u8], pitch: usize| {
            for y in 0..pattern_h {
                let ly = y / scale_y;
                let row = &mut buf[y * pitch..(y + 1) * pitch];
                for x in 0..pattern_w {
                    let lx = x / scale_x;
                    let bright = ((lx + ly + phase) & 1) == 0;
                    let c = if bright { 0xd0u8 } else { 0x20u8 };
                    let off = x * 4;
                    // ARGB8888 little-endian bytes in memory: B, G, R, A
                    row[off] = c;
                    row[off + 1] = c;
                    row[off + 2] = c;
                    row[off + 3] = 0xff;
                }
            }
        })
        .map_err(|e| std::io::Error::other(e.to_string()))?;
    Ok(())
}

fn create_phase_texture<'a>(
    texture_creator: &'a TextureCreator<WindowContext>,
    pattern_w: usize,
    pattern_h: usize,
    scale_x: usize,
    scale_y: usize,
    phase: usize,
) -> Result<Texture<'a>, Box<dyn std::error::Error>> {
    let mut texture = texture_creator
        .create_texture_streaming(
            Some(Into::<sdl3::pixels::PixelFormat>::into(
                sdl3::pixels::PixelFormatEnum::ARGB8888,
            )),
            pattern_w as u32,
            pattern_h as u32,
        )
        .map_err(|e| std::io::Error::other(e.to_string()))?;
    fill_pattern_texture(
        &mut texture,
        pattern_w,
        pattern_h,
        scale_x,
        scale_y,
        phase,
    )?;
    Ok(texture)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Request VSync-backed presents for the renderer.
    let _ = sdl3::hint::set(sdl3::hint::names::RENDER_VSYNC, "1");

    let sdl = sdl3::init()?;
    let video = sdl.video()?;
    let mouse = sdl.mouse();

    let window = video
        .window("Rust SDL3 Bench", 1280, 800)
        .position_centered()
        .resizable()
        .build()?;

    let mut canvas = window.into_canvas();
    canvas.window_mut().set_fullscreen(true)?;

    // Keep cursor hidden in fullscreen, matching the Java probe policy.
    mouse.show_cursor(false);
    canvas.window_mut().raise();
    canvas.window_mut().set_keyboard_grab(true);
    canvas.window_mut().set_mouse_grab(true);

    let mut event_pump = sdl.event_pump()?;

    let logical_w = 140usize;
    let logical_h = 192usize;
    let scale_x = 4usize;
    let scale_y = 2usize;
    let pattern_w = logical_w * scale_x; // 560
    let pattern_h = logical_h * scale_y; // 384

    let texture_creator = canvas.texture_creator();
    let texture_phase_0 = create_phase_texture(
        &texture_creator,
        pattern_w,
        pattern_h,
        scale_x,
        scale_y,
        0,
    )?;
    let texture_phase_1 = create_phase_texture(
        &texture_creator,
        pattern_w,
        pattern_h,
        scale_x,
        scale_y,
        1,
    )?;

    let mut pattern_enabled = true;
    let mut invert_phase = false;
    let mut mouse_x: i32 = (pattern_w / 2) as i32;
    let mut mouse_y: i32 = (pattern_h / 2) as i32;

    let mut perf_start = Instant::now();
    let mut frames: u64 = 0;
    let mut present_total = Duration::ZERO;
    let mut present_min = Duration::MAX;
    let mut present_max = Duration::ZERO;
    let mut draw_total = Duration::ZERO;

    println!("Rust SDL3 bench started. Left-click toggles pattern. Esc exits.");

    'running: loop {
        for event in event_pump.poll_iter() {
            match event {
                Event::Quit { .. } => break 'running,
                Event::KeyDown { keycode, .. } => {
                    if let Some(sdl3::keyboard::Keycode::Escape) = keycode {
                        break 'running;
                    }
                }
                Event::MouseMotion { x, y, .. } => {
                    mouse_x = x.round() as i32;
                    mouse_y = y.round() as i32;
                }
                Event::MouseButtonDown { mouse_btn, x, y, .. } => {
                    mouse_x = x.round() as i32;
                    mouse_y = y.round() as i32;
                    if mouse_btn == MouseButton::Left {
                        pattern_enabled = !pattern_enabled;
                        println!("[pattern] enabled={pattern_enabled}");
                    }
                }
                Event::MouseButtonUp { mouse_btn, x, y, .. } => {
                    mouse_x = x.round() as i32;
                    mouse_y = y.round() as i32;
                    let _ = mouse_btn;
                }
                _ => {}
            }
        }

        if pattern_enabled {
            invert_phase = !invert_phase;
        }

        let render_start = Instant::now();
        canvas.set_draw_color(Color::RGB(0, 0, 0));
        canvas.clear();

        if pattern_enabled {
            let (win_w, win_h) = canvas.output_size()?;
            let fit = f32::min(win_w as f32 / pattern_w as f32, win_h as f32 / pattern_h as f32);
            let draw_w = (pattern_w as f32 * fit).round().max(1.0);
            let draw_h = (pattern_h as f32 * fit).round().max(1.0);
            let draw_x = ((win_w as f32 - draw_w) / 2.0).max(0.0);
            let draw_y = ((win_h as f32 - draw_h) / 2.0).max(0.0);
            let active_texture = if invert_phase {
                &texture_phase_1
            } else {
                &texture_phase_0
            };
            canvas.copy(active_texture, None, Some(FRect::new(draw_x, draw_y, draw_w, draw_h)))?;
        }

        // 11x11 inverse crosshair
        let inv = if invert_phase { 0u8 } else { 255u8 };
        canvas.set_draw_color(Color::RGB(inv, inv, inv));
        canvas.draw_line((mouse_x - 5, mouse_y), (mouse_x + 5, mouse_y))?;
        canvas.draw_line((mouse_x, mouse_y - 5), (mouse_x, mouse_y + 5))?;

        let present_start = Instant::now();
        let draw_elapsed = present_start.duration_since(render_start);
        let _ = canvas.present();
        let present_elapsed = present_start.elapsed();

        frames += 1;
        present_total += present_elapsed;
        draw_total += draw_elapsed;
        if present_elapsed < present_min {
            present_min = present_elapsed;
        }
        if present_elapsed > present_max {
            present_max = present_elapsed;
        }

        mouse.show_cursor(false);

        let elapsed = perf_start.elapsed();
        if elapsed >= Duration::from_secs(2) {
            let secs = elapsed.as_secs_f64();
            let fps = frames as f64 / secs;
            let avg_present_ms = if frames == 0 {
                0.0
            } else {
                (present_total.as_secs_f64() * 1000.0) / frames as f64
            };
            let min_present_ms = if frames == 0 { 0.0 } else { present_min.as_secs_f64() * 1000.0 };
            let max_present_ms = if frames == 0 { 0.0 } else { present_max.as_secs_f64() * 1000.0 };
            let draw_pct = if elapsed.is_zero() {
                0.0
            } else {
                (draw_total.as_secs_f64() * 100.0) / elapsed.as_secs_f64()
            };
            let present_wait_pct = if elapsed.is_zero() {
                0.0
            } else {
                (present_total.as_secs_f64() * 100.0) / elapsed.as_secs_f64()
            };
            let draw_ms_per_frame = if frames == 0 {
                0.0
            } else {
                (draw_total.as_secs_f64() * 1000.0) / frames as f64
            };
            let present_wait_ms_per_frame = if frames == 0 {
                0.0
            } else {
                (present_total.as_secs_f64() * 1000.0) / frames as f64
            };
            println!(
                "[perf] fps={fps:.2} present_ms(avg/min/max)={avg_present_ms:.3}/{min_present_ms:.3}/{max_present_ms:.3} draw_pct={draw_pct:.3}% present_wait_pct={present_wait_pct:.3}% draw_ms_per_frame={draw_ms_per_frame:.4} present_wait_ms_per_frame={present_wait_ms_per_frame:.4} frames={frames}"
            );
            perf_start = Instant::now();
            frames = 0;
            present_total = Duration::ZERO;
            present_min = Duration::MAX;
            present_max = Duration::ZERO;
            draw_total = Duration::ZERO;
        }

        thread::sleep(Duration::from_millis(1));
    }

    Ok(())
}
