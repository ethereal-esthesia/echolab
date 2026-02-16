use echo_lab::postfx::PersistenceBlend;

fn main() {
    let blend = PersistenceBlend::default();
    let frames = 60usize;

    let mut displayed = [0xff00_0000u32; 1];
    let current_on = [0xffff_ffffu32; 1];
    let current_off = [0xff00_0000u32; 1];

    println!(
        "Persistence table (bleed_num={}, current_weight={}, previous_weight={}, frames={})",
        blend.bleed_num(),
        blend.current_weight_num(),
        blend.previous_weight_num(),
        frames
    );
    println!("frame,current_rgb,result_rgb,result_percent");

    blend.apply(&current_on, &mut displayed);
    print_row(0, 255, displayed[0] & 0xff);

    for frame in 1..=frames {
        blend.apply(&current_off, &mut displayed);
        print_row(frame, 0, displayed[0] & 0xff);
    }
}

fn print_row(frame: usize, current: u32, result: u32) {
    let percent = (result as f64 / 255.0) * 100.0;
    println!("{frame},{current},{result},{percent:.4}");
}
