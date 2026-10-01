#!/usr/bin/env python3
"""Render dashboard preview charts (SVG only) from the KPI tables exported by run_pipeline.py."""
import json, pathlib, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from svgmin import minify_svg

plt.rcParams.update({"svg.fonttype": "none", "font.family": "sans-serif", "font.size": 9,
                     "axes.spines.top": False, "axes.spines.right": False, "axes.grid": False})
C1, C2, C3 = "#1f6f8b", "#e07a5f", "#81b29a"


def save(fig, path):
    import io
    buf = io.StringIO(); fig.savefig(buf, format="svg", bbox_inches="tight"); plt.close(fig)
    path.write_text(minify_svg(buf.getvalue()))


def p_monthly(ax, t):
    m = pd.read_csv(t / "a_monthly_revenue.csv"); lab = m.month_start.str[:7]
    ax.bar(range(len(m)), m.gmv_brl / 1e6, color=C1)
    ax.set_xticks(range(0, len(m), 3)); ax.set_xticklabels(lab[::3], rotation=45, ha="right")
    ax.set_ylabel("GMV (BRL m)"); ax.set_title("Monthly GMV and AOV (2017-01..2018-08)")
    a2 = ax.twinx(); a2.plot(range(len(m)), m.aov_brl, color=C2, marker="o", ms=3); a2.set_ylabel("AOV (BRL)", color=C2)
    a2.set_ylim(0, m.aov_brl.max() * 1.3); a2.spines["top"].set_visible(False)


def p_delivery(ax, t):
    d = pd.read_csv(t / "a_delivery_vs_review.csv").sort_values("delivery_bucket")
    lab = d.delivery_bucket.str[4:]
    ax.bar(lab, d.avg_review, color=C1); ax.set_ylim(0, 5.4); ax.set_ylabel("avg review (1-5)")
    for i, (v, lp) in enumerate(zip(d.avg_review, d.low_review_pct)):
        ax.text(i, v + 0.05, f"{v:.2f}\n{lp:.0f}% low", ha="center", fontsize=7)
    ax.set_title("Delivery time vs review score"); ax.set_xlabel("days from purchase to delivery")


def p_category(ax, t):
    c = pd.read_csv(t / "a_category_performance.csv").sort_values("gmv_rank").head(10)[::-1]
    ax.barh(c.category_en, c.gmv_brl / 1e6, color=C3)
    for i, (v, r) in enumerate(zip(c.gmv_brl / 1e6, c.avg_review)):
        ax.text(v, i, f" {v:.2f}m | {r:.2f}*", va="center", fontsize=7)
    ax.set_xlabel("GMV (BRL m)"); ax.set_title("Top 10 categories by GMV (label: GMV | avg review)")
    ax.set_xlim(0, c.gmv_brl.max() / 1e6 * 1.45)


def p_state(ax, t):
    s = pd.read_csv(t / "a_region_performance.csv").sort_values("gmv_brl", ascending=False).head(12)
    ax.bar(s.customer_state, s.gmv_brl / 1e6, color=C1); ax.set_ylabel("GMV (BRL m)")
    a2 = ax.twinx(); a2.plot(s.customer_state, s.avg_delivery_days, color=C2, marker="o", ms=3)
    a2.set_ylabel("avg delivery days", color=C2); a2.set_ylim(0, s.avg_delivery_days.max() * 1.3)
    a2.spines["top"].set_visible(False); ax.set_title("Top 12 customer states: GMV vs delivery days")


def p_cohort(ax, t):
    c = pd.read_csv(t / "a_cohort_retention.csv")
    c = c[(c.month_number >= 1) & (c.month_number <= 6)]
    pv = c.pivot(index="cohort_month", columns="month_number", values="retention_pct").sort_index()
    # vector heatmap (pcolormesh + 8-step BoundaryNorm) so the SVG has no embedded PNG
    import numpy as np
    from matplotlib.colors import BoundaryNorm
    bounds = np.arange(0, np.ceil(np.nanmax(pv.values) * 10) / 10 + 0.05, 0.1)
    im = ax.pcolormesh(np.arange(pv.shape[1] + 1) - 0.5, np.arange(len(pv) + 1) - 0.5, pv.values,
                       cmap="Blues", norm=BoundaryNorm(bounds, 256))
    ax.set_xlim(-0.5, pv.shape[1] - 0.5); ax.set_ylim(len(pv) - 0.5, -0.5)
    ax.set_xticks(range(pv.shape[1])); ax.set_xticklabels([f"M+{i}" for i in pv.columns])
    ax.set_yticks(range(0, len(pv), 2)); ax.set_yticklabels(pv.index.str[:7][::2])
    plt.colorbar(im, ax=ax, label="% of cohort active")
    ax.set_title("Cohort retention (% of first-month buyers buying again)")


def p_payment(ax, t):
    p = pd.read_csv(t / "a_payment_mix.csv").sort_values("orders", ascending=False)
    ax.bar(p.main_payment_type, p.orders_share_pct, color=[C1, C2, C3, "#999"][: len(p)])
    for i, (v, inst) in enumerate(zip(p.orders_share_pct, p.avg_installments)):
        ax.text(i, v + 1, f"{v:.1f}%\n{inst:.1f} inst.", ha="center", fontsize=7)
    ax.set_ylabel("% of orders"); ax.set_ylim(0, 100); ax.set_title("Payment mix (main payment type)")


PANELS = [("monthly_gmv_aov", p_monthly), ("delivery_vs_review", p_delivery), ("category_top10", p_category),
          ("state_gmv_delivery", p_state), ("cohort_retention", p_cohort), ("payment_mix", p_payment)]


def make_all(tables, out):
    tables, out = pathlib.Path(tables), pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    for name, fn in PANELS:
        fig, ax = plt.subplots(figsize=(6.4, 3.6)); fn(ax, tables); save(fig, out / f"{name}.svg")
    k = pd.read_csv(tables / "a_kpi_headline.csv").iloc[0]
    fig, axes = plt.subplots(3, 2, figsize=(14, 13.5)); fig.subplots_adjust(hspace=0.55, wspace=0.35, top=0.88)
    for ax, (_, fn) in zip(axes.flat, PANELS):
        fn(ax, tables)
    cards = [("GMV", f"R$ {k.gmv_brl/1e6:.2f}m"), ("Orders", f"{int(k.revenue_orders):,}"), ("AOV", f"R$ {k.aov_brl:.2f}"),
             ("Customers", f"{int(k.unique_customers):,}"), ("Repeat", f"{k.repeat_customer_pct:.2f}%"),
             ("Avg review", f"{k.avg_review_score:.2f}"), ("Late", f"{k.late_delivery_pct:.2f}%")]
    fig.suptitle("Olist e-commerce sales dashboard (preview rendered from SQL outputs)", fontsize=14, y=0.975)
    for i, (lab, val) in enumerate(cards):
        x = 0.07 + i * 0.135
        fig.text(x, 0.935, val, fontsize=13, weight="bold", ha="center", color=C1)
        fig.text(x, 0.918, lab, fontsize=9, ha="center", color="#555")
    save(fig, out / "dashboard.svg")
    print("charts ->", out, sorted(p.name for p in out.glob("*.svg")))


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/charts")
