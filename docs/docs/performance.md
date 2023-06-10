---
id: performance
title: Performance
sidebar_label: Performance
---

The performance of Panko is measured using microbenchmarks and load testing.

## Microbenchmarks

The following microbenchmarks are run on MacBook Pro (16-inch, 2021, M1 Max), Ruby 3.2.0 with Rails 7.0.5
demonstrating the performance of ActiveModelSerializers 0.10.13 and Panko 0.8.0

| Benchmark         | AMS ip/s | Panko ip/s |
| ----------------- | -------- | ---------- |
| Simple_Posts_2300 | 11.72    | 523.05     |
| Simple_Posts_50   | 557.29   | 23,011.9   |
| HasOne_Posts_2300 | 5.91     | 233.44     |
| HasOne_Posts_50   | 285.8    | 10,362.79  |

## Real-world benchmark

The real-world benchmark here is endpoint which serializes 7,884 entries with 48 attributes and no associations.
The benchmark took place in environment that simulates production environment and run using `wrk` from machine on the same cluster.

| Metric             | AMS   | Panko |
| ------------------ | ----- | ----- |
| Avg Response Time  | 4.89s | 1.48s |
| Max Response Time  | 5.42s | 1.83s |
| 99th Response Time | 5.42s | 1.74s |
| Total Requests     | 61    | 202   |

_Thanks to [Bringg](https://www.bringg.com) for providing the infrastructure for the benchmarks_
