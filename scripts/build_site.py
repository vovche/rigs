#!/usr/bin/env python3
"""build_site.py — render the landing page (site/) for the latest GitHub release.

    scripts/build_site.py --repo vovche/rigs --out _site            # CI: asks the GitHub API
    scripts/build_site.py --release-json release.json --out _site   # offline (tests, previews)

The release JSON has the shape of GET /repos/{repo}/releases/latest. Every package link comes
from the release's own assets, so the page always points at files that exist. The build FAILS
when a translation key, an asset or a placeholder is missing — a broken page is never deployed.
Languages: English at /, Ukrainian at /uk/ (site/i18n/<lang>.json, identical key sets).
"""
import argparse
import html
import json
import os
import re
import shutil
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
LANGS = {"en": "", "uk": "uk/"}  # language → path below the site root
SITE_URL = "https://vovche.github.io/rigs/"
UK_MONTHS = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня",
             "серпня", "вересня", "жовтня", "листопада", "грудня"]

# Root page only: Ukrainian or Russian preferred by the browser → /uk/, unless the visitor
# already chose a language with the switch (stored by site.js).
AUTO_LANGUAGE = """<script>
(function () {
  var saved = null;
  try { saved = localStorage.getItem("rigs-lang"); } catch (e) {}
  if (saved) { if (saved === "uk") location.replace("uk/" + location.hash); return; }
  var langs = navigator.languages || [navigator.language || ""];
  for (var i = 0; i < langs.length; i++) {
    var primary = String(langs[i]).toLowerCase().split("-")[0];
    if (primary === "en") return;
    if (primary === "uk" || primary === "ru") { location.replace("uk/" + location.hash); return; }
  }
})();
</script>"""


def fail(message):
    sys.exit("build_site: " + message)


def fetch_release(repo):
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest",
                                     headers={"Accept": "application/vnd.github+json",
                                              "User-Agent": "rigs-site-builder"})
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def pick(assets, pattern, what):
    regex = re.compile(pattern)
    matches = [a for a in assets if regex.match(a["name"])]
    if len(matches) != 1:
        fail(f"expected exactly one {what} asset matching {pattern}, found {[a['name'] for a in matches]}")
    return matches[0]


def release_values(release, repo):
    tag = release["tag_name"]
    version = tag[1:] if tag.startswith("v") else tag
    v = re.escape(version)
    assets = release.get("assets", [])
    files = {
        "deb": pick(assets, rf"^rigs_{v}(\+[^_]*)?_amd64\.deb$", ".deb"),
        "rpm": pick(assets, rf"^rigs-{v}-[^-]+\.x86_64\.rpm$", ".rpm"),
        "arch": pick(assets, rf"^rigs-{v}(\.r[^-]+)?-\d+-x86_64\.pkg\.tar\.zst$", "Arch"),
        "src": pick(assets, rf"^rigs-{v}\.tar\.gz$", "source tarball"),
        "sums": pick(assets, r"^SHA256SUMS$", "checksum"),
    }
    repo_url = f"https://github.com/{repo}"
    values = {"version": version, "release_url": release["html_url"],
              "releases_url": repo_url + "/releases", "repo_url": repo_url,
              "published": release["published_at"]}
    for key, asset in files.items():
        values[key + "_url"] = asset["browser_download_url"]
        values[key + "_name"] = asset["name"]
        values[key + "_size"] = asset["size"]
    return values


def human_size(size, lang):
    mb = size / (1024 * 1024)
    text = f"{mb:.1f}" if mb >= 0.1 else "0.1"
    return text.replace(".", ",") + " МБ" if lang == "uk" else text + " MB"


def human_date(iso, lang):
    date = datetime.strptime(iso[:10], "%Y-%m-%d")
    if lang == "uk":
        return f"{date.day} {UK_MONTHS[date.month - 1]} {date.year}"
    return date.strftime("%B ") + str(date.day) + date.strftime(", %Y")


def render(template, strings, release, lang):
    other = "uk" if lang == "en" else "en"
    base = "../" if LANGS[lang] else ""
    fields = {
        "lang": lang, "base": base, "site_url": SITE_URL, "lang_path": LANGS[lang],
        "alt_lang": other, "alt_href": base + LANGS[other] if LANGS[other] else base or "./",
        "auto_language_script": AUTO_LANGUAGE if lang == "en" else "",
    }
    values = dict(release)
    values["date"] = human_date(release["published"], lang)
    for key in ("deb", "rpm", "arch", "src", "sums"):
        values[key + "_size"] = human_size(release[key + "_size"], lang)

    def replace(match):
        name = match.group(1)
        if name.startswith("t."):
            if name[2:] not in strings:
                fail(f"missing translation '{name[2:]}' for {lang}")
            return html.escape(strings[name[2:]])
        if name.startswith("r."):
            if name[2:] not in values:
                fail(f"unknown release field '{name[2:]}'")
            return html.escape(str(values[name[2:]]))
        if name not in fields:
            fail(f"unknown placeholder '{name}'")
        return fields[name] if name == "auto_language_script" else html.escape(fields[name])

    page = re.sub(r"\{\{([a-z_.0-9]+)\}\}", replace, template)
    if "{{" in page:
        fail("unreplaced placeholder left in the page")
    if re.search(r'href=""', page):
        fail("empty link in the page")
    return page


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--repo", help="owner/name: read the latest release from the GitHub API")
    source.add_argument("--release-json", type=Path, help="release JSON file (API shape)")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    release_json = json.loads(args.release_json.read_text()) if args.release_json else fetch_release(args.repo)
    release = release_values(release_json, args.repo or "vovche/rigs")

    template = (SITE / "template.html").read_text()
    translations = {lang: json.loads((SITE / "i18n" / f"{lang}.json").read_text()) for lang in LANGS}
    keys = {lang: set(strings) for lang, strings in translations.items()}
    if keys["en"] != keys["uk"]:
        fail(f"translation keys differ: only en {sorted(keys['en'] - keys['uk'])}, only uk {sorted(keys['uk'] - keys['en'])}")
    used = set(re.findall(r"\{\{t\.([a-z_0-9]+)\}\}", template))
    if used - keys["en"] or keys["en"] - used:
        fail(f"template/translation mismatch: missing {sorted(used - keys['en'])}, unused {sorted(keys['en'] - used)}")

    if args.out.exists():
        shutil.rmtree(args.out)
    for lang, path in LANGS.items():
        target = args.out / path
        target.mkdir(parents=True, exist_ok=True)
        (target / "index.html").write_text(render(template, translations[lang], release, lang))
    for name in ("style.css", "site.js"):
        shutil.copy(SITE / name, args.out / name)
    icons = ROOT / "data" / "icons" / "hicolor"
    shutil.copy(icons / "scalable/apps/io.github.vovche.Rigs.svg", args.out / "icon.svg")
    shutil.copy(icons / "symbolic/apps/io.github.vovche.Rigs-symbolic.svg", args.out / "icon-symbolic.svg")
    shutil.copy(icons / "512x512/apps/io.github.vovche.Rigs.png", args.out / "icon-512.png")
    (args.out / ".nojekyll").write_text("")
    print(f"site for Rigs {release['version']} written to {args.out}")


if __name__ == "__main__":
    main()
