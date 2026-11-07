# Verification method

| Layer | Executed scope |
|---|---|
| Directed Icarus | Stuck bits, both transition directions, address aliasing, inversion coupling, rejected spares, capacity, late faults, reset/restart and normal access |
| Geometry matrix | (AW,DW,S) = (1,1,1), (1,3,2), (2,8,1), (3,4,3), (4,8,2), (4,16,4), (5,32,2), each at L=0 and L=1 |
| Independent oracle | Every March command, final diagnostic field and logical mapping for 100 fault maps at each latency; seed 20261105 |
| Cocotb | Two test functions per latency: 15 fault scenarios with oracle/user access checking, and stage abort/restart |
| Controller formal | AW=1,DW=2,S=1; clean and symbolic single faulty row; 55 steps at L=0, 80 at L=1 |
| User-port formal | Same small geometry, symbolic single faulty row and arbitrary user traffic; two MBIST runs, with/without reset before retest; 125/175 steps |
| Mutation | Wrong write background, allocation of bad spare, bypassed verification mapping and omitted synchronous wait must be rejected |
| Verilator | Boundary (1,1,1) and default (4,8,2) geometry at both latencies |
| Strict lint | Three production tops × seven geometries × two latencies; no warning suppression |
| Synthesis | Generic controller, subsystem, reference RAM and integrated memory; structural checks |

The transition, decoder and coupling tests are specific examples. Random campaigns model static stuck-at-zero/one bits, not all fault classes. Formal proofs assume the documented memory timing and bounded reset/start sequences. They do not cover arbitrary schedules indefinitely.

Run `make verify` from an activated project virtual environment. Optional dependencies are detected from PATH and skips are recorded. `docs/results.json` is a portable summary; full logs, source hashes, exact formal scripts and traces are regenerated under build. A skipped suite is not an executed pass.
