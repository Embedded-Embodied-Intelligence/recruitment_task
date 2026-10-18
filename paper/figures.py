"""Figure 2 of the paper: the two quiet traps of v5, drawn from the published files only.

    python paper/figures.py      # writes paper/fig_quiet_traps.png
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#e4e3df"
SERIES, HIGHLIGHT = "#2a78d6", "#eb6834"   # categorical slots 1 and 2 of the reference palette

batches = pd.read_csv(ROOT / "data" / "batches.csv")
l2 = batches[batches["line"] == "L2"].drop_duplicates().copy()
l2["date"] = pd.to_datetime(l2["production_date"], format="%Y-%m-%d")
l2 = l2[l2["humidity_pct"] > 0].sort_values("date")
frozen = l2["humidity_pct"] == 50.2

cleanings = pd.read_csv(ROOT / "data" / "maintenance.csv")
l4 = pd.to_datetime(cleanings.query("line == 'L4' and event == 'mold_cleaning'")["date"]).sort_values()
days = pd.date_range("2025-01-01", "2025-09-30")
last = l4.searchsorted(days, side="right") - 1
since = pd.Series([(d - l4.iloc[i]).days if i >= 0 else None for d, i in zip(days, last)], index=days)
gap_start, gap_end = pd.Timestamp("2025-02-10"), pd.Timestamp("2025-04-06")

plt.rcParams.update({"font.family": "Inter", "font.size": 8.5, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "axes.spines.top": False, "axes.spines.right": False})
fig, (a, b) = plt.subplots(1, 2, figsize=(7.0, 2.35), dpi=300, constrained_layout=True)

a.scatter(l2.loc[~frozen, "date"], l2.loc[~frozen, "humidity_pct"], s=3, color=SERIES, linewidths=0, label="valid readings")
a.scatter(l2.loc[frozen, "date"], l2.loc[frozen, "humidity_pct"], s=6, color=HIGHLIGHT, linewidths=0,
          label=f"frozen at 50.2 ({frozen.sum()} readings)")
a.set_title("(a) L2 hall humidity, % (A2, C2)", loc="left", fontsize=9, color=INK)
a.set_ylim(8, 84)
a.legend(frameon=False, loc="upper center", ncol=2, fontsize=7.5, markerscale=2.5, handletextpad=0.3, columnspacing=1.2)

b.plot(since.index, since.values, color=SERIES, linewidth=1.2)
b.axvspan(gap_start, gap_end, color=HIGHLIGHT, alpha=0.18, linewidth=0)
b.axhline(14, color=MUTED, linewidth=0.8, linestyle=(0, (3, 3)))
b.annotate("cleanings done\nbut not logged", xy=(gap_end - pd.Timedelta(days=4), 58), xytext=(gap_end + pd.Timedelta(days=12), 60),
           ha="left", va="center", fontsize=7.5, color=INK, arrowprops={"arrowstyle": "-", "color": MUTED, "linewidth": 0.8})
b.set_title("(b) L4 days since the last logged cleaning (C3)", loc="left", fontsize=9, color=INK)

for ax in (a, b):
    ax.grid(axis="y", color=GRID, linewidth=0.6)
    ax.set_axisbelow(True)
    ax.xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%b"))
fig.savefig(ROOT / "paper" / "fig_quiet_traps.png")
