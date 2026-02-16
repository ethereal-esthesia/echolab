use echo_lab::postfx::PersistenceBlend;

#[test]
fn persistence_blend_matches_expected_integer_decay_sequence() {
    let blend = PersistenceBlend::default(); // bleed_num = 196
    let mut displayed = [0xff00_0000u32; 1];

    // Frame 0: current pixel is fully on.
    let current_on = [0xffff_ffffu32; 1];
    blend.apply(&current_on, &mut displayed);
    assert_eq!(displayed[0] & 0xff, 59);

    // Frames 1..: current pixel is off and only persistence remains.
    let current_off = [0xff00_0000u32; 1];
    let expected_channel_values = [45u32, 34, 26, 19, 14, 10, 7, 5, 3, 2, 1, 0];

    for expected in expected_channel_values {
        blend.apply(&current_off, &mut displayed);
        let r = (displayed[0] >> 16) & 0xff;
        let g = (displayed[0] >> 8) & 0xff;
        let b = displayed[0] & 0xff;
        assert_eq!(r, expected);
        assert_eq!(g, expected);
        assert_eq!(b, expected);
    }
}
