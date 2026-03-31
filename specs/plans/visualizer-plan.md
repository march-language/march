# Compiler Visualization & GC Instrumentation Plan

## Goals

Build a system to:
- Visualize compiler phases (AST → IR → LLVM)
- Inspect optimization passes (e.g. inlining, constant folding)
- Trace and validate reference counting (Perseus)
- Provide an interactive UI for exploring transformations over time

---

## High-Level Architecture

Compiler (OCaml)
   ↓
[Instrumentation Layer]  ← (enabled via flags)
   ↓
Structured Output (JSON)
   ↓
Visualization Backend (static files or dev server)
   ↓
Frontend (Cytoscape.js + optional timeline)

---

## Feature Flags

Introduce compile-time flags to control instrumentation:

- `-dump-phases`
- `-trace-passes`
- `-trace-gc`
- `-trace-all`

All instrumentation should be zero-cost when disabled.

---

## Phase 1: Graph Representation

Standardize a graph format usable across all compiler stages.

Nodes:
- id (stable)
- label
- kind
- metadata

Edges:
- source
- target
- kind

---

## Phase 2: Phase Dumping

Emit one file per stage:

01_ast.json
02_typed_ast.json
03_ir.json
04_cfg.json
05_llvm.json

---

## Phase 3: Pass-Level Instrumentation

For each pass:
- Graph before
- Graph after
- Change set (added, removed, modified)

---

## Phase 4: Diffing Strategy

Match nodes by ID and compare structure + attributes.

---

## Phase 5: GC / RC Instrumentation

Track:
- alloc
- free
- inc_ref
- dec_ref

Emit JSONL events.

---

## Phase 6: Data Pipeline

/trace/
  phases/
  passes/
  gc/

---

## Phase 7: Visualization UI

- Phase viewer
- Pass viewer
- GC viewer

---

## Phase 8: Interaction Design

- Click nodes for metadata
- Step through passes
- Highlight changes

---

## Phase 9: Advanced Features

- Optimization reasoning
- Ownership visualization
- Performance analysis

---

## Phase 10: Validation

Detect:
- leaks
- double frees
- negative refcounts

---

## Summary

Treat compilation as observable transformations, not a black box.

plan.md
Displaying plan.md.
