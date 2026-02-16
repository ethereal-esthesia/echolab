use crate::screen_buffer::ScreenBuffer;
use std::path::PathBuf;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CaptureOptions {
    pub screenshot_requested: bool,
    pub screenshot_dir_override: Option<String>,
}

impl CaptureOptions {
    pub fn parse_arg(&mut self, args: &[String], index: &mut usize) -> Result<bool, String> {
        if args[*index] != "--screenshot" {
            return Ok(false);
        }

        self.screenshot_requested = true;
        if *index + 1 < args.len() && !args[*index + 1].starts_with('-') {
            self.screenshot_dir_override = Some(args[*index + 1].clone());
            *index += 2;
        } else {
            *index += 1;
        }

        Ok(true)
    }

    pub fn resolved_screenshot_dir(&self, default_dir: &str) -> Option<String> {
        if !self.screenshot_requested {
            return None;
        }

        Some(
            self.screenshot_dir_override
                .clone()
                .unwrap_or_else(|| default_dir.to_owned()),
        )
    }

    pub fn capture_frame_if_requested(
        &self,
        frame: &ScreenBuffer,
        default_dir: &str,
    ) -> Result<Option<PathBuf>, String> {
        let Some(dir) = self.resolved_screenshot_dir(default_dir) else {
            return Ok(None);
        };

        let path = frame
            .save_timestamped_ppm_in_dir(&dir)
            .map_err(|e| format!("failed to save screenshot in '{}': {}", dir, e))?;
        Ok(Some(path))
    }
}
