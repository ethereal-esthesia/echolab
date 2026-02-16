use crate::screen_buffer::ScreenBuffer;

pub const TEXT_COLS: usize = 40;
pub const TEXT_ROWS: usize = 24;
pub const CELL_WIDTH: usize = 7;
pub const CELL_HEIGHT: usize = 8;
pub const FRAME_WIDTH: usize = TEXT_COLS * CELL_WIDTH;
pub const FRAME_HEIGHT: usize = TEXT_ROWS * CELL_HEIGHT;

pub const COLOR_BLACK: u32 = 0xff00_0000;
pub const COLOR_PHOSPHOR_GREEN: u32 = 0xff33_ff66;

pub struct TextVideoController {
    text_base: u16,
}

impl Default for TextVideoController {
    fn default() -> Self {
        Self::new(0x0400)
    }
}

impl TextVideoController {
    pub fn new(text_base: u16) -> Self {
        Self { text_base }
    }

    pub fn frame_dimensions(&self) -> (usize, usize) {
        (FRAME_WIDTH, FRAME_HEIGHT)
    }

    pub fn render_frame(&self, ram: &[u8; 65536], out: &mut ScreenBuffer) {
        assert_eq!(out.dimensions(), (FRAME_WIDTH, FRAME_HEIGHT));

        out.clear(COLOR_BLACK);

        for row in 0..TEXT_ROWS {
            for col in 0..TEXT_COLS {
                let char_addr = self.text_base as usize + row * TEXT_COLS + col;
                let ch = ram[char_addr & 0xffff];
                self.render_cell(ch, col, row, out);
            }
        }

        out.publish_frame();
    }

    fn render_cell(&self, ch: u8, col: usize, row: usize, out: &mut ScreenBuffer) {
        let x0 = col * CELL_WIDTH;
        let y0 = row * CELL_HEIGHT;

        for y in 0..CELL_HEIGHT {
            // "Every-other-scanline" model: odd scanlines are black.
            let active_scanline = y % 2 == 0;
            let color = if active_scanline && ch != b' ' {
                COLOR_PHOSPHOR_GREEN
            } else {
                COLOR_BLACK
            };

            let py = y0 + y;
            for x in 0..CELL_WIDTH {
                let px = x0 + x;
                let _ = out.set_pixel(px, py, color);
            }
        }
    }
}
