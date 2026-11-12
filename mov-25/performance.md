# Performance: origin/main 7ed4629 (old look) vs MOV-25 477e7b0 (fitted negative + display floor −6)

`EMULSION_PERF=1 swift test --skip-build --filter PerformanceProbe` on this Mac (14 cores), before and after alternated 5 times. Each cell: median over the 5 runs of the probe's own median, ms; brackets: min–max of the 5. Mac only; no device timing. 7ed4629 has the same tree as 1354a18, and 477e7b0 the same tree as 01bf5e2.

## Run 1 (requested re-time): machine busy

Other sessions were building and testing: 1-minute load average 9.3–22.1 (median 21.7) on 14 cores, CPU 44–61 % idle (`top`, sampled every ~20 s; `/private/tmp/claude-501/-Users-hammad-Documents-Github-emulsion--claude-worktrees-suspicious-mayer-6a7d54/6dc6c6eb-83ea-4d7f-b794-1e746075f853/scratchpad/proof-main/load.txt`). Spreads are wide and several before/after differences flip sign against run 2, so read only the consistent ones.

| Case | runs | before | after | change |
| --- | ---: | ---: | ---: | ---: |
| 1600x1200 display-referred full | 5/5 | 7.7 [4.1–59.4] | 4.6 [4.4–6.6] | -40% |
| 1600x1200 display-referred look only | 5/5 | 2.9 [1.6–4.7] | 1.9 [1.9–3.1] | -34% |
| 1600x1200 full | 5/5 | 7.4 [7.2–9.8] | 8.0 [7.5–10.0] | +8% |
| 1600x1200 look only | 5/5 | 2.8 [2.4–7.4] | 2.9 [2.9–3.7] | +4% |
| 1600x1200 viewfinder full | 5/5 | 7.8 [7.5–10.7] | 7.9 [7.8–28.8] | +1% |
| 1600x1200 viewfinder look only | 5/5 | 2.9 [2.8–4.3] | 2.9 [2.9–3.8] | +0% |
| 1600x1200 viewfinder via per-pixel solve full | 5/5 | 8.0 [6.6–10.3] | 7.9 [6.8–9.7] | -1% |
| 1600x1200 viewfinder via per-pixel solve look only | 5/5 | 5.3 [4.3–8.5] | 5.6 [5.2–7.9] | +6% |
| 4032x3024 display-referred full | 5/5 | 22.0 [17.1–77.8] | 20.2 [18.3–33.3] | -8% |
| 4032x3024 display-referred look only | 5/5 | 7.8 [7.5–17.7] | 8.3 [7.8–14.3] | +6% |
| 4032x3024 full | 5/5 | 23.3 [19.6–33.4] | 19.5 [18.1–53.5] | -16% |
| 4032x3024 look only | 5/5 | 7.8 [7.6–12.0] | 7.5 [7.3–11.2] | -4% |
| 4032x3024 viewfinder full | 5/5 | 20.4 [18.4–23.8] | 19.9 [18.9–25.2] | -2% |
| 4032x3024 viewfinder look only | 5/5 | 6.9 [6.7–11.9] | 7.0 [6.8–26.9] | +1% |
| 4032x3024 viewfinder via per-pixel solve full | 5/5 | 30.0 [28.7–34.9] | 34.0 [32.9–34.6] | +13% |
| 4032x3024 viewfinder via per-pixel solve look only | 5/5 | 17.9 [17.6–21.4] | 22.6 [21.9–26.8] | +26% |
| 8064x6048 display-referred full | 5/5 | 125.5 [86.0–155.9] | 116.7 [98.3–189.7] | -7% |
| 8064x6048 display-referred look only | 5/5 | 49.7 [36.7–53.7] | 41.2 [39.5–72.8] | -17% |
| 8064x6048 full | 5/5 | 108.3 [86.1–205.8] | 91.6 [88.8–170.8] | -15% |
| 8064x6048 look only | 5/5 | 41.6 [30.4–54.7] | 38.3 [34.0–42.7] | -8% |
| 8064x6048 viewfinder full | 5/5 | 101.6 [91.4–189.2] | 101.2 [95.9–194.9] | -0% |
| 8064x6048 viewfinder look only | 5/5 | 45.2 [36.1–67.4] | 44.2 [37.5–61.0] | -2% |
| 8064x6048 viewfinder via per-pixel solve full | 5/5 | 157.3 [143.5–169.2] | 167.6 [167.2–263.4] | +7% |
| 8064x6048 viewfinder via per-pixel solve look only | 5/5 | 84.9 [74.8–103.8] | 99.2 [97.2–121.9] | +17% |

## Run 2 (earlier today, same two trees): load not recorded, spreads narrow

| Case | runs | before | after | change |
| --- | ---: | ---: | ---: | ---: |
| 1600x1200 display-referred full | 5/5 | 3.6 [3.5–10.7] | 3.9 [3.7–4.5] | +8% |
| 1600x1200 display-referred look only | 5/5 | 1.4 [1.3–3.6] | 1.7 [1.5–3.4] | +21% |
| 1600x1200 full | 5/5 | 3.9 [3.5–8.9] | 3.9 [3.8–4.5] | +0% |
| 1600x1200 look only | 5/5 | 2.8 [1.6–2.8] | 2.9 [2.5–2.9] | +4% |
| 1600x1200 viewfinder full | 5/5 | 4.0 [3.5–4.5] | 3.9 [3.5–7.7] | -3% |
| 1600x1200 viewfinder look only | 5/5 | 2.8 [1.7–3.0] | 2.9 [2.6–3.1] | +4% |
| 1600x1200 viewfinder via per-pixel solve full | 5/5 | 4.8 [4.7–4.9] | 5.5 [5.3–5.6] | +15% |
| 1600x1200 viewfinder via per-pixel solve look only | 5/5 | 3.0 [2.9–3.4] | 3.6 [3.6–8.3] | +20% |
| 4032x3024 display-referred full | 5/5 | 19.3 [18.0–20.0] | 19.5 [18.5–20.5] | +1% |
| 4032x3024 display-referred look only | 5/5 | 7.5 [7.3–7.6] | 8.3 [8.0–8.3] | +11% |
| 4032x3024 full | 5/5 | 18.8 [17.0–19.3] | 18.9 [18.2–19.2] | +1% |
| 4032x3024 look only | 5/5 | 6.3 [6.3–6.4] | 6.5 [6.4–6.7] | +3% |
| 4032x3024 viewfinder full | 5/5 | 19.3 [18.4–21.0] | 18.7 [18.0–20.0] | -3% |
| 4032x3024 viewfinder look only | 5/5 | 6.7 [6.5–6.8] | 6.7 [6.7–6.9] | +0% |
| 4032x3024 viewfinder via per-pixel solve full | 5/5 | 29.0 [28.2–55.1] | 32.9 [32.4–35.7] | +13% |
| 4032x3024 viewfinder via per-pixel solve look only | 5/5 | 17.4 [17.4–17.9] | 22.2 [21.8–22.4] | +28% |
| 8064x6048 display-referred full | 5/5 | 93.8 [90.0–97.6] | 94.7 [93.1–95.9] | +1% |
| 8064x6048 display-referred look only | 5/5 | 38.2 [37.3–45.3] | 39.6 [38.1–42.9] | +4% |
| 8064x6048 full | 5/5 | 93.4 [93.0–101.1] | 95.5 [88.9–96.0] | +2% |
| 8064x6048 look only | 5/5 | 39.2 [35.2–49.0] | 37.5 [33.0–41.4] | -4% |
| 8064x6048 viewfinder full | 5/5 | 97.2 [94.4–98.5] | 98.3 [96.5–100.7] | +1% |
| 8064x6048 viewfinder look only | 5/5 | 37.2 [35.8–40.8] | 38.3 [36.8–38.3] | +3% |
| 8064x6048 viewfinder via per-pixel solve full | 5/5 | 145.5 [144.6–150.1] | 168.5 [166.1–172.9] | +16% |
| 8064x6048 viewfinder via per-pixel solve look only | 5/5 | 78.9 [75.3–81.3] | 98.6 [95.0–102.3] | +25% |

Consistent across both runs: look-only, full, display-referred and the 1D-curve viewfinder are within noise (no change beyond run-to-run spread); only the per-pixel-solve viewfinder path, which the app does not use, is slower after (+13–28 %, it inverts the fitted curve per pixel).

Raw lines: `/private/tmp/claude-501/-Users-hammad-Documents-Github-emulsion--claude-worktrees-suspicious-mayer-6a7d54/6dc6c6eb-83ea-4d7f-b794-1e746075f853/scratchpad/proof-main/perf-raw.txt` (run 1), `/private/tmp/claude-501/-Users-hammad-Documents-Github-emulsion--claude-worktrees-suspicious-mayer-6a7d54/6dc6c6eb-83ea-4d7f-b794-1e746075f853/scratchpad/rebase-update/perf-raw.txt` (run 2).
