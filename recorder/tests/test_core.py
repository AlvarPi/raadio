"""Kiired kontrollid, mis peavad töötama ka vanal Pythonil (macOS-i vaikimisi 3.9)."""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.argv = ["test"]
import kuku_recorder as k  # noqa: E402
import webserver as w  # noqa: E402


def test_parse_ts_browser_and_server_formats():
    for s in ["2026-10-05T02:30:00.000Z", "2026-10-11T12:57:10.822Z",
              "2026-10-06T10:00:00.000000+03:00", "2026-10-11T15:57:00+03:00"]:
        assert k.parse_ts(s) == w.parse_ts(s)
        assert k.parse_ts(s).tzinfo is not None


def test_split_hours_and_titles():
    a = datetime(2026, 10, 11, 14, 23).astimezone()
    ep = {"id": "now:r2:1", "title": "t", "title_prefix": "R2 otse", "start": a.isoformat(),
          "end": (a + timedelta(minutes=120)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
          "lineup": [{"start": a.isoformat(), "end": (a + timedelta(hours=3)).isoformat(), "name": "Saade"}]}
    parts = k.split_hours(ep)
    assert len(parts) == 3 and parts[0]["title"].startswith("R2 otse: Saade")


def test_timer_same_start_end_skipped():
    t = {"id": "timer:x", "station": "r", "name": "n", "days": list(range(7)), "start": "07:00", "end": "07:00"}
    assert k.expand_timers([t], datetime.now(timezone.utc)) == []


def test_prune_done():
    now = datetime.now(timezone.utc)
    keys = {"a@" + (now - timedelta(days=5)).isoformat(), "b@" + now.isoformat(), "junk"}
    assert {x.split("@")[0] for x in k.prune_done(keys)} == {"b"}


def test_normalize_config_drops_bad_timers():
    cfg = w.normalize_config({"timers": [{"id": "timer:a", "start": "25:00", "end": "08:00"},
                                         {"id": "timer:b", "station": "r", "days": [0, 9], "start": "07:00", "end": "08:00"}]})
    assert [t["id"] for t in cfg["timers"]] == ["timer:b"] and cfg["timers"][0]["days"] == [0]


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
