#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验宏观雷达三项官方序列的健康快照，并输出可选诊断。"""

from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import sys
import types

from macro_source_health import SERIES_SPECS, make_macro_health, validate_macro_health


ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "apps" / "macro-radar" / "data.json"
HEALTH_PATH = ROOT / "apps" / "macro-radar" / "health.json"
BUILD_RADAR_PATH = ROOT / "scripts" / "macro-radar" / "build_radar.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def reference(series_id: str, provider: str, price: float, previous: float, *, status: str = "ok",
              attempted_at: str = "2026-08-05T22:00:00Z") -> dict:
    return {
        "id": series_id,
        "frequency": "daily",
        "demo": False,
        "status": status,
        "price": price,
        "previousPrice": previous,
        "changePct": (price / previous - 1) * 100,
        "asOf": "2026-08-05",
        "previousAsOf": "2026-08-04",
        "updatedAt": "2026-08-05T22:00:00Z" if status == "ok" else "2026-08-04T22:00:00Z",
        "lastAttemptAt": attempted_at,
        "source": {"name": provider, "url": SERIES_SPECS[series_id]["url"], "seriesId": series_id},
    }


def fixture(attempted_at: str = "2026-08-05T22:00:00Z") -> dict:
    return {
        "updatedAt": attempted_at,
        "macro": [{
            "zh": "实际利率与通胀预期",
            "src": "FRED",
            "rows": [{
                "id": "DGS10", "name": "10 年期美债收益率", "val": "4.25%", "chg": "+2bp",
                "tone": "up", "price": 4.25, "previousPrice": 4.23, "changeBps": 2,
                "asOf": "2026-08-05", "previousAsOf": "2026-08-04", "frequency": "daily",
                "observations": [
                    {"asOf": "2026-08-04", "value": 4.23},
                    {"asOf": "2026-08-05", "value": 4.25},
                ],
                "status": "ok", "updatedAt": attempted_at, "lastAttemptAt": attempted_at,
                "source": {"name": SERIES_SPECS["DGS10"]["provider"],
                           "url": SERIES_SPECS["DGS10"]["url"], "seriesId": "DGS10"},
            }],
        }],
        "referenceSeries": {
            "DTWEXBGS": reference("DTWEXBGS", SERIES_SPECS["DTWEXBGS"]["provider"], 121.1, 120.9,
                                    attempted_at=attempted_at),
            "RWTC": reference("RWTC", SERIES_SPECS["RWTC"]["provider"], 82.4, 81.7,
                              attempted_at=attempted_at),
        },
    }


def load_build_radar():
    spec = importlib.util.spec_from_file_location("macro_build_radar_contract", BUILD_RADAR_PATH)
    require(spec is not None and spec.loader is not None, "无法加载宏观雷达生成器")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    inserted_stub = "requests" not in sys.modules
    if inserted_stub:
        requests_stub = types.ModuleType("requests")
        requests_stub.get = lambda *_args, **_kwargs: None
        sys.modules["requests"] = requests_stub
    try:
        spec.loader.exec_module(module)
    finally:
        if inserted_stub:
            sys.modules.pop("requests", None)
    return module


def test_builder_contract() -> None:
    builder = load_build_radar()
    attempted_at = "2026-08-06T22:00:00Z"
    current = fixture("2026-08-05T22:00:00Z")
    observations = [
        ("2026-08-01", 4.20), ("2026-08-04", 4.23),
        ("2026-08-05", 4.25), ("2026-08-06", 4.28),
    ]
    success = builder.build_dgs10_reference(current, attempted_at, fetcher=lambda *_: observations)
    require(success["status"] == "ok" and success["changeBps"] == 3
            and success["updatedAt"] == attempted_at, "DGS10成功刷新语义错误")
    require(success["observations"] == [
        {"asOf": observed, "value": value} for observed, value in observations
    ], "DGS10最近观测窗口映射错误")
    fallback = builder.build_dgs10_reference(current, attempted_at, fetcher=lambda *_: [])
    require(fallback["status"] == "stale" and fallback["asOf"] == "2026-08-05"
            and fallback["updatedAt"] == "2026-08-05T22:00:00Z"
            and fallback["lastAttemptAt"] == attempted_at, "DGS10失败回退未保留成功时间")
    require(fallback["observations"] == current["macro"][0]["rows"][0]["observations"],
            "DGS10失败回退必须完整保留最近观测窗口")
    unavailable = builder.build_dgs10_reference({}, attempted_at, fetcher=lambda *_: [])
    require(unavailable["status"] == "error" and unavailable["price"] is None,
            "无历史DGS10时不得生成默认值")
    require(unavailable["observations"] == [], "无历史DGS10时观测窗口必须为空")
    invalid = builder.build_dgs10_reference(
        current, attempted_at, fetcher=lambda *_: [("2026-08-06", 4.28), ("2026-08-05", 4.25)]
    )
    require(invalid["status"] == "stale"
            and invalid["observations"] == current["macro"][0]["rows"][0]["observations"],
            "DGS10非递增观测必须回退旧窗口")
    patched = builder.upsert_dgs10_macro(current["macro"], success)
    rows = [row for category in patched for row in category.get("rows", []) if row.get("id") == "DGS10"]
    require(len(rows) == 1 and rows[0]["asOf"] == "2026-08-06", "DGS10宏观行应精确替换")
    removed = builder.upsert_dgs10_macro(current["macro"], unavailable)
    require(not any(row.get("id") == "DGS10" for category in removed for row in category.get("rows", [])),
            "无历史有效值时不得保留伪DGS10行")


def run_contract_tests() -> None:
    test_builder_contract()
    first_at = "2026-08-05T22:00:00Z"
    data = fixture(first_at)
    healthy = make_macro_health(data, attempted_at=first_at)
    require(healthy["status"] == "healthy" and healthy["attempt"]["status"] == "success",
            "三源成功应生成healthy")
    require(healthy["coverage"]["freshCoveragePct"] == 100.0, "三源成功覆盖率应为100%")
    require(not validate_macro_health(healthy, data), "健康三源契约应通过")

    second_at = "2026-08-06T22:00:00Z"
    partial_data = fixture(second_at)
    partial_data["referenceSeries"]["DTWEXBGS"] = reference(
        "DTWEXBGS", SERIES_SPECS["DTWEXBGS"]["provider"], 121.1, 120.9,
        status="stale", attempted_at=second_at,
    )
    partial_data["referenceSeries"]["RWTC"] = {
        "id": "RWTC", "status": "error", "price": None, "previousPrice": None,
        "asOf": None, "previousAsOf": None, "updatedAt": None, "lastAttemptAt": second_at,
        "source": {"name": SERIES_SPECS["RWTC"]["provider"],
                   "url": SERIES_SPECS["RWTC"]["url"], "seriesId": "RWTC"},
    }
    partial = make_macro_health(partial_data, attempted_at=second_at, previous_health=healthy)
    modes = {source["id"]: source["mode"] for source in partial["sources"]}
    require(partial["status"] == "degraded" and partial["attempt"]["status"] == "partial",
            "单源成功应生成degraded/partial")
    require(modes == {"DGS10": "market", "DTWEXBGS": "fallback", "RWTC": "unavailable"},
            "三种逐源模式错误")
    require(not validate_macro_health(partial, partial_data), "部分回退契约应通过")

    third_at = "2026-08-07T22:00:00Z"
    failed_data = deepcopy(partial_data)
    failed_data["macro"][0]["rows"][0]["status"] = "stale"
    failed_data["macro"][0]["rows"][0]["lastAttemptAt"] = third_at
    failed_data["referenceSeries"]["DTWEXBGS"]["lastAttemptAt"] = third_at
    failed_data["referenceSeries"]["RWTC"]["lastAttemptAt"] = third_at
    failed = make_macro_health(failed_data, attempted_at=third_at, previous_health=partial)
    require(failed["status"] == "failed" and failed["snapshotPreserved"] is True,
            "三源失败且有旧值时应保留快照并标记failed")
    failures = {source["id"]: source["consecutiveFailures"] for source in failed["sources"]}
    require(failures == {"DGS10": 1, "DTWEXBGS": 2, "RWTC": 2}, "逐源连续失败计数错误")
    require(not validate_macro_health(failed, failed_data), "整批失败契约应通过")

    migrated = make_macro_health(data, attempted_at=first_at, migrated=True)
    require(migrated["historyStatus"] == "migrated" and migrated["consecutiveFailures"] is None,
            "迁移快照不得伪造历史次数")
    require(all(source["mode"] == "unknown" for source in migrated["sources"]),
            "迁移逐源模式必须为unknown")
    require(not validate_macro_health(migrated, data), "迁移契约应通过")

    tampered = deepcopy(partial)
    tampered["coverage"]["freshCoveragePct"] = 100
    tampered["sources"][1]["source"]["seriesId"] = "DXY"
    require(validate_macro_health(tampered, partial_data), "篡改覆盖率或序列ID必须失败")


def load(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise SystemExit(f"缺少文件：{path.relative_to(ROOT)}") from error
    except json.JSONDecodeError as error:
        raise SystemExit(f"JSON无效：{path.relative_to(ROOT)} · {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"JSON根节点必须为对象：{path.relative_to(ROOT)}")
    return value


def write_report(path: Path, health: dict) -> None:
    report = {
        "contractVersion": 1,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dataset": health["dataset"],
        "status": health["status"],
        "lastAttemptAt": health["lastAttemptAt"],
        "lastSuccessfulAt": health["lastSuccessfulAt"],
        "consecutiveFailures": health["consecutiveFailures"],
        "coverage": health["coverage"],
        "sources": health["sources"],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    run_contract_tests()
    data = load(DATA_PATH)
    health = load(HEALTH_PATH)
    errors = validate_macro_health(health, data)
    if errors:
        raise SystemExit("macro-radar来源健康校验失败：\n- " + "\n- ".join(errors))
    coverage = health["coverage"]
    print(
        f"macro-radar: PASS · {health['status']} · fresh={coverage['freshCoveragePct']:.2f}%"
        f" · available={coverage['availableCoveragePct']:.2f}% · failures={health['consecutiveFailures']}"
    )
    if args.report:
        write_report(args.report, health)
        print(f"诊断汇总：{args.report}")


if __name__ == "__main__":
    main()
