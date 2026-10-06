#!/usr/bin/env python3
"""Assemble the SCORM 1.2 package from the Web export.

Godot's Web preset drops a bare index.html set into build/scorm_build and
knows nothing about SCORM, so three things have to happen after it:

  1. imsmanifest.xml goes in beside the export. Without it an LMS rejects the
     zip outright - it is the only thing that makes the folder a course.
  2. SCORM_API_wrapper.js goes in too. scorm_shell.html loads it in <head>
     and scripts/core/lms.gd calls pipwerks.SCORM.* through JavaScriptBridge.
     It is third-party (pipwerks, MIT) and IS vendored, at
     scorm/vendor/SCORM_API_wrapper.js, because the failure mode when it is
     missing is silent: the shell guards on `typeof pipwerks !== 'undefined'`,
     so a package built without it still runs and still plays and simply
     tells the LMS nothing at all. That shipped once. The absent-wrapper
     branch below is kept as a loud diagnostic, not as a supported build.
  3. The whole folder is zipped with the manifest at the ROOT of the archive,
     not inside a top-level directory. This is the single most common way to
     get a "manifest not found" from an LMS.

scorm/imsmanifest.xml is deliberately a near-copy of the one in the 3D
Substation package, which the client's LMS (Cloud Assess) imported without
complaint at 147 MB. Ours, at 58 MB, it refused - so the refusal was never
about size, and the manifest was the only other thing that differed. The two
files now differ only in their identifiers and titles.

That means the manifest keeps three things that look wrong and are not
mistakes to "fix":

  - The adlcp namespace is adlcp_v1p3, SCORM 2004's, beside a schemaversion
    of 1.2. Mismatched on paper. It is what the accepted package carries, and
    importers key off schemaversion, so it stays until something proves
    otherwise.
  - <resource> declares only index.html and SCORM_API_wrapper.js, not the
    wasm, the pck, the worklets or the icons. Undeclared files that are
    present in the archive are tolerated everywhere; declared files that are
    absent are not. The accepted package declares two, so ours declares two.
  - There are no XML comments in it, and no encoding attribute. A comment
    between the declaration and the root element is legal XML that a
    hand-rolled importer can still trip over, and this file is not the place
    to find out. The reasoning lives here instead.

Usage, from the project root:

    "C:/Program Files/Godot.exe" --headless --path . --export-release index build/scorm_build/index.html
    python tools/make_scorm.py

The loose export files stay in build/scorm_build so that build/ itself holds
only the two things anyone ships: the .exe and the .zip.

build/.gdignore is not optional, and it covers this subfolder too - Godot skips
a .gdignore'd directory and everything under it. Without it Godot walks a tree
holding a 260 MB PCK, a 39 MB wasm and a 370 MB exe on every filesystem scan,
and can fold the last build into the next export's PCK.

build/scorm_build must EXIST before the export runs. Godot does not create its
target folder - it stops with "Target folder does not exist or is inaccessible"
and writes nothing. That is why build/scorm_build/.gitkeep is tracked.
"""

import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "scorm_build"
MANIFEST = ROOT / "scorm" / "imsmanifest.xml"
WRAPPER = ROOT / "scorm" / "vendor" / "SCORM_API_wrapper.js"
OUT = ROOT / "build" / "LVR_CPR_SCORM12.zip"

# Written by the export. A missing one of these means the export did not run,
# or ran into a different folder than the preset's export_path.
EXPORTED = [
    "index.html",
    "index.js",
    "index.wasm",
    "index.pck",
    "index.audio.worklet.js",
    "index.audio.position.worklet.js",
    "index.png",
    "index.icon.png",
    "index.apple-touch-icon.png",
]


def main() -> int:
    if not BUILD.is_dir():
        print("no %s - run the Web export first" % BUILD, file=sys.stderr)
        return 1

    missing = [n for n in EXPORTED if not (BUILD / n).is_file()]
    if missing:
        print("export incomplete, missing: %s" % ", ".join(missing), file=sys.stderr)
        return 1

    reporting = WRAPPER.is_file()
    if reporting:
        shutil.copy2(WRAPPER, BUILD / "SCORM_API_wrapper.js")
        print("+ SCORM_API_wrapper.js")
    else:
        print("! %s absent - packaging WITHOUT SCORM reporting" % WRAPPER)
        print("! the exercise will run and will report nothing to the LMS")

    # A <file> the archive does not contain is a validator error on some LMSes
    # and a silent 404 on the rest, so the declaration follows what is
    # actually bundled rather than what the manifest wishes were there.
    manifest = MANIFEST.read_text(encoding="utf-8")
    if not reporting:
        manifest = "".join(
            ln for ln in manifest.splitlines(keepends=True)
            if "SCORM_API_wrapper.js" not in ln
        )
    (BUILD / "imsmanifest.xml").write_text(manifest, encoding="utf-8")
    print("+ imsmanifest.xml")

    # Manifest first, then the rest in name order - the layout of the package
    # this one is modelled on. An importer has no business caring about entry
    # order, but matching costs nothing and removes one more difference.
    rest = list(EXPORTED)
    if reporting:
        rest.append("SCORM_API_wrapper.js")
    names = ["imsmanifest.xml"] + sorted(rest, key=str.lower)

    # Everything deflates, the .pck and .wasm included. The ZIP_STORED shortcut
    # that used to live here assumed both were already compressed; measured,
    # they are not - the wasm gives up most of its size and the pck a third.
    # It costs a minute at packaging, and only there: the LMS unzips once on
    # install, so it is the upload that shrinks, not the learner's download.
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name in names:
            src = BUILD / name
            z.write(src, arcname=name)
            print("  %-34s %9.1f MB" % (name, src.stat().st_size / 1e6))

    print("\n%s  (%.1f MB)" % (OUT, OUT.stat().st_size / 1e6))
    if not reporting:
        print("NO SCORM REPORTING IN THIS PACKAGE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
