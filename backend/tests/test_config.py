from sideproof import config


def test_secret_from_bare_file(tmp_path, monkeypatch):
    f = tmp_path / 'key'
    f.write_text('sk-abc123==\n')
    monkeypatch.delenv('YOUCAM_API_KEY', raising=False)
    monkeypatch.setenv('YOUCAM_API_KEY_FILE', str(f))
    assert config.secret('YOUCAM_API_KEY') == 'sk-abc123=='


def test_secret_from_env_file(tmp_path, monkeypatch):
    f = tmp_path / 'sideproof.env'
    f.write_text('# keys\nYOUCAM_API_KEY=yc-1\nexport GEMINI_API_KEY="gm-2"\n')
    for name in ('YOUCAM_API_KEY', 'GEMINI_API_KEY', 'DEEPSEEK_API_KEY'):
        monkeypatch.delenv(name, raising=False)
        monkeypatch.setenv(name + '_FILE', str(f))
    assert config.secret('YOUCAM_API_KEY') == 'yc-1'
    assert config.secret('GEMINI_API_KEY') == 'gm-2'
    assert config.secret('DEEPSEEK_API_KEY') is None
