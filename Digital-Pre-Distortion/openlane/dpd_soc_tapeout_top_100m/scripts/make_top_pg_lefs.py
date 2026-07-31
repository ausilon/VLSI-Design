#!/usr/bin/env python3
"""Create top-only LEF abstracts with met4-only VPWR/VGND access."""

import sys
from pathlib import Path


def filter_pg_ports(source):
    lines = source.splitlines(keepends=True)
    output = []
    pin = None
    removed = 0
    index = 0
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if stripped in {"PIN VPWR", "PIN VGND"}:
            pin = stripped.split()[1]
        elif pin and stripped == f"END {pin}":
            pin = None

        if pin and stripped == "PORT":
            block = [line]
            index += 1
            while index < len(lines):
                block.append(lines[index])
                if lines[index].startswith("    END"):
                    break
                index += 1
            if any("LAYER met5 ;" in item for item in block):
                removed += 1
            else:
                output.extend(block)
            index += 1
            continue

        output.append(line)
        index += 1
    return "".join(output), removed


def main():
    if len(sys.argv) < 3:
        print("usage: make_top_pg_lefs.py output_dir input.lef...", file=sys.stderr)
        return 2
    output_dir = Path(sys.argv[1])
    output_dir.mkdir(parents=True, exist_ok=True)
    for source_name in sys.argv[2:]:
        source = Path(source_name)
        filtered, removed = filter_pg_ports(source.read_text())
        if removed == 0:
            raise SystemExit(f"{source}: no met5 VPWR/VGND ports found")
        target = output_dir / source.name
        target.write_text(filtered)
        print(f"{target}: removed {removed} met5 PG ports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
