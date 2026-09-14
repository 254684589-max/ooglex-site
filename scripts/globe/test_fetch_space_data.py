#!/usr/bin/env python3
"""fetch_space_data.py 的校验逻辑自测（无网络依赖）。

覆盖两件最容易出错、且出错代价最大的事：

1. **坏响应必须被识别。** 上游返回 HTML 错误页、空响应或残缺 TLE 时，
   绝不能当成有效数据落盘。
2. **失败必须保留上一份有效数据**（仓库规则第 13 条）。绝不允许用空文件或
   部分数据覆盖已有快照来「掩盖抓取失败」。

跑法：python3 scripts/globe/test_fetch_space_data.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fsd", HERE / "fetch_space_data.py")
assert spec and spec.loader
fsd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fsd)

GOOD_TLE = (
    "ISS (ZARYA)\n"
    "1 25544U 98067A   24001.00000000  .00016717  00000+0  10270-3 0  9002\n"
    "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537\n"
)

_passed = 0
_failed: list[str] = []


def check(label: str, cond: bool) -> None:
    global _passed
    if cond:
        _passed += 1
        print(f"  ok   {label}")
    else:
        _failed.append(label)
        print(f"  FAIL {label}")


def test_valid_tle() -> None:
    print("valid_tle：")
    check("合法 TLE 通过", fsd.valid_tle(GOOD_TLE)[0])
    check("颗数计算正确", fsd.valid_tle(GOOD_TLE)[1] == "1 颗")
    check("空响应被拒", not fsd.valid_tle("")[0])
    check("仅空白被拒", not fsd.valid_tle("   \n\n ")[0])
    check("行数非 3 倍数被拒", not fsd.valid_tle("NAME\n1 xxx\n")[0])
    check("行首标记顺序错误被拒", not fsd.valid_tle("NAME\n2 aaa\n1 bbb\n")[0])
    check("HTML 错误页被拒", not fsd.valid_tle("<html><body>503</body></html>")[0])


def test_keeps_last_good() -> None:
    print("write_if_valid（规则第 13 条：失败保留上一份）：")
    checker = lambda b: fsd.valid_tle(b.decode("utf-8", "replace"))  # noqa: E731
    with tempfile.TemporaryDirectory() as td:
        target = pathlib.Path(td) / "celestrak" / "stations"

        ok, _ = fsd.write_if_valid(target, GOOD_TLE.encode(), checker)
        check("首次有效数据写入成功", ok and target.exists())
        baseline = target.read_bytes()

        ok, detail = fsd.write_if_valid(target, b"<html>503</html>", checker)
        check("HTML 错误页被拒写", not ok)
        check("已有快照未被覆盖", target.read_bytes() == baseline)
        check("状态说明标明保留上一份", "保留上一份" in detail)

        ok, _ = fsd.write_if_valid(target, b"", checker)
        check("空响应被拒且快照仍在", (not ok) and target.read_bytes() == baseline)

        missing = pathlib.Path(td) / "celestrak" / "never-fetched"
        ok, detail = fsd.write_if_valid(missing, b"", checker)
        check("此前无数据时说明为『此前也无数据』", (not ok) and "此前也无数据" in detail)
        check("被拒写时不创建空文件", not missing.exists())


def main() -> int:
    test_valid_tle()
    test_keeps_last_good()
    print(f"\n{_passed} 通过 / {len(_failed)} 失败")
    for label in _failed:
        print(f"  失败项：{label}")
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
