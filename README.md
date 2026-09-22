# AMBA APB5 RTL Implementation

A SystemVerilog RTL implementation of the **AMBA Advanced Peripheral Bus (APB)** protocol, developed from the AMBA APB Protocol Specification.

The core subsystem — **Requester, Interconnect, Completer(s), and a structural top-level integration** — is implemented and connected end-to-end, including optional APB5 interface parity protection. A **Testbench** and a full verification environment are the next milestones.

> **Project status:** Core RTL implemented 🟢 — Testbench / verification environment in progress 🚧

---

## Overview

The goal of this project is a modular RTL implementation of the APB protocol, built up from individual components into a complete, verifiable APB subsystem.

APB is a simple, synchronous, non-pipelined interface intended primarily for accessing peripheral control and configuration registers. An APB transfer consists of a **SETUP phase** followed by an **ACCESS phase**, with `PREADY` allowing the Completer to extend the transfer when necessary.

The implementation is based on the **AMBA APB Protocol Specification Issue D (APB5)**.

The project contains:

- ✅ APB Requester
- ✅ APB Interconnect
- ✅ APB Completer
- ✅ Structural top-level integration (`APB5_Top`)
- ✅ APB parity generation/checking, integrated end-to-end
- 🚧 Testbench
- 🚧 Protocol / functional / corner-case verification

---

## Architecture

```text
                    ┌──────────────────┐
                    │   APB Requester  │
                    └────────┬─────────┘
                             │
                             │ APB (+ optional *CHK parity)
                             ▼
                    ┌──────────────────┐
                    │ APB Interconnect │
                    └───────┬──────┬───┘
                            │      │
                       APB  │      │  APB
                            │      │
                            ▼      ▼
                    ┌──────────┐ ┌──────────┐
                    │Completer │ │Completer │
                    │    #0    │ │    #1    │
                    └──────────┘ └──────────┘
```

This topology is instantiated by the structural top-level module **`APB5_Top`**, which wires one `Requester`, one `Interconnect`, and `NUM_of_Completers` instances of `Completer` together (the number of Completers is a parameter, not fixed at two).

`APB5_Top` exposes:

- A simple **valid/ready request interface** upstream (`i_valid`, `i_addr`, `i_write`, `i_wdata`, ..., `o_ready`, `o_rdata`, ...), driven into the `Requester`.
- A **per-Completer peripheral interface**, as unpacked arrays sized `[NUM_of_Completers]` (`i_periph_PRDATA`, `i_periph_PSLVERR`, `o_periph_PADDR`, `o_periph_PWDATA`, ...), one set per Completer.
- Three **parity error outputs** — `o_requester_parity_err`, `o_interconnect_parity_err`, and `o_completer_parity_err[NUM_of_Completers]` — active whenever `Check_Type = 1`.

The final test environment will surround this complete subsystem:

```text
                         ┌───────────────────────┐
                         │      Testbench        │
                         │                       │
                         │  Stimulus / Checks    │
                         │  Assertions / Monitor │
                         └───────────┬───────────┘
                                     │
                                     ▼
                         ┌───────────────────────┐
                         │  APB5_Top Subsystem   │
                         │                       │
                         │ Requester             │
                         │      ↓                │
                         │ Interconnect          │
                         │      ↓                │
                         │ Completers            │
                         └───────────────────────┘
```

---

## Current Implementation

The project has moved from a single standalone building block to a fully connected APB5 subsystem. The following RTL modules are implemented:

### APB Requester (`Requester`)

- Implements the APB SETUP/ACCESS FSM (`IDLE → SETUP → ACCESS`) per the specification, driven by a simple `i_valid`/`o_ready` upstream request interface.
- Registers the transfer's address, control, write-data, strobes, and user attributes (`PADDR`, `PPROT`, `PWRITE`, `PWDATA`, `PSTRB`, `PAUSER`, `PWUSER`) at the start of each access and drives `PSEL`/`PENABLE` through the FSM.
- Optional `PWAKEUP` generation, controlled by the `Wakeup_Signal` parameter.
- Optional APB5 interface parity: generates check bits for every request-side signal it drives, and checks the response-side check bits (`PREADYCHK`, `PRDATACHK`, `PSLVERRCHK`, `PRUSERCHK`, `PBUSERCHK`) coming back from the Interconnect, reporting any mismatch on `o_parity_err`. Controlled by the `Check_Type` parameter.

### APB Interconnect (`Interconnect`)

- Performs address-based Completer selection: the top `SEL_BITS = $clog2(NUM_of_Completers)` bits of `PADDR` select the target Completer, one-hot, via `PSELx`.
- Muxes the response-phase signals (`PRDATA`, `PREADY`, `PSLVERR`, `PBUSER`, `PRUSER`) from the selected Completer back to the Requester.
- Optional parity: generates parity for `PSELx`, checks each Completer's response-side check bits for the Completer → Interconnect hop (`o_hop1_parity_err`), and regenerates fresh check bits for the muxed response it forwards on to the Requester. Controlled by `Check_Type`.
- Parameterizable number of Completers via `NUM_of_Completers`.

### APB Completer (`Completer`)

- Configurable wait-state insertion via `WAIT_STATES_NUM`: holds `PREADY` low for the configured number of cycles after the start of each selected access.
- Decodes `PSTRB` into a per-byte write mask and applies it to the incoming write data.
- Drives the Completer-to-peripheral interface (`PADDR`, `PPROT`, `PWDATA`, `PAUSER`, `PWUSER`) and reflects the peripheral's read data, response, and user attributes (`i_PRDATA`, `i_PSLVERR`, `i_PBUSER`, `i_PRUSER`) back onto the APB interface.
- Optional APB5 interface parity: checks everything driven to it from the Requester/Interconnect side (address, control, `PSELx`, `PENABLE`, write data, strobes, wakeup, user signals) and generates parity for the response signals it drives, reporting any mismatch on `o_parity_err`. Controlled by `Check_Type`.
- Optional clock gating of its internal wait-state logic based on `PWAKEUP`, via the `Wakeup_Signal` parameter and the `CLK_GATE` primitive.

### Top-Level Integration (`APB5_Top`)

- Structurally connects one `Requester`, one `Interconnect`, and a `generate`-loop of `NUM_of_Completers` `Completer` instances.
- `Check_Type` is a top-level parameter: when set, all `*CHK` parity signals are wired end-to-end following the same topology as the functional payload signals they protect (request-side checks fan out from the Requester to every Completer; `PSELx`/`PSELxCHK` fan out from the Interconnect; response-side checks flow from each Completer to the Interconnect, which regenerates checks for the hop back to the Requester).
- Aggregates the three block-level parity error outputs to the external interface: `o_requester_parity_err`, `o_interconnect_parity_err`, `o_completer_parity_err[NUM_of_Completers]`.

### Parity Protection (`APB_parity_gen`, `APB_parity_check`)

- `APB_parity_gen` is parameterized by payload `WIDTH` and check granularity `GRAN`, generating one odd-parity check bit per `GRAN`-bit group of the payload.
- `APB_parity_check` instantiates `APB_parity_gen` internally and compares the regenerated check bits against a received `sent_check` value, flagging `error` only while `Check_Enable` is asserted.
- Instantiated throughout the Requester, Interconnect, and Completer to implement the APB5 interface parity scheme end-to-end, matching the granularity conventions of the spec (e.g. `GRAN = 8` for data-width and user-data signals, `GRAN = 1` for single-bit control signals).

### Clock Gating (`CLK_GATE`)

- Simulation model: a transparent low latch captures `CLK_EN` while `CLK` is low; the latch output is ANDed with `CLK` to emulate an integrated clock-gating cell without glitching.
- A commented-out synthesis instantiation (`TLATNCAX4M`) shows the intended standard-cell mapping for implementation.

---

## APB Protocol

The implementation follows the APB transfer model defined by the specification.

### Transfer Phases

An APB transfer consists of:

1. **IDLE**
2. **SETUP**
3. **ACCESS**

During SETUP, the appropriate `PSEL` signal is asserted while the transfer information becomes valid.

During ACCESS, `PENABLE` is asserted. The transfer completes when `PREADY` is asserted.

If `PREADY` remains low, the Completer can extend the ACCESS phase for additional cycles — implemented via the `WAIT_STATES_NUM` wait-state counter in `Completer`.

Conceptually:

```text
        ┌──────┐
        │ IDLE │
        └───┬──┘
            │ Transfer
            ▼
       ┌─────────┐
       │  SETUP  │
       │ PSEL=1  │
       │ PENABLE=0
       └────┬────┘
            │
            ▼
       ┌─────────┐
       │ ACCESS  │◄──────────┐
       │ PSEL=1  │           │
       │ PENABLE=1           │
       └────┬────┘           │
            │                │
        PREADY=0              │
            └────────────────┘
            
        PREADY=1
            │
            ▼
          IDLE
```

---

## Main APB Signals

The APB interface includes signals such as:

| Signal    | Purpose                                  |
| --------- | ----------------------------------------- |
| `PCLK`    | APB clock                                |
| `PRESETn` | Active-low reset                         |
| `PADDR`   | Address                                  |
| `PSELx`   | Peripheral select                        |
| `PENABLE` | Access-phase indication                  |
| `PWRITE`  | Read/write direction                     |
| `PWDATA`  | Write data                               |
| `PSTRB`   | Write byte strobes                       |
| `PREADY`  | Transfer completion / wait-state control |
| `PRDATA`  | Read data                                |
| `PSLVERR` | Transfer error indication                |
| `PPROT`   | Protection attributes                    |
| `PWAKEUP` | APB5 wake-up signaling                   |
| `PAUSER`  | User request attribute                   |
| `PWUSER`  | User write-data attribute                |
| `PRUSER`  | User read-data attribute                 |
| `PBUSER`  | User response attribute                  |

When `Check_Type = 1`, each of these signals has a companion `Pxxx` **`CHK`** signal (e.g. `PADDRCHK`, `PWDATACHK`), generated at the block that drives the payload and checked at the block that consumes it, with one check bit per `GRAN`-bit group as described in [Parity Protection](#parity-protection-apb_parity_gen-apb_parity_check).

---

## APB5 Features

### Basic Transfers

Implemented: APB read and write transfers using the standard SETUP and ACCESS phases, including wait-state handling through `PREADY` (`WAIT_STATES_NUM` in `Completer`).

### Write Strobes

Implemented: `PSTRB` is decoded per byte lane in `Completer` and applied as a write mask, supporting sparse/byte-lane writes.

### Error Response

Implemented: `PSLVERR` is driven by the Completer from its peripheral-side `i_PSLVERR` input and propagated through the Interconnect back to the Requester.

### Protection

Implemented: `PPROT[2:0]` is carried from the Requester through the Completer to the peripheral interface.

### APB5 User Signals

Implemented: `PAUSER`, `PWUSER`, `PRUSER`, and `PBUSER` are carried end-to-end between the Requester, Interconnect, Completer, and peripheral interface.

### Wake-Up Signaling

Implemented: `PWAKEUP` is generated by the Requester (gated by the `Wakeup_Signal` parameter) and used by each Completer to clock-gate its internal wait-state logic via `CLK_GATE`.

### Parity Protection

Implemented: APB5 interface parity protection is integrated end-to-end across the Requester, Interconnect, and every Completer, built from the parameterized `APB_parity_gen` / `APB_parity_check` primitives and controlled by the top-level `Check_Type` parameter.

---

# Project Structure

The project is organized around independent RTL components and (upcoming) verification files.

A planned structure is:

```text
.
├── rtl/
│   ├── requester/
│   │   └── ...
│   │
│   ├── interconnect/
│   │   └── ...
│   │
│   ├── completer/
│   │   └── ...
│   │
│   ├── top/
│   │   └── APB5_Top.sv
│   │
│   └── parity/
│       └── ...
│
├── tb/
│   ├── ...
│   └── ...
│
├── verification/
│   ├── ...
│   └── ...
│
├── docs/
│   └── ...
│
└── README.md
```

The exact file organization can evolve as the project grows.

---

# Development Roadmap

### Requester ✅ Implemented

The APB Requester implements APB transfer control and read/write transaction generation, with optional parity protection and wake-up signaling.

### Interconnect ✅ Implemented

The APB Interconnect performs address decoding, peripheral selection, request routing, and response routing between the Requester and multiple Completers, with optional parity checking on the Completer-facing hop.

### Completer ✅ Implemented

The APB Completer handles APB accesses, wait-state generation, `PREADY`/`PRDATA`/`PSLVERR`, and the peripheral-facing interface, with optional parity checking and clock gating.

### Integration ✅ Implemented (`APB5_Top`)

The individual components are connected to form the complete subsystem, parameterized by `NUM_of_Completers`:

```text
Requester
    │
    ▼
Interconnect
    │
    ├────► Completer #0
    │
    └────► Completer #1
    │
    └────► Completer #N-1
```

Parity logic is integrated throughout, controlled by the top-level `Check_Type` parameter.

### Testbench 🚧 Not yet started

The next stage is a testbench to generate APB transactions and exercise the complete subsystem.

The initial tests will focus on fundamental read/write transactions before expanding to wait states, error responses, multiple Completers, and APB5-specific features (parity, wake-up, user signals).

### Full Verification 🚧 Not yet started

The long-term goal is a comprehensive verification environment covering protocol behavior, functional behavior, corner cases, error conditions, parity protection, and end-to-end transactions.

The verification environment is expected to include monitors, scoreboards, assertions, functional coverage, randomized testing, error injection, and regression testing.

---

# Verification Strategy

The verification effort will be built up progressively once the testbench is in place.

### Directed Verification

Initially, the testbench will exercise fundamental APB transactions:

```text
Write
  ↓
SETUP
  ↓
ACCESS
  ↓
PREADY
  ↓
Complete
```

and:

```text
Read
  ↓
SETUP
  ↓
ACCESS
  ↓
PRDATA + PREADY
  ↓
Complete
```

### Wait-State Verification

The testbench will verify Completers that hold `PREADY` low for one or more cycles, exercising the `WAIT_STATES_NUM` parameter.

### Error Verification

Both read and write transactions can produce an APB error response through `PSLVERR`.

### Protocol Verification

The eventual verification environment will check properties such as:

- Correct SETUP → ACCESS sequencing
- Stable transfer signals during ACCESS
- Correct `PSEL` behavior
- Correct `PENABLE` behavior
- Correct `PREADY` handling
- Correct read/write behavior
- Correct response timing
- Correct error signaling
- Correct interconnect routing
- Correct parity behavior

---

# Project Status

**Current stage: Core RTL subsystem complete — moving into testbench development**

The Requester, Interconnect, Completer, and structural top-level integration (`APB5_Top`) are implemented and connected end-to-end, including optional APB5 interface parity protection across all three hops (Requester ↔ Interconnect, Interconnect ↔ Completer, Completer ↔ peripheral-facing checks).

The next major milestone is the **top-level Testbench**, followed by a more comprehensive verification environment covering protocol behavior, corner cases, error conditions, parity protection, and end-to-end transactions.

---

# Reference

This project is based on:

**AMBA APB Protocol Specification — ARM IHI 0024D, Issue D (APB5)**.

The specification describes APB as a low-cost, synchronous, non-pipelined interface and defines its transfer states, signals, transfer behavior, error response, protection, wake-up signaling, user signaling, and parity protection.

---

## Disclaimer

This is an independent educational/engineering implementation of the APB protocol.

AMBA and APB are specifications/trademarks associated with Arm Limited. Refer to the official specification and applicable licensing terms when using or distributing implementations based on the specification.
