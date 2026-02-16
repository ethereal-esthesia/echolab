#[cfg(not(feature = "sdl3"))]
fn main() {
    eprintln!("This example requires the 'sdl3' feature.");
    eprintln!("Run: cargo run --example sdl3_text40x24 --features sdl3 -- --screenshot");
}

#[cfg(feature = "sdl3")]
mod app {
    use echo_lab::capture::CaptureOptions;
    use echo_lab::sdl_display_core::{run_text_display, SdlDisplayCoreOptions};
    use echo_lab::video::{COLOR_BLACK, COLOR_WHITE};

    struct CliOptions {
        config_path: String,
        config_path_explicit: bool,
        capture: CaptureOptions,
        white: bool,
        flip_test: bool,
        bw_flip_test: bool,
        fullscreen: bool,
        vsync_off: bool,
        crossover_vsync_off: bool,
    }

    impl Default for CliOptions {
        fn default() -> Self {
            Self {
                config_path: "echolab.toml".to_owned(),
                config_path_explicit: false,
                capture: CaptureOptions::default(),
                white: false,
                flip_test: false,
                bw_flip_test: false,
                fullscreen: false,
                vsync_off: false,
                crossover_vsync_off: false,
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
                    "--bw-flip-test" => {
                        options.bw_flip_test = true;
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
                    "--crossover-vsync-off" | "--crossfade-vsync-off" => {
                        options.crossover_vsync_off = true;
                        i += 1;
                    }
                    "-h" | "--help" => {
                        println!(
                            "Usage: cargo run --example sdl3_text40x24 --features sdl3 -- [--config <path>] [--white] [--flip-test] [--bw-flip-test] [--fullscreen] [--vsync-off] [--crossover-vsync-off] [--screenshot [dir]]"
                        );
                        println!("Config default path: ./echolab.toml");
                        println!("Default text color is green; pass --white for white-on-black.");
                        println!("Pass --flip-test to randomize all cells with codes 0..15 every frame.");
                        println!("Pass --bw-flip-test for full-frame black/white flipping every frame.");
                        println!("Pass --fullscreen to start in fullscreen mode.");
                        println!("Default sync uses host-refresh crossover to Apple IIe timing.");
                        println!("Pass --crossover-vsync-off to disable renderer VSync while keeping crossover sync.");
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

    struct DemoState {
        flip_test: bool,
        bw_flip_test: bool,
        bw_is_white: bool,
        rng: echo_lab::rng::FastRng,
    }

    impl DemoState {
        fn new(flip_test: bool, bw_flip_test: bool) -> Self {
            Self {
                flip_test,
                bw_flip_test,
                bw_is_white: false,
                rng: echo_lab::rng::FastRng::new(0x4543_484f_4c41_42u64),
            }
        }

        fn update(&mut self, ram: &mut [u8; 65536], guest_steps: usize) -> Option<u32> {
            if self.bw_flip_test {
                self.bw_is_white = !self.bw_is_white;
                return Some(if self.bw_is_white {
                    COLOR_WHITE
                } else {
                    COLOR_BLACK
                });
            }

            if self.flip_test {
                let steps = guest_steps.max(1);
                for _ in 0..steps {
                    fill_text_page_random_0_to_15(ram, 0x0400, &mut self.rng);
                }
            }
            None
        }
    }

    pub fn run() -> Result<(), String> {
        let options = CliOptions::parse()?;
        let mut state = DemoState::new(options.flip_test, options.bw_flip_test);

        let core_options = SdlDisplayCoreOptions {
            title: "Echo Lab SDL3 Text 40x24".to_owned(),
            config_path: options.config_path,
            config_path_explicit: options.config_path_explicit,
            capture: options.capture,
            fullscreen: options.fullscreen,
            vsync_off: options.vsync_off,
            crossover_vsync_off: options.crossover_vsync_off,
            text_base: 0x0400,
            foreground_color: if options.white {
                COLOR_WHITE
            } else {
                echo_lab::video::COLOR_PHOSPHOR_GREEN
            },
        };

        run_text_display(
            core_options,
            |ram| fill_text_page_demo_layout(ram, 0x0400),
            |ram, guest_steps| state.update(ram, guest_steps),
        )
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

    fn fill_text_page_random_0_to_15(
        ram: &mut [u8; 65536],
        text_base: usize,
        rng: &mut echo_lab::rng::FastRng,
    ) {
        const COLS: usize = 40;
        const ROWS: usize = 24;
        for i in 0..(COLS * ROWS) {
            ram[text_base + i] = rng.next_u8() & 0x0f;
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
