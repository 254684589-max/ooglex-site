#!/usr/bin/env python3
"""Offline contract tests for the bounded proxy runtime history."""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime, timedelta, timezone

from finance_terminal_proxy_runtime_history import (
    ContractError,
    build_history,
    cycle_date,
    render_markdown,
    SafeArtifactRedirect,
    summarize_evidence,
    validate_history,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_error(callback, message: str) -> None:
    try:
        callback()
    except ContractError:
        return
    raise AssertionError(message)


def evidence(generated_at: str, mounted: int, loaded: int, failed: int, category: str | None) -> dict:
    failure_categories = {key: 0 for key in ("dns", "tls", "connection", "timeout", "blocked", "other")}
    if category:
        failure_categories[category] = failed
    diagnosis_counts = {
        "healthy": 3 if mounted == 12 and loaded == 3 else 0,
        "degraded": 3 if 0 < mounted < 12 and loaded == 3 else 0,
        "unavailable": 3 if mounted == 0 else 0,
        "unknown": 0,
    }
    if sum(diagnosis_counts.values()) != 3:
        diagnosis_counts["degraded"] = 3 - sum(diagnosis_counts.values())
    fallback = 12 - mounted
    return {
        "schemaVersion": 5,
        "generatedAt": generated_at,
        "scope": "finance-terminal-free-proxy-runtime",
        "source": "Chrome DevTools Protocol / static branch checkout",
        "viewports": [{}, {}, {}],
        "summary": {
            "viewportCount": 3,
            "proxyCountPerViewport": 4,
            "observationCount": 12,
            "mountedObservations": mounted,
            "fallbackObservations": fallback,
            "verifiedFallbackObservations": fallback,
            "hiddenFallbackObservations": mounted,
            "providerScriptLoadedViewports": loaded,
            "providerScriptFailedViewports": failed,
            "providerScriptPendingViewports": 3 - loaded - failed,
            "providerScriptNotObservedViewports": 0,
            "providerScriptFailureCategories": failure_categories,
            "diagnosisCounts": diagnosis_counts,
            "allViewportsPassed": True,
        },
        "doesNotAssert": ["quote-rendered", "quote-freshness", "market-open"],
        "doesNotReadOrStoreQuotes": True,
    }


require(cycle_date("2026-08-13T20:59:59Z") == "2026-08-12", "21:00前应属于上一周期")
require(cycle_date("2026-08-13T21:00:00Z") == "2026-08-13", "21:00起应属于本周期")

redirect = SafeArtifactRedirect().redirect_request(
    urllib.request.Request("https://api.github.com/repos/example/repo/actions/artifacts/1/zip", headers={
        "Authorization": "Bearer must-not-leak",
        "User-Agent": "history-test",
    }),
    None,
    302,
    "Found",
    {},
    "https://signed.example.test/artifact.zip",
)
require(redirect.get_header("Authorization") is None, "跨主机Artifact重定向不得携带令牌")

records = []
start = datetime(2026, 8, 5, 21, 30, tzinfo=timezone.utc)
for index in range(9):
    timestamp = (start + timedelta(days=index)).isoformat().replace("+00:00", "Z")
    records.append(evidence(timestamp, 12 if index % 3 == 0 else 0, 3 if index % 3 == 0 else 0,
                            0 if index % 3 == 0 else 3, None if index % 3 == 0 else "connection"))

# Same-cycle rerun must replace, not add, the earlier observation.
records.append(evidence("2026-08-13T22:30:00Z", 6, 3, 0, None))
collection = {
    "status": "complete",
    "reason": None,
    "remoteArtifactsSeen": 7,
    "remoteArtifactsAccepted": 6,
    "remoteArtifactsSkipped": 1,
}
history = build_history(records, "agent/finance-terminal-supporting-qualification",
                        "2026-08-13T23:00:00Z", collection)
require(history["summary"]["observedCycles"] == 7, "历史必须限制为7个周期")
require(history["cycles"][0]["cycleDate"] == "2026-08-13", "最新周期顺序错误")
require(history["cycles"][0]["summary"]["mountedObservations"] == 6, "同周期未保留最新证据")
require(history["summary"]["mixedHostCycles"] == 1, "混合宿主周期复算错误")
require(validate_history(history) is history, "历史契约验证应返回原对象")
markdown = render_markdown(history)
require("21:00 UTC daily cycle" in markdown and "does not read quotes" in markdown,
        "Markdown边界说明缺失")

partial = build_history([records[-1]], "agent/finance-terminal-supporting-qualification",
                        "2026-08-13T23:00:00Z", {
                            "status": "partial",
                            "reason": "api-unavailable",
                            "remoteArtifactsSeen": 0,
                            "remoteArtifactsAccepted": 0,
                            "remoteArtifactsSkipped": 0,
                        })
require(partial["summary"]["observedCycles"] == 1, "API失败时必须保留当前真实证据")

old_schema = evidence("2026-08-13T22:00:00Z", 0, 0, 3, "dns")
old_schema["schemaVersion"] = 4
expect_error(lambda: summarize_evidence(old_schema), "旧格式证据必须跳过")

forged_summary = copy.deepcopy(history)
forged_summary["summary"]["fullyMountedCycles"] = 7
expect_error(lambda: validate_history(forged_summary), "不可复算趋势汇总必须拒绝")

quote_leak = copy.deepcopy(history)
quote_leak["cycles"][0]["summary"]["price"] = 123.45
expect_error(lambda: validate_history(quote_leak), "趋势不得加入行情字段")

invalid_counts = copy.deepcopy(history)
invalid_counts["cycles"][0]["summary"]["mountedObservations"] = 13
expect_error(lambda: validate_history(invalid_counts), "趋势周期计数必须有界")

raw_error = evidence("2026-08-13T22:00:00Z", 0, 0, 3, "other")
raw_error["summary"]["providerScriptErrorText"] = "net::ERR_FAILED"
expect_error(lambda: summarize_evidence(raw_error), "趋势输入不得接受原始浏览器错误")

with tempfile.TemporaryDirectory(prefix="finance-proxy-history-") as temporary_directory:
    temporary = Path(temporary_directory)
    current_path = temporary / "current.json"
    json_path = temporary / "history.json"
    markdown_path = temporary / "history.md"
    current_path.write_text(json.dumps(records[-1]), encoding="utf-8")
    environment = dict(os.environ)
    environment.pop("GITHUB_TOKEN", None)
    result = subprocess.run([
        sys.executable,
        str(Path(__file__).with_name("finance_terminal_proxy_runtime_history.py")),
        "--repository", "example/ooglex",
        "--branch", "agent/finance-terminal-supporting-qualification",
        "--current-evidence", str(current_path),
        "--output-json", str(json_path),
        "--output-markdown", str(markdown_path),
    ], check=False, capture_output=True, text=True, env=environment)
    require(result.returncode == 0, f"无令牌诚实降级CLI失败：{result.stdout}{result.stderr}")
    cli_history = json.loads(json_path.read_text(encoding="utf-8"))
    require(cli_history["collection"] == {
        "status": "partial",
        "reason": "token-unavailable",
        "remoteArtifactsSeen": 0,
        "remoteArtifactsAccepted": 0,
        "remoteArtifactsSkipped": 0,
    } and cli_history["summary"]["observedCycles"] == 1,
            "无令牌CLI必须只保留当前证据并标记partial")
    require("partial / token-unavailable" in markdown_path.read_text(encoding="utf-8"),
            "无令牌Markdown必须公开降级原因")

print("Finance Terminal proxy runtime history contract: PASS")
print("- 21:00 UTC cycle grouping / same-cycle latest evidence / 7-cycle bound: PASS")
print("- complete and honest partial collection states: PASS")
print("- schema-v5 summary normalization / incompatible evidence rejection: PASS")
print("- no quote fields / no raw transport error / derived summary: PASS")
print("- cross-host artifact redirect strips GitHub authorization: PASS")
print("- no-token CLI writes a current-only partial artifact: PASS")
