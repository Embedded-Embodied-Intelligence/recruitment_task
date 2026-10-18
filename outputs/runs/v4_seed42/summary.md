# Benchmark results

23 scored runs. Scores are in [0, 1]; sd is the run-to-run standard deviation.

## Total score

| model | variant | count | mean | std | min | max | equal_weights_mean | format_ok | tool_calls_mean | turn_limit_runs |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 5 | 0.879 | 0.067 | 0.808 | 0.947 | 0.881 | 1.000 | 53.800 | 0 |
| claude-haiku | no_quality_hint | 5 | 0.563 | 0.514 | 0.000 | 0.970 | 0.556 | 0.600 | 53.800 | 1 |
| claude-opus | full | 3 | 0.969 | 0.007 | 0.961 | 0.974 | 0.965 | 1.000 | 21.000 | 0 |
| claude-sonnet | full | 5 | 0.960 | 0.044 | 0.882 | 0.985 | 0.956 | 1.000 | 28.400 | 0 |
| claude-sonnet | no_quality_hint | 5 | 0.937 | 0.052 | 0.858 | 0.985 | 0.937 | 1.000 | 31.200 | 0 |

## Mean score per question

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 1.00 | 1.00 | 1.00 | 0.54 | 0.96 | 1.00 | 0.77 | 1.00 | 0.81 | 0.73 |
| claude-haiku | no_quality_hint | 0.60 | 0.60 | 0.60 | 0.28 | 0.60 | 0.60 | 0.59 | 0.60 | 0.54 | 0.55 |
| claude-opus | full | 1.00 | 1.00 | 0.99 | 0.77 | 1.00 | 1.00 | 1.00 | 1.00 | 0.91 | 0.97 |
| claude-sonnet | full | 1.00 | 1.00 | 1.00 | 0.71 | 1.00 | 1.00 | 0.99 | 1.00 | 0.90 | 0.96 |
| claude-sonnet | no_quality_hint | 1.00 | 1.00 | 1.00 | 0.69 | 1.00 | 1.00 | 0.97 | 1.00 | 0.98 | 0.73 |

Run-to-run sd per question:

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.49 | 0.06 | 0.00 | 0.43 | 0.00 | 0.18 | 0.41 |
| claude-haiku | no_quality_hint | 0.55 | 0.55 | 0.55 | 0.39 | 0.55 | 0.55 | 0.54 | 0.55 | 0.50 | 0.51 |
| claude-opus | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.05 | 0.00 |
| claude-sonnet | full | 0.00 | 0.00 | 0.00 | 0.40 | 0.00 | 0.00 | 0.02 | 0.00 | 0.11 | 0.01 |
| claude-sonnet | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.40 | 0.00 | 0.00 | 0.04 | 0.00 | 0.02 | 0.42 |

## How often the trap answer was given

Share of runs whose answer was closer to the naive (trap) answer than to the truth.

| model | variant | A1 | A2 | A3 | A4 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.40 | 0.20 | 0.00 | 0.00 | 0.00 |
| claude-haiku | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.33 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-opus | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-sonnet | full | 0.00 | 0.00 | 0.00 | 0.20 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-sonnet | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.20 | 0.00 | 0.00 | 0.00 | 0.00 |

## Wrong items in set answers

`+x` = listed but wrong, `-x` = missed; counts over runs.

- claude-haiku / full / B1: `+operator_id` x2
- claude-haiku / no_quality_hint / B1: `-cycle_time_s` x2, `-humidity_pct` x2, `-mold_temp` x2, `-shift` x2
- claude-haiku / no_quality_hint / B2: `-qc_inspection_min` x2, `-rework_cost_eur` x2

## Prompt ablation: full minus no_quality_hint

Positive = the data-quality hint helped.

| model | total | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | 0.316 | 0.400 | 0.400 | 0.400 | 0.262 | 0.356 | 0.400 | 0.187 | 0.400 | 0.263 | 0.180 |
| claude-sonnet | 0.023 | 0.000 | 0.000 | 0.001 | 0.018 | 0.000 | 0.000 | 0.020 | 0.000 | -0.083 | 0.233 |

## Robustness of the ranking to the weights

The ranking of models by mean total is the same with equal question weights (variant `full`).
