# Benchmark results

13 scored runs. Scores are in [0, 1]; sd is the run-to-run standard deviation.

## Total score

| model | variant | count | mean | std | min | max | equal_weights_mean | format_ok | tool_calls_mean | turn_limit_runs |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 5 | 0.504 | 0.462 | 0.000 | 0.879 | 0.487 | 0.600 | 56.000 | 2 |
| claude-opus | full | 3 | 0.985 | 0.010 | 0.974 | 0.994 | 0.987 | 1.000 | 29.667 | 0 |
| claude-sonnet | full | 5 | 0.866 | 0.080 | 0.780 | 0.982 | 0.837 | 1.000 | 26.400 | 0 |

## Mean score per question

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.60 | 0.00 | 0.60 | 0.34 | 0.56 | 0.60 | 0.59 | 0.60 | 0.44 | 0.54 |
| claude-opus | full | 1.00 | 1.00 | 0.99 | 0.97 | 1.00 | 1.00 | 1.00 | 1.00 | 0.95 | 0.95 |
| claude-sonnet | full | 1.00 | 0.20 | 1.00 | 0.51 | 1.00 | 1.00 | 1.00 | 1.00 | 0.97 | 0.69 |

Run-to-run sd per question:

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.55 | 0.00 | 0.55 | 0.47 | 0.51 | 0.55 | 0.54 | 0.55 | 0.42 | 0.50 |
| claude-opus | full | 0.00 | 0.00 | 0.00 | 0.04 | 0.00 | 0.00 | 0.00 | 0.00 | 0.09 | 0.00 |
| claude-sonnet | full | 0.00 | 0.45 | 0.00 | 0.47 | 0.00 | 0.00 | 0.00 | 0.00 | 0.04 | 0.40 |

## How often the trap answer was given

Share of runs whose answer was closer to the naive (trap) answer than to the truth.

| model | variant | A1 | A2 | A3 | A4 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 1.00 | 0.00 | 0.33 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-opus | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-sonnet | full | 0.00 | 0.80 | 0.00 | 0.40 | 0.00 | 0.00 | 0.00 | 0.20 |

## Wrong items in set answers

`+x` = listed but wrong, `-x` = missed; counts over runs.

- claude-haiku / full / B1: `-cycle_time_s` x2, `-humidity_pct` x2, `-mold_temp` x2, `-shift` x2, `+ambient_temp_c` x1, `+operator_id` x1
- claude-haiku / full / B2: `-qc_inspection_min` x2, `-rework_cost_eur` x2

## Robustness of the ranking to the weights

The ranking of models by mean total is the same with equal question weights (variant `full`).
