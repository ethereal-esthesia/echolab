use echo_lab::screen_buffer::ScreenBuffer;
use echo_lab::video::{
    CELL_WIDTH, COLOR_WHITE, FRAME_HEIGHT, FRAME_WIDTH, TEXT_COLS, TextVideoController,
};

fn main() {
    let mut ram = [b' '; 65536];
    let message = b"HELLO WORLD";
    let base = 0x0400usize;

    for (i, ch) in message.iter().enumerate() {
        ram[base + i] = *ch;
    }

    let mut out = ScreenBuffer::new(FRAME_WIDTH, FRAME_HEIGHT);
    let video = TextVideoController::default();
    video.render_frame(&ram, &mut out);

    println!(
        "Rendered frame_id={} at {}x{}",
        out.frame_id(),
        FRAME_WIDTH,
        FRAME_HEIGHT
    );

    let mut row_preview = String::with_capacity(TEXT_COLS);
    for col in 0..TEXT_COLS {
        let px = col * CELL_WIDTH;
        let on = out.get_pixel(px, 0) == Some(COLOR_WHITE);
        row_preview.push(if on { '#' } else { '.' });
    }

    println!("Top text row (cell occupancy):");
    println!("{}", row_preview);
    println!("Expected message in RAM: HELLO WORLD");
}
