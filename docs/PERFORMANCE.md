# Performance

This page records periodic performance snapshots of the primary TrueNAS server (svlnas — Intel Core i3-9100, 4C/4T, 64 GB ECC RAM; full specs in [Infrastructure](INFRASTRUCTURE.md)). It exists as a baseline and historical log so trends can be spotted over time: each reporting period is captured as a dated subsection under [Snapshots](#snapshots), and new periods are appended without rewriting older entries.

## How to Read the Numbers

The figures below are min / mean / max aggregates collected over the reporting period.

<!-- dprint-ignore -->
!!! tip "Judge load average against 4 cores"
    Linux load average represents the number of processes runnable or waiting on I/O — it is **not** a percentage. On this 4-core / 4-thread CPU, the saturation point is **4.0**, not `1.0`. A load of `1.24` means roughly 31% of total CPU capacity is in use on average, with comfortable headroom. Only sustained values above `4.0` indicate the machine is consistently oversubscribed.

When interpreting a snapshot:

- **Load average** — Compare the mean against the core count (4). Brief short-term (1m) spikes above 4 are normal and self-clearing; what matters is whether the long-term (15m) figure stays below 4, which signals no persistent backlog.
- **CPU usage** — Reported as a percentage (0–100% per core). A non-zero idle floor is expected on this box: ZFS ARC and scrub housekeeping plus the always-on container stack (Traefik, AdGuard, Plex/arr suite, Immich, etc.) idle-poll continuously.
- **Per-core balance** — Near-identical min/mean/max across cores indicates the scheduler is spreading work evenly and there is no single-threaded bottleneck.

## Snapshots

Snapshots are listed newest first. Each entry covers a fixed reporting period and includes the raw aggregates plus a short interpretation.

### 2026-06-06 → 2026-06-13 (1 week)

**Period:** 2026-06-06 14:53:30 → 2026-06-13 14:53:30

#### Load average

| Window          | Max  | Mean | Min  |
| --------------- | ---- | ---- | ---- |
| Short term (1m) | 5.48 | 1.24 | 0.37 |
| Mid term (5m)   | 4.07 | 1.24 | 0.65 |
| Long term (15m) | 2.98 | 1.22 | 0.80 |

#### CPU usage (%)

| Core            | Max  | Mean | Min  |
| --------------- | ---- | ---- | ---- |
| cpu (aggregate) | 41.9 | 18.8 | 16.0 |
| cpu0            | 40.2 | 18.7 | 15.5 |
| cpu1            | 40.3 | 18.6 | 15.4 |
| cpu2            | 40.6 | 18.6 | 15.5 |
| cpu3            | 44.4 | 19.0 | 15.4 |

#### CPU temperature (°C)

| Core          | Max  | Mean | Min  |
| ------------- | ---- | ---- | ---- |
| cpu (package) | 42.8 | 38.5 | 37.0 |
| cpu0          | 42.3 | 37.6 | 36.3 |
| cpu1          | 44.6 | 40.2 | 38.5 |
| cpu2          | 43.4 | 39.0 | 37.4 |
| cpu3          | 43.0 | 38.7 | 36.9 |

#### Interpretation

Load average (against 4 cores):

- A mean of ~1.24 across all three windows is roughly 31% of total CPU capacity — comfortable headroom, far from saturation.
- The short-term max of 5.48 briefly exceeds 4 cores (~137%, a handful of queued processes), but it is a momentary spike that does not propagate into the longer windows.
- The long-term max of 2.98 stays below 4, so even sustained busy periods remain under full capacity with no persistent backlog.
- The near-identical mean across the short, mid, and long windows points to a steady, predictable workload with no creeping upward trend.

CPU usage:

- A mean of ~18.8% with peaks around 42% is a light-to-moderate load with plenty of idle headroom.
- The ~16% floor even at idle is normal for this box: ZFS ARC/scrub housekeeping plus the always-on container stack idle-polling.
- Load is spread evenly across all four cores (near-identical per-core max/mean/min), indicating good scheduler balancing and no single-threaded bottleneck.

CPU temperature:

- A package mean of ~38.5 °C with a peak of 42.8 °C is excellent for the passively/fanless-cooled Arctic Alpine 12 — well below the i3-9100's ~100 °C T_JMAX and miles from any thermal-throttling threshold.
- The ~37 °C idle floor and tight ~6 °C spread between idle and peak confirm the cooler comfortably dissipates this workload with no thermal stress.
- Per-core temperatures track closely (within ~2–3 °C), consistent with the evenly balanced CPU load and good case airflow from the Noctua/Scythe fans.

**Verdict:** The system sits well within its envelope — averaging around 30% of capacity with brief, self-clearing spikes. That headroom matters for a passively/fanless-cooled build's thermals. Worth watching whether the short-term load max climbs week-over-week (for example, Immich ML jobs or media transcodes coinciding with ZFS scrubs), but a one-off 5.48 against a 1.22 long-term mean is a non-issue.
