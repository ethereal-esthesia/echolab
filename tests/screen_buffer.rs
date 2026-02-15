use echo_lab::screen_buffer::ScreenBuffer;
use std::fs;
use std::path::PathBuf;

#[test]
fn screen_buffer_has_expected_dimensions_and_size() {
    let buffer = ScreenBuffer::new(560, 192);
    assert_eq!(buffer.dimensions(), (560, 192));
    assert_eq!(buffer.pixels().len(), 560 * 192);
}

#[test]
fn set_and_get_pixel_with_bounds_checking() {
    let mut buffer = ScreenBuffer::new(4, 3);

    assert!(buffer.set_pixel(2, 1, 0xff00_ff00));
    assert_eq!(buffer.get_pixel(2, 1), Some(0xff00_ff00));

    assert!(!buffer.set_pixel(4, 1, 0x1234_5678));
    assert_eq!(buffer.get_pixel(4, 1), None);
    assert_eq!(buffer.get_pixel(0, 3), None);
}

#[test]
fn clear_fills_entire_surface() {
    let mut buffer = ScreenBuffer::new(3, 2);
    buffer.set_pixel(1, 1, 0x0102_0304);

    buffer.clear(0xaabb_ccdd);
    assert!(buffer.pixels().iter().all(|p| *p == 0xaabb_ccdd));
}

#[test]
fn publish_frame_monotonically_increments_frame_id() {
    let mut buffer = ScreenBuffer::new(2, 2);
    assert_eq!(buffer.frame_id(), 0);

    assert_eq!(buffer.publish_frame(), 1);
    assert_eq!(buffer.publish_frame(), 2);
    assert_eq!(buffer.frame_id(), 2);
}

#[test]
fn save_as_ppm_writes_valid_header_and_pixels() {
    let mut buffer = ScreenBuffer::new(2, 1);
    assert!(buffer.set_pixel(0, 0, 0xffff_0000));
    assert!(buffer.set_pixel(1, 0, 0xff00_ff00));

    let mut path: PathBuf = std::env::temp_dir();
    path.push(format!(
        "echolab_screenbuffer_{}_{}.ppm",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("time should be after epoch")
            .as_nanos()
    ));

    buffer
        .save_as_ppm(&path)
        .expect("ppm should be written successfully");
    let bytes = fs::read(&path).expect("ppm should be readable");
    let _ = fs::remove_file(&path);

    let header = b"P6\n2 1\n255\n";
    assert!(bytes.starts_with(header));
    assert_eq!(&bytes[header.len()..], &[255, 0, 0, 0, 255, 0]);
}
