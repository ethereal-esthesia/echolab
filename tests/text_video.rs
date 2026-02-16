use echo_lab::screen_buffer::ScreenBuffer;
use echo_lab::video::{
    COLOR_BLACK, COLOR_PHOSPHOR_GREEN, FRAME_HEIGHT, FRAME_WIDTH, TextVideoController,
};

#[test]
fn text_video_renders_non_space_cells_on_even_scanlines_only() {
    let mut ram = [0u8; 65536];
    ram[0x0400] = b'A';

    let mut out = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
    let video = TextVideoController::default();
    video.render_frame(&ram, &mut out);

    for x in 0..7 {
        assert_eq!(out.get_pixel(x, 0), Some(COLOR_PHOSPHOR_GREEN));
        assert_eq!(out.get_pixel(x, 1), Some(COLOR_BLACK));
    }
}

#[test]
fn text_video_keeps_space_cells_black_even_on_active_scanlines() {
    let mut ram = [0u8; 65536];
    ram[0x0401] = b' ';

    let mut out = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
    let video = TextVideoController::default();
    video.render_frame(&ram, &mut out);

    for x in 7..14 {
        assert_eq!(out.get_pixel(x, 0), Some(COLOR_BLACK));
        assert_eq!(out.get_pixel(x, 1), Some(COLOR_BLACK));
    }
}

#[test]
fn render_frame_publishes_new_frame() {
    let ram = [0u8; 65536];
    let mut out = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
    let video = TextVideoController::default();

    assert_eq!(out.frame_id(), 0);
    video.render_frame(&ram, &mut out);
    assert_eq!(out.frame_id(), 1);
}
