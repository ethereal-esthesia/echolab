#[inline]
fn xorshift64(x: &mut u64) -> u64 {
    *x ^= *x << 13;
    *x ^= *x >> 7;
    *x ^= *x << 17;
    *x
}

#[inline]
fn mix64(mut z: u64) -> u64 {
    z = (z ^ (z >> 33)).wrapping_mul(0xff51_afd7_ed55_8ccd);
    z = (z ^ (z >> 33)).wrapping_mul(0xc4ce_b9fe_1a85_ec53);
    z ^ (z >> 33)
}

pub struct FastRng {
    state: u64,
}

impl FastRng {
    pub fn new(seed: u64) -> Self {
        let mixed = mix64(seed);
        let state = if mixed == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            mixed
        };
        Self { state }
    }

    #[inline]
    pub fn next_u64(&mut self) -> u64 {
        xorshift64(&mut self.state)
    }

    #[inline]
    pub fn next_u16(&mut self) -> u16 {
        (self.next_u64() >> 48) as u16
    }

    #[inline]
    pub fn next_u8(&mut self) -> u8 {
        (self.next_u64() >> 56) as u8
    }
}
