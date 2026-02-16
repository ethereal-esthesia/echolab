use echo_lab::capture::CaptureOptions;
use echo_lab::screen_buffer::ScreenBuffer;
use std::fs;

#[test]
fn parse_arg_accepts_screenshot_with_optional_dir() {
    let args = vec!["--screenshot".to_owned(), "shots".to_owned()];
    let mut i = 0usize;
    let mut opts = CaptureOptions::default();

    let handled = opts.parse_arg(&args, &mut i).expect("parse should succeed");
    assert!(handled);
    assert_eq!(i, 2);
    assert!(opts.screenshot_requested);
    assert_eq!(opts.screenshot_dir_override.as_deref(), Some("shots"));

    let args2 = vec!["--screenshot".to_owned()];
    let mut i2 = 0usize;
    let mut opts2 = CaptureOptions::default();
    opts2
        .parse_arg(&args2, &mut i2)
        .expect("parse should succeed");
    assert_eq!(i2, 1);
    assert!(opts2.screenshot_requested);
    assert_eq!(opts2.screenshot_dir_override, None);
}

#[test]
fn capture_frame_if_requested_uses_default_dir_and_timestamped_name() {
    let mut buffer = ScreenBuffer::new(1, 1);
    assert!(buffer.set_pixel(0, 0, 0xffff_ffff));

    let mut dir = std::env::temp_dir();
    dir.push(format!(
        "echolab_capture_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("time should be after epoch")
            .as_nanos()
    ));

    let opts = CaptureOptions {
        screenshot_requested: true,
        screenshot_dir_override: None,
    };

    let saved = opts
        .capture_frame_if_requested(&buffer, dir.to_str().expect("utf-8 dir"))
        .expect("capture should succeed")
        .expect("capture should produce a file");

    let filename = saved
        .file_name()
        .and_then(|n| n.to_str())
        .expect("filename should be utf-8");
    assert!(filename.starts_with("screenshot_"));
    assert!(filename.ends_with(".ppm"));
    assert!(saved.exists());

    let _ = fs::remove_file(saved);
    let _ = fs::remove_dir_all(dir);
}
