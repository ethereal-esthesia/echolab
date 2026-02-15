use echo_lab::config::EchoLabConfig;

#[test]
fn parse_config_overrides_defaults() {
    let cfg = EchoLabConfig::from_toml_like(
        r#"
[sdl3_text40x24]
default_screenshot_path = "screenshots/custom.ppm"
auto_exit_seconds = 12
"#,
    )
    .expect("config should parse");

    assert_eq!(
        cfg.sdl3_text40x24.default_screenshot_path,
        "screenshots/custom.ppm"
    );
    assert_eq!(cfg.sdl3_text40x24.auto_exit_seconds, 12);
}

#[test]
fn parse_config_uses_defaults_when_values_missing() {
    let cfg = EchoLabConfig::from_toml_like("").expect("empty config should parse");
    assert_eq!(
        cfg.sdl3_text40x24.default_screenshot_path,
        "screenshots/echolab_last_frame.ppm"
    );
    assert_eq!(cfg.sdl3_text40x24.auto_exit_seconds, 5);
}
