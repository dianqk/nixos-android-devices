#!/usr/bin/env python3
"""Generate docs/<device>/status{,.zh}.md from docs/<device>/status.toml.

Every device file must give each item of docs/status/items.toml one of the
legend's statuses; missing, unknown or duplicate items, a note in only one
language, a Partial or Broken item without a note, a malformed `verified`
date or `benchmark` URL, or unknown fields are errors. `--check` reports
pages that differ from what would be generated, without writing.
"""
import argparse
import sys
import tomllib
from pathlib import Path

DEVICE_FIELDS = ("name", "name_zh", "soc", "kernel", "kernel_zh", "updated")
ITEM_FIELDS = {"status", "note", "note_zh", "verified", "benchmark"}
BENCHMARK_PREFIX = "https://browser.geekbench.com/"
NEEDS_NOTE = ("Partial", "Broken")

TEXT = {
    "en": {
        "title": "Support status: ",
        "other": "[中文](status.zh.md)",
        "guide": "[Device guide](README.md)",
        "hardware": "[Hardware support](hardware.md)",
        "generated": "Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.",
        "device": "Device",
        "soc": "SoC",
        "kernel": "Kernel",
        "updated": "Last updated",
        "summary": "Summary",
        "item": "Item",
        "status": "Status",
        "notes": "Notes",
        "legend": "Status legend",
        "meaning": "Meaning",
        "works": "“Works” requires",
        "verified": "(Verified on {}.)",
        "benchmark": "[Geekbench {version}]({url})",
    },
    "zh": {
        "title": "支持状态：",
        "other": "[English](status.md)",
        "guide": "[设备指南](README.zh.md)",
        "hardware": "[硬件支持](hardware.zh.md)",
        "generated": "由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。",
        "device": "设备",
        "soc": "SoC",
        "kernel": "内核",
        "updated": "最后更新",
        "summary": "概览",
        "item": "项目",
        "status": "状态",
        "notes": "说明",
        "legend": "状态说明",
        "meaning": "含义",
        "works": "判定为 Works 的条件",
        "verified": "（{} 验证。）",
        "benchmark": "[Geekbench {version}]({url})",
    },
}


class StatusError(Exception):
    pass


def cell(text):
    return " ".join(text.split()).replace("|", "\\|")


def load_items(path):
    data = tomllib.loads(path.read_text())
    statuses = data["statuses"]
    items = []
    seen = set()
    for category in data["categories"]:
        for item in category["items"]:
            if item["id"] in seen:
                raise StatusError(f"{path}: duplicate item {item['id']}")
            seen.add(item["id"])
            items.append(item)
    return statuses, data["categories"], items


def load_device(path, statuses, items):
    data = tomllib.loads(path.read_text())
    unknown = set(data) - {"device", "items"}
    if unknown:
        raise StatusError(f"{path}: unknown tables {sorted(unknown)}")
    device = data.get("device", {})
    missing = [f for f in DEVICE_FIELDS if not isinstance(device.get(f), str) or not device[f]]
    extra = set(device) - set(DEVICE_FIELDS)
    if missing or extra:
        raise StatusError(f"{path}: [device] needs {list(DEVICE_FIELDS)}; missing {missing}, unknown {sorted(extra)}")
    entries = data.get("items", {})
    ids = {i["id"] for i in items}
    if set(entries) != ids:
        raise StatusError(
            f"{path}: missing items {sorted(ids - set(entries))}, unknown items {sorted(set(entries) - ids)}"
        )
    for name, entry in entries.items():
        if set(entry) - ITEM_FIELDS:
            raise StatusError(f"{path}: {name}: unknown fields {sorted(set(entry) - ITEM_FIELDS)}")
        if entry.get("status") not in statuses:
            raise StatusError(f"{path}: {name}: status must be one of {list(statuses)}")
        if ("note" in entry) != ("note_zh" in entry):
            raise StatusError(f"{path}: {name}: give both note and note_zh, or neither")
        if entry["status"] in NEEDS_NOTE and "note" not in entry:
            raise StatusError(f"{path}: {name}: {entry['status']} needs a short note")
        verified = entry.get("verified")
        if verified is not None and not (
            isinstance(verified, str) and len(verified) == 10 and verified[4] == verified[7] == "-"
        ):
            raise StatusError(f"{path}: {name}: verified must be a YYYY-MM-DD string")
        benchmark = entry.get("benchmark")
        if benchmark is not None and not (isinstance(benchmark, str) and benchmark.startswith(BENCHMARK_PREFIX)):
            raise StatusError(f"{path}: {name}: benchmark must be a {BENCHMARK_PREFIX} URL")
    return device, entries


def render(lang, device, entries, statuses, categories, has_hardware, has_guide=True):
    t = TEXT[lang]
    links = " · ".join([t["other"]] + ([t["guide"]] if has_guide else []) + ([t["hardware"]] if has_hardware else []))
    suffix = "" if lang == "en" else "_zh"
    lines = [
        f"# {t['title']}{device['name' + suffix]}",
        "",
        links,
        "",
        t["generated"],
        "",
        f"| {t['device']} | {t['soc']} | {t['kernel']} | {t['updated']} |",
        "| --- | --- | --- | --- |",
        f"| {cell(device['name' + suffix])} | {cell(device['soc'])} | {cell(device['kernel' + suffix])} | {device['updated']} |",
        "",
        f"## {t['summary']}",
        "",
        "| " + " | ".join(statuses) + " |",
        "| " + " | ".join("---" for _ in statuses) + " |",
        "| " + " | ".join(str(sum(e["status"] == s for e in entries.values())) for s in statuses) + " |",
    ]
    for category in categories:
        lines += [
            "",
            f"## {category[lang]}",
            "",
            f"| {t['item']} | {t['status']} | {t['notes']} |",
            "| --- | --- | --- |",
        ]
        for item in category["items"]:
            entry = entries[item["id"]]
            note = cell(entry.get("note" + suffix, ""))
            if "verified" in entry:
                verified = t["verified"].format(entry["verified"])
                note = f"{note} {verified}" if note else verified
            if "benchmark" in entry:
                url = entry["benchmark"]
                version = "6" if "/v6/" in url else "7"
                link = t["benchmark"].format(version=version, url=url)
                note = f"{note} {link}" if note else link
            lines.append(f"| {cell(item[lang])} | {entry['status']} | {note} |")
    lines += [
        "",
        f"## {t['legend']}",
        "",
        f"| {t['status']} | {t['meaning']} |",
        "| --- | --- |",
    ]
    lines += [f"| {name} | {cell(text[lang])} |" for name, text in statuses.items()]
    if lang == "en":
        lines += ["", f"{t['works']}:", ""]
        for category in categories:
            for item in category["items"]:
                lines.append(f"- {item['en']}: {item['works']}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=Path(__file__).resolve().parent.parent, type=Path)
    parser.add_argument("--check", action="store_true", help="fail when a page is stale; write nothing")
    args = parser.parse_args()
    docs = args.root / "docs"
    try:
        statuses, categories, items = load_items(docs / "status" / "items.toml")
        sources = sorted(docs.glob("*/status.toml"))
        if not sources:
            raise StatusError("no docs/<device>/status.toml files")
        stale = []
        for source in sources:
            device, entries = load_device(source, statuses, items)
            for lang, name in (("en", "status.md"), ("zh", "status.zh.md")):
                page = source.parent / name
                hardware = source.parent / ("hardware.md" if lang == "en" else "hardware.zh.md")
                guide = source.parent / ("README.md" if lang == "en" else "README.zh.md")
                text = render(lang, device, entries, statuses, categories, hardware.is_file(), guide.is_file())
                if args.check:
                    if not page.is_file() or page.read_text() != text:
                        stale.append(page)
                else:
                    page.write_text(text)
    except (StatusError, KeyError, tomllib.TOMLDecodeError) as error:
        print(f"status-pages: {error}", file=sys.stderr)
        return 1
    if stale:
        for page in stale:
            print(f"status-pages: stale {page}; run tools/status-pages.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
