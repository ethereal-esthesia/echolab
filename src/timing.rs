use std::thread;
use std::time::{Duration, Instant};

pub struct CrossoverSync {
    guest_hz: f64,
    guest_per_host: f64,
    host_period_secs: f64,
    accumulator: f64,
}

impl CrossoverSync {
    pub fn new(guest_hz: f64, host_hz: f64) -> Self {
        let host_period_secs = 1.0 / host_hz;
        Self {
            guest_hz,
            guest_per_host: guest_hz / host_hz,
            host_period_secs,
            accumulator: 1.0,
        }
    }

    pub fn on_host_tick(&mut self) -> usize {
        self.accumulator += self.guest_per_host;
        let steps = self.accumulator.floor() as usize;
        self.accumulator -= steps as f64;
        steps
    }

    pub fn update_host_period_from_measurement(&mut self, dt_secs: f64) {
        if dt_secs <= (1.0 / 240.0) || dt_secs >= (1.0 / 20.0) {
            return;
        }
        self.host_period_secs = self.host_period_secs * 0.9 + dt_secs * 0.1;
        self.guest_per_host = self.guest_hz * self.host_period_secs;
    }

    pub fn host_period(&self) -> Duration {
        Duration::from_secs_f64(self.host_period_secs)
    }
}

pub fn pace_to_next_frame(next_frame_deadline: &mut Instant, frame_period: Duration) {
    *next_frame_deadline += frame_period;
    let now = Instant::now();
    if now + Duration::from_millis(1) < *next_frame_deadline {
        thread::sleep(*next_frame_deadline - now - Duration::from_millis(1));
    }
    while Instant::now() < *next_frame_deadline {
        std::hint::spin_loop();
    }
    let now = Instant::now();
    if now.duration_since(*next_frame_deadline) > frame_period.saturating_mul(2) {
        *next_frame_deadline = now;
    }
}
