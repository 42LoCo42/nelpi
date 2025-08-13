#!/usr/bin/env python3
import json
from pathlib import Path

src = Path("raw")
dst = Path("src/nelpi/datasets")


def extract(name: str, keys: list[str], subpath: str | None = None) -> None:
    file = f"{name}.json"
    access = lambda x: x if subpath == None else x[subpath]
    entries = [
        " --- ".join(x for key in keys if (x := entry[key]) != None).strip()
        for entry in access(json.load(open(src / file, "r")))
    ]
    json.dump(entries, open(dst / file, "w"))
    print(f"[1;32mExtracted {len(entries)} entries from dataset '{name}'![m")


extract("berlin", ["betreff", "sachverhalt"], "index")
extract("bonn", ["title", "description"])
extract("dormagen", ["text"])
extract("münster", ["description"])
