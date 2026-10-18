# Benchmark results

5 scored runs. Scores are in [0, 1]; sd is the run-to-run standard deviation.

## Total score

| model | variant | count | mean | std | min | max | equal_weights_mean | format_ok | tool_calls_mean | turn_limit_runs |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 5 | 0.971 | 0.049 | 0.884 | 1.000 | 0.973 | 1.000 | 25.800 | 0 |

## Mean score per question

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 1.00 | 1.00 | 1.00 | 1.00 | 0.98 | 1.00 | 0.80 | 1.00 | 1.00 | 0.95 |

Run-to-run sd per question:

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.05 | 0.00 | 0.45 | 0.00 | 0.00 | 0.08 |

## How often the trap answer was given

Share of runs whose answer was closer to the naive (trap) answer than to the truth.

| model | variant | A1 | A2 | A3 | A4 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.00 | 1.00 | 0.00 | 0.00 |

## Wrong items in set answers

`+x` = listed but wrong, `-x` = missed; counts over runs.

- claude-haiku / full / B1: `+operator_id` x1

## Robustness of the ranking to the weights

The ranking of models by mean total is the same with equal question weights (variant `full`).
