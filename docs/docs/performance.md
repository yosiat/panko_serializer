---
id: performance
title: Performance
sidebar_label: Performance
---

The performance of Panko is measured using microbenchmarks and load testing.

## Microbenchmarks

The following microbenchmarks are run on MacBook Pro (15-inch, 2018), Ruby 2.6.3 with Rails 6.0.2.1
demonstrating the performance of ActiveModelSerializers 0.10.10 and Panko 0.7.2

| Benchmark         | AMS ip/s | Panko ip/s |
| ----------------- | -------- | ---------- |
| Simple_Posts_2300 | 5.4      | 190.48     |
| Simple_Posts_50   | 261.28   | 9,347.4    |
| HasOne_Posts_2300 | 2.54     | 90.71      |
| HasOne_Posts_50   | 124.29   | 5,421.55   |

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
