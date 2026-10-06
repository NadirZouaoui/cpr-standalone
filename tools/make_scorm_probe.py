#!/usr/bin/env python3
"""Build a tiny SCORM 1.2 package that is structurally identical to the real one.

Diagnostic only - it teaches nothing. Its whole job is to answer one question
when an LMS refuses the real package: is the refusal about the SIZE of the
upload, or about its SHAPE?

Same schemaversion, same identifiers, same flat archive layout, same single
SCO at index.html, same pipwerks wrapper, same LMSInitialize/LMSFinish
handshake. The only difference is that it weighs kilobytes instead of tens of
megabytes, because the 39 MB wasm and 68 MB pck are replaced by a page that
says hello.

So:
  - probe uploads, real package does not  -> a size or upload-timeout limit,
    and the fix is a smaller build (or the LMS raising the cap).
  - probe is refused too                  -> the manifest or the archive shape
    is what the importer objects to, and the size is a red herring.

Usage, from the project root:

    python tools/make_scorm_probe.py

Writes build/LVR_CPR_SCORM12_probe.zip. Hand that to whoever is doing the
upload and ask which of the two outcomes they get.
"""

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WRAPPER = ROOT / "scorm" / "vendor" / "SCORM_API_wrapper.js"
OUT = ROOT / "build" / "LVR_CPR_SCORM12_probe.zip"

MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest identifier="LVR_CPR_MANIFEST" version="1.0"
\txmlns="http://www.imsproject.org/xsd/imscp_rootv1p1p2"
\txmlns:adlcp="http://www.adlnet.org/xsd/adlcp_rootv1p2"
\txmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
\txsi:schemaLocation="http://www.imsproject.org/xsd/imscp_rootv1p1p2 imscp_rootv1p1p2.xsd
\t\thttp://www.imsglobal.org/xsd/imsmd_rootv1p2p1 imsmd_rootv1p2p1.xsd
\t\thttp://www.adlnet.org/xsd/adlcp_rootv1p2 adlcp_rootv1p2.xsd">

\t<metadata>
\t\t<schema>ADL SCORM</schema>
\t\t<schemaversion>1.2</schemaversion>
\t</metadata>

\t<organizations default="LVR_CPR_ORG">
\t\t<organization identifier="LVR_CPR_ORG">
\t\t\t<title>Low Voltage Rescue and CPR (upload probe)</title>
\t\t\t<item identifier="LVR_CPR_ITEM" identifierref="LVR_CPR_RES" isvisible="true">
\t\t\t\t<title>Low Voltage Rescue and CPR (upload probe)</title>
\t\t\t</item>
\t\t</organization>
\t</organizations>

\t<resources>
\t\t<resource identifier="LVR_CPR_RES" type="webcontent"
\t\t\tadlcp:scormtype="sco" href="index.html">
\t\t\t<file href="index.html"/>
\t\t\t<file href="SCORM_API_wrapper.js"/>
\t\t</resource>
\t</resources>
</manifest>
"""

PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>LVR CPR upload probe</title>
<script src="SCORM_API_wrapper.js"></script>
</head>
<body style="font:16px/1.5 sans-serif;max-width:34em;margin:4em auto">
<h1>Upload probe</h1>
<p id="state">Looking for the LMS...</p>
<p>This package carries no course. It exists to prove that a package with
this manifest and this archive layout can be imported at all.</p>
<script>
pipwerks.SCORM.version = "1.2";
pipwerks.SCORM.handleExitMode = false;
var ok = pipwerks.SCORM.init();
document.getElementById("state").textContent = ok
\t? "Connected. The LMS accepted this package and the SCO reached the API."
\t: "No LMS API found. The package imported, but this page is not running inside an LMS.";
if (ok) {
\tpipwerks.SCORM.set("cmi.core.lesson_status", "completed");
\tpipwerks.SCORM.set("cmi.core.session_time", "0000:00:01.00");
\tpipwerks.SCORM.quit();
}
</script>
</body>
</html>
"""


def main() -> int:
    if not WRAPPER.is_file():
        print("missing %s" % WRAPPER, file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        z.writestr("imsmanifest.xml", MANIFEST)
        z.writestr("index.html", PAGE)
        z.write(WRAPPER, arcname="SCORM_API_wrapper.js")
    print("%s  (%.1f KB)" % (OUT, OUT.stat().st_size / 1024))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
