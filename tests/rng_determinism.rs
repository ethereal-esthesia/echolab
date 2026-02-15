use echo_lab::rng::FastRng;

#[test]
fn fast_rng_matches_known_vector() {
    let mut rng = FastRng::new(0x6502_2026);
    let expected = [
        0xcd55_7e29_3b77_e682,
        0x91bf_e9a4_9bb6_e9cf,
        0xb41d_a823_cdba_17dc,
        0xc574_ae89_8fb9_14f3,
        0xf884_74ba_2449_3a1a,
        0x5a59_dc4b_b8d0_6eee,
    ];

    for value in expected {
        assert_eq!(rng.next_u64(), value);
    }
}

#[test]
fn fast_rng_same_seed_is_reproducible() {
    let mut a = FastRng::new(12345);
    let mut b = FastRng::new(12345);

    for _ in 0..1024 {
        assert_eq!(a.next_u64(), b.next_u64());
    }
}

#[test]
fn fast_rng_different_seeds_diverge_quickly() {
    let mut a = FastRng::new(1);
    let mut b = FastRng::new(2);

    let mut any_diff = false;
    for _ in 0..64 {
        if a.next_u64() != b.next_u64() {
            any_diff = true;
            break;
        }
    }

    assert!(any_diff);
}
