# AMBA APB5 RTL Implementation

A SystemVerilog/Verilog RTL implementation of the **AMBA Advanced Peripheral Bus (APB)** protocol, developed from the AMBA APB Protocol Specification.

The project is being developed incrementally, starting from individual APB protocol components and building toward a complete APB-based system including a **Requester, Interconnect, Completer, Testbench, and eventually a full verification environment**.

> **Project status:** Work in progress 🚧

---

## Overview

The goal of this project is to develop a modular RTL implementation of the APB protocol and gradually build a complete, verifiable APB subsystem.

APB is a simple, synchronous, non-pipelined interface intended primarily for accessing peripheral control and configuration registers. An APB transfer consists of a **SETUP phase** followed by an **ACCESS phase**, with `PREADY` allowing the Completer to extend the transfer when necessary.

The implementation is based on the **AMBA APB Protocol Specification Issue D (APB5)**.

The project will eventually contain:

- APB Requester
- APB Interconnect
- APB Completer
- APB protocol support logic
- APB parity generation/checking
- Testbench
- Protocol verification
- Functional and corner-case verification

---

## Architecture

The planned architecture is:

```text
                    ┌──────────────────┐
                    │   APB Requester  │
                    └────────┬─────────┘
                             │
                             │ APB
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

The final test environment will surround the complete system:

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
                         │    APB Subsystem      │
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

The project is currently being developed at the **component level**.

One of the implemented building blocks is the APB parity-check functionality. The current RTL contains a parameterized `APB_parity_check` module with configurable payload width and parity granularity. It receives a payload and transmitted check bits, generates the expected parity internally, and reports an error when checking is enabled and the generated and received values do not match.

The RTL is intentionally being developed as separate modules so that each component can later be integrated and verified independently.

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

If `PREADY` remains low, the Completer can extend the ACCESS phase for additional cycles.

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
| --------- | ---------------------------------------- |
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

The APB5 specification defines these signals and their optional/conditional nature depending on the interface configuration.

---

## APB5 Features

The long-term implementation is intended to cover relevant APB5 functionality, including:

### Basic Transfers

The system will support APB read and write transfers using the standard SETUP and ACCESS phases, including wait-state handling through `PREADY`.

### Write Strobes

APB4/APB5 supports `PSTRB`, where each strobe corresponds to a byte lane of the write data bus.

The implementation will eventually support byte-lane handling and sparse writes.

### Error Response

`PSLVERR` can indicate an error on a completed APB transfer and is valid during the final transfer cycle.

The Completer and Interconnect will eventually support appropriate error generation and propagation.

### Protection

APB provides `PPROT[2:0]` for transaction protection attributes, including normal/privileged, secure/non-secure, and data/instruction indications.

### APB5 User Signals

APB5 provides optional user-defined transaction attributes such as `PAUSER`, `PWUSER`, `PRUSER`, and `PBUSER`.

These signals will be considered during the Interconnect and Completer implementation where required.

### Wake-Up Signaling

APB5 introduces `PWAKEUP`, which can indicate activity associated with an APB interface and can be used in clock/power-control related applications.

### Parity Protection

APB5 defines interface parity protection for detecting single-bit errors on the interface. The current project already includes a parameterized parity generation/checking building block, which will later be integrated into the complete APB system.

---

# Project Structure

The project is being organized around independent RTL components and verification files.

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

The project is intentionally being developed in stages.

### Requester

The next stages will include implementation of the APB Requester, including APB transfer control and read/write transaction generation.

### Interconnect

An APB Interconnect will then be developed to perform address decoding, peripheral selection, request routing, and response routing between the Requester and multiple Completers.

### Completer

The project will then include an APB Completer responsible for handling APB accesses, register interactions, `PREADY`, `PRDATA`, and `PSLVERR`.

### Integration

The individual components will be connected to form the complete:

```text
Requester
    │
    ▼
Interconnect
    │
    ├────► Completer #0
    │
    └────► Completer #1
```

The parity logic will also be integrated into the system.

### Testbench

After the main RTL components are integrated, a testbench will be developed to generate APB transactions and exercise the complete subsystem.

The initial tests will focus on fundamental read/write transactions before expanding to wait states, error responses, multiple Completers, and APB5-specific features.

### Full Verification

The long-term goal is to develop a comprehensive verification environment covering protocol behavior, functional behavior, corner cases, error conditions, parity protection, and end-to-end transactions.

The verification environment is expected to include monitors, scoreboards, assertions, functional coverage, randomized testing, error injection, and regression testing.

---

# Verification Strategy

The verification effort will be expanded progressively.

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

The testbench will later verify Completers that hold `PREADY` low for one or more cycles. APB explicitly allows the ACCESS phase to be extended by keeping `PREADY` low.

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

**Current stage: RTL component development**

The project is **not yet a complete APB subsystem**. The current work focuses on implementing the individual RTL components first.

The next major milestones are the **APB Interconnect**, **APB Completer**, and **top-level Testbench**.

After the initial system is operational, the project will move toward a more comprehensive verification environment covering protocol behavior, corner cases, error conditions, parity protection, and end-to-end transactions.

---

# Reference

This project is based on:

**AMBA APB Protocol Specification — ARM IHI 0024D, Issue D (APB5)**.

The specification describes APB as a low-cost, synchronous, non-pipelined interface and defines its transfer states, signals, transfer behavior, error response, protection, wake-up signaling, user signaling, and parity protection.

---

## Disclaimer

This is an independent educational/engineering implementation of the APB protocol.

AMBA and APB are specifications/trademarks associated with Arm Limited. Refer to the official specification and applicable licensing terms when using or distributing implementations based on the specification.