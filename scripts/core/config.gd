class_name Config
## Settings: defaults below, then res://settings.cfg, then command-line overrides after "--"
## (e.g. `-- --rounds=2 --mode=bot`). A bare flag like `--bot-vs-bot` means true.


static func load_settings() -> Dictionary:
	var s := {
		"rounds": 3, "round_seconds": 180.0, "rest_seconds": 60.0,
		"dummy_sway": true, "bot_skill": 0.6,
		"port": 47230, "discovery_port": 47231,
		# Launch options (command line only):
		"mode": "",            # practice | bot | host | join: skip the lobby
		"join": "",            # host IP to join directly instead of LAN discovery
		"bot_vs_bot": false,   # a bot drives your boxer too (headless testing)
		"timescale": 1.0,      # run the simulation faster (headless testing)
		"quit_on_end": false,  # quit when the match ends (headless testing)
	}
	var cfg := ConfigFile.new()
	if cfg.load("res://settings.cfg") == OK:
		for section in cfg.get_sections():
			for key in cfg.get_section_keys(section):
				s[key] = cfg.get_value(section, key)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var key := kv[0].replace("-", "_")
		if not s.has(key):
			push_warning("Unknown option: " + arg)
			continue
		s[key] = true if kv.size() == 1 else _parse_like(s[key], kv[1])
	return s


static func _parse_like(old: Variant, text: String) -> Variant:
	match typeof(old):
		TYPE_BOOL:
			return text in ["1", "true", "yes", "on"]
		TYPE_INT:
			return text.to_int()
		TYPE_FLOAT:
			return text.to_float()
	return text
