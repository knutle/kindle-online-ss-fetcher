import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".github/scripts/release.sh"
MOCK_GH = """\
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state_path = Path(os.environ["MOCK_GH_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
if args[0] == "api":
    if state.get("api_error"):
        print("API unavailable", file=sys.stderr)
        sys.exit(1)
    print(json.dumps([state["releases"]]))
elif args[:2] == ["release", "create"]:
    assert "--verify-tag" in args and "--draft" in args
    tag = args[2]
    archive = Path(args[3])
    assert archive.is_file()
    state["releases"].append({
        "tag_name": tag, "draft": True, "body": args[args.index("--notes") + 1]
    })
    state["uploads"].append(archive.name)
elif args[:2] == ["release", "upload"]:
    assert "--clobber" in args
    assert Path(args[3]).is_file()
    state["uploads"].append(Path(args[3]).name)
else:
    raise SystemExit("Unexpected gh arguments: " + repr(args))
state_path.write_text(json.dumps(state))
"""


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "work"
        self.repo.mkdir()
        self.remote = self.root / "remote.git"
        self.output = self.root / "output"
        self.output.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        gh = self.bin / "gh"
        gh.write_text(MOCK_GH)
        gh.chmod(0o755)
        self.state_path = self.root / "gh.json"
        self.save_state({"releases": [], "uploads": []})
        for directory in ("documents", "extensions"):
            shutil.copytree(ROOT / directory, self.repo / directory)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Release test")
        self.git("add", "documents", "extensions")
        self.git("commit", "-qm", "Package")
        subprocess.run(["git", "init", "--bare", "-q", str(self.remote)], check=True)
        self.git("remote", "add", "origin", str(self.remote))
        self.branch = "release/v1.2.3"
        self.git("push", "-q", "origin", f"HEAD:refs/heads/{self.branch}")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.repo, check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ).stdout.strip()

    def save_state(self, state):
        self.state_path.write_text(json.dumps(state))

    def state(self):
        return json.loads(self.state_path.read_text())

    def run_release(self, branch=None, commit=None):
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.bin}{os.pathsep}{env['PATH']}",
            "GITHUB_REF_NAME": branch or self.branch,
            "GITHUB_SHA": commit or self.git("rev-parse", "HEAD"),
            "GITHUB_REPOSITORY": "example/project",
            "RUNNER_TEMP": str(self.output),
            "MOCK_GH_STATE": str(self.state_path),
        })
        return subprocess.run(
            ["bash", str(SCRIPT)], cwd=self.repo, env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def remote_tag(self):
        return self.git("ls-remote", "--refs", "origin", "refs/tags/v1.2.3").split()[0]

    def test_updater_scriptlets_are_in_package(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.output / "upd_knutle_online_ss_pkg-1.2.3.zip"
        with zipfile.ZipFile(archive) as package:
            names = set(package.namelist())
            self.assertIn("documents/knutle_online_ss_update_local.sh", names)
            self.assertIn("documents/knutle_online_ss_update_auto.sh", names)
            self.assertNotIn("documents/knutle_online_ss_update.sh", names)

    def test_auto_updater_uses_hardened_release_asset_parsing(self):
        updater = ROOT / "documents/knutle_online_ss_update_auto.sh"
        text = updater.read_text()
        self.assertIn("command -v jq", text)
        self.assertIn("^upd_knutle_online_ss_pkg-[0-9]+", text)
        self.assertIn("https://", text)
        self.assertIn("unzip -tq", text)

    def test_create_and_refresh_draft_with_installable_archive(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.output / "upd_knutle_online_ss_pkg-1.2.3.zip"
        expected = set(self.git("ls-files", "documents", "extensions").splitlines())
        with zipfile.ZipFile(archive) as package:
            files = {item.filename for item in package.infolist() if not item.is_dir()}
            self.assertEqual(files, expected)
            self.assertTrue(package.getinfo("extensions/online-ss/bin/fbink_hf").external_attr >> 16 & 0o111)
        extracted = self.root / "extracted"
        subprocess.run(["unzip", "-q", str(archive), "-d", str(extracted)], check=True)
        self.assertTrue(os.access(extracted / "extensions/online-ss/bin/fbink_hf", os.X_OK))
        self.assertEqual(self.remote_tag(), self.git("rev-parse", "HEAD"))
        self.assertEqual(self.state()["releases"][0]["body"], "<!-- online-ss-release-workflow:release/v1.2.3 -->")

        (self.repo / "documents/knutle_online_ss_stop.sh").write_text("#!/bin/sh\nexit 0\n")
        self.git("add", "documents/knutle_online_ss_stop.sh")
        self.git("commit", "-qm", "Next release change")
        self.git("push", "-q", "origin", f"HEAD:refs/heads/{self.branch}")
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_tag(), self.git("rev-parse", "HEAD"))
        self.assertEqual(len(self.state()["releases"]), 1)
        self.assertEqual(self.state()["uploads"], [archive.name, archive.name])
        with zipfile.ZipFile(archive) as package:
            self.assertEqual(package.read("documents/knutle_online_ss_stop.sh"), b"#!/bin/sh\nexit 0\n")

    def test_rejects_published_unmanaged_and_orphan_tags(self):
        self.git("push", "-q", "origin", "HEAD:refs/tags/v1.2.3")
        original = self.remote_tag()
        marker = "<!-- online-ss-release-workflow:release/v1.2.3 -->"
        for releases in (
            [{"tag_name": "v1.2.3", "draft": False, "body": marker}],
            [{"tag_name": "v1.2.3", "draft": True, "body": "Unmanaged"}],
            [],
        ):
            with self.subTest(releases=releases):
                self.save_state({"releases": releases, "uploads": []})
                result = self.run_release()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.remote_tag(), original)
                self.assertEqual(self.state()["uploads"], [])

    def test_rejects_invalid_versions_and_api_failures(self):
        for branch in ("release/v01.2.3", "release/v1.2.3-rc.1", "release/1.2.3"):
            with self.subTest(branch=branch):
                self.assertNotEqual(self.run_release(branch=branch).returncode, 0)
        self.save_state({"releases": [], "uploads": [], "api_error": True})
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertEqual(self.git("ls-remote", "--refs", "origin", "refs/tags/v1.2.3"), "")

    def test_stale_branch_does_not_publish(self):
        old_commit = self.git("rev-parse", "HEAD")
        (self.repo / "documents/knutle_online_ss_stop.sh").write_text("#!/bin/sh\nexit 0\n")
        self.git("add", "documents/knutle_online_ss_stop.sh")
        self.git("commit", "-qm", "Next release change")
        self.git("push", "-q", "origin", f"HEAD:refs/heads/{self.branch}")
        self.git("checkout", "-q", old_commit)
        result = self.run_release(commit=old_commit)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Skipping stale release run", result.stdout)
        self.assertEqual(self.state()["releases"], [])

    def test_refuses_unusable_package(self):
        self.git("update-index", "--chmod=-x", "extensions/online-ss/bin/fbink_hf")
        self.git("commit", "-qm", "Remove executable mode")
        self.git("push", "-q", "origin", f"HEAD:refs/heads/{self.branch}")
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be executable", result.stderr)
        self.assertEqual(self.git("ls-remote", "--refs", "origin", "refs/tags/v1.2.3"), "")


if __name__ == "__main__":
    unittest.main()
