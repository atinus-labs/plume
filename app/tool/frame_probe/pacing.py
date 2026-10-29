"""Compares the frames Flutter produced with the frames that reached the
screen, for a run of tool/frame_probe/main.dart under WAYLAND_DEBUG=client.

    python3 tool/frame_probe/pacing.py <probe stdout> <wayland log> [refresh Hz]

GTK 3 asks for no frame callbacks or presentation feedback, so the screen side
comes from the window's own surface commits: each commit hands the compositor
one new frame. Commits about one refresh apart look smooth; a longer gap means
the screen showed the same frame again (a hitch), and two commits within half
a refresh mean one of them was most likely never seen.

In idle mode it only counts frames: an idle window should draw none.
"""

import datetime
import json
import re
import sys


def load_probe(path):
    for line in open(path, errors="replace"):
        if "PROBE " in line:
            return json.loads(line.split("PROBE ", 1)[1])
    sys.exit(f"no PROBE line in {path}")


def seconds_of_day(wall_us):
    d = datetime.datetime.fromtimestamp(wall_us / 1e6, datetime.timezone.utc)
    return d.hour * 3600 + d.minute * 60 + d.second + d.microsecond / 1e6


def stats(xs):
    xs = sorted(xs)
    return f"avg {sum(xs) / len(xs):5.2f}  p90 {xs[9 * len(xs) // 10]:5.2f}  max {xs[-1]:5.2f} ms"


def main():
    probe = load_probe(sys.argv[1])
    hz = float(sys.argv[3]) if len(sys.argv) > 3 else probe["refreshRate"]
    period = 1 / hz
    start = seconds_of_day(probe["startWallUs"])
    # The probe keeps rendering for a moment after it stops recording.
    end = seconds_of_day(probe["endWallUs"]) - 0.3
    secs = end - start

    # libwayland (1.23+) stamps lines with the UTC time of day.
    line = re.compile(
        r"\[(\d\d):(\d\d):(\d\d\.\d+)\] \{mesa egl surface queue\}\s*->\s*wl_surface#\d+\.commit"
    )
    commits = []
    for text in open(sys.argv[2], errors="replace"):
        m = line.search(text)
        if m:
            t = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
            if start <= t <= end:
                commits.append(t)
    frames = probe["frames"]
    if probe["mode"] == "idle":
        print(f"idle: {secs:.1f} s")
        print(f"  Flutter produced      {len(frames)} frames, "
              f"{len(commits)} reached the compositor")
        return
    if len(commits) < 2:
        sys.exit("no commits in the measured window; was WAYLAND_DEBUG=client set?")
    gaps = [(b - a) / period for a, b in zip(commits, commits[1:])]
    steady = sum(1 for g in gaps if 0.5 <= g <= 1.5)
    repeats = sum(round(g) - 1 for g in gaps if g > 1.5)
    overwritten = sum(1 for g in gaps if g < 0.5)

    skipped = sum(1 for a, b in zip(frames, frames[1:]) if b[0] - a[0] > 1.5e6 / hz)

    print(f"{probe['mode']}: {secs:.1f} s at {hz:.2f} Hz")
    print(f"  Flutter produced      {len(frames) / (secs + 0.3):5.1f} frames/s, "
          f"{skipped} vsync ticks skipped")
    print(f"  frames to compositor  {len(commits) / secs:5.1f} /s, "
          f"{100 * steady / len(gaps):.1f}% one refresh apart")
    print(f"  hitches               {repeats} refreshes repeated a frame, "
          f"{overwritten} frames overwritten")
    print(f"  vsync -> build start  {stats([(f[1] - f[0]) / 1e3 for f in frames])}")
    print(f"  build                 {stats([(f[2] - f[1]) / 1e3 for f in frames])}")
    print(f"  raster                {stats([(f[4] - f[3]) / 1e3 for f in frames])}")


main()
