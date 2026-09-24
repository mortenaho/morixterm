"""Exercise the workflow's actual Bash steps against local Git repositories and a fake gh."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = yaml.safe_load((ROOT / ".github/workflows/release.yml").read_text())


def step_script(job, name):
    return next(step["run"] for step in WORKFLOW["jobs"][job]["steps"] if step["name"] == name)


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="morixterm-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        (self.repo / "scripts").mkdir()
        shutil.copy(ROOT / "scripts/next_release_version.py", self.repo / "scripts")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "-qm", "First")
        self.first = self.git("rev-parse", "HEAD")
        self.git("tag", "v3")
        (self.repo / "new.txt").write_text("Next release")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "-qm", "Second")
        self.head = self.git("rev-parse", "HEAD")
        self.output = self.root / "outputs"
        self.env = dict(os.environ, GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_SHA=self.head,
                        GITHUB_OUTPUT=str(self.output), EVENT_TAG="", REQUESTED_TAG="",
                        RELEASE_TAG="v4", RELEASE_VERSION="4", RELEASE_SHA=self.head,
                        GITHUB_REPOSITORY="test/repo", GH_TOKEN="")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True).strip()

    def run_step(self, job, name, **env):
        return subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c",
                               step_script(job, name)], cwd=self.repo, env={**self.env, **env},
                              capture_output=True, text=True)

    def resolve(self, **env):
        result = self.run_step("prepare", "Resolve release version", **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return dict(line.split("=", 1) for line in self.output.read_text().splitlines())

    def test_manual_run_chooses_next_version_at_checked_out_commit(self):
        self.assertEqual(self.resolve(), {"tag": "v4", "version": "4", "sha": self.head})

    def test_push_to_main_chooses_next_version(self):
        self.assertEqual(self.resolve(GITHUB_EVENT_NAME="push"),
                         {"tag": "v4", "version": "4", "sha": self.head})

    def test_workflow_triggers_include_main_push(self):
        # PyYAML 1.1 parses the key "on" as boolean True.
        triggers = WORKFLOW.get("on", WORKFLOW.get(True))
        self.assertIn("push", triggers)
        self.assertEqual(triggers["push"]["branches"], ["main"])
        self.assertIn("workflow_dispatch", triggers)
        self.assertIn("release", triggers)

    def test_published_release_builds_tagged_commit_not_main(self):
        self.assertEqual(self.resolve(GITHUB_EVENT_NAME="release", EVENT_TAG="v3", GITHUB_SHA=self.first),
                         {"tag": "v3", "version": "3", "sha": self.first})

    def test_manual_retry_reuses_existing_semver_tag(self):
        self.git("tag", "v4.1.0", self.first)
        self.assertEqual(self.resolve(REQUESTED_TAG="v4.1.0"),
                         {"tag": "v4.1.0", "version": "4.1.0", "sha": self.first})

    def test_invalid_tags_and_missing_tags_fail(self):
        for tag in ("v4\nsha=bad", "--help", "../v4", "v04", "v4-beta", "v9"):
            with self.subTest(tag=tag):
                result = self.run_step("prepare", "Resolve release version", REQUESTED_TAG=tag)
                self.assertNotEqual(result.returncode, 0)

    def test_moved_release_tag_fails(self):
        result = self.run_step("prepare", "Resolve release version", EVENT_TAG="v3",
                               GITHUB_EVENT_NAME="release", GITHUB_SHA=self.head)
        self.assertNotEqual(result.returncode, 0)

    def test_required_packages_without_appimage(self):
        assets = self.repo / "release-assets"
        assets.mkdir()
        names = ("morixterm_4_amd64.deb", "MoriXterm-4-Windows-x64-Setup.exe",
                 "MoriXterm-4-Windows-x64-Portable.zip")
        for name in names:
            (assets / name).write_bytes(b"package fixture")
        result = self.run_step("release", "Verify complete release assets")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in names:
            for empty in (False, True):
                with self.subTest(name=name, empty=empty):
                    path = assets / name
                    path.unlink()
                    if empty:
                        path.touch()
                    self.assertNotEqual(self.run_step("release", "Verify complete release assets").returncode, 0)
                    path.write_bytes(b"package fixture")

    def test_tag_creation_retry_and_mismatched_commit(self):
        remote = self.root / "remote.git"
        subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
        self.git("remote", "add", "origin", str(remote))
        for attempt in range(2):
            result = self.run_step("release", "Create or verify version tag")
            self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_step("release", "Create or verify version tag", RELEASE_SHA=self.first)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "v4^{commit}"), self.head)

    def test_publish_new_release_and_retry_upload(self):
        tools = self.root / "bin"
        tools.mkdir()
        gh = tools / "gh"
        gh.write_text("#!/usr/bin/env python3\n"
                      "import json, os, sys\n"
                      "with open(os.environ['GH_TEST_LOG'], 'a') as log:\n"
                      "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                      "if sys.argv[1:3] == ['release', 'view']:\n"
                      "    sys.exit(0 if os.environ['GH_TEST_EXISTS'] == 'yes' else 1)\n"
                      "sys.exit(int(os.environ.get('GH_TEST_UPLOAD_EXIT', '0')))\n")
        gh.chmod(0o755)
        assets = self.repo / "release-assets"
        assets.mkdir()
        for name in ("package.deb", "setup.exe", "portable.zip"):
            (assets / name).write_bytes(b"package fixture")
        log = self.root / "gh-log"
        for exists in ("no", "yes"):
            log.write_text("")
            result = self.run_step("release", "Publish or update release assets",
                                   PATH=str(tools) + os.pathsep + os.environ["PATH"],
                                   GH_TEST_LOG=str(log), GH_TEST_EXISTS=exists)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(calls[-1][:3], ["release", "upload" if exists == "yes" else "create", "v4"])
            self.assertIn("release-assets/portable.zip", calls[-1])
            if exists == "yes":
                self.assertIn("--clobber", calls[-1])
                self.assertNotIn("--generate-notes", calls[-1])
        result = self.run_step("release", "Publish or update release assets",
                               PATH=str(tools) + os.pathsep + os.environ["PATH"],
                               GH_TEST_LOG=str(log), GH_TEST_EXISTS="yes", GH_TEST_UPLOAD_EXIT="1")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
