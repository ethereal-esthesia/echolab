#[derive(Debug, Clone)]
pub struct ScreenBuffer {
    width: usize,
    height: usize,
    pixels: Vec<u32>,
    frame_id: u64,
}

impl ScreenBuffer {
    pub fn new(width: usize, height: usize) -> Self {
        assert!(width > 0, "width must be > 0");
        assert!(height > 0, "height must be > 0");

        let len = width
            .checked_mul(height)
            .expect("screen buffer dimensions overflow");

        Self {
            width,
            height,
            pixels: vec![0; len],
            frame_id: 0,
        }
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    pub fn dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    pub fn frame_id(&self) -> u64 {
        self.frame_id
    }

    pub fn pixels(&self) -> &[u32] {
        self.pixels.as_slice()
    }

    pub fn clear(&mut self, color: u32) {
        self.pixels.fill(color);
    }

    pub fn get_pixel(&self, x: usize, y: usize) -> Option<u32> {
        self.index_of(x, y).map(|i| self.pixels[i])
    }

    pub fn set_pixel(&mut self, x: usize, y: usize, color: u32) -> bool {
        match self.index_of(x, y) {
            Some(i) => {
                self.pixels[i] = color;
                true
            }
            None => false,
        }
    }

    pub fn publish_frame(&mut self) -> u64 {
        self.frame_id = self.frame_id.wrapping_add(1);
        self.frame_id
    }

    fn index_of(&self, x: usize, y: usize) -> Option<usize> {
        if x >= self.width || y >= self.height {
            return None;
        }

        Some(y * self.width + x)
    }
}
