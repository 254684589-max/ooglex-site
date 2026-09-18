#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验想法流（public.thoughts）的权限模型：RLS 策略与触发器的实际行为。

## 这个校验器存在的理由

`apps/ideas/` 是站内第一处用户生成内容。它跟站里其他板块有一个根本区别：
**别人能往你的数据库里写东西。**

写入路径上的每一条规则——谁是作者、能发多长、多久能发一条、初始是否公开、
谁能隐藏、谁能删——都只能由数据库保证。浏览器里的 JS 是给人看的提示，不是防线：
`apps/ideas/app.js` 整个被替换掉，攻击者拿到的权限也不该多一分。

而 RLS 策略最难受的一点是**写错了不会报错**，只会静默放行或静默拦截。
`status = 'visible' or author_id = auth.uid()` 这种策略，在「帖子是公开的」时候
永远走第一个分支，第二个分支写错了也测不出来——只有等到第一条帖子被隐藏，
才会暴露。所以这些行为必须逐条真跑一遍，而不是读一遍 SQL 觉得对。

开发本文件时，这套用例真实挡下了三个问题：

1. insert 策略原本写成 `author_id = auth.uid() or auth.uid() is not null`，
   后半句让前半句形同虚设。
2. 测试桩里的 `auth.uid()` 比 Supabase 线上实现严格（先转 jsonb 再挡空串），
   导致未登录读取隐藏帖时抛 json 语法错误。这暴露出公开读策略实际上依赖
   `or` 的短路求值——公开帖走第一个分支就不会去算 `auth.uid()`。
3. **限流本来能被删帖绕过。** 限流最初数的是 `public.thoughts` 的当前行数，
   而作者有权删自己的帖，于是「发满 → 删掉 → 再发」可以把每小时 20 条、
   每天 100 条的上限无限循环绕开。改成数只增不删的 `public.thought_post_log`
   才拦住。「限流不能靠删帖重置」那一段就是这条的回归测试。

## 怎么跑

    python3 scripts/validate_thoughts_rls.py

本机需要 PostgreSQL 服务端（initdb/pg_ctl）。脚本自己起一个临时实例、打桩
`auth` schema、按顺序应用 `account/schema.sql` 与 `account/migrations/*.sql`，
跑完用例后销毁实例。不连任何线上数据库，不需要任何凭据，纯离线。

找不到 PostgreSQL 服务端时退出码 2（视为跳过，不是失败），与
`scripts/macro-radar/verify-cn.mjs` 找不到 Chrome 时的约定一致。
"""
from __future__ import annotations

import glob
import os
import pwd
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ALICE = "11111111-1111-1111-1111-111111111111"
BOB = "22222222-2222-2222-2222-222222222222"
OWNER = "33333333-3333-3333-3333-333333333333"
SUSPENDED = "44444444-4444-4444-4444-444444444444"

# Supabase 环境打桩。只补 schema.sql 与迁移真正依赖的东西。
# auth.uid() 照抄 Supabase 线上实现：先用 nullif 挡掉空串再转 jsonb，
# 否则未登录（claims 为空串）时会抛 json 语法错误，那是桩的缺陷而不是策略的。
STUB_SQL = """
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create or replace function auth.uid() returns uuid
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid
$$;

grant usage on schema public to anon, authenticated, service_role;
"""

SEED_SQL = """
insert into auth.users (id, email, raw_user_meta_data) values
  ('%s','alice@example.com','{"display_name":"Alice"}'),
  ('%s','bob@example.com','{"display_name":"Bob"}'),
  ('%s','owner@example.com','{"display_name":"站主"}'),
  ('%s','suspended@example.com','{"display_name":"Suspended"}');
update public.profiles set role='owner' where id='%s';
update public.profiles set status='suspended' where id='%s';
""" % (ALICE, BOB, OWNER, SUSPENDED, OWNER, SUSPENDED)


def find_pg_bin() -> str | None:
    """返回 PostgreSQL 服务端 bin 目录；找不到返回 None。"""
    for cand in sorted(glob.glob("/usr/lib/postgresql/*/bin"), reverse=True):
        if os.path.exists(os.path.join(cand, "initdb")):
            return cand
    which = shutil.which("initdb")
    return os.path.dirname(which) if which else None


class Cluster:
    """一个用完就销毁的本地 PostgreSQL 实例。

    Postgres 拒绝以 root 身份运行，所以 root 环境下整套操作都 su 到一个非 root
    账户。socket 目录必须短——Unix socket 路径上限 107 字节，放在长路径下会直接失败。
    """

    def __init__(self, pg_bin: str):
        self.pg_bin = pg_bin
        self.as_user = None if os.geteuid() != 0 else self._pick_user()
        base = "/var/lib/postgresql" if self.as_user else tempfile.gettempdir()
        self.data = os.path.join(base, "ooglex-rls-test", "data")
        self.sock = os.path.join(tempfile.gettempdir(), "ooglex-rls-sock")
        self.started = False

    @staticmethod
    def _pick_user() -> str:
        for name in ("postgres", "nobody"):
            try:
                pwd.getpwnam(name)
                return name
            except KeyError:
                continue
        raise SystemExit("以 root 运行但找不到可降权的账户（postgres/nobody）")

    def _sh(self, cmd: str, check: bool = True) -> subprocess.CompletedProcess:
        full = ["su", self.as_user, "-c", cmd] if self.as_user else ["bash", "-c", cmd]
        p = subprocess.run(full, capture_output=True, text=True)
        if check and p.returncode != 0:
            raise SystemExit("命令失败：%s\n%s" % (cmd, (p.stderr or p.stdout)[:600]))
        return p

    def start(self) -> None:
        for d in (os.path.dirname(self.data), self.sock):
            shutil.rmtree(d, ignore_errors=True)
            os.makedirs(d, exist_ok=True)
            if self.as_user:
                shutil.chown(d, user=self.as_user, group=self.as_user)
        self._sh("%s/initdb -D %s -A trust --locale=C --encoding=UTF8"
                 % (self.pg_bin, self.data))
        self._sh("%s/pg_ctl -D %s -o \"-k %s -c listen_addresses=''\" "
                 "-l %s/../log start -w -t 60" % (self.pg_bin, self.data, self.sock, self.data))
        self.started = True

    def stop(self) -> None:
        if self.started:
            self._sh("%s/pg_ctl -D %s stop -m immediate" % (self.pg_bin, self.data), check=False)
            self.started = False
        shutil.rmtree(os.path.dirname(self.data), ignore_errors=True)
        shutil.rmtree(self.sock, ignore_errors=True)

    def psql(self, sql: str, role: str | None = None, uid: str | None = None):
        """以指定角色和用户身份执行 SQL，返回 (returncode, stdout, stderr)。"""
        pre = ""
        if uid:
            pre += "set request.jwt.claims = '{\"sub\":\"%s\"}';\n" % uid
        else:
            pre += "select set_config('request.jwt.claims','',false);\n"
        if role:
            pre += "set role %s;\n" % role
        quoted = "'" + (pre + sql).replace("'", "'\\''") + "'"
        p = self._sh("psql -h %s -d postgres -v ON_ERROR_STOP=1 -tAq -c %s"
                     % (self.sock, quoted), check=False)
        return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()

    def apply_file(self, path: str) -> None:
        dest = os.path.join(self.sock, os.path.basename(path))
        shutil.copyfile(path, dest)
        os.chmod(dest, 0o644)
        self._sh("psql -h %s -d postgres -v ON_ERROR_STOP=1 -q -f %s" % (self.sock, dest))

    def apply_sql(self, sql: str) -> None:
        quoted = "'" + sql.replace("'", "'\\''") + "'"
        self._sh("psql -h %s -d postgres -v ON_ERROR_STOP=1 -q -c %s" % (self.sock, quoted))


class Suite:
    def __init__(self, pg: Cluster):
        self.pg = pg
        self.failures: list[str] = []
        self.total = 0

    def section(self, title: str) -> None:
        print("\n=== %s ===" % title)

    def case(self, name, sql, role, uid, expect, contains=None):
        self.total += 1
        rc, out, err = self.pg.psql(sql, role, uid)
        ok = (rc == 0) if expect == "ok" else (rc != 0)
        detail = ""
        if ok and contains is not None:
            hay = out if expect == "ok" else err
            if contains not in hay:
                ok = False
                detail = "期望包含 %r，实际 %r" % (contains, hay[:160])
        if not ok and not detail:
            detail = (err or out)[:160].replace("\n", " ")
        if not ok:
            self.failures.append(name)
        print(("  PASS  " if ok else "  FAIL  ") + name + (("\n         " + detail) if detail else ""))

    def reset(self) -> None:
        self.pg.apply_sql(
            "alter table public.thoughts disable trigger all;"
            "truncate public.thought_reports, public.thoughts, public.thought_post_log;"
            "alter table public.thoughts enable trigger all;")

    def seed(self, author: str, body: str, status: str = "visible") -> str:
        """绕过触发器直接造数据，用于测读取与删改（触发器会强制作者与时间）。"""
        self.pg.apply_sql(
            "alter table public.thoughts disable trigger all;"
            "insert into public.thoughts(author_id,author_name,body,status) "
            "values ('%s','测试用户','%s','%s');"
            "alter table public.thoughts enable trigger all;" % (author, body, status))
        _, out, _ = self.pg.psql("select id from public.thoughts where body='%s';" % body)
        return out.strip().splitlines()[-1].strip()


def main() -> int:
    pg_bin = find_pg_bin()
    if not pg_bin:
        print("::warning::未找到 PostgreSQL 服务端（initdb），本次跳过想法流权限校验")
        return 2

    pg = Cluster(pg_bin)
    try:
        pg.start()
        pg.apply_sql(STUB_SQL)
        pg.apply_file(os.path.join(ROOT, "account", "schema.sql"))
        for path in sorted(glob.glob(os.path.join(ROOT, "account", "migrations", "*.sql"))):
            pg.apply_file(path)
        pg.apply_sql(SEED_SQL)

        s = Suite(pg)

        s.section("未登录访客不能写")
        s.reset()
        s.case("anon 不能发帖", "insert into public.thoughts(body) values ('anon 发言');",
               "anon", None, "fail", contains="permission denied")
        s.case("anon 不能举报",
               "insert into public.thought_reports(thought_id,reason) values (gen_random_uuid(),'x');",
               "anon", None, "fail", contains="permission denied")

        s.section("发帖：身份与内容约束都在数据库里")
        s.reset()
        s.case("alice 能发帖", "insert into public.thoughts(body) values ('第一条想法');",
               "authenticated", ALICE, "ok")
        s.case("author_id 被强制为发帖人", "select author_id from public.thoughts;",
               "authenticated", ALICE, "ok", contains=ALICE)
        s.case("author_name 取昵称快照", "select author_name from public.thoughts;",
               "authenticated", ALICE, "ok", contains="Alice")
        s.case("初始状态被强制为 visible", "select status from public.thoughts;",
               "authenticated", ALICE, "ok", contains="visible")
        s.case("超 500 字被拒", "insert into public.thoughts(body) values (repeat('长',501));",
               "authenticated", ALICE, "fail", contains="thoughts_body_length")
        s.case("纯空白被拒", "insert into public.thoughts(body) values ('   ');",
               "authenticated", ALICE, "fail", contains="thoughts_body_length")
        s.case("不能自己塞 author_id（列无权限）",
               "insert into public.thoughts(body,author_id) values ('冒充','%s');" % BOB,
               "authenticated", ALICE, "fail", contains="permission denied")
        s.case("不能自己塞 status（列无权限）",
               "insert into public.thoughts(body,status) values ('偷偷藏','hidden');",
               "authenticated", ALICE, "fail", contains="permission denied")
        s.case("停用账户不能发帖", "insert into public.thoughts(body) values ('我被停用');",
               "authenticated", SUSPENDED, "fail", contains="停用")
        s.case("十分钟内复读被拒", "insert into public.thoughts(body) values ('第一条想法');",
               "authenticated", ALICE, "fail", contains="一模一样")

        s.section("限流：每分钟 2 条")
        s.reset()
        s.case("第 1 条", "insert into public.thoughts(body) values ('a1');",
               "authenticated", ALICE, "ok")
        s.case("第 2 条", "insert into public.thoughts(body) values ('a2');",
               "authenticated", ALICE, "ok")
        s.case("第 3 条被拒", "insert into public.thoughts(body) values ('a3');",
               "authenticated", ALICE, "fail", contains="发得太快")
        s.case("换个人不受影响", "insert into public.thoughts(body) values ('b1');",
               "authenticated", BOB, "ok")

        # 这一段是回归测试。限流最初是数 public.thoughts 的当前行数，
        # 于是「发满 → 删掉 → 再发」能把每小时/每天的上限无限循环绕开。
        # 改成数只增不删的 thought_post_log 之后，删帖不再重置限额。
        s.section("限流不能靠删帖重置")
        s.reset()
        s.case("发满当分钟的 2 条（1）", "insert into public.thoughts(body) values ('c1');",
               "authenticated", ALICE, "ok")
        s.case("发满当分钟的 2 条（2）", "insert into public.thoughts(body) values ('c2');",
               "authenticated", ALICE, "ok")
        s.case("把两条都删掉",
               "with x as (delete from public.thoughts where author_id='%s' returning 1) "
               "select count(*) from x;" % ALICE,
               "authenticated", ALICE, "ok", contains="2")
        s.case("删完之后仍然发不出第 3 条", "insert into public.thoughts(body) values ('c3');",
               "authenticated", ALICE, "fail", contains="发得太快")
        s.case("删完之后复读也仍然被拒", "insert into public.thoughts(body) values ('c1');",
               "authenticated", ALICE, "fail")
        s.case("客户端读不到发帖流水", "select count(*) from public.thought_post_log;",
               "authenticated", ALICE, "fail", contains="permission denied")
        s.case("客户端写不进发帖流水",
               "insert into public.thought_post_log(author_id,body_hash) values ('%s','x');" % ALICE,
               "authenticated", ALICE, "fail", contains="permission denied")

        s.section("公开读与列级隔离")
        s.reset()
        s.seed(ALICE, "公开帖")
        s.seed(ALICE, "被隐藏帖", status="hidden")
        s.case("anon 只看见公开帖", "select count(*) from public.thoughts;",
               "anon", None, "ok", contains="1")
        s.case("anon 读不到 author_id 列", "select author_id from public.thoughts;",
               "anon", None, "fail", contains="permission denied")
        s.case("anon 读不到 profiles", "select count(*) from public.profiles;",
               "anon", None, "fail", contains="permission denied")
        s.case("作者能看见自己被隐藏的帖", "select count(*) from public.thoughts;",
               "authenticated", ALICE, "ok", contains="2")
        s.case("别人看不见被隐藏的帖", "select count(*) from public.thoughts;",
               "authenticated", BOB, "ok", contains="1")
        s.case("站主看得见全部", "select count(*) from public.thoughts;",
               "authenticated", OWNER, "ok", contains="2")

        s.section("隐藏：只有站主，且只能改可见性")
        s.reset()
        tid = s.seed(ALICE, "待隐藏帖")
        upd = ("with x as (update public.thoughts set status='hidden' where id='%s' returning 1) "
               "select count(*) from x;" % tid)
        s.case("bob 改不动（策略过滤为 0 行）", upd, "authenticated", BOB, "ok", contains="0")
        s.case("作者自己也改不动可见性", upd, "authenticated", ALICE, "ok", contains="0")
        s.case("站主能隐藏", upd, "authenticated", OWNER, "ok", contains="1")
        s.case("站主改正文被列权限挡住",
               "update public.thoughts set body='被改写' where id='%s';" % tid,
               "authenticated", OWNER, "fail", contains="permission denied")
        # 列权限是第一道锁。下面用表属主（绕过 RLS 与列权限）验证 before update 触发器
        # 本身也拦得住——这道锁是为了防将来后台或别的角色直接改历史内容。
        s.case("触发器拦住属主改正文",
               "update public.thoughts set body='属主改写' where id='%s';" % tid,
               None, OWNER, "fail", contains="只能改可见性")
        s.case("触发器拦住属主改发布时间",
               "update public.thoughts set created_at=now() where id='%s';" % tid,
               None, OWNER, "fail", contains="只能改可见性")

        s.section("删除")
        s.reset()
        t1 = s.seed(ALICE, "alice 的帖")
        t2 = s.seed(BOB, "bob 的帖")
        dele = "with x as (delete from public.thoughts where id='%s' returning 1) select count(*) from x;"
        s.case("bob 删不掉 alice 的帖", dele % t1, "authenticated", BOB, "ok", contains="0")
        s.case("alice 能删自己的", dele % t1, "authenticated", ALICE, "ok", contains="1")
        s.case("站主能删任何人的", dele % t2, "authenticated", OWNER, "ok", contains="1")

        s.section("举报")
        s.reset()
        rid = s.seed(ALICE, "会被举报的帖")
        s.case("bob 能举报",
               "insert into public.thought_reports(thought_id,reason) values ('%s','测试举报');" % rid,
               "authenticated", BOB, "ok")
        s.case("同一人重复举报被拒",
               "insert into public.thought_reports(thought_id,reason) values ('%s','再报');" % rid,
               "authenticated", BOB, "fail", contains="thought_reports_once")
        s.case("举报人读不到举报表", "select count(*) from public.thought_reports;",
               "authenticated", BOB, "ok", contains="0")
        s.case("站主能读举报", "select count(*) from public.thought_reports;",
               "authenticated", OWNER, "ok", contains="1")
        s.case("站主待办函数返回该帖", "select report_count from public.reported_thoughts();",
               "authenticated", OWNER, "ok", contains="1")
        s.case("非站主调待办函数拿不到数据", "select count(*) from public.reported_thoughts();",
               "authenticated", BOB, "ok", contains="0")
        s.case("举报理由超 200 字被拒",
               "insert into public.thought_reports(thought_id,reason) values ('%s',repeat('长',201));" % rid,
               "authenticated", ALICE, "fail", contains="reason_length")

        print("\n" + "=" * 62)
        print("共 %d 个用例，通过 %d，失败 %d"
              % (s.total, s.total - len(s.failures), len(s.failures)))
        for name in s.failures:
            print("  失败：" + name)
        return 1 if s.failures else 0
    finally:
        pg.stop()


if __name__ == "__main__":
    sys.exit(main())
