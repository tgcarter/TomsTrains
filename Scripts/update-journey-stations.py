#!/usr/bin/env python3
"""Build the CRS-to-stop-ID lookup from stops.txt in the Transitous National Rail GTFS feed."""

import argparse
import csv
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stops", type=Path, help="stops.txt extracted from gb_national-rail.gtfs.zip")
    args = parser.parse_args()
    station_ids = {}
    with args.stops.open(encoding="utf-8-sig", newline="") as source:
        for stop in csv.DictReader(source):
            code = stop["stop_code"]
            stop_id = stop["stop_id"]
            if stop["location_type"] != "1" or not stop_id.startswith("910G") or not re.fullmatch("[A-Z]{3}", code):
                continue
            if code in station_ids:
                raise ValueError(f"Multiple station IDs for {code}")
            station_ids[code] = stop_id

    if len(station_ids) < 2500:
        raise ValueError("The feed did not supply enough station identifiers.")
    destination = Path(__file__).resolve().parents[1] / "TomsTrains/Plan/JourneyStationIDs.json"
    destination.write_text(json.dumps(station_ids, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
