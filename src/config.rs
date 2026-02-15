use std::fs;
use std::io;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sdl3Text40x24Config {
    pub default_screenshot_path: String,
    pub auto_exit_seconds: u64,
}

impl Default for Sdl3Text40x24Config {
    fn default() -> Self {
        Self {
            default_screenshot_path: "screenshots/echolab_last_frame.ppm".to_owned(),
            auto_exit_seconds: 5,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct EchoLabConfig {
    pub sdl3_text40x24: Sdl3Text40x24Config,
}

impl EchoLabConfig {
    pub fn load_from_path<P: AsRef<Path>>(path: P, strict_missing: bool) -> Result<Self, String> {
        let path_ref = path.as_ref();
        match fs::read_to_string(path_ref) {
            Ok(contents) => Self::from_toml_like(&contents),
            Err(err) if err.kind() == io::ErrorKind::NotFound && !strict_missing => {
                Ok(Self::default())
            }
            Err(err) => Err(format!(
                "failed to read config '{}': {}",
                path_ref.display(),
                err
            )),
        }
    }

    pub fn from_toml_like(contents: &str) -> Result<Self, String> {
        let mut cfg = Self::default();
        let mut section = String::new();

        for (line_no, raw_line) in contents.lines().enumerate() {
            let line = raw_line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            if line.starts_with('[') && line.ends_with(']') {
                section = line[1..line.len() - 1].trim().to_owned();
                continue;
            }

            let Some((key_raw, value_raw)) = line.split_once('=') else {
                return Err(format!(
                    "invalid config line {}: expected key = value",
                    line_no + 1
                ));
            };

            let key = key_raw.trim();
            let value = parse_string_value(value_raw.trim(), line_no + 1)?;

            if section == "sdl3_text40x24" {
                match key {
                    "default_screenshot_path" => {
                        cfg.sdl3_text40x24.default_screenshot_path = value;
                    }
                    "auto_exit_seconds" => {
                        cfg.sdl3_text40x24.auto_exit_seconds =
                            value.parse::<u64>().map_err(|e| {
                                format!("invalid auto_exit_seconds on line {}: {}", line_no + 1, e)
                            })?;
                    }
                    _ => {}
                }
            }
        }

        Ok(cfg)
    }
}

fn parse_string_value(raw: &str, line_no: usize) -> Result<String, String> {
    if raw.starts_with('"') {
        if raw.len() < 2 || !raw.ends_with('"') {
            return Err(format!("unterminated quoted value on line {}", line_no));
        }
        Ok(raw[1..raw.len() - 1].to_owned())
    } else {
        Ok(raw.to_owned())
    }
}
