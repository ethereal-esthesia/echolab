use echo_lab::timing::CrossoverSync;

#[test]
fn crossover_sync_maintains_expected_cadence_over_five_minutes() {
    let host_hz = 60.0;
    let guest_hz = 59.92;
    let host_frames = (5.0 * 60.0 * host_hz) as usize; // 5 minutes at 60 Hz

    let mut sync = CrossoverSync::new(guest_hz, host_hz);
    let mut guest_steps = 0usize;
    let mut zero_step_frames = 0usize;

    for _ in 0..host_frames {
        let steps = sync.on_host_tick();
        guest_steps += steps;
        if steps == 0 {
            zero_step_frames += 1;
        }
    }

    // With 5-minute span and this accumulator initialization, we expect
    // stable cadence around 59.92 Hz with one startup-biased extra guest step.
    assert_eq!(guest_steps, 17_977);
    assert_eq!(zero_step_frames, 23);
}

#[test]
fn crossover_sync_drop_intervals_are_about_every_750_host_frames() {
    let mut sync = CrossoverSync::new(59.92, 60.0);
    let mut drop_frames = Vec::new();

    for frame in 1..=18_000usize {
        if sync.on_host_tick() == 0 {
            drop_frames.push(frame);
        }
    }

    assert!(!drop_frames.is_empty());
    for pair in drop_frames.windows(2) {
        let interval = pair[1] - pair[0];
        assert!(
            (749..=751).contains(&interval),
            "unexpected interval between drops: {}",
            interval
        );
    }
}
