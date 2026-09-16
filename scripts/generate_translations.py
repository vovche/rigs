#!/usr/bin/env python3
import os
import re
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SCRIPT_DIR)
POT_FILE = os.path.join(REPO_DIR, "po", "rigs.pot")
PO_DIR = os.path.join(REPO_DIR, "po")

# Load existing translations dictionary
with open(os.path.join(SCRIPT_DIR, "generate_translations.py"), "r", encoding="utf-8") as f:
    text = f.read()

# Import LANGUAGES from previous script definition
# We will define the full LANGUAGES dict directly
from translation_data import LANGUAGES

# 1. First generate POT using xgettext if not present or to ensure freshness
subprocess.run([
    "xgettext", "--from-code=UTF-8", "--keyword=_", "--keyword=N_",
    "-o", POT_FILE,
    os.path.join(REPO_DIR, "src", "main.vala"),
    os.path.join(REPO_DIR, "src", "application.vala"),
    os.path.join(REPO_DIR, "src", "window.vala"),
    os.path.join(REPO_DIR, "src", "vm_card.vala"),
    os.path.join(REPO_DIR, "src", "add_dialog.vala"),
], check=True)

with open(POT_FILE, "r", encoding="utf-8") as f:
    pot_raw = f.read()

def parse_blocks(content):
    # Split blocks by double newlines or comments
    raw_blocks = content.split("\n\n")
    return raw_blocks

def extract_msgid(block):
    lines = block.split("\n")
    in_msgid = False
    msgid_parts = []
    for line in lines:
        if line.startswith("msgid "):
            in_msgid = True
            val = line[6:].strip()
            if val.startswith('"') and val.endswith('"'):
                msgid_parts.append(val[1:-1])
        elif in_msgid:
            if line.startswith('"') and line.endswith('"'):
                msgid_parts.append(line[1:-1])
            elif line.startswith("msgstr"):
                break
    return "".join(msgid_parts).replace('\\"', '"').replace('\\n', '\n')

for lang_code, lang_data in LANGUAGES.items():
    trans = lang_data["strings"]
    plural = lang_data["plural"]
    lang_name = lang_data["name"]

    po_file = os.path.join(PO_DIR, f"{lang_code}.po")

    # Run msginit
    cmd = ["msginit", "--no-translator", f"--locale={lang_code}.UTF-8", f"--input={POT_FILE}", f"--output-file={po_file}"]
    subprocess.run(cmd, check=True)

    with open(po_file, "r", encoding="utf-8") as f:
        po_content = f.read()

    blocks = po_content.split("\n\n")
    new_blocks = []

    for block in blocks:
        if not block.strip():
            continue
        # Header block
        if 'msgid ""\nmsgstr ""' in block:
            header = block.replace("#, fuzzy\n", "")
            header = header.replace('"Project-Id-Version: PACKAGE VERSION\\n"', '"Project-Id-Version: Rigs 1.0.0\\n"')
            # Ensure Language and Plural-Forms are correct
            if "Plural-Forms:" in header:
                header = re.sub(r'"Plural-Forms:[^"]*"', lambda m: f'"Plural-Forms: {plural}\\n"', header)
            else:
                header = header.replace('"Content-Transfer-Encoding: 8bit\\n"\n', f'"Content-Transfer-Encoding: 8bit\\n"\n"Plural-Forms: {plural}\\n"\n')
            new_blocks.append(header)
            continue

        msgid = extract_msgid(block)
        if msgid in trans and trans[msgid]:
            translation = trans[msgid]
            escaped_trans = translation.replace('\\', '\\\\').replace('"', '\\"')

            # Replace msgstr "" with translated msgstr
            # Note: handle both 'msgstr ""' at end of block
            if 'msgstr ""' in block:
                block_updated = block.replace('msgstr ""', f'msgstr "{escaped_trans}"')
                block_updated = block_updated.replace("#, fuzzy\n", "")
                new_blocks.append(block_updated)
            else:
                new_blocks.append(block)
        else:
            new_blocks.append(block)

    with open(po_file, "w", encoding="utf-8") as f:
        f.write("\n\n".join(new_blocks) + "\n")

    # Validate with msgfmt
    res = subprocess.run(["msgfmt", "-c", "-v", "-o", "/dev/null", po_file], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error compiling {lang_code}.po: {res.stderr}")
    else:
        print(f"[{lang_code}] {lang_name}: {res.stderr.strip()}")

print("Translation generation and validation complete!")
