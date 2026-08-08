#!/usr/bin/env python3
"""Offline integration tests for supporting-feed builders and failure retention."""

from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types

from supporting_source_health import load_json, validate_health


ROOT = Path(__file__).resolve().parents[1]
BUILDERS = {
    "fear-greed": ROOT / "scripts" / "fear-greed" / "build_fear_greed.py",
    "ofr-monitor": ROOT / "scripts" / "ofr-monitor" / "build_ofr.py",
    "econ-calendar": ROOT / "scripts" / "econ-calendar" / "build_calendar.py",
    "whats-latest": ROOT / "scripts" / "whats-latest" / "build_news.py",
}


try:
    import requests as _requests  # noqa: F401
except ModuleNotFoundError:
    requests_stub = types.ModuleType("requests")

    def _unexpected_request(*_args, **_kwargs):
        raise RuntimeError("离线生成器测试禁止网络请求")

    requests_stub.get = _unexpected_request
    sys.modules["requests"] = requests_stub


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_builder(dataset: str):
    path = BUILDERS[dataset]
    name = "supporting_builder_" + dataset.replace("-", "_")
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, f"无法加载{dataset}生成器")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def copy_current(dataset: str, temp: Path) -> tuple[Path, Path]:
    data_path = temp / "data.json"
    health_path = temp / "health.json"
    data_path.write_bytes((ROOT / "apps" / dataset / "data.json").read_bytes())
    health_path.write_bytes((ROOT / "apps" / dataset / "health.json").read_bytes())
    return data_path, health_path


def fail(message: str):
    def _raise(*_args, **_kwargs):
        raise RuntimeError(message)
    return _raise


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return deepcopy(self.payload)


def test_fear_greed() -> None:
    module = load_builder("fear-greed")
    with tempfile.TemporaryDirectory() as directory:
        data_path, health_path = copy_current("fear-greed", Path(directory))
        module.OUT_PATH = str(data_path)
        module.HEALTH_PATH = str(health_path)
        module.utc_now = lambda: datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc)
        module.fetch = lambda: {
            "fear_and_greed": {
                "score": 57.4,
                "rating": "greed",
                "previous_close": 55.1,
                "previous_1_week": 49.0,
                "previous_1_month": 51.0,
                "previous_1_year": 61.0,
            },
            "fear_and_greed_historical": {"data": []},
        }
        require(module.build() is True, "CNN成功响应未发布")
        data = load_json(data_path)
        health = load_json(health_path)
        validate_health("fear-greed", data, health)
        require(data["score"] == 57 and health["status"] == "healthy",
                "CNN成功值或健康状态错误")

        before = data_path.read_bytes()
        module.utc_now = lambda: datetime(2026, 8, 8, 13, 0, tzinfo=timezone.utc)
        module.fetch = fail("cnn unavailable")
        require(module.build() is False, "CNN失败运行不应发布")
        require(data_path.read_bytes() == before, "CNN失败覆盖了最后有效data.json")
        failed_health = load_json(health_path)
        validate_health("fear-greed", load_json(data_path), failed_health)
        require(failed_health["status"] == "failed"
                and failed_health["consecutiveFailures"] == 1
                and failed_health["snapshotPreserved"] is True,
                "CNN失败健康未记录旧快照与失败次数")


def test_ofr_monitor() -> None:
    module = load_builder("ofr-monitor")
    fixture = load_json(ROOT / "apps" / "ofr-monitor" / "data.json")
    with tempfile.TemporaryDirectory() as directory:
        data_path, health_path = copy_current("ofr-monitor", Path(directory))
        module.OUT_PATH = str(data_path)
        module.HEALTH_PATH = str(health_path)
        module.utc_now = lambda: datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc)
        module.build_fsi = lambda: deepcopy(fixture["fsi"])
        module.build_funding = lambda: deepcopy(fixture["funding"])
        module.build_mmf = lambda: deepcopy(fixture["mmf"])
        module.build_hedge = lambda: deepcopy(fixture["hedge"])
        require(module.main() is True, "OFR全组件成功未发布")
        data = load_json(data_path)
        health = load_json(health_path)
        validate_health("ofr-monitor", data, health)
        require(health["status"] == "healthy" and health["coverage"]["refreshedComponents"] == 5,
                "OFR全组件成功健康错误")

        module.utc_now = lambda: datetime(2026, 8, 8, 13, 0, tzinfo=timezone.utc)
        module.build_fsi = lambda: deepcopy(fixture["fsi"])
        module.build_funding = fail("funding unavailable")
        module.build_mmf = fail("mmf unavailable")
        module.build_hedge = fail("hedge unavailable")
        require(module.main() is True, "OFR部分成功应发布带回退快照")
        partial_data = load_json(data_path)
        partial_health = load_json(health_path)
        validate_health("ofr-monitor", partial_data, partial_health)
        require(partial_health["status"] == "degraded"
                and partial_health["attempt"]["refreshedComponents"] == ["fsi", "bank"]
                and partial_health["attempt"]["fallbackComponents"] == ["funding", "mmf", "hedge"],
                "OFR部分成功未准确记录逐组件回退")

        before = data_path.read_bytes()
        module.utc_now = lambda: datetime(2026, 8, 8, 14, 0, tzinfo=timezone.utc)
        module.build_fsi = fail("fsi unavailable")
        module.build_funding = fail("funding unavailable")
        module.build_mmf = fail("mmf unavailable")
        module.build_hedge = fail("hedge unavailable")
        require(module.main() is False, "OFR全部动态来源失败不应发布")
        require(data_path.read_bytes() == before, "OFR整批失败重写了旧data.json时间")
        failed_health = load_json(health_path)
        validate_health("ofr-monitor", load_json(data_path), failed_health)
        require(failed_health["status"] == "failed"
                and failed_health["consecutiveFailures"] == 1
                and failed_health["snapshotPreserved"] is True,
                "OFR整批失败健康错误")


def test_econ_calendar() -> None:
    module = load_builder("econ-calendar")
    events = [{
        "date": "2026-08-08T13:00:00+00:00",
        "country": "USD",
        "title": "Non-Farm Employment Change",
        "impact": "High",
        "forecast": "100K",
        "previous": "90K",
        "actual": "110K",
    }]
    with tempfile.TemporaryDirectory() as directory:
        data_path, health_path = copy_current("econ-calendar", Path(directory))
        module.OUT_PATH = str(data_path)
        module.HEALTH_PATH = str(health_path)
        module.utc_now = lambda: datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc)
        module.requests.get = lambda *_args, **_kwargs: FakeResponse(events)
        require(module.build() is True, "经济日历成功响应未发布")
        data = load_json(data_path)
        health = load_json(health_path)
        validate_health("econ-calendar", data, health)
        require(data["count"] == 1 and health["status"] == "healthy",
                "经济日历成功数据或健康错误")

        before = data_path.read_bytes()
        module.utc_now = lambda: datetime(2026, 8, 8, 13, 0, tzinfo=timezone.utc)
        module.requests.get = fail("calendar unavailable")
        require(module.build() is False, "经济日历失败不应发布")
        require(data_path.read_bytes() == before, "经济日历失败覆盖了旧data.json")
        failed_health = load_json(health_path)
        validate_health("econ-calendar", load_json(data_path), failed_health)
        require(failed_health["status"] == "failed"
                and failed_health["consecutiveFailures"] == 1
                and failed_health["snapshotPreserved"] is True,
                "经济日历失败健康错误")


def news_item(category: str, sequence: int) -> dict:
    return {
        "title": f"{category} 测试新闻 {sequence}",
        "source": "测试媒体",
        "link": f"https://news.google.com/rss/articles/{category}-{sequence}",
        "published": 1786190400 + sequence,
    }


def feed_sequence(module, *, fail_first: bool = False, fail_all: bool = False):
    calls = {"count": 0}

    def _fetch(_url, _n=7):
        index = calls["count"]
        calls["count"] += 1
        if fail_all or (fail_first and index == 0):
            raise RuntimeError("news feed unavailable")
        key = module.CATS[index]["key"]
        return [news_item(key, index)]

    return _fetch


def test_whats_latest() -> None:
    module = load_builder("whats-latest")
    with tempfile.TemporaryDirectory() as directory:
        data_path, health_path = copy_current("whats-latest", Path(directory))
        module.OUT_PATH = str(data_path)
        module.HEALTH_PATH = str(health_path)
        module.time.sleep = lambda _seconds: None
        module.utc_now = lambda: datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc)
        module.fetch_feed = feed_sequence(module)
        module.fetch_quote = lambda _symbol: (100.0, 1.0)
        require(module.build() is True, "资讯五板块成功未发布")
        data = load_json(data_path)
        health = load_json(health_path)
        validate_health("whats-latest", data, health)
        require(health["status"] == "healthy"
                and health["coverage"]["refreshedComponents"] == 6,
                "资讯全成功健康错误")

        module.utc_now = lambda: datetime(2026, 8, 8, 13, 0, tzinfo=timezone.utc)
        module.fetch_feed = feed_sequence(module, fail_first=True)
        module.fetch_quote = lambda _symbol: (101.0, 1.0)
        require(module.build() is True, "资讯部分板块成功应发布")
        partial_data = load_json(data_path)
        partial_health = load_json(health_path)
        validate_health("whats-latest", partial_data, partial_health)
        require(partial_health["status"] == "degraded"
                and partial_health["attempt"]["fallbackComponents"] == ["markets-news"]
                and "markets" in [category["key"] for category in partial_data["categories"]],
                "市场新闻失败时未保留同板块旧内容或未降级")

        before = data_path.read_bytes()
        module.utc_now = lambda: datetime(2026, 8, 8, 14, 0, tzinfo=timezone.utc)
        module.fetch_feed = feed_sequence(module, fail_all=True)
        module.fetch_quote = fail("quotes should not run")
        require(module.build() is False, "资讯全部板块失败不应发布")
        require(data_path.read_bytes() == before, "资讯整批失败重写了旧data.json")
        failed_health = load_json(health_path)
        validate_health("whats-latest", load_json(data_path), failed_health)
        require(failed_health["status"] == "failed"
                and failed_health["consecutiveFailures"] == 1
                and failed_health["snapshotPreserved"] is True,
                "资讯整批失败健康错误")


def main() -> None:
    test_fear_greed()
    print("fear-greed builder: PASS · success/failure retention")
    test_ofr_monitor()
    print("ofr-monitor builder: PASS · success/partial/failure retention")
    test_econ_calendar()
    print("econ-calendar builder: PASS · success/failure retention")
    test_whats_latest()
    print("whats-latest builder: PASS · success/partial/failure retention")
    print("Supporting source builders validation: PASS")


if __name__ == "__main__":
    main()
