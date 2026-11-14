import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from image_release import aliases_allowed, aliases_match, inspect_alias, release_plan, resolve_versions, select_targets, validate_version

VERSIONS = {"claude": "2.1.325", "codex": "0.169.0", "codex_vsix": "26.51111.21308", "t3": "0.1.9"}
REVISION = "a" * 40


def published_configs(plan):
    labels = {f"io.zeroae.version.{key.replace('_', '-')}": value for key, value in plan['versions'].items()}
    labels['org.opencontainers.image.revision'] = plan['revision']
    return {
        f"linux/{arch}": {"os": "linux", "architecture": arch, "config": {"Labels": dict(labels)}}
        for arch in ('amd64', 'arm64')
    }


class ImageReleaseTests(unittest.TestCase):
    def test_main_builds_three_independent_targets(self):
        self.assertEqual(select_targets(ref="refs/heads/main"), ({"target": ["claude", "codex", "t3"]}, ""))

    def test_product_source_tags_select_only_their_product(self):
        for tag, target, version in (("v2.1.325", "claude", "2.1.325"), ("codex-v0.169.0", "codex", "0.169.0"), ("t3-v0.1.9", "t3", "0.1.9")):
            with self.subTest(tag=tag):
                self.assertEqual(select_targets(ref=f"refs/tags/{tag}"), ({"target": [target]}, version))

    def test_version_override_requires_one_target(self):
        with self.assertRaises(ValueError):
            select_targets("all", "0.169.0")
        self.assertEqual(select_targets("codex", "0.169.0"), ({"target": ["codex"]}, "0.169.0"))

    def test_versions_cannot_inject_paths_or_outputs(self):
        for version in ("../latest", "1.2.3\nmarker=oops", "latest", "1.2.3;false"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                validate_version(version)

    def test_codex_resolution_does_not_depend_on_claude_or_t3(self):
        requested = []
        def fetch(product):
            requested.append(product)
            if product in ("claude", "t3"):
                raise RuntimeError("Unrelated provider unavailable")
            return VERSIONS[product]
        versions = resolve_versions("codex", fetch=fetch)
        self.assertEqual(versions, {"codex": "0.169.0", "codex_vsix": "26.51111.21308"})
        self.assertEqual(requested, ["codex", "codex_vsix"])

    def test_claude_does_not_resolve_codex_or_t3(self):
        requested = []
        resolve_versions("claude", fetch=lambda p: requested.append(p) or VERSIONS[p])
        self.assertEqual(requested, ["claude"])

    def test_t3_version_override_keeps_resolving_its_dependencies(self):
        versions = resolve_versions("t3", {"t3": "0.1.8"}, fetch=VERSIONS.__getitem__)
        self.assertEqual(versions, {**VERSIONS, "t3": "0.1.8"})

    def test_registry_names_and_tags_use_product_versions(self):
        for target, name in (("claude", "claude-code"), ("codex", "codex"), ("t3", "t3-code")):
            with self.subTest(target=target):
                plan = release_plan(target, VERSIONS, "ZeroAE", REVISION)
                self.assertEqual(plan["image"], f"ghcr.io/zeroae/{name}")
                self.assertEqual(plan["version"], VERSIONS[target])
                self.assertTrue(plan["snapshot"].startswith(VERSIONS[target]))
                self.assertTrue(plan["snapshot"].endswith("-r" + REVISION[:12]))

    def test_each_t3_dependency_update_changes_snapshot_but_not_primary_tag(self):
        original = release_plan("t3", VERSIONS, "zeroae", REVISION)
        for product in ("claude", "codex", "codex_vsix"):
            with self.subTest(product=product):
                updated = release_plan("t3", {**VERSIONS, product: "99.0.0"}, "zeroae", REVISION)
                self.assertNotEqual(updated["snapshot"], original["snapshot"])
                self.assertNotEqual(updated["marker"], original["marker"])
                self.assertEqual(updated["version"], "0.1.9")

    def test_claude_updates_do_not_change_codex_tags(self):
        before = release_plan("codex", VERSIONS, "zeroae", REVISION)
        after = release_plan("codex", {**VERSIONS, "claude": "2.1.326"}, "zeroae", REVISION)
        self.assertEqual(before, after)

    def test_extension_update_rebuilds_codex(self):
        before = release_plan("codex", VERSIONS, "zeroae", REVISION)
        after = release_plan("codex", {**VERSIONS, "codex_vsix": "26.51112.1"}, "zeroae", REVISION)
        self.assertNotEqual(before["marker"], after["marker"])
        self.assertEqual(before["version"], after["version"])

    def test_source_changes_create_new_snapshot(self):
        before = release_plan("t3", VERSIONS, "zeroae", REVISION)
        after = release_plan("t3", VERSIONS, "zeroae", "b" * 40)
        self.assertNotEqual(before["snapshot"], after["snapshot"])

    def test_rebuilds_have_distinct_snapshot_tags_but_the_same_success_marker(self):
        before = release_plan("t3", VERSIONS, "zeroae", REVISION, "1234-1")
        after = release_plan("t3", VERSIONS, "zeroae", REVISION, "1234-2")
        self.assertNotEqual(before["snapshot"], after["snapshot"])
        self.assertEqual(before["marker"], after["marker"])

    def test_historical_release_cannot_roll_back_latest(self):
        current = {"codex": "0.169.0", "codex_vsix": VERSIONS['codex_vsix']}
        historical = {**current, "codex": "0.168.0"}
        self.assertFalse(aliases_allowed(historical, REVISION, REVISION, current))
        self.assertTrue(aliases_allowed(current, REVISION, REVISION, current))

    def test_stale_code_or_provider_combination_cannot_promote_aliases(self):
        self.assertFalse(aliases_allowed(VERSIONS, "b"*40, REVISION, VERSIONS))
        self.assertFalse(aliases_allowed({**VERSIONS, "codex": "0.168.0"}, REVISION, REVISION, VERSIONS))

    def test_all_aliases_must_match_versions_and_revision_on_both_platforms(self):
        plan = release_plan('codex', VERSIONS, 'zeroae', REVISION)
        expected = published_configs(plan)
        checked = []
        def inspect(reference):
            checked.append(reference)
            return expected
        self.assertTrue(aliases_match(plan, inspect))
        self.assertEqual(checked, [plan['image']+':'+tag for tag in ('latest', '0.169.0', '0.169', '0')])
        for label, stale in (('io.zeroae.version.codex', '0.168.0'), ('org.opencontainers.image.revision', 'b'*40)):
            with self.subTest(label=label):
                drifted = published_configs(plan)
                drifted['linux/arm64']['config']['Labels'][label] = stale
                self.assertFalse(aliases_match(plan, lambda ref: drifted))
        self.assertFalse(aliases_match(plan, lambda ref: None))
        self.assertFalse(aliases_match(plan, lambda ref: {'linux/amd64': expected['linux/amd64']}))
        self.assertFalse(aliases_match(plan, lambda ref: None if ref.endswith(':0') else expected))

    def test_registry_errors_are_not_mistaken_for_missing_aliases(self):
        with patch('image_release.subprocess.run', return_value=subprocess.CompletedProcess([], 1, '', 'manifest unknown')):
            self.assertIsNone(inspect_alias('ghcr.io/zeroae/codex:latest'))
        with patch('image_release.subprocess.run', return_value=subprocess.CompletedProcess([], 1, '', 'unauthorized')):
            with self.assertRaises(RuntimeError):
                inspect_alias('ghcr.io/zeroae/codex:latest')

    def test_success_markers_skip_only_the_exact_published_snapshot(self):
        script = str(Path(__file__).with_name("image_release.py").resolve())
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], text=True).strip()
            git("init", "--quiet")
            git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "--allow-empty", "-m", "Initial")
            command = [sys.executable, script, "plan", "--target", "t3", "--check-existing"]
            for key, value in VERSIONS.items():
                command.extend([f"--{key.replace('_', '-')}-version", value])
            fixture = Path(directory, 'alias-configs.json')
            docker = Path(directory, 'docker')
            docker.write_text(f"#!{sys.executable}\nimport sys\nsys.stdout.write(open({str(fixture)!r}).read())\n")
            docker.chmod(0o755)
            environment = {**os.environ, 'PATH': directory + os.pathsep + os.environ['PATH']}
            def plan(extra=()):
                return json.loads(subprocess.check_output([*command, *extra], cwd=directory, env=environment, text=True))
            first = plan()
            self.assertEqual(first["should_build"], "true")
            self.assertEqual(git("tag", "--list"), "")  # Planning never records a premature success.
            git("tag", first["marker"])
            configs = published_configs(first)
            fixture.write_text(json.dumps(configs))
            self.assertEqual(plan()["should_build"], "false")
            drifted = published_configs(first)
            drifted['linux/amd64']['config']['Labels']['io.zeroae.version.codex'] = '0.168.0'
            fixture.write_text(json.dumps(drifted))
            self.assertEqual(plan()["should_build"], "true")  # Existing marker cannot hide alias drift.
            fixture.write_text(json.dumps(configs))
            self.assertEqual(plan()["should_build"], "false")
            self.assertEqual(plan(["--codex-version", "0.170.0"])["should_build"], "true")
            self.assertEqual(plan(["--revision", "b" * 40])["should_build"], "true")


if __name__ == "__main__":
    unittest.main()
