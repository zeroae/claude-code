#!/usr/bin/env python3
"""Resolve product releases and plan image tags without publishing anything."""
import argparse
import json
import os
import re
import subprocess
import urllib.request

PRODUCTS = {
    "claude": ("claude-code", ("claude",)),
    "codex": ("codex", ("codex", "codex_vsix")),
    "t3": ("t3-code", ("t3", "claude", "codex", "codex_vsix")),
}
SOURCES = {
    "claude": "https://downloads.claude.ai/claude-code-releases/latest",
    "codex": "https://registry.npmjs.org/@openai%2fcodex/latest",
    "codex_vsix": "https://open-vsx.org/api/openai/chatgpt/linux-x64/latest",
    "t3": "https://api.github.com/repos/pingdotgg/t3code/releases/latest",
}
VERSION = re.compile(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?\Z")


def validate_version(value):
    value = value.strip().removeprefix("v")
    if not VERSION.fullmatch(value):
        raise ValueError(f"Invalid release version: {value!r}")
    return value


def fetch_version(product):
    headers = {"User-Agent": "zeroae-agent-images"}
    if product == "t3" and os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
    request = urllib.request.Request(SOURCES[product], headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read().decode()
    if product == "claude":
        return body
    data = json.loads(body)
    return data["tag_name" if product == "t3" else "version"]


def select_targets(target="all", version="", ref=""):
    if target not in (*PRODUCTS, "all"):
        raise ValueError(f"Unknown image target: {target}")
    if ref.startswith("refs/tags/"):
        tag = ref.removeprefix("refs/tags/")
        for prefix, product in (("codex-v", "codex"), ("t3-v", "t3"), ("v", "claude")):
            if tag.startswith(prefix):
                return {"target": [product]}, validate_version(tag[len(prefix):])
        raise ValueError(f"Unsupported release tag: {tag}")
    if version and target == "all":
        raise ValueError("A version override requires one explicit image target")
    return {"target": list(PRODUCTS) if target == "all" else [target]}, (
        validate_version(version) if version else ""
    )


def resolve_versions(target, overrides=None, fetch=None):
    overrides = overrides or {}
    fetch = fetch or fetch_version
    return {
        product: validate_version(overrides.get(product) or fetch(product))
        for product in PRODUCTS[target][1]
    }


def release_plan(target, versions, owner, revision, build_id=""):
    if not re.fullmatch(r"[A-Za-z0-9-]+", owner):
        raise ValueError("Invalid registry owner")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Expected a full Git commit SHA")
    versions = {key: validate_version(versions[key]) for key in PRODUCTS[target][1]}
    primary = versions[target]
    snapshot = primary
    if target == "t3":
        snapshot += f"-claude{versions['claude']}-codex{versions['codex']}"
    if "codex_vsix" in versions:
        snapshot += f"-vsix{versions['codex_vsix']}"
    snapshot += f"-r{revision[:12]}"
    marker = f"images/{target}/{snapshot}"
    if build_id:
        if not re.fullmatch(r"\d+-\d+", build_id):
            raise ValueError("Invalid workflow run identifier")
        snapshot += f"-b{build_id}"
    if len(snapshot) > 128:
        raise ValueError("Dependency snapshot exceeds the Docker tag length limit")
    return {
        "target": target,
        "image": f"ghcr.io/{owner.lower()}/{PRODUCTS[target][0]}",
        "version": primary,
        "revision": revision,
        "snapshot": snapshot,
        "marker": marker,
        "versions": versions,
        "labels": "\n".join(
            f"io.zeroae.version.{key.replace('_', '-')}={value}"
            for key, value in versions.items()
        ),
        **{f"{key}_version": versions.get(key, "") for key in SOURCES},
    }


def marker_exists(marker):
    result = subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/tags/{marker}"])
    if result.returncode not in (0, 1):
        raise RuntimeError("Failed to check published release markers")
    return result.returncode == 0


def inspect_alias(reference):
    result = subprocess.run(
        ["docker", "buildx", "imagetools", "inspect", reference, "--format", "{{json .Image}}"],
        capture_output=True, text=True,
    )
    if result.returncode:
        if any(error in result.stderr.lower() for error in ("not found", "manifest unknown", "404")):
            return None
        raise RuntimeError(f"Cannot inspect {reference}: {result.stderr.strip()}")
    return json.loads(result.stdout)


def aliases_match(plan, inspect=None):
    inspect = inspect or inspect_alias
    major, minor, _ = plan["version"].split(".", 2)
    aliases = ("latest", plan["version"], f"{major}.{minor}", major)
    expected = {f"io.zeroae.version.{key.replace('_', '-')}": value for key, value in plan["versions"].items()}
    expected["org.opencontainers.image.revision"] = plan["revision"]
    for alias in dict.fromkeys(aliases):
        data = inspect(f"{plan['image']}:{alias}")
        if not data:
            return False
        configs = [data] if "config" in data else list(data.values())
        platforms = set()
        for config in configs:
            platforms.add((config.get("os"), config.get("architecture")))
            labels = (config.get("config") or {}).get("Labels") or {}
            if any(labels.get(key) != value for key, value in expected.items()):
                return False
        if not {("linux", "amd64"), ("linux", "arm64")} <= platforms:
            return False
    return True


def aliases_allowed(versions, revision, main_revision, latest_versions):
    return revision == main_revision and versions == latest_versions


def write_outputs(values):
    if not os.environ.get("GITHUB_OUTPUT"):
        return
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in values.items():
            if isinstance(value, (dict, list)):
                value = json.dumps(value, separators=(",", ":"))
            if "\n" in str(value):
                output.write(f"{key}<<RELEASE_OUTPUT\n{value}\nRELEASE_OUTPUT\n")
            else:
                output.write(f"{key}={value}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    select = subparsers.add_parser("select")
    select.add_argument("--target", default="all")
    select.add_argument("--version", default="")
    select.add_argument("--ref", default="")
    plan = subparsers.add_parser("plan")
    plan.add_argument("--target", choices=PRODUCTS, required=True)
    plan.add_argument("--owner", default=os.environ.get("GITHUB_REPOSITORY_OWNER", "zeroae"))
    plan.add_argument("--revision")
    plan.add_argument("--version", default="")
    plan.add_argument("--check-existing", action="store_true")
    for product in SOURCES:
        plan.add_argument(f"--{product.replace('_', '-')}-version", default="")
    aliases = subparsers.add_parser("aliases")
    aliases.add_argument("--target", choices=PRODUCTS, required=True)
    aliases.add_argument("--versions-json", required=True)
    aliases.add_argument("--revision", required=True)
    args = parser.parse_args()
    if args.command == "select":
        matrix, version = select_targets(args.target, args.version, args.ref)
        result = {"matrix": matrix, "version": version}
    elif args.command == "aliases":
        main_revision = subprocess.check_output(
            ["git", "ls-remote", "origin", "refs/heads/main"], text=True,
        ).split()[0]
        allowed = aliases_allowed(
            json.loads(args.versions_json), args.revision,
            main_revision, resolve_versions(args.target),
        )
        result = {"promote_aliases": str(allowed).lower()}
    else:
        overrides = {product: getattr(args, f"{product}_version") for product in SOURCES}
        if args.version:
            overrides[args.target] = args.version
        versions = resolve_versions(args.target, overrides)
        revision = args.revision or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        build_id = f"{os.environ['GITHUB_RUN_ID']}-{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}" if os.environ.get("GITHUB_RUN_ID") else ""
        result = release_plan(args.target, versions, args.owner, revision, build_id)
        published = args.check_existing and marker_exists(result["marker"]) and aliases_match(result)
        result["should_build"] = str(not published).lower()
    write_outputs(result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
