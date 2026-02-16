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

    pub fn previous_weight_num(&self) -> u16 {
        self.bleed_num.min(256)
    }

    pub fn current_weight_num(&self) -> u16 {
        256u16.saturating_sub(self.previous_weight_num())
    }

    pub fn apply(&self, src: &[u32], dst: &mut [u32]) {
        assert_eq!(src.len(), dst.len(), "source and destination lengths differ");
        let prev_w = self.previous_weight_num();
        let cur_w = self.current_weight_num();
        for (current, displayed) in src.iter().zip(dst.iter_mut()) {
            *displayed = blend_rgb(*current, *displayed, cur_w, prev_w);
        }
    }
}

fn blend_rgb(current: u32, previous: u32, current_w: u16, previous_w: u16) -> u32 {
    let cr = ((current >> 16) & 0xff) as u16;
    let cg = ((current >> 8) & 0xff) as u16;
    let cb = (current & 0xff) as u16;
    let pr = ((previous >> 16) & 0xff) as u16;
    let pg = ((previous >> 8) & 0xff) as u16;
    let pb = (previous & 0xff) as u16;

    let r = ((cr * current_w + pr * previous_w) / 256) as u32;
    let g = ((cg * current_w + pg * previous_w) / 256) as u32;
    let bl = ((cb * current_w + pb * previous_w) / 256) as u32;
    0xff00_0000 | (r << 16) | (g << 8) | bl
}
