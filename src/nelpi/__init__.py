import importlib.resources as resources
import json
from glob import glob
from re import match


def main() -> None:
    datasets = glob(str(resources.files(__name__) / "datasets/*.json"))
    entries = []

    for path in datasets:
        # fmt: off
        name = match(r".*/([^/]+)\.json$", path)[1] # pyright: ignore[reportOptionalSubscript]
        # fmt: on

        data = json.load(open(path, "r"))
        entries += data
        print(f"Loaded {len(data)} entries from dataset '{name}'!")

    print(f"{len(entries)} entries in total!")
    # TODO topic identification!
