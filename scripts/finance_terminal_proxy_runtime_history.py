#!/usr/bin/env python3
"""Build a bounded, quote-free trend from Finance Terminal browser evidence artifacts."""

from __future__ import annotations

import argparse
import io
import json
import os
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
EVIDENCE_SCHEMA_VERSION = 5
MAX_CYCLES = 7
ARTIFACT_LOOKBACK_DAYS = 14
MAX_ARTIFACTS = 7
MAX_ARCHIVE_BYTES = 5 * 1024 * 1024
MAX_EVIDENCE_BYTES = 1024 * 1024
ARTIFACT_PREFIX = "finance-terminal-proxy-runtime-"
EVIDENCE_FILENAME = "finance-terminal-browser-evidence.json"
DOES_NOT_ASSERT = ["quote-rendered", "quote-freshness", "market-open"]
FAILURE_CATEGORIES = ["dns", "tls", "connection", "timeout", "blocked", "other"]
DIAGNOSIS_STATES = ["healthy", "degraded", "unavailable", "unknown"]
COLLECTION_REASONS = {None, "token-unavailable", "api-unavailable"}
WARNING_THRESHOLD_CYCLES = 2
ASSESSMENT_STATES = {"healthy", "watch", "warn", "unknown"}
ASSESSMENT_REASONS = {
    "collection-partial",
    "no-compatible-cycles",
    "insufficient-history",
    "consecutive-full-fallback",
    "consecutive-provider-script-failure",
    "recovered-after-warning",
    "two-cycle-all-hosts-mounted",
    "latest-cycle-partial-hosts",
    "latest-cycle-not-fully-mounted",
}


class ContractError(ValueError):
    """Raised when evidence or history violates the bounded contract."""


class SafeArtifactRedirect(urllib.request.HTTPRedirectHandler):
    """Never forward the GitHub token from api.github.com to signed artifact storage."""

    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        redirected = super().redirect_request(request, file_pointer, code, message, headers, new_url)
        require(redirected is not None and urllib.parse.urlparse(new_url).scheme == "https",
                "代理证据Artifact重定向无效")
        if urllib.parse.urlparse(request.full_url).netloc != urllib.parse.urlparse(new_url).netloc:
            for header_map in (redirected.headers, redirected.unredirected_hdrs):
                for key in list(header_map):
                    if key.lower() == "authorization":
                        del header_map[key]
        return redirected


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def exact_keys(record: Any, expected: set[str]) -> bool:
    return isinstance(record, dict) and set(record) == expected


def parse_timestamp(value: Any) -> datetime:
    require(isinstance(value, str) and value.endswith(("Z", "+00:00")), "时间必须是UTC ISO 8601")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ContractError("时间必须是UTC ISO 8601") from exc
    require(parsed.tzinfo is not None, "时间必须包含时区")
    return parsed.astimezone(timezone.utc)


def cycle_date(value: str) -> str:
    observed = parse_timestamp(value)
    boundary = datetime.combine(observed.date(), time(21, 0), tzinfo=timezone.utc)
    return (observed.date() if observed >= boundary else observed.date() - timedelta(days=1)).isoformat()


def nonnegative_integer(value: Any, maximum: int) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= maximum


def consecutive_cycles(cycles: list[dict[str, Any]], predicate) -> int:
    count = 0
    for item in cycles:
        if not predicate(item["summary"]):
            break
        count += 1
    return count


# 三档视口是固定的；每轮的代理项数随所有者的展示决定变化（2026-08-25 由4项收敛为
# DIA与GLD两项），因此「一轮的观测总数」一律读该轮自己声明的 observationCount，
# 历史周期沿用它当时的数字，不被现在的项数改写。
EXPECTED_VIEWPORTS = 3
EXPECTED_PROXY_COUNT = 2


def cycle_total(summary: dict[str, Any]) -> int:
    """该周期的宿主观测总数：视口数 × 当轮代理项数。"""
    return summary["observationCount"]


def assess_runtime(cycles: list[dict[str, Any]], collection: dict[str, Any]) -> dict[str, Any]:
    full_fallback = consecutive_cycles(
        cycles, lambda summary: summary["fallbackObservations"] == cycle_total(summary))
    script_failure = consecutive_cycles(
        cycles, lambda summary: summary["providerScriptFailedViewports"] > 0
    )
    all_hosts_mounted = consecutive_cycles(
        cycles, lambda summary: summary["mountedObservations"] == cycle_total(summary)
    )
    all_scripts_loaded = consecutive_cycles(
        cycles, lambda summary: summary["providerScriptLoadedViewports"] == EXPECTED_VIEWPORTS
    )
    latest_cycle_date = cycles[0]["cycleDate"] if cycles else None
    assessment = {
        "state": "unknown",
        "reason": "no-compatible-cycles",
        "warningThresholdCycles": WARNING_THRESHOLD_CYCLES,
        "consecutiveFullFallbackCycles": full_fallback,
        "consecutiveProviderScriptFailureCycles": script_failure,
        "consecutiveAllHostsMountedCycles": all_hosts_mounted,
        "consecutiveAllProviderScriptsLoadedCycles": all_scripts_loaded,
        "latestCycleDate": latest_cycle_date,
    }
    if collection["status"] != "complete":
        assessment.update(state="unknown", reason="collection-partial")
        return assessment
    if not cycles:
        return assessment
    if full_fallback >= WARNING_THRESHOLD_CYCLES:
        assessment.update(state="warn", reason="consecutive-full-fallback")
        return assessment
    if script_failure >= WARNING_THRESHOLD_CYCLES:
        assessment.update(state="warn", reason="consecutive-provider-script-failure")
        return assessment
    if len(cycles) < WARNING_THRESHOLD_CYCLES:
        assessment.update(state="watch", reason="insufficient-history")
        return assessment
    latest = cycles[0]["summary"]
    previous = cycles[1]["summary"]
    latest_healthy = latest["mountedObservations"] == cycle_total(latest) \
        and latest["providerScriptLoadedViewports"] == EXPECTED_VIEWPORTS
    previous_warning = previous["fallbackObservations"] == cycle_total(previous) \
        or previous["providerScriptFailedViewports"] > 0
    if latest_healthy and previous_warning:
        assessment.update(state="watch", reason="recovered-after-warning")
    elif all_hosts_mounted >= WARNING_THRESHOLD_CYCLES \
            and all_scripts_loaded >= WARNING_THRESHOLD_CYCLES:
        assessment.update(state="healthy", reason="two-cycle-all-hosts-mounted")
    elif 0 < latest["mountedObservations"] < cycle_total(latest):
        assessment.update(state="watch", reason="latest-cycle-partial-hosts")
    else:
        assessment.update(state="watch", reason="latest-cycle-not-fully-mounted")
    return assessment


def summarize_evidence(evidence: Any) -> dict[str, Any]:
    require(exact_keys(evidence, {
        "schemaVersion", "generatedAt", "scope", "source", "viewports", "summary",
        "doesNotAssert", "doesNotReadOrStoreQuotes",
    }), "浏览器证据顶层字段无效")
    require(evidence["schemaVersion"] == EVIDENCE_SCHEMA_VERSION, "浏览器证据版本不兼容")
    generated_at = evidence["generatedAt"]
    parse_timestamp(generated_at)
    require(evidence["scope"] == "finance-terminal-free-proxy-runtime", "浏览器证据范围无效")
    require(evidence["doesNotAssert"] == DOES_NOT_ASSERT, "浏览器证据断言边界无效")
    require(evidence["doesNotReadOrStoreQuotes"] is True, "浏览器证据不得读取或保存行情")
    require(isinstance(evidence["viewports"], list) and len(evidence["viewports"]) == 3,
            "浏览器证据视口数量无效")

    summary = evidence["summary"]
    expected_summary_keys = {
        "viewportCount", "proxyCountPerViewport", "observationCount", "mountedObservations",
        "fallbackObservations", "verifiedFallbackObservations", "hiddenFallbackObservations",
        "providerScriptLoadedViewports", "providerScriptFailedViewports",
        "providerScriptPendingViewports", "providerScriptNotObservedViewports",
        "providerScriptFailureCategories", "diagnosisCounts", "allViewportsPassed",
    }
    require(exact_keys(summary, expected_summary_keys), "浏览器证据汇总字段无效")
    total = summary["observationCount"]
    require(summary["viewportCount"] == EXPECTED_VIEWPORTS
            and summary["proxyCountPerViewport"] == EXPECTED_PROXY_COUNT
            and total == EXPECTED_VIEWPORTS * EXPECTED_PROXY_COUNT
            and summary["allViewportsPassed"] is True,
            "浏览器证据固定覆盖无效")
    mounted = summary["mountedObservations"]
    fallback = summary["fallbackObservations"]
    require(nonnegative_integer(mounted, total) and nonnegative_integer(fallback, total)
            and mounted + fallback == total, "浏览器宿主观测汇总无效")
    require(summary["verifiedFallbackObservations"] == fallback
            and summary["hiddenFallbackObservations"] == mounted,
            "浏览器回退可见性汇总无效")
    script_counts = [summary[key] for key in (
        "providerScriptLoadedViewports", "providerScriptFailedViewports",
        "providerScriptPendingViewports", "providerScriptNotObservedViewports",
    )]
    require(all(nonnegative_integer(value, 3) for value in script_counts) and sum(script_counts) == 3,
            "提供方脚本汇总无效")
    failure_categories = summary["providerScriptFailureCategories"]
    require(exact_keys(failure_categories, set(FAILURE_CATEGORIES))
            and all(nonnegative_integer(failure_categories[key], 3) for key in FAILURE_CATEGORIES)
            and sum(failure_categories.values()) <= summary["providerScriptFailedViewports"],
            "提供方脚本失败分类无效")
    diagnosis_counts = summary["diagnosisCounts"]
    require(exact_keys(diagnosis_counts, set(DIAGNOSIS_STATES))
            and all(nonnegative_integer(diagnosis_counts[key], 3) for key in DIAGNOSIS_STATES)
            and sum(diagnosis_counts.values()) == 3, "关联诊断汇总无效")

    return {
        "cycleDate": cycle_date(generated_at),
        "generatedAt": generated_at,
        "summary": {
            "viewportCount": EXPECTED_VIEWPORTS,
            "observationCount": summary["observationCount"],
            "mountedObservations": mounted,
            "fallbackObservations": fallback,
            "providerScriptLoadedViewports": summary["providerScriptLoadedViewports"],
            "providerScriptFailedViewports": summary["providerScriptFailedViewports"],
            "providerScriptFailureCategories": {key: failure_categories[key] for key in FAILURE_CATEGORIES},
            "diagnosisCounts": {key: diagnosis_counts[key] for key in DIAGNOSIS_STATES},
        },
    }


def build_history(
    evidences: list[dict[str, Any]],
    target_branch: str,
    generated_at: str,
    collection: dict[str, Any],
) -> dict[str, Any]:
    require(bool(target_branch), "目标分支不能为空")
    parse_timestamp(generated_at)
    latest_by_cycle: dict[str, dict[str, Any]] = {}
    for evidence in evidences:
        cycle = summarize_evidence(evidence)
        current = latest_by_cycle.get(cycle["cycleDate"])
        if current is None or parse_timestamp(cycle["generatedAt"]) > parse_timestamp(current["generatedAt"]):
            latest_by_cycle[cycle["cycleDate"]] = cycle
    cycles = sorted(latest_by_cycle.values(), key=lambda item: item["cycleDate"], reverse=True)[:MAX_CYCLES]
    latest = cycles[0] if cycles else None
    summary = {
        "observedCycles": len(cycles),
        "fullyMountedCycles": sum(item["summary"]["mountedObservations"] == cycle_total(item["summary"])
                                  for item in cycles),
        "fallbackOnlyCycles": sum(item["summary"]["fallbackObservations"] == cycle_total(item["summary"])
                                  for item in cycles),
        "mixedHostCycles": sum(0 < item["summary"]["mountedObservations"] < cycle_total(item["summary"])
                               for item in cycles),
        "allProviderScriptsLoadedCycles": sum(
            item["summary"]["providerScriptLoadedViewports"] == 3 for item in cycles
        ),
        "anyProviderScriptFailedCycles": sum(
            item["summary"]["providerScriptFailedViewports"] > 0 for item in cycles
        ),
        "latestCycleDate": latest["cycleDate"] if latest else None,
        "latestDiagnosisCounts": latest["summary"]["diagnosisCounts"] if latest else {
            key: 0 for key in DIAGNOSIS_STATES
        },
    }
    history = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": generated_at,
        "scope": "finance-terminal-free-proxy-runtime-history",
        "source": "GitHub Actions proxy runtime evidence artifacts",
        "targetBranch": target_branch,
        "window": {
            "cycleBoundaryUtc": "21:00",
            "maximumCycles": MAX_CYCLES,
            "artifactLookbackDays": ARTIFACT_LOOKBACK_DAYS,
        },
        "collection": collection,
        "cycles": cycles,
        "summary": summary,
        "assessment": assess_runtime(cycles, collection),
        "doesNotAssert": DOES_NOT_ASSERT,
        "doesNotReadOrStoreQuotes": True,
    }
    return validate_history(history)


def validate_history(history: Any) -> dict[str, Any]:
    require(exact_keys(history, {
        "schemaVersion", "generatedAt", "scope", "source", "targetBranch", "window",
        "collection", "cycles", "summary", "assessment", "doesNotAssert",
        "doesNotReadOrStoreQuotes",
    }), "代理趋势顶层字段无效")
    require(history["schemaVersion"] == SCHEMA_VERSION, "代理趋势版本无效")
    parse_timestamp(history["generatedAt"])
    require(history["scope"] == "finance-terminal-free-proxy-runtime-history"
            and history["source"] == "GitHub Actions proxy runtime evidence artifacts",
            "代理趋势范围或来源无效")
    require(isinstance(history["targetBranch"], str) and history["targetBranch"], "代理趋势分支无效")
    require(history["window"] == {
        "cycleBoundaryUtc": "21:00", "maximumCycles": 7, "artifactLookbackDays": 14,
    }, "代理趋势窗口无效")
    collection = history["collection"]
    require(exact_keys(collection, {
        "status", "reason", "remoteArtifactsSeen", "remoteArtifactsAccepted", "remoteArtifactsSkipped",
    }), "代理趋势收集状态字段无效")
    require(collection["status"] in {"complete", "partial"}
            and collection["reason"] in COLLECTION_REASONS
            and (collection["status"] == "complete") == (collection["reason"] is None),
            "代理趋势收集状态无效")
    require(all(nonnegative_integer(collection[key], MAX_ARTIFACTS) for key in (
        "remoteArtifactsSeen", "remoteArtifactsAccepted", "remoteArtifactsSkipped",
    )) and collection["remoteArtifactsAccepted"] + collection["remoteArtifactsSkipped"]
            == collection["remoteArtifactsSeen"], "代理趋势远端计数无效")
    cycles = history["cycles"]
    require(isinstance(cycles, list) and len(cycles) <= MAX_CYCLES, "代理趋势周期数量无效")
    require([item["cycleDate"] for item in cycles] == sorted(
        [item["cycleDate"] for item in cycles], reverse=True
    ) and len({item["cycleDate"] for item in cycles}) == len(cycles), "代理趋势周期未去重或未倒序")
    for item in cycles:
        require(exact_keys(item, {"cycleDate", "generatedAt", "summary"}), "代理趋势周期字段无效")
        require(item["cycleDate"] == cycle_date(item["generatedAt"]), "代理趋势周期边界无效")
        summary = item["summary"]
        require(exact_keys(summary, {
            "viewportCount", "observationCount", "mountedObservations", "fallbackObservations",
            "providerScriptLoadedViewports", "providerScriptFailedViewports",
            "providerScriptFailureCategories", "diagnosisCounts",
        }), "代理趋势周期汇总字段无效")
        # 历史周期只记录视口数与观测总数：代理项数会随展示决定变化，
        # 旧周期沿用它当时的总数，这里只要求是视口数的正整数倍。
        require(summary["viewportCount"] == EXPECTED_VIEWPORTS
                and isinstance(summary["observationCount"], int)
                and summary["observationCount"] > 0
                and summary["observationCount"] % summary["viewportCount"] == 0,
                "代理趋势周期固定覆盖无效")
        mounted = summary["mountedObservations"]
        fallback = summary["fallbackObservations"]
        total = summary["observationCount"]
        require(nonnegative_integer(mounted, total) and nonnegative_integer(fallback, total)
                and mounted + fallback == total, "代理趋势宿主计数无效")
        loaded = summary["providerScriptLoadedViewports"]
        failed = summary["providerScriptFailedViewports"]
        require(nonnegative_integer(loaded, 3) and nonnegative_integer(failed, 3)
                and loaded + failed <= 3, "代理趋势脚本计数无效")
        failure_categories = summary["providerScriptFailureCategories"]
        require(exact_keys(failure_categories, set(FAILURE_CATEGORIES))
                and all(nonnegative_integer(failure_categories[key], 3) for key in FAILURE_CATEGORIES)
                and sum(failure_categories.values()) <= failed, "代理趋势失败分类无效")
        diagnosis_counts = summary["diagnosisCounts"]
        require(exact_keys(diagnosis_counts, set(DIAGNOSIS_STATES))
                and all(nonnegative_integer(diagnosis_counts[key], 3) for key in DIAGNOSIS_STATES)
                and sum(diagnosis_counts.values()) == 3, "代理趋势诊断计数无效")
    expected_summary = {
        "observedCycles": len(cycles),
        "fullyMountedCycles": sum(item["summary"]["mountedObservations"] == cycle_total(item["summary"])
                                  for item in cycles),
        "fallbackOnlyCycles": sum(item["summary"]["fallbackObservations"] == cycle_total(item["summary"])
                                  for item in cycles),
        "mixedHostCycles": sum(0 < item["summary"]["mountedObservations"] < cycle_total(item["summary"])
                               for item in cycles),
        "allProviderScriptsLoadedCycles": sum(
            item["summary"]["providerScriptLoadedViewports"] == 3 for item in cycles
        ),
        "anyProviderScriptFailedCycles": sum(
            item["summary"]["providerScriptFailedViewports"] > 0 for item in cycles
        ),
        "latestCycleDate": cycles[0]["cycleDate"] if cycles else None,
        "latestDiagnosisCounts": cycles[0]["summary"]["diagnosisCounts"] if cycles else {
            key: 0 for key in DIAGNOSIS_STATES
        },
    }
    require(history["summary"] == expected_summary, "代理趋势总览不可由周期复算")
    assessment = history["assessment"]
    require(exact_keys(assessment, {
        "state", "reason", "warningThresholdCycles", "consecutiveFullFallbackCycles",
        "consecutiveProviderScriptFailureCycles", "consecutiveAllHostsMountedCycles",
        "consecutiveAllProviderScriptsLoadedCycles", "latestCycleDate",
    }), "代理趋势运维评估字段无效")
    require(assessment["state"] in ASSESSMENT_STATES
            and assessment["reason"] in ASSESSMENT_REASONS
            and assessment["warningThresholdCycles"] == WARNING_THRESHOLD_CYCLES,
            "代理趋势运维评估状态无效")
    require(history["assessment"] == assess_runtime(cycles, collection),
            "代理趋势运维评估不可由周期与收集状态复算")
    require(history["doesNotAssert"] == DOES_NOT_ASSERT
            and history["doesNotReadOrStoreQuotes"] is True, "代理趋势行情边界无效")
    return history


def github_json(url: str, token: str) -> Any:
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "User-Agent": "ooglex-finance-terminal-history",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = response.read(MAX_EVIDENCE_BYTES + 1)
    if len(payload) > MAX_EVIDENCE_BYTES:
        raise ContractError("GitHub API响应超过大小限制")
    return json.loads(payload)


def artifact_evidence(url: str, token: str) -> dict[str, Any]:
    parsed_url = urllib.parse.urlparse(url)
    require(parsed_url.scheme == "https" and parsed_url.netloc == "api.github.com",
            "代理证据Artifact下载地址无效")
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "User-Agent": "ooglex-finance-terminal-history",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    opener = urllib.request.build_opener(SafeArtifactRedirect())
    with opener.open(request, timeout=30) as response:
        archive = response.read(MAX_ARCHIVE_BYTES + 1)
    if len(archive) > MAX_ARCHIVE_BYTES:
        raise ContractError("代理证据Artifact超过大小限制")
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        candidates = [name for name in bundle.namelist() if Path(name).name == EVIDENCE_FILENAME]
        require(len(candidates) == 1, "代理证据Artifact文件数量无效")
        info = bundle.getinfo(candidates[0])
        require(info.file_size <= MAX_EVIDENCE_BYTES, "代理证据JSON超过大小限制")
        return json.loads(bundle.read(info))


def collect_remote_evidence(repository: str, branch: str, token: str | None, now: datetime) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    collection = {
        "status": "complete",
        "reason": None,
        "remoteArtifactsSeen": 0,
        "remoteArtifactsAccepted": 0,
        "remoteArtifactsSkipped": 0,
    }
    if not token:
        collection.update(status="partial", reason="token-unavailable")
        return [], collection
    query = urllib.parse.urlencode({"per_page": 100})
    url = f"https://api.github.com/repos/{repository}/actions/artifacts?{query}"
    try:
        payload = github_json(url, token)
        cutoff = now - timedelta(days=ARTIFACT_LOOKBACK_DAYS)
        latest_artifact_by_cycle: dict[str, tuple[datetime, dict[str, Any]]] = {}
        for artifact in payload.get("artifacts", []):
            workflow_run = artifact.get("workflow_run") or {}
            created_at = parse_timestamp(artifact.get("created_at"))
            if (artifact.get("expired") is False
                    and artifact.get("name", "").startswith(ARTIFACT_PREFIX)
                    and workflow_run.get("head_branch") == branch
                    and created_at >= cutoff):
                artifact_cycle = cycle_date(artifact["created_at"])
                existing = latest_artifact_by_cycle.get(artifact_cycle)
                if existing is None or created_at > existing[0]:
                    latest_artifact_by_cycle[artifact_cycle] = (created_at, artifact)
        candidates = sorted(latest_artifact_by_cycle.values(), key=lambda item: item[0], reverse=True)
        candidates = candidates[:MAX_ARTIFACTS]
        collection["remoteArtifactsSeen"] = len(candidates)
        accepted = []
        for _, artifact in candidates:
            try:
                evidence = artifact_evidence(artifact["archive_download_url"], token)
                summarize_evidence(evidence)
                accepted.append(evidence)
                collection["remoteArtifactsAccepted"] += 1
            except (KeyError, OSError, ValueError, json.JSONDecodeError, zipfile.BadZipFile, ContractError):
                collection["remoteArtifactsSkipped"] += 1
        return accepted, collection
    except (OSError, urllib.error.HTTPError, urllib.error.URLError, ValueError, json.JSONDecodeError, ContractError):
        collection.update(status="partial", reason="api-unavailable")
        return [], collection


def render_markdown(history: dict[str, Any]) -> str:
    validate_history(history)
    collection = history["collection"]
    lines = [
        "# Finance Terminal free-proxy runtime history",
        "",
        f"Generated: {history['generatedAt']}",
        f"Branch: `{history['targetBranch']}`",
        f"Collection: {collection['status']}"
        + (f" / {collection['reason']}" if collection["reason"] else ""),
        f"Assessment: **{history['assessment']['state'].upper()}** / {history['assessment']['reason']}",
        "",
        "This bounded report groups the latest schema-v5 host evidence by the 21:00 UTC daily cycle. It does not read quotes or assert quote rendering, freshness, or market-open state.",
        "",
        "| Cycle | Script loaded | Script failed | Mounted hosts | Fallback hosts | Diagnosis |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for item in history["cycles"]:
        summary = item["summary"]
        diagnosis = ", ".join(
            f"{key}={summary['diagnosisCounts'][key]}" for key in DIAGNOSIS_STATES
        )
        lines.append(
            f"| {item['cycleDate']} | {summary['providerScriptLoadedViewports']}/3 | "
            f"{summary['providerScriptFailedViewports']}/3 | "
            f"{summary['mountedObservations']}/{cycle_total(summary)} | "
            f"{summary['fallbackObservations']}/{cycle_total(summary)} | {diagnosis} |"
        )
    if not history["cycles"]:
        lines.append("| No compatible evidence | - | - | - | - | - |")
    lines.append("")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="GitHub owner/repository")
    parser.add_argument("--branch", required=True, help="Exact development branch")
    parser.add_argument("--current-evidence", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    parser.add_argument("--output-markdown", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    current = json.loads(args.current_evidence.read_text(encoding="utf-8"))
    summarize_evidence(current)
    remote, collection = collect_remote_evidence(
        args.repository, args.branch, os.environ.get("GITHUB_TOKEN"), parse_timestamp(generated_at)
    )
    history = build_history([*remote, current], args.branch, generated_at, collection)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_markdown.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(history, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.output_markdown.write_text(render_markdown(history), encoding="utf-8")
    print(
        "Finance Terminal proxy runtime history: "
        f"{history['summary']['observedCycles']}/{MAX_CYCLES} cycles · "
        f"collection {collection['status']}"
        + (f"/{collection['reason']}" if collection["reason"] else "")
        + f" · assessment {history['assessment']['state']}/{history['assessment']['reason']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
