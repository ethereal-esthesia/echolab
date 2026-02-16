use crate::screen_buffer::ScreenBuffer;

pub const TEXT_COLS: usize = 40;
pub const TEXT_ROWS: usize = 24;
pub const GLYPH_WIDTH: usize = 7;
pub const CELL_WIDTH: usize = GLYPH_WIDTH * 2;
pub const GLYPH_HEIGHT: usize = 8;
pub const CELL_HEIGHT: usize = GLYPH_HEIGHT * 2;
pub const FRAME_WIDTH: usize = TEXT_COLS * CELL_WIDTH;
pub const FRAME_HEIGHT: usize = TEXT_ROWS * CELL_HEIGHT;

pub const COLOR_BLACK: u32 = 0xff00_0000;
pub const COLOR_PHOSPHOR_GREEN: u32 = 0xff33_ff66;

const TEXT_DISPLAY_ROM: &[u8; 6144] =
    include_bytes!("../../assets/roms/APPLE2E_TEXT_DISPLAY_ROUNDED.bin");
const TEXT_DISPLAY_BANK_SIZE: usize = 2048;
const NORMAL_BANK_OFFSET: usize = 0;
const NON_INVERSE_GLYPH_OFFSET: usize = 128 * GLYPH_HEIGHT;

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
        let code = (ch & 0x7f) as usize;
        let glyph_base = NORMAL_BANK_OFFSET + NON_INVERSE_GLYPH_OFFSET + code * GLYPH_HEIGHT;

        debug_assert!(glyph_base + GLYPH_HEIGHT <= TEXT_DISPLAY_BANK_SIZE);

        for glyph_y in 0..GLYPH_HEIGHT {
            let row_bits = TEXT_DISPLAY_ROM[glyph_base + glyph_y] & 0x7f;
            let py = y0 + glyph_y * 2;

            for x in 0..CELL_WIDTH {
                let px = x0 + x;
                let glyph_x = x / 2;
                // Apple IIe glyph rows in this ROM table are stored LSB-left for 7-bit pixels.
                let glyph_on = ((row_bits >> glyph_x) & 0x01) != 0;
                let color = if glyph_on {
                    COLOR_PHOSPHOR_GREEN
                } else {
                    COLOR_BLACK
                };
                let _ = out.set_pixel(px, py, color);
            }
        }
    }
}
