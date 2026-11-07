# Final technical report

## Objective and delivered scope

Design and verify a portable RTL subsystem that detects memory mismatches, allocates healthy spare rows, verifies repaired memory, and provides a normal logical memory port. The final deliverable is a simulation-based project with reproducible tests, generic synthesis, bounded formal verification, a fault-diagnosis demonstration, and source packaging. It does not require a physical FPGA board.

## Design method

The March C− sequence is: ascending write 0; ascending read 0/write 1; ascending read 1/write 0; descending read 0/write 1; descending read 1/write 0; ascending read 0. Reads and writes are separate operations. There are ten memory operations per tested word.

Three stages run in order: spare qualification, raw main-memory diagnosis, and remapped logical-memory verification. Failing spares are excluded. Each newly observed failing main address takes the first free healthy spare; repeated failures consume no additional spare. Allocation stays fixed during verification. A verification mismatch or insufficient capacity prevents normal access.

For D main words, S spares, and read latency L in {0,1}, completion takes `(10 + 5L) × (S + 2D)` cycles after the start edge. Registered reads use a request cycle followed by a response-consumption cycle without another memory command.

Each logical word is a row. Physical spares start at D. Normal requests pass through the map after successful qualification. The reference RAM remains a generic inference model; it is not an ASIC macro or a confirmed vendor block RAM.

## Fault diagnosis demonstration

The demo uses D=16, width=8 and S=4. At read latency 1, each case completes in 540 cycles.

| Scenario | First observed failure | Final mapping | Outcome |
|---|---|---|---|
| Clean | None | Identity | Pass |
| Main rows 3 and 7 faulty | Physical 7, XOR 0x80 | 7→16, 3→17 | Pass |
| Main row 3 and spare 16 faulty | Physical 16, XOR 0x01 | 3→17; spare 16 rejected | Pass |
| Five faulty main rows | Physical 1, XOR 0x01 | 1→16, 3→17, 5→18, 7→19 | Unrepairable |

These classes are known injected stimuli. Hardware diagnostics report mismatch observations; they do not uniquely identify the underlying physical defect. First-failure reporting is accompanied by a saturating failing-read count, rejected-spare bitmap and completion/repair status.

## Validation evidence

The authoritative portable summary is [results.json](results.json), regenerated from executed suites. Verification combines directed tests, a parameter matrix, a separately implemented March oracle, seeded physical stuck-bit campaigns, Cocotb, a second simulator, mutation checks, generic synthesis and bounded SAT proofs. Details and exact bounds are documented in [VERIFICATION.md](VERIFICATION.md).

Two hundred seeded campaign simulations include both repairable and unrepairable outcomes; passing a test means the expected outcome was correctly produced, not that every fault set was repairable. Successful cases also perform data reads/writes while faults remain active.

The source archive is checked against the successful verification source hashes, extracted into a fresh directory, and tested with `make test synth`. Repeated packaging of identical inputs uses fixed metadata and ordering. New verification timestamps can change archive bytes even when RTL is unchanged.

## Conclusions and limitations

Within the executed models and parameter sets, the subsystem diagnoses observed failures, avoids rejected spares, enforces capacity, verifies remapping, and gates normal access correctly. Small-instance proofs additionally establish bounded control and data properties under symbolic faults and user traffic.

This evidence supports a simulation-based RTL demonstrator. It does not establish arbitrary-parameter correctness, exhaustive physical defect coverage, unbounded formal correctness, silicon reliability, timing closure, power, vendor memory inference, nonvolatile repair, or production readiness. Hardware validation is intentionally outside the completed project scope.
