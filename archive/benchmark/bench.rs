use std::env;
use std::time::Instant;

#[inline(always)]
fn xorshift64(mut s: u64) -> u64 {
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    s
}

fn main() {
    let steps: u64 = env::args()
        .nth(1)
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(50_000_000);

    let mut mem = [0u8; 65536];
    let mut a: u8 = 0x12;
    let mut x: u8 = 0x34;
    let mut y: u8 = 0x56;
    let mut p: u8 = 0x24;
    let mut pc: u16 = 0x4000;
    let mut state: u64 = 0x6502_2026;

    for i in 0..mem.len() {
        mem[i] = (i as u8) ^ ((i >> 8) as u8);
    }

    let t0 = Instant::now();
    for _ in 0..steps {
        state = xorshift64(state);
        let op = (state & 0xFF) as u8;
        let addr = pc.wrapping_add(x as u16).wrapping_add((y as u16) << 1);
        let m = mem[addr as usize];

        match op & 0x0F {
            0 => {
                a = a.wrapping_add(m).wrapping_add(p & 1);
                p = (p & !0x83) | if a == 0 { 0x02 } else { 0 } | if (a & 0x80) != 0 { 0x80 } else { 0 };
            }
            1 => {
                a ^= m;
                p = (p & !0x82) | if a == 0 { 0x02 } else { 0 } | if (a & 0x80) != 0 { 0x80 } else { 0 };
            }
            2 => {
                a |= m;
                p = (p & !0x82) | if a == 0 { 0x02 } else { 0 } | if (a & 0x80) != 0 { 0x80 } else { 0 };
            }
            3 => {
                a &= m;
                p = (p & !0x82) | if a == 0 { 0x02 } else { 0 } | if (a & 0x80) != 0 { 0x80 } else { 0 };
            }
            4 => mem[addr as usize] = m.wrapping_add(x),
            5 => mem[addr as usize] = m.wrapping_sub(y),
            6 => x = x.wrapping_add(1),
            7 => y = y.wrapping_sub(1),
            8 => pc = pc.wrapping_add(m as i8 as i16 as u16),
            9 => p ^= 0x41,
            10 => a = a.rotate_left(1),
            11 => a = a.rotate_right(1),
            12 => {
                let ix = pc.wrapping_add(x as u16) as usize;
                mem[ix] ^= a;
            }
            13 => {
                let iy = pc.wrapping_add(y as u16) as usize;
                mem[iy] = mem[iy].wrapping_add(p);
            }
            14 => x ^= y,
            _ => y = y.wrapping_add(a),
        }
        pc = pc.wrapping_add(1);
    }

    let secs = t0.elapsed().as_secs_f64();
    let mops = (steps as f64 / 1_000_000.0) / secs;
    let checksum: u64 = (a as u64)
        | ((x as u64) << 8)
        | ((y as u64) << 16)
        | ((p as u64) << 24)
        | ((pc as u64) << 32)
        | ((mem[0x1234] as u64) << 48);

    println!(
        "lang=rust steps={} seconds={:.6} mops={:.3} checksum=0x{:x}",
        steps, secs, mops, checksum
    );
}
