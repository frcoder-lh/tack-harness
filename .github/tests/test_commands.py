"""Run real harness commands against disposable local Git repositories."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest
import xml.etree.ElementTree as ET


SOURCE = Path(__file__).resolve().parents[2]
SHELL = os.environ.get("TACK_TEST_SH") or shutil.which("sh")


class Commands(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tack-ci-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "space with spaces"
        self.root.mkdir()
        self.scripts = self.root / "harness/script"
        shutil.copytree(SOURCE / "tack/harness", self.root / "harness")
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("GIT_", "TACK_"))}
        config = self.base / "empty-gitconfig"
        config.touch()
        self.env.update(
            GIT_CONFIG_GLOBAL=config.as_posix(), GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_COUNT="3",
            GIT_CONFIG_KEY_0="user.name", GIT_CONFIG_VALUE_0="Harness CI",
            GIT_CONFIG_KEY_1="user.email", GIT_CONFIG_VALUE_1="ci@example.invalid",
            GIT_CONFIG_KEY_2="core.autocrlf", GIT_CONFIG_VALUE_2="false",
            GIT_EDITOR="true", GIT_TERMINAL_PROMPT="0",
            LC_ALL="C", PYTHONDONTWRITEBYTECODE="1",
        )
        self.write(self.root / "AGENTS.md", "# Test space\n")
        self.write(self.root / ".gitignore", ".tack/\nrepo/\nspace/*/repo/\n")
        self.git(self.root, "init", "-b", "main")
        self.sh("project.sh", "ensure", self.root, "--no-commit")
        self.sh("project.sh", "project-add", self.root, "demo", "Test", "--no-commit")
        self.commit(self.root, "AGENTS.md", ".gitignore", "tack.yaml", "harness", "wiki")

    def call(self, *args, code=0):
        command = [a.as_posix() if isinstance(a, Path) else str(a) for a in args]
        result = subprocess.run(command, cwd=self.base, env=self.env,
                                capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=90)
        self.assertEqual(result.returncode, code,
                         f"{command!r}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        return result.stdout

    def sh(self, script, *args, code=0):
        return self.call(SHELL, self.scripts / script, *args, code=code)

    def git(self, repo, *args, code=0):
        return self.call("git", "-C", repo, *args, code=code)

    @staticmethod
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")

    def commit(self, repo, *paths):
        self.git(repo, "add", "--", *paths)
        self.git(repo, "commit", "-m", "Regression fixture")

    def create(self, branch, workflow="development"):
        output = self.sh("command-batch.sh", "work-create", self.root, "demo",
                         branch, "Test workspace", "", "", workflow)
        return re.search(r"^WORKSPACE=(.+)$", output, re.M)[1]

    def status(self, workspace):
        return self.root / "space" / workspace / "status.yaml"

    def repository(self):
        origin = self.base / "origin.git"
        self.call("git", "init", "--bare", origin)
        repo = self.root / "repo/demo"
        repo.parent.mkdir(exist_ok=True)
        self.call("git", "clone", origin, repo)
        self.git(repo, "checkout", "-b", "main")
        self.write(repo / "file.txt", "base\n")
        self.commit(repo, "file.txt")
        self.sh("git-push-helper.sh", "push", repo)
        self.sh("git-fetch-helper.sh", "sync", repo)
        return repo

    def test_repository_boundary_and_directory_link(self):
        """F01: reject parent discovery while accepting physical roots and links."""
        child = self.root / "plain"
        child.mkdir()
        self.write(self.root / "sentinel.txt", "preserve staged content\n")
        self.git(self.root, "add", "sentinel.txt")
        head = self.git(self.root, "rev-parse", "HEAD")
        for script, action in [
            ("git-commit-helper.sh", "inspect"), ("git-commit-helper.sh", "commit"),
            ("git-fetch-helper.sh", "fetch"), ("git-fetch-helper.sh", "sync"),
            ("git-push-helper.sh", "inspect"), ("git-push-helper.sh", "push"),
            ("git-facts.sh", "status"),
        ]:
            with self.subTest(script=script, action=action):
                args = ["must stay uncommitted"] if action == "commit" else []
                self.sh(script, action, child, *args, code=1)
        self.sh("git-diff-context.sh", child, self.base / "diff", code=1)
        self.assertEqual(head, self.git(self.root, "rev-parse", "HEAD"))
        self.assertEqual("sentinel.txt", self.git(self.root, "diff", "--cached", "--name-only").strip())
        link = self.base / "linked root"
        if os.name == "nt":
            self.call("cmd.exe", "/c", "mklink", "/J", str(link), str(self.root))
            self.addCleanup(lambda: os.rmdir(link) if link.exists() else None)
        else:
            link.symlink_to(self.root, target_is_directory=True)
        self.assertIn("branch: main", self.sh("git-facts.sh", "status", link))
        plain_repo = self.root / "repo/plain"
        plain_repo.mkdir(parents=True)
        self.sh("branch-op.sh", "prepare", self.root, "space/new", "plain",
                "merge", "main", "other", code=1)

    def test_dirty_worktree_and_local_remote(self):
        """F02: tracked and untracked changes survive a rejected removal."""
        repo = self.repository()
        self.sh("git-worktree-helper.sh", "create", self.root, "wt", "feature", "demo")
        wt = self.root / "space/wt/repo/demo"
        self.assertIn("branch: feature", self.sh("git-facts.sh", "status", wt))
        self.write(wt / "file.txt", "changed\n")
        self.write(wt / "untracked.txt", "keep\n")
        self.sh("git-worktree-helper.sh", "remove", self.root, "wt", "demo", code=1)
        self.assertEqual("changed\n", (wt / "file.txt").read_text())
        self.assertEqual("keep\n", (wt / "untracked.txt").read_text())
        self.git(wt, "add", "file.txt", "untracked.txt")
        self.assertIn("COMMIT_RESULT=ok", self.sh("git-commit-helper.sh", "commit", wt, "Save changes"))
        self.sh("git-worktree-helper.sh", "remove", self.root, "wt", "demo")
        self.assertFalse(wt.exists())
        self.assertNotIn("space/wt", self.git(repo, "worktree", "list", "--porcelain"))

    def test_all_command_routes(self):
        """F03: every declared command spelling, with and without arguments."""
        commands = 0
        cases = 0
        for file in sorted((self.root / "harness/cmd").glob("*/*.md")):
            fields = dict(re.findall(r"^(command|short|triggers): (.*)$",
                                     file.read_text(encoding="utf-8"), re.M))
            if "command" not in fields:
                continue
            commands += 1
            keys = [fields["command"], fields.get("short", "")]
            keys += fields.get("triggers", "").split(",")
            for key in dict.fromkeys(k.strip() for k in keys if k.strip()):
                for suffix in ("", " sample-argument"):
                    with self.subTest(command=fields["command"], input=key + suffix):
                        route = self.sh("scan-routes.sh", "resolve", self.root / "harness",
                                        key + suffix).strip().split("|")
                        self.assertEqual(fields["command"], route[3])
                        self.assertEqual(suffix.strip(), route[-1])
                    cases += 1
        self.assertGreaterEqual(commands, 28)
        self.assertGreaterEqual(cases, 438)
        print(f"\nValidated {commands} commands / {cases} route inputs", flush=True)

    def test_route_prefix_and_chinese_fallback(self):
        """/tack prefix, polite prefixes and glued Chinese arguments resolve deterministically."""
        harness = self.root / "harness"
        for text, name, args in [
            ("/tack code", "code", ""), ("/TACK commit fix login", "commit", "fix login"),
            ("提交代码", "commit", "代码"), ("推送代码", "push", "代码"),
            ("帮我改bug", "bugfix", ""), ("/tack 提交代码", "commit", "代码"),
            ("请提交", "commit", ""), ("提交 修复登录", "commit", "修复登录"),
        ]:
            with self.subTest(input=text):
                route = self.sh("scan-routes.sh", "resolve", harness, text).strip().split("|")
                self.assertEqual((name, args), (route[3], route[-1]))
        for text in ("/tack", "运行时报错是什么原因", "hello world"):
            with self.subTest(input=text):
                self.sh("scan-routes.sh", "resolve", harness, text, code=1)
        index = self.sh("scan-routes.sh", "index", harness)
        self.assertNotIn("——", index)

    def test_stale_space_lock_is_reclaimed(self):
        """A lock left by a dead process is reclaimed; a live holder still blocks."""
        lock = self.root / ".tack/lock"
        lock.mkdir(parents=True)
        # pid 由 sh 自己写入 $$，与生产口径一致（Git for Windows 下 MSYS pid 不同于 Windows pid）
        self.call(SHELL, "-c", f'echo $$ > "{(lock / "pid").as_posix()}"')
        self.sh("project.sh", "project-set", self.root, "demo", "description", "Reclaimed",
                "--no-commit")
        self.assertFalse(lock.exists())
        lock.mkdir(parents=True)
        live = subprocess.Popen([SHELL, "-c", f'echo $$ > "{(lock / "pid").as_posix()}"; exec sleep 30'])
        self.addCleanup(live.wait)
        self.addCleanup(live.kill)
        for _ in range(50):
            if (lock / "pid").exists() and (lock / "pid").read_text().strip():
                break
            time.sleep(0.1)
        script = (f'. "{(self.scripts / "space-lock.sh").as_posix()}"; '
                  f'tack_space_lock_acquire "{self.root.as_posix()}" 2')
        self.call(SHELL, "-c", script, code=1)
        self.assertTrue((lock / "pid").exists())

    def test_update_check_times_out_silently(self):
        """An unresponsive update host neither hangs check-update nor reports an error."""
        import socket
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        self.addCleanup(server.close)
        self.env.update(TACK_UPDATE_URL=f"http://127.0.0.1:{server.getsockname()[1]}",
                        TACK_NET_TIMEOUT="2")
        started = time.monotonic()
        self.assertEqual("", self.sh("check-update.sh", self.root))
        self.assertLess(time.monotonic() - started, 30)
        self.assertIn("last_check=", (self.root / ".tack/state/update-state").read_text())

    def run_plan(self, rows):
        directory = self.base / "run instruction"
        self.write(directory / "do.sh", "#!/bin/sh\nprintf done >> local/result\n")
        self.write(directory / "run.md", "<!-- run-plan:start -->\n"
                   "seq\tscript\tcommand\tdeps\trequires\n" + rows +
                   "<!-- run-plan:end -->\n")
        return directory

    def test_run_normalization_manual_and_resume(self):
        """F04: normalization, dependency gates, acknowledgement and input freshness."""
        directory = self.run_plan(
            " 1 \t do.sh \t sh do.sh \t - \t - \n"
            "2\t@manual\tApprove\t 1 \t-\n3\tdo.sh\tsh do.sh\t2\t-\n")
        out = self.sh("run-plan.sh", "execute", directory, code=6)
        self.assertIn("STEP=1:ok", out)
        self.assertIn("MANUAL=2", out)
        self.assertEqual("done", (directory / "local/result").read_text())
        self.sh("run-plan.sh", "execute", directory, "--resume", "--ack", "2")
        self.sh("run-plan.sh", "execute", directory, "--resume")
        self.assertEqual("donedone", (directory / "local/result").read_text())
        self.write(directory / "do.sh", "#!/bin/sh\nexit 1\n")
        self.sh("run-plan.sh", "execute", directory, "--resume", code=5)
        bad = self.run_plan("1\tdo.sh\tsh do.sh\t9\t-\n")
        self.sh("run-plan.sh", "execute", bad, code=4)

    def test_run_failure_and_uncertain_retry(self):
        directory = self.run_plan("1\tdo.sh\texit 7\t\t\n2\tdo.sh\tsh do.sh\t1\t\n")
        self.sh("run-plan.sh", "execute", directory, code=7)
        self.assertFalse((directory / "local/result").exists())
        self.run_plan("1\tdo.sh\tsh do.sh\t\t\n")
        self.sh("run-plan.sh", "execute", directory, "--new")
        journal = directory / "local/.run-state/journal"
        self.write(journal, "1\trunning\t0\n")
        self.sh("run-plan.sh", "execute", directory, "--resume", code=5)
        self.sh("run-plan.sh", "execute", directory, "--resume", "--retry", "1")
        self.assertEqual("donedone", (directory / "local/result").read_text())

    def test_rename_children_and_rollback(self):
        """F05: real branches, worktree moves, child links and late-failure rollback."""
        self.repository()
        parent, child = self.create("parent"), self.create("child")
        child_status = self.status(child)
        self.sh("work-status.sh", child_status, "set", "parent_workspace", parent)
        self.sh("git-worktree-helper.sh", "create", self.root, parent, "parent", "demo")
        self.commit(self.root, "space", "tack.yaml")
        head = self.git(self.root, "rev-parse", "HEAD")
        out = self.sh("work.sh", "rename", self.root, "parent", "renamed", "--dry-run")
        self.assertIn("child:", out)
        self.assertEqual(head, self.git(self.root, "rev-parse", "HEAD"))
        self.assertEqual("", self.git(self.root, "status", "--porcelain"))
        self.sh("work.sh", "rename", self.root, "parent", "renamed", "--apply")
        renamed = parent[:9] + "renamed"
        wt = self.root / "space" / renamed / "repo/demo"
        self.assertEqual("renamed", self.git(wt, "branch", "--show-current").strip())
        self.assertIn(child, self.sh("work-status.sh", self.root, "related", "children", renamed))
        self.assertIn(f"space/{child}/status.yaml", self.git(self.root, "show", "--format=", "--name-only"))
        self.assertEqual("", self.git(self.root, "status", "--porcelain"))
        # An unmanaged directory makes final removal fail after all status writes.
        sentinel = wt.parent / "unmanaged/keep"
        self.write(sentinel, "preserve\n")
        paths = [self.status(renamed), child_status, self.root / "tack.yaml"]
        before = [p.read_bytes() for p in paths]
        out = self.sh("work.sh", "rename", self.root, "renamed", "failed", "--apply", code=1)
        self.assertIn("ROLLBACK=complete", out)
        self.assertEqual(before, [p.read_bytes() for p in paths])
        self.assertEqual("preserve\n", sentinel.read_text())
        self.assertEqual("renamed", self.git(wt, "branch", "--show-current").strip())
        self.assertEqual("", self.git(self.root, "status", "--porcelain"))
        self.sh("work-status.sh", child_status, "set", "parent_workspace", "missing")
        self.assertIn("DANGLING_PARENT", self.sh("project.sh", "work-reconcile", self.root))

    def test_confirmation_and_review_dependencies(self):
        """F06: files added, edited or removed invalidate accepted evidence."""
        workspace = self.create("evidence")
        work = self.status(workspace).parent
        for name in ("analysis", "spec", "plan"):
            self.write(work / f"story/s1/{name}.md", "# Test\n")
        wiki = self.root / "wiki/demo/rule/decisions.md"
        self.write(wiki, "# Rules\n")
        self.sh("command-context.sh", "confirm", self.root, workspace, "s1", "plan")
        self.sh("command-context.sh", "check", self.root, workspace, "s1", "plan")
        self.write(wiki, "# Changed rules\n")
        self.sh("command-context.sh", "check", self.root, workspace, "s1", "plan", code=3)

        def evidence():
            return self.sh("command-context.sh", "evidence", self.root, workspace, "review", "main")

        def accept():
            token = re.search(r"^EVIDENCE_TOKEN=(.*)$", evidence(), re.M)[1]
            self.sh("command-context.sh", "accept", self.root, workspace, "review", "main", token)
            self.assertIn("EVIDENCE=unchanged", evidence())

        for dep in (wiki, work / "doc/tech-design-s1.md", self.root / "wiki/demo/config/new.md"):
            for content in ("# Added\n", "# Modified\n", None):
                with self.subTest(file=dep.name, content=content):
                    accept()
                    if content is None:
                        dep.unlink()
                    else:
                        self.write(dep, content)
                    self.assertIn("EVIDENCE=changed", evidence())

    def test_task_replace_and_resume(self):
        """F07/F08: export/replace validates dependencies and preserves other stories."""
        status = self.status(self.create("tasks"))
        tsv = self.base / "tasks.tsv"
        self.write(tsv, "A\tFirst\tm\tdemo\t\tpending\nB\tSecond\tm\tdemo\tA\tpending\n")
        self.sh("work-status.sh", status, "tasks", "import", "s1", tsv)
        self.write(tsv, "C\tOther\tm\tdemo\t\tpending\n")
        self.sh("work-status.sh", status, "tasks", "import", "s2", tsv)
        self.assertIn("CLAIMED=A", self.sh("work-status.sh", status, "tasks", "claim", "A"))
        self.assertIn("A\tin_progress", self.sh("work-status.sh", status, "tasks", "list"))
        self.sh("work-status.sh", status, "tasks", "set", "A", "done")
        rows = self.sh("work-status.sh", status, "tasks", "export").splitlines()
        self.write(tsv, "\n".join(r for r in rows if not r.startswith("A\t")) + "\n")
        before = status.read_bytes()
        self.sh("work-status.sh", status, "tasks", "replace", tsv, code=4)
        self.assertEqual(before, status.read_bytes())
        self.write(tsv, "\n".join(r for r in rows if not r.startswith("B\t")) + "\n")
        self.sh("work-status.sh", status, "tasks", "replace", tsv)
        rows = self.sh("work-status.sh", status, "tasks", "export")
        self.assertNotIn("B\t", rows)
        self.assertIn("\tdone\ts1", rows)
        self.assertIn("s2", rows)
        self.assertIn("CLAIMED=C", self.sh("work-status.sh", status, "tasks", "claim"))

    def test_workflow_definitions_and_lint_with_spaces(self):
        """F10/F11: work accepts defined workflows; signature lint preserves paths."""
        self.create("builtin")
        empty = self.create("empty", "")
        self.assertIn('workflow: ""', self.status(empty).read_text())
        self.write(self.root / "harness/workflow/custom.md",
                   "---\nworkflow: custom\nshort: cust\ntriggers: custom flow\n"
                   "params: 无\nsummary: Test\n---\n# Custom\n")
        custom = self.create("custom", "custom")
        self.assertIn('workflow: "custom"', self.status(custom).read_text())
        self.sh("command-batch.sh", "work-create", self.root, "demo", "bad",
                "Test", "", "", "missing", code=2)
        self.assertEqual([], list((self.root / "space").glob("*-bad")))
        self.assertIn("0 warning(s)", self.sh("lint-doc-scripts.sh", self.root / "harness"))

    def test_guidance_archive_and_cascade_commit(self):
        """F12/F14/F15: guidance survives deferral; all deleted paths enter one commit."""
        parent, child = self.create("parent"), self.create("child")
        sf = self.status(child)
        self.sh("work-status.sh", sf, "set", "parent_workspace", parent)
        self.write(sf, sf.read_text().replace("guidance: []",
                   'guidance:\n  - id: "G1"\n    status: "pending"\n'
                   '    stage: "code"\n    guidance: "Keep this rule"'))
        self.commit(self.root, "space", "tack.yaml")
        self.sh("command-batch.sh", "close-remove", self.root, child, "child", code=3)
        self.sh("work.sh", "purge", self.root, child, code=1)
        self.assertTrue(sf.exists())
        self.assertIn("Keep this rule", self.sh("work-status.sh", self.root, "guidance", "all", "pending"))
        landing = self.root / "harness/rule/captured.md"
        self.write(landing, "# Captured rule\n")
        tsv = self.base / "guidance.tsv"
        self.write(tsv, "G1\tapplied\tharness/rule/captured.md\n")
        self.assertIn("GUIDANCE_STATUS=", self.sh("command-batch.sh", "guidance", self.root, child, tsv))
        self.sh("space.sh", "commit", self.root, "Capture guidance",
                f"space/{child}/status.yaml", "harness/rule/captured.md")
        changed = self.git(self.root, "show", "--format=", "--name-only")
        self.assertIn(f"space/{child}/status.yaml", changed)
        self.assertIn("harness/rule/captured.md", changed)
        self.sh("command-batch.sh", "close-remove", self.root, parent, "parent", code=3)
        run_dir = sf.parent / "run/example"
        self.write(run_dir / "run.md", "# Archived instruction\n")
        self.sh("command-batch.sh", "close-remove", self.root, child, "child", code=3)
        self.sh("workspace-archive.sh", "move", self.root, "demo", child, "run")
        self.sh("command-batch.sh", "close-remove", self.root, child, "child")
        self.sh("command-batch.sh", "close-remove", self.root, parent, "parent")
        self.sh("space.sh", "commit", self.root, "Close family",
                f"space/{child}", f"space/{parent}", "tack.yaml", f"wiki/demo/history/{child}")
        changed = self.git(self.root, "show", "--format=", "--name-only")
        for name in (child, parent):
            self.assertIn(f"space/{name}/status.yaml", changed)
            self.assertFalse(self.status(name).exists())
        self.assertTrue((self.root / f"wiki/demo/history/{child}/run/example/run.md").exists())
        self.assertEqual("", self.git(self.root, "status", "--porcelain"))

    def test_conflict_continue_and_remote_target(self):
        """F09/F13: continue once and verify the actual destination ref."""
        repo = self.repository()
        for branch in ("source", "target"):
            self.git(repo, "checkout", "-b", branch, "main")
            self.write(repo / "file.txt", branch + "\n")
            self.commit(repo, "file.txt")
        self.git(repo, "push", "origin", "source", "target")
        out = self.sh("branch-op.sh", "prepare", self.root, "space/conflict", "demo",
                      "merge", "source", "target", "local", "local")
        source = re.search(r"^BRANCH_OP_SOURCE_TMP=(.*)$", out, re.M)[1]
        target = re.search(r"^BRANCH_OP_TARGET_TMP=(.*)$", out, re.M)[1]
        self.sh("branch-op.sh", "integrate", self.root, "space/conflict", "demo",
                "merge", source, target, code=10)
        wt = self.root / "space/conflict/repo/demo"
        self.write(wt / "file.txt", "source and target\n")
        self.git(wt, "add", "file.txt")
        self.sh("branch-op.sh", "continue", self.root, "space/conflict", "demo", "merge")
        self.assertIn("operation: none", self.sh("git-facts.sh", "status", wt))
        self.sh("branch-op.sh", "push", self.root, "space/conflict", "demo",
                "merge", "source", "target", source, target)
        self.sh("git-fetch-helper.sh", "fetch", wt)
        self.git(wt, "merge-base", "--is-ancestor", "HEAD", "origin/target")
        self.sh("branch-op.sh", "cleanup", self.root, "space/conflict", "demo", source, target)
        self.assertFalse(wt.exists())

    def test_upgrade_preserves_local_customizations(self):
        incoming = self.base / "incoming"
        incoming.mkdir()
        for tree in (self.root, incoming):
            for name in ("upstream", "local", "conflict", "deleted"):
                self.write(tree / f"harness/rule/{name}.md", "base\n")
        self.sh("harness-baseline.sh", "seed", self.root, incoming)
        self.write(incoming / "harness/rule/upstream.md", "upstream\n")
        self.write(self.root / "harness/rule/local.md", "local\n")
        self.write(self.root / "harness/rule/conflict.md", "local\n")
        self.write(incoming / "harness/rule/conflict.md", "upstream\n")
        (incoming / "harness/rule/deleted.md").unlink()
        out = self.sh("harness-baseline.sh", "classify", self.root, incoming)
        for kind, name in (("UPSTREAM", "upstream"), ("LOCAL", "local"),
                           ("CONFLICT", "conflict"), ("UPSTREAM_DELETED", "deleted")):
            self.assertIn(f"{kind}\tharness/rule/{name}.md", out)
        self.sh("harness-baseline.sh", "apply-clean", self.root, incoming)
        for name, expected in (("upstream", "upstream\n"), ("local", "local\n"),
                               ("conflict", "local\n"), ("deleted", "base\n")):
            self.assertEqual(expected, (self.root / f"harness/rule/{name}.md").read_text())


class ReportResult(unittest.TextTestResult):
    """Emit one JUnit testcase per test, including subtest and cleanup failures."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.xml = ET.Element("testsuite", name="harness-command-regression")
        self.nodes = {}

    def startTest(self, test):
        super().startTest(test)
        self.nodes[test] = ET.SubElement(self.xml, "testcase", name=test.id())
        self.started = time.monotonic()

    def stopTest(self, test):
        self.nodes[test].set("time", f"{time.monotonic() - self.started:.3f}")
        super().stopTest(test)

    def addFailure(self, test, err):
        super().addFailure(test, err)
        ET.SubElement(self.nodes[test], "failure").text = self._exc_info_to_string(err, test)

    def addError(self, test, err):
        super().addError(test, err)
        ET.SubElement(self.nodes[test], "error").text = self._exc_info_to_string(err, test)

    def addSubTest(self, test, subtest, err):
        super().addSubTest(test, subtest, err)
        if err:
            ET.SubElement(self.nodes[test], "failure", message=str(subtest)).text = (
                self._exc_info_to_string(err, test))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, help="JUnit XML output outside the checkout")
    parser.add_argument("tests", nargs="*", help="Optional unittest method names")
    args = parser.parse_args()
    if not SHELL:
        parser.error("POSIX sh is required; use .github/tests/run.sh from Git Bash on Windows")
    suite = (unittest.TestSuite(Commands(name) for name in args.tests) if args.tests
             else unittest.defaultTestLoader.loadTestsFromTestCase(Commands))
    result = unittest.TextTestRunner(verbosity=2, resultclass=ReportResult).run(suite)
    if args.report:
        result.xml.set("tests", str(result.testsRun))
        result.xml.set("failures", str(len(result.failures)))
        result.xml.set("errors", str(len(result.errors)))
        args.report.parent.mkdir(parents=True, exist_ok=True)
        ET.ElementTree(result.xml).write(args.report, encoding="utf-8", xml_declaration=True)
    raise SystemExit(0 if result.wasSuccessful() else 1)
