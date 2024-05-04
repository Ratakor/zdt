# -*- coding: utf-8 -*-
#!/usr/bin/env python3
#
# ADAPTED FROM https://raw.githubusercontent.com/regebro/tzlocal/master/update_windows_mappings.py
#
# This script generates the mapping between MS Windows timezone names and
# tzdata/Olsen timezone names, by retrieving a file:
# http://unicode.org/cldr/data/common/supplemental/supplementalData.xml
# and parsing it, and from this generating the file windows_tz.zig.

# import ftplib
from datetime import datetime, timezone
import logging

# import tarfile
# from io import BytesIO
from pathlib import Path

# from pprint import pprint
# from urllib.parse import urlparse
from urllib.request import urlopen
from xml.dom import minidom

WIN_ZONES_URL = "https://raw.githubusercontent.com/unicode-org/cldr/master/common/supplemental/windowsZones.xml"
ZONEINFO_URL = "ftp://ftp.iana.org/tz/tzdata-latest.tar.gz"

dst = Path("../lib/windows/windows_tznames.zig")

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("tznames")


def update_windows_zones():
    # backward = update_old_names()

    log.info("Fetching Windows mapping info from unicode.org")
    source = urlopen(WIN_ZONES_URL).read()
    dom = minidom.parseString(source)

    for element in dom.getElementsByTagName("mapTimezones"):
        if element.getAttribute("type") == "windows":
            break

    log.info("Making windows mapping")
    win_tz = {}

    for mapping in element.getElementsByTagName("mapZone"):  # NodeList[Element]
        if mapping.getAttribute("territory") == "001":
            win_tz[mapping.getAttribute("other")] = mapping.getAttribute("type").split(
                " "
            )[0]
            if win_tz[mapping.getAttribute("other")].startswith("Etc"):
                print(
                    win_tz[mapping.getAttribute("other")],
                    mapping.getAttribute("type").split(" ")[0],
                )

    # sort win_tz for binary search by key
    win_tz = dict(sorted(win_tz.items()))

    log.info("Writing mapping")
    with open(dst, "w") as out:
        out.write(
            "//! A mapping of Windows time zone names to IANA db identifiers.\n"
            "// This file is autogenerated by generate_wintz_mapping.py;\n"
            "//\n"
            "// --- Do not edit ---\n"
            "//\n"
            f"// latest referesh: {datetime.now(timezone.utc).isoformat(timespec='seconds')}\n"
            "// windows_names are sorted alphabetically so we can do binary search (later)\n"
            "pub const windows_names = [_][]const u8{\n"
        )
        for k in win_tz:
            out.write(f'    "{k}",\n')
        out.write("};\n\n")

        out.write("pub const iana_names = [_][]const u8{\n")
        for k in win_tz.values():
            out.write(f'    "{k}",\n')

        out.write("};\n")

    log.info("Done")


if __name__ == "__main__":
    update_windows_zones()
