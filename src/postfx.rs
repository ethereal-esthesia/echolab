#[derive(Debug, Clone, Copy)]
pub struct PersistenceBlend {
    bleed_num: u16,
}

impl Default for PersistenceBlend {
    fn default() -> Self {
        Self { bleed_num: 196 }
    }
}

impl PersistenceBlend {
    pub fn new(bleed_num: u16) -> Self {
        Self { bleed_num }
    }

    pub fn bleed_num(&self) -> u16 {
        self.bleed_num
    }

    pub fn apply(&self, src: &[u32], dst: &mut [u32]) {
        assert_eq!(src.len(), dst.len(), "source and destination lengths differ");
        for (current, displayed) in src.iter().zip(dst.iter_mut()) {
            let decayed_prev = scale_rgb(*displayed, self.bleed_num);
            *displayed = max_rgb(*current, decayed_prev);
        }
    }
}

fn scale_rgb(pixel: u32, scale_num: u16) -> u32 {
    let r = (((pixel >> 16) & 0xff) as u16 * scale_num / 256) as u32;
    let g = (((pixel >> 8) & 0xff) as u16 * scale_num / 256) as u32;
    let b = ((pixel & 0xff) as u16 * scale_num / 256) as u32;
    0xff00_0000 | (r << 16) | (g << 8) | b
}

fn max_rgb(a: u32, b: u32) -> u32 {
    let ar = (a >> 16) & 0xff;
    let ag = (a >> 8) & 0xff;
    let ab = a & 0xff;
    let br = (b >> 16) & 0xff;
    let bg = (b >> 8) & 0xff;
    let bb = b & 0xff;

    let r = ar.max(br);
    let g = ag.max(bg);
    let bl = ab.max(bb);
    0xff00_0000 | (r << 16) | (g << 8) | bl
}
