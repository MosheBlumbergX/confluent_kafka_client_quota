# Findings: what we measured

[Back to README](../README.md)

**Setup:** Enterprise cluster on Azure (UK South) over Private Link; load
from a Standard_B2s VM in the same VNet; `kafka-producer-perf-test` with
1 KB records, `acks=all`, no compression, `--throughput -1`. Throughput is
shown in MB/s (10^6 bytes, the unit quotas use); perf-test prints MiB/s, so
the scripts convert.

## Summary

- **Steady state is precise.** Every quota we tested settled within a few
  percent of its value, for ingress and egress.
- **It is not an instant hard cap.** After idle, or right after a quota is
  created or changed, a client can run far above its quota until the quota
  has been distributed to the brokers.
- **The warm-up varies.** We saw anything from ~7 s to more than 90 s. That is
  why the demo runs for 3 minutes and judges only the final third.
- **Throttling is latency, never errors.** The 1 MB/s tenant's average send
  latency climbed to ~34 s (peaks of a minute) while every send succeeded.
- **No quota means no limit.** The tenant without a quota took everything the
  VM's network could push: up to ~98 MB/s.

Practical takeaway: **size the cluster for bursts; use quotas to control
sustained behaviour.** Quotas stop a runaway job from monopolising a cluster
for minutes or hours, not for the first few seconds.

## Run 1: the demo (`./scripts/demo.sh`, 180 s race)

```
  TENANT         QUOTA      FINAL MB/s     PEAK MB/s    VERDICT
  new-team       none       97.77          98.29        NO QUOTA: unlimited
  nightly-etl    1 MB/s     1.00           46.85        held at quota
  payments-api   10 MB/s    9.91           49.51        held at quota
```

`nightly-etl` over time (every third 5 s window):

```
  30.57 MB/s   avg latency  0.5 s   above quota (warm-up burst)
  46.85 MB/s   avg latency  1.1 s   above quota (warm-up burst)
  39.12 MB/s   avg latency  0.8 s   above quota (warm-up burst)
  40.42 MB/s   avg latency  0.0 s   above quota (warm-up burst)
   0.93 MB/s   avg latency  7.6 s   held at quota          <- ~60 s in
   0.92 MB/s   avg latency 22.8 s   held at quota
   1.06 MB/s   avg latency 32.8 s   held at quota
   1.01 MB/s   avg latency 34.6 s   held at quota
   1.00 MB/s   avg latency 33.6 s   held at quota
```

## Run 2: an earlier 60 s race (settled fast)

The same race, earlier in the day, settled within ~10 s:

| Tenant | Quota | Steady state | `produce-throttle-time-avg` / `-max` | Worst latency |
|---|---|---|---|---|
| `payments-api` | 10 MB/s | 9.9 MB/s | 50.5 ms / 156 ms | 4.2 s |
| `nightly-etl` | 1 MB/s | 1.0 MB/s | 677 ms / 5,144 ms | 33.9 s |
| `new-team` | none | up to 81.6 MB/s | 0 / 0 | 5.3 s |

(Throttle times come from the producer's own metrics at the end of a run.)
A third 90 s race, run later, had **not** settled for `nightly-etl` by the
end, which is what prompted the 3-minute default.

## Run 3: changing a quota live

A single `nightly-etl` producer ran for 150 s while its quota was changed
with `terraform apply`:

| Time | Quota | Observed |
|---|---|---|
| 0 to 40 s | 1 MB/s (re-applied just before) | ~104 MiB/s: the VM's network limit, unthrottled |
| 40 to 100 s | 1 MB/s | 0.92 to 1.04 MB/s, latency rising to 58 s |
| ~65 s | raised to 3 MB/s | |
| 100 s to end | 3 MB/s | unthrottled again while the new limit was distributed |

A fresh 120 s run at 3 MB/s, with no change in between: one 5 s burst, then
23 consecutive windows at 2.9 to 3.05 MB/s.

## Run 4: egress

`nightly-etl` consumer, egress quota 3 MB/s: one burst window (~19 MiB/s),
then 2.96 to 2.98 MB/s.

## Broker-side confirmation

`./scripts/metrics.sh` (Metrics API, `io.confluent.kafka.server/request_bytes`,
`type=Produce`, by `principal_id`) showed the same picture from the brokers:
`nightly-etl` at 46 to 56 MB/s per minute during the unthrottled phases and
~3 MB/s once the 3 MB/s quota held. Metrics arrive a few minutes late.
