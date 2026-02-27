# Homomorphic Encryption Evaluation for EyeD Iris Recognition

**Date:** February 21, 2026
**Author:** EyeD Engineering
**Status:** Technical Evaluation (Pre-Implementation)
**Scope:** Feasibility of applying Homomorphic Encryption to protect iris biometric templates

---

## Executive Summary

This report evaluates the feasibility and trade-offs of applying Homomorphic Encryption (HE) to EyeD's iris recognition pipeline. The core question: can we perform IrisCode matching (Hamming distance computation) on encrypted templates, so that the server never sees plaintext biometric data?

**Bottom line:** HE is feasible for 1:1 verification with acceptable latency (~50-100ms overhead per match). For 1:N identification against large galleries, it requires SIMD batching and will add meaningful latency. The recommended library is **OpenFHE** using the **BFV scheme** with plaintext modulus t=2 (binary arithmetic). A phased approach starting with AES-at-rest, then adding HE for 1:1, then 1:N, manages risk effectively.

---

## Table of Contents

1. [Library Comparison Matrix](#1-library-comparison-matrix)
2. [Scheme Selection Analysis](#2-scheme-selection-analysis)
3. [Performance Projections](#3-performance-projections)
4. [Architecture Integration](#4-architecture-integration)
5. [Threat Model](#5-threat-model)
6. [Implementation Roadmap](#6-implementation-roadmap)
7. [Risks and Mitigations](#7-risks-and-mitigations)
8. [Recommendation](#8-recommendation)

---

## 1. Library Comparison Matrix

### Overview of Candidates

Three libraries are viable for EyeD: **OpenFHE**, **Microsoft SEAL**, and **TFHE-rs**. All three implement lattice-based schemes at 128-bit security. They differ significantly in language ecosystem, scheme support, and operational maturity.

### Detailed Comparison

| Criterion | OpenFHE | Microsoft SEAL | TFHE-rs (Zama) |
|-----------|---------|----------------|----------------|
| **Language** | C++ (core) | C++ (core) | Rust (core) |
| **Latest Version** | v1.4.2 (Oct 2025) | v4.1 (2024) | v1.0.0 (Feb 2025) |
| **License** | BSD 2-Clause | MIT | BSD-3-Clause-Clear |
| **Schemes** | BFV, BGV, CKKS, DM, CGGI/TFHE, LMKCDEY | BFV, BGV, CKKS | TFHE (gate-level + integer) |
| **Build System** | CMake | CMake | Cargo (Rust) |
| **Docker Support** | Official Docker base image available | No official Docker image; CMake builds in Docker easily | No official Docker image; Cargo builds in Docker |
| **Debian Packages** | Ubuntu 20.04/22.04/24.04 supported | No official apt packages | No system packages; crates.io only |
| **Python Bindings** | `openfhe-python` on PyPI (v1.3.0, May 2025) via pybind11 | No official Python bindings; community `tenseal` wraps SEAL | No Python bindings; Rust FFI required |
| **C++ API** | Native, well-documented | Native, well-documented | Requires Rust-C++ FFI bridge (cxx) |
| **GitHub Stars** | ~800+ | ~3,500+ | ~1,800+ |
| **Contributors** | ~40+ | ~30+ | ~50+ (Zama team) |
| **Funding** | DARPA, NumFOCUS | Microsoft Research | Zama (VC-funded, $73M Series A) |
| **Community Forum** | Active Discourse forum | GitHub Issues only | GitHub Issues, Zama community |
| **Documentation** | ReadTheDocs + examples | Manual PDF + examples | docs.zama.org + examples |

### Performance Benchmarks (Published)

From the 2025 benchmark study by the International Conference on Cyber Security, AI and Digital Economy (CSAIDE 2025), comparing SEAL, HElib, OpenFHE, and Lattigo:

| Operation | OpenFHE (BFV) | SEAL (BFV) | HElib (BGV) | Lattigo (BGV) |
|-----------|---------------|------------|-------------|---------------|
| Addition (per op) | 0.055 ms | 0.04 ms | 0.021 ms | 0.06 ms |
| Multiplication (per op) | ~0.8 ms | ~1.2 ms | ~1.5 ms | ~1.0 ms |
| Memory usage (base) | ~15 MB | ~15 MB | ~30 MB | ~20 MB |

From the cross-platform FHE benchmarking study (ePrint 2025/473, Miran et al.):

- **300 FHE additions:** OpenFHE ~4 seconds vs SEAL ~7 seconds (Linux)
- **Memory efficiency:** OpenFHE uses less than half of SEAL's memory consumption
- **Linux vs Windows:** Linux outperforms Windows for both libraries; OpenFHE is the optimal choice on Linux across diverse cryptographic settings
- **Multiplication depth:** OpenFHE is competitive or faster than SEAL beyond 10 consecutive multiplications

For **TFHE-rs** (from Zama's published benchmarks, v1.0):

| Operation | TFHE-rs (CPU, 128-bit security) |
|-----------|-------------------------------|
| Boolean gate (AND/XOR) | ~7 ms per gate |
| 8-bit integer addition | ~80 ms |
| 8-bit integer multiplication | ~150 ms |
| Programmable bootstrapping | ~7 ms |
| GPU acceleration factor | Up to 4.2x faster than CPU |

### Assessment for EyeD

| Factor | OpenFHE | SEAL | TFHE-rs |
|--------|---------|------|---------|
| BFV for binary HD | Excellent | Good | N/A (different scheme) |
| Python integration | Official bindings | Requires TenSEAL wrapper | No Python path |
| C++ integration | Native | Native | FFI overhead |
| CMake compatibility | Direct | Direct | Cargo + cxx bridge |
| Docker/Debian | Best-in-class | Manual | Manual |
| Learning curve | Moderate (many options) | Low (focused API) | Moderate (Rust ecosystem) |
| Production readiness | Good (DARPA backing) | Good (Microsoft backing) | Good (Zama backing) |
| Scheme flexibility | Best (6 schemes) | Good (3 schemes) | Single scheme |

**Why TFHE-rs is a poor fit for EyeD:** TFHE operates at the gate level. Computing Hamming distance on 10,240 bits would require ~10,240 XOR gates at ~7ms each, totaling ~72 seconds -- entirely impractical. TFHE-rs shines for arbitrary boolean circuits but cannot exploit SIMD batching the way BFV/BGV can. TFHE-rs also has no Python bindings, making iris-engine integration difficult.

**Why OpenFHE over SEAL:** Both are strong C++ libraries with CMake. OpenFHE wins on three fronts: (1) official Python bindings for iris-engine integration, (2) better BFV multiplication performance for our workload, and (3) Docker/Debian packaging. SEAL's API is slightly more beginner-friendly, but OpenFHE's documentation has matured significantly with ReadTheDocs and active Discourse support.

### References

- CSAIDE 2025 Benchmark Study: https://dl.acm.org/doi/10.1145/3729706.3729711
- Cross-Platform FHE Benchmarking (ePrint 2025/473): https://eprint.iacr.org/2025/473
- OpenFHE paper (ePrint 2022/915): https://eprint.iacr.org/2022/915
- TFHE-rs benchmarks: https://docs.zama.org/tfhe-rs/get-started/benchmarks

---

## 2. Scheme Selection Analysis

### Why BFV for IrisCode Hamming Distance

The three main HE scheme families differ in what they compute on:

| Scheme | Plaintext Domain | Native Operations | Best For |
|--------|-----------------|-------------------|----------|
| **BFV** | Integers mod t | Add, Multiply (exact) | Binary/integer arithmetic |
| **BGV** | Integers mod t | Add, Multiply (exact) | Same as BFV, modulus switching exposed |
| **CKKS** | Approximate real numbers | Add, Multiply (approximate) | ML inference, floating point |

**IrisCodes are binary vectors.** Hamming distance is fundamentally a binary integer operation (XOR + popcount). This eliminates CKKS immediately -- approximate arithmetic on binary data is wasteful and introduces unnecessary error.

Between BFV and BGV: both support exact integer arithmetic over Z_t. BFV is preferred because it hides modulus switching inside multiplication operations (scale invariance), making it easier to program correctly. BGV exposes the moduli chain and requires the developer to track which level each ciphertext is at. For our relatively simple circuit (one multiplication + summation), BFV's simplicity wins with no performance penalty.

**Verdict: BFV with plaintext modulus t = 2.**

With t=2, addition in BFV becomes XOR (addition mod 2), and multiplication becomes AND (multiplication mod 2). This is exactly the arithmetic we need.

### Parameter Selection

For 128-bit security with BFV, the Homomorphic Encryption Security Standard (community standard adopted by all major libraries) prescribes:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Polynomial degree N | 8192 | Minimum for 128-bit security with our coeff modulus budget |
| Plaintext modulus t | 2 | Binary arithmetic (Z_2); addition = XOR, multiplication = AND |
| Coefficient modulus q | ~218 bits total | Maximum allowed for N=8192 at 128-bit security |
| SIMD slot count | N/ord(2, N) | With t=2 and N=8192, the number of usable slots depends on the factorization of the cyclotomic polynomial x^N+1 mod 2 |
| Security level | 128-bit | HE Security Standard, ternary secret distribution |

**SIMD Slot Count with t=2:**

When the plaintext modulus t=2, the cyclotomic polynomial x^N + 1 (for N=8192) factors over GF(2) into irreducible polynomials. The number of SIMD slots equals N / d, where d is the multiplicative order of 2 modulo 2N. For N=8192 (2^13), with t=2, the slot structure yields **slots of dimension d** that pack binary values.

In practice, with OpenFHE's BFV and t=2, you can pack binary vectors into coefficient encoding (not batching), where each of the N=8192 coefficients carries one bit. This means **one ciphertext can hold 8,192 bits**.

For EyeD's 10,240-bit IrisCodes: we need **2 ciphertexts** to hold one IrisCode (8,192 + 2,048 bits, with the second ciphertext zero-padded).

**Alternative: N=16384** gives 16,384 slots, fitting the entire IrisCode in a single ciphertext. The trade-off:

| Parameter | N=8192 | N=16384 |
|-----------|--------|---------|
| Ciphertexts per IrisCode | 2 | 1 |
| Max coeff modulus | 218 bits | 438 bits |
| Ciphertext size | ~436 KB each | ~1.75 MB |
| Operations speed | Faster per operation | ~4x slower per operation |
| Security | 128-bit | 128-bit (more headroom for larger q) |
| Multiplicative depth | Limited (~3 levels) | More levels available |

**Recommendation: Start with N=8192, use 2 ciphertexts per IrisCode.** The lower per-operation latency and smaller ciphertext sizes outweigh the inconvenience of splitting across two ciphertexts. Sum the partial Hamming distances from both ciphertexts.

### Multiplicative Depth Budget

The Hamming distance computation requires exactly **1 multiplication** (element-wise multiply of the two IrisCode vectors) plus **summation** (a series of additions plus rotations). Additions and rotations do not consume multiplicative depth. Therefore:

**Multiplicative depth = 1.**

This is extremely shallow. Even the minimal BFV parameter set (N=8192, 218-bit modulus) supports multiplicative depth of ~3, which is more than sufficient.

### The Algebraic Trick: Hamming Distance from Add + Multiply

The standard Hamming distance formula for binary vectors x, y in {0,1}^n:

```
HD(x, y) = Σ (x_i XOR y_i)
```

Since XOR(a,b) = a + b - 2ab (over integers, not mod 2), we can compute:

```
HD(x, y) = Σx_i + Σy_i - 2·Σ(x_i · y_i)
```

**Step-by-step with concrete numbers:**

Let x = [1,0,1,1,0,1,0,0] and y = [1,1,0,1,0,0,1,0] (8-bit example):

1. **Σx = 1+0+1+1+0+1+0+0 = 4** (popcount of x, computed in plaintext)
2. **Σy = 1+1+0+1+0+0+1+0 = 4** (popcount of y, computed in plaintext)
3. **Element-wise x·y = [1,0,0,1,0,0,0,0]** (AND operation -- this is the HE multiplication)
4. **Σ(x·y) = 1+0+0+1+0+0+0+0 = 2** (inner product, computed under encryption)
5. **HD = 4 + 4 - 2(2) = 4**

Verify: XOR = [0,1,1,0,0,1,1,0], popcount = 4. Correct.

**Why this trick matters for HE:**

In BFV with t=2, addition IS XOR (mod 2). We cannot directly get the integer Hamming distance from mod-2 arithmetic because the sum wraps around. The algebraic trick reformulates HD using integer arithmetic:
- Σx_i and Σy_i are computed on plaintext (the client knows its own IrisCode in the clear; the server knows enrolled templates' popcounts)
- Σ(x_i · y_i) is the inner product, which can be computed homomorphically

**HE computation (server-side):**

The server holds Enc(x) (the probe, encrypted by the client). The server knows y (the enrolled template, stored in plaintext on the server -- or also encrypted, depending on threat model).

1. **Multiply:** Compute Enc(x) * y = Enc(x · y), element-wise. Since y is a known plaintext vector, this is a **ciphertext-plaintext multiplication** (very fast, no relinearization needed, no multiplicative depth consumed when using the efficient variant).
2. **Sum (inner product):** Rotate-and-add to sum all slots: Enc(Σ(x_i · y_i)). This requires log2(N) rotations + additions.
3. **Return:** Send the encrypted inner product value back to the client.

The client decrypts to get Σ(x_i · y_i), then computes HD = Σx + Σy - 2·Σ(x·y) in the clear.

**Ciphertext-plaintext multiply is key.** If both templates were encrypted (fully encrypted database), we would need ciphertext-ciphertext multiplication, which is much more expensive and consumes multiplicative depth. The standard model encrypts only the probe; gallery templates can remain in plaintext on the server (the server already has them).

### Masked Hamming Distance

Open-IRIS produces both **IrisCodes** and **MaskCodes**. The MaskCode indicates which bits of the IrisCode are reliable (not occluded by eyelids/eyelashes). The masked fractional Hamming distance is:

```
FHD(x, y) = HD(x AND mask_x AND mask_y, y AND mask_x AND mask_y) / popcount(mask_x AND mask_y)
```

Only bits where BOTH masks are 1 (both bits are reliable) are compared.

**Under HE, this becomes:**

1. **Client-side (before encryption):** Compute combined_mask = mask_x AND mask_y. The client needs mask_y (the enrolled template's mask). Options:
   - Server sends mask_y in plaintext (masks are not biometrically sensitive -- they indicate eyelid position, not iris texture)
   - Pre-compute masked IrisCodes: x' = x AND mask_x, send Enc(x') plus mask_x in plaintext

2. **Server-side (under encryption):** Apply masks to both codes before the inner product:
   - x_masked = x AND mask_combined (ciphertext-plaintext multiply, since mask is plaintext)
   - y_masked = y AND mask_combined (plaintext operation)
   - inner_product = Σ(x_masked · y_masked) as before

3. **Client-side (after decryption):** Divide by popcount(mask_combined) to get fractional HD.

**Security note:** Sending mask codes in plaintext is standard practice. Masks encode geometric occlusion patterns (eyelid shape), not iris texture. They have negligible biometric information content and are routinely treated as public metadata in iris recognition systems (see ISO/IEC 19794-6).

---

## 3. Performance Projections

### Baseline: Plaintext Matching

Current EyeD plaintext matching performance (from MODERN_ARCHITECTURE.md):

| Operation | Time | Notes |
|-----------|------|-------|
| Hamming distance (1 pair) | ~1 ms | XOR + popcount, CPU |
| Full pipeline (segment + encode + match) | ~43 ms | GPU for segmentation |
| 1:N search (1,000 templates) | ~1 second | Sequential, single-threaded |
| 1:N search (1,000 templates, vectorized) | ~50 ms | AVX2/NEON bitwise ops |

### HE Performance Estimates (BFV, N=8192, t=2, OpenFHE)

These estimates are derived from published benchmarks (ePrint 2025/473, CSAIDE 2025) and the Yasuda et al. (2013) packed lattice biometrics paper, scaled to modern hardware (Xeon-class server, single-threaded).

#### Key Generation (One-Time)

| Operation | Estimated Time | Size |
|-----------|---------------|------|
| Key generation (public + secret) | ~50-100 ms | Public key: ~870 KB, Secret key: ~30 KB |
| Relinearization key generation | ~200-500 ms | ~7-15 MB |
| Galois (rotation) keys | ~2-5 s (for all log2(N) rotations) | ~100-200 MB (13 rotation keys) |

Key generation is a one-time cost per client/session. Rotation keys are large but only need to be transmitted once and cached on the server.

#### Per-Operation Timing (Server, Single-Threaded)

| Operation | Estimated Time | Notes |
|-----------|---------------|-------|
| **Encryption** (client) | ~5-10 ms | Encrypt one 8192-bit IrisCode chunk |
| **Ciphertext-Plaintext Multiply** | ~0.1-0.5 ms | AND of encrypted probe with plaintext gallery template |
| **Rotate-and-Sum** (inner product) | ~10-30 ms | 13 rotations + additions for 8192 slots |
| **Decryption** (client) | ~1-3 ms | Decrypt inner product result |
| **Total per 1:1 match** | **~20-50 ms** | Server-side HE computation only |
| **End-to-end 1:1 verification** | **~30-70 ms** | Including encrypt + decrypt + network |

Comparison: Plaintext matching is ~1ms. HE adds **~30-70x overhead** for 1:1 verification. This is within acceptable bounds for a verification scenario (user presents iris, waits for result).

#### Reference Point: Yasuda et al. (2013)

Yasuda et al. demonstrated secure Hamming distance of 2,048-bit binary vectors using packed lattice-based HE:
- Encryption: 19.89 ms
- Secure Hamming distance: 18.10 ms
- Decryption: 9.08 ms
- **Total: 47.07 ms** (on a 2013-era Intel Xeon X3480 @ 3.07 GHz)

Our IrisCodes are ~5x longer (10,240 vs 2,048 bits). On modern hardware (~3-5x faster than 2013 Xeon), we can expect roughly comparable total times (~50-100ms), which aligns with our estimates above.

#### 1:N Identification Throughput

| Gallery Size | Plaintext (vectorized) | HE (sequential) | HE (SIMD amortized) |
|-------------|----------------------|-----------------|---------------------|
| 100 | ~5 ms | ~3-5 s | ~200-500 ms |
| 1,000 | ~50 ms | ~30-50 s | ~2-5 s |
| 10,000 | ~500 ms | ~5-8 min | ~20-50 s |
| 100,000 | ~5 s | ~50-80 min | ~3-8 min |

**SIMD amortization strategy:** Pack multiple gallery templates into different SIMD slots. With N=8192, we could in principle compare a probe against up to ~8 gallery templates in a single ciphertext operation (by interleaving bits across slots). This yields roughly ~10x throughput improvement but requires careful slot layout engineering.

**Verdict:** 1:1 verification is practical. 1:N identification is feasible for small-to-medium galleries (up to ~10K) with SIMD optimization. For 100K+ galleries, indexing or pruning strategies are essential to avoid scanning the entire database.

### Memory Footprint

| Item | Size | Notes |
|------|------|-------|
| **Fresh ciphertext** (N=8192) | ~436 KB | 2 polynomials x 8192 coefficients x 218 bits |
| **Encrypted IrisCode** (2 ciphertexts) | ~870 KB | vs ~1.3 KB plaintext (10,240 bits) |
| **Expansion factor** | **~670x** | Plaintext to ciphertext size ratio |
| **Public key** | ~870 KB | Same structure as ciphertext |
| **Relinearization key** | ~7-15 MB | Depends on decomposition |
| **Rotation keys (all 13)** | ~100-200 MB | One per power-of-2 rotation distance |
| **Server RAM per enrolled user** | ~1.3 KB (plaintext gallery) | Gallery templates stay in plaintext |
| **Server RAM for eval keys** | ~100-200 MB (per client session) | Cached, shared across matches for that client |
| **NATS message (encrypted probe)** | ~870 KB | vs ~1.3 KB plaintext |

**Key observation:** The 670x ciphertext expansion is significant for network transport (NATS messages go from ~1.3KB to ~870KB) but manageable. The largest concern is **rotation key transfer** (~100-200MB), which should be a one-time session setup cost.

If the gallery is also encrypted (fully encrypted database model), each enrolled user costs ~870 KB instead of ~1.3 KB. For 10,000 users, that is ~8.5 GB instead of ~13 MB -- a 670x storage increase.

---

## 4. Architecture Integration

### Where HE Operations Happen

```
  CAPTURE DEVICE          GATEWAY                IRIS-ENGINE              TEMPLATE-DB
  (RPi / Client)          (C++ / Go)             (Python + OpenFHE)       (PostgreSQL)

  ┌────────────┐          ┌──────────┐           ┌──────────────┐        ┌──────────┐
  │ Camera     │          │          │           │              │        │          │
  │ Quality    │──frame──▶│  Route   │──NATS────▶│  Open-IRIS   │        │ Plaintext│
  │ Gate       │          │          │           │  Pipeline    │        │ Gallery  │
  │            │          │          │           │              │        │ Templates│
  │ ┌────────┐ │          │          │           │  ┌────────┐  │        │          │
  │ │HE Key  │ │          │          │           │  │Segment │  │        │          │
  │ │Gen     │ │          │          │           │  │Encode  │  │        │          │
  │ │(once)  │ │          │          │           │  │        │  │        │          │
  │ └────────┘ │          │          │           │  │Encrypt │◀─┤────────│ Load     │
  │            │          │          │           │  │IrisCode│  │        │ Template │
  │ ┌────────┐ │          │          │           │  │        │  │        │          │
  │ │Send    │ │          │          │           │  │HE Match│  │        │          │
  │ │EvalKeys│──keys(1x)─▶│  Cache  │──keys────▶│  │(server)│  │        │          │
  │ │(once)  │ │          │  EvalKeys│           │  └───┬────┘  │        │          │
  │ └────────┘ │          │          │           │      │       │        │          │
  │            │          │          │           │  Enc(result) │        │          │
  │ ┌────────┐ │◀─────────│◀─NATS───│◀──────────│──────┘       │        │          │
  │ │Decrypt │ │          │          │           │              │        │          │
  │ │Result  │ │          │          │           └──────────────┘        └──────────┘
  │ │Compare │ │          │          │
  │ │w/ thres│ │          │          │
  │ └────────┘ │          │          │
  └────────────┘          └──────────┘
```

### Key Management

| Key | Held By | Purpose | Lifetime |
|-----|---------|---------|----------|
| **Secret Key (sk)** | Capture Device / Client | Decrypt match results | Per-device, persistent |
| **Public Key (pk)** | Iris-Engine (server) | Encrypt (if server encrypts gallery) | Shared from client |
| **Evaluation Keys (evk)** | Iris-Engine (server) | Perform HE multiply + rotate | Transmitted once per session |
| **Relinearization Key (rlk)** | Iris-Engine (server) | Reduce ciphertext size after multiply | Part of evk |
| **Galois Keys (gk)** | Iris-Engine (server) | Rotate SIMD slots for summation | Part of evk |

**Critical security property:** The secret key NEVER leaves the capture device. The server can compute on encrypted data using only the public and evaluation keys, but it cannot decrypt.

### Protocol Flow: Enrollment

```
1. Client captures iris image
2. Image sent to iris-engine via gateway (plaintext JPEG, same as today)
3. iris-engine runs Open-IRIS pipeline: segment -> normalize -> encode
4. iris-engine returns IrisCode + MaskCode to gateway
5. Gateway stores plaintext IrisCode + MaskCode in template-db
   (enrollment templates are stored in plaintext -- they are the server's data)
6. Enrollment is complete
```

**Note:** Enrollment does NOT use HE. The user is voluntarily providing their biometric to the system. The enrolled template is the system's reference data. HE protects the **probe** (live capture during verification), not the enrolled gallery.

If the threat model requires encrypted gallery storage (see Section 5), enrollment would additionally encrypt the template before storage, but this significantly increases matching cost.

### Protocol Flow: 1:1 Verification

```
1.  Client captures iris image
2.  Image sent to iris-engine (plaintext JPEG -- HE doesn't protect the raw image)
3.  iris-engine runs Open-IRIS pipeline, produces probe IrisCode + MaskCode
4.  iris-engine encrypts probe IrisCode: Enc(probe) using client's public key
5.  iris-engine loads enrolled template (plaintext) from template-db
6.  iris-engine computes HE inner product:
      result = RotateAndSum(Enc(probe) * gallery_template)
7.  iris-engine sends Enc(inner_product) back to client via gateway
8.  Client decrypts inner_product
9.  Client computes: HD = popcount(probe) + popcount(gallery) - 2 * inner_product
10. Client computes: FHD = HD / popcount(mask_combined)
11. Client checks: FHD < 0.39 → match, else no match
```

**Wait -- who encrypts?** In this flow, iris-engine encrypts the probe IrisCode after producing it. This means the iris-engine momentarily sees the plaintext IrisCode. If the goal is to protect against a compromised iris-engine, the encryption must happen earlier -- on the capture device, BEFORE the image is sent. But then we cannot run the Open-IRIS pipeline (which requires the plaintext image).

**This is the fundamental tension:** The iris recognition pipeline (segmentation, normalization, encoding) operates on plaintext images and produces plaintext IrisCodes. HE protects the template AFTER the pipeline runs. If the pipeline itself runs on an untrusted server, the server already sees the raw image, which is more sensitive than the IrisCode.

**Practical resolution:** HE's primary value is **template protection at rest and during matching**, not during pipeline execution. The server processes the image, produces the IrisCode, encrypts it, and then discards the plaintext. The encrypted template is what gets stored/compared. This protects against database theft and offline attacks, even if the server was once trusted to run the pipeline.

### NATS Message Size Impact

| Message | Current Size | With HE | Factor |
|---------|-------------|---------|--------|
| Capture frame (JPEG) | ~10-30 KB | ~10-30 KB (unchanged) | 1x |
| Analysis result (IrisCode + metadata) | ~2-3 KB | ~2-3 KB (unchanged) | 1x |
| Encrypted probe (new message type) | N/A | ~870 KB | New |
| Encrypted match result | N/A | ~436 KB | New |
| Evaluation keys (one-time setup) | N/A | ~100-200 MB | One-time |

NATS default max message size is 1 MB; the encrypted probe (~870 KB) fits. Evaluation keys (~100-200 MB) should be transferred via a dedicated channel (direct gRPC stream or chunked transfer), not NATS.

### Impact on Open-IRIS Pipeline

**None.** The Open-IRIS pipeline (segment, normalize, encode, match) operates on plaintext data and produces plaintext IrisCodes. HE is applied **after** the pipeline, as a post-processing encryption step before storage or as a replacement for the plaintext matching step.

The `HammingDistanceMatcher` in Open-IRIS would be supplemented (not replaced) with an `HEHammingDistanceMatcher` that:
1. Accepts an encrypted IrisCode (ciphertext)
2. Performs ciphertext-plaintext multiply + rotate-and-sum
3. Returns an encrypted inner product (ciphertext)

The existing plaintext matcher remains available for local/trusted matching scenarios.

---

## 5. Threat Model

### What HE Protects Against

| Threat | Protection Level | Explanation |
|--------|-----------------|-------------|
| **Database theft (server compromise)** | **Strong** | Stolen encrypted templates cannot be decrypted without the client's secret key. Attacker gets ciphertexts that are computationally indistinguishable from random under RLWE hardness (128-bit security). |
| **Template inversion** | **Strong** | Encrypted templates cannot be inverted to recover iris images. Even plaintext IrisCodes are difficult to invert (lossy encoding), and encryption adds a cryptographic barrier. |
| **Insider threat (admin access)** | **Partial** | A malicious admin cannot decrypt stored templates. However, an admin with access to the live iris-engine process could intercept plaintext IrisCodes before encryption (see "fundamental tension" above). |
| **Cross-system template linkage** | **Strong (if using different keys)** | The same IrisCode encrypted under different keys produces completely different ciphertexts. Templates cannot be linked across systems. |
| **Regulatory compliance (GDPR, CCPA, BIPA)** | **Supports** | HE demonstrates technical measures for biometric data protection, supporting compliance arguments. |

### What HE Does NOT Protect Against

| Threat | Gap | Mitigation |
|--------|-----|------------|
| **Man-in-the-middle (image interception)** | HE doesn't encrypt the raw iris image in transit. The JPEG frame sent from capture device to server is plaintext. | **mTLS** on gRPC channel (already in EyeD architecture). TLS encrypts the transport layer. |
| **Replay attacks** | An attacker who captures the encrypted probe can replay it. The server cannot distinguish a fresh capture from a replayed one. | **Challenge-response nonce** in the verification protocol. Server sends a random nonce; client includes it in the HE computation. Or timestamp-binding. |
| **Presentation attacks (spoofing)** | HE doesn't verify that the iris image is from a live person. A printed photo or synthetic iris would produce a valid IrisCode. | **Presentation Attack Detection (PAD)** module. This is an existing known gap in EyeD (per MEMORY.md). PAD must be addressed independently of HE. |
| **Compromised capture device** | If the capture device is compromised, the attacker has the secret key and the plaintext iris image. HE provides no protection. | **Secure element / TPM** for key storage. Hardware attestation. Physical security of capture devices. |
| **Side-channel attacks on server** | Timing and memory access patterns during HE computation may leak information about the plaintext. | **Constant-time implementations** (OpenFHE uses constant-time NTT). Cache-oblivious algorithms. |
| **Key compromise (secret key leaked)** | If the secret key is obtained, all templates encrypted under that key can be decrypted. Irreversibility is lost. | **Key rotation** with re-encryption. Combine HE with **cancelable biometrics** (apply a non-invertible transform before encryption) for defense in depth. See Bassit et al. (2022). |

### Security Analysis Summary

HE provides strong protection for **data at rest** (stored templates) and **data in use** (during matching computation). It does NOT protect **data in transit** (that is TLS's job) or against **liveness/presentation attacks** (that is PAD's job).

The most important gap is the **fundamental tension**: the iris-engine must see plaintext images to run the Open-IRIS pipeline. A fully untrusted server model would require running the entire recognition pipeline inside HE, which is computationally infeasible (DNN inference under HE takes minutes to hours). For practical purposes, we treat the server as "trusted during processing, untrusted for storage."

### References

- ISO/IEC 24745:2022 - Biometric template protection
- Bassit et al. (2022) - Hybrid biometric template protection: https://ietresearch.onlinelibrary.wiley.com/doi/full/10.1049/bme2.12075
- Review of HE for biometrics (PMC 2023): https://pmc.ncbi.nlm.nih.gov/articles/PMC10098691/

---

## 6. Implementation Roadmap

### Phase A: Plaintext Baseline with AES-at-Rest (Quick Win)

**Goal:** Protect stored templates without HE complexity.

**What to do:**
- Encrypt template-db at rest using AES-256-GCM (PostgreSQL TDE or application-level encryption)
- Enable mTLS on all gRPC channels (capture device to gateway, gateway to iris-engine)
- Enable NATS TLS for inter-service communication
- Encrypt object-store (raw images) at rest

**Effort:** ~1-2 weeks
**Complexity:** Low
**Protection gained:** Data-at-rest encryption, transport encryption
**What it doesn't do:** Templates are decrypted in server memory during matching

**Prerequisites:**
- Certificate infrastructure (CA, per-service certificates)
- Key management for AES keys (could use environment variables for dev, HashiCorp Vault for production)

### Phase B: HE for 1:1 Verification

**Goal:** Probe IrisCodes are encrypted; matching happens on encrypted data.

**What to do:**
1. Add OpenFHE C++ dependency to iris-engine build (or use openfhe-python bindings)
2. Implement `HEHammingDistanceMatcher`:
   - BFV context setup (N=8192, t=2, 128-bit security)
   - Encrypt probe IrisCode (server-side, after pipeline)
   - Ciphertext-plaintext multiply with gallery template
   - Rotate-and-sum for inner product
   - Return encrypted result
3. Add key management:
   - Generate HE keypair per capture device (or per session)
   - Transmit evaluation keys to iris-engine at session start
   - Store secret key securely on capture device
4. Add decryption + threshold check on the client side
5. Update NATS message schemas for encrypted payloads
6. Integration tests: verify match accuracy is identical to plaintext matching (HE is exact for BFV, so zero accuracy loss)

**Effort:** ~4-6 weeks
**Complexity:** Medium-High
**Protection gained:** Probe templates never stored in plaintext; matching result is encrypted
**Dependencies:** Phase A complete, OpenFHE library integrated

**Key risk:** Python bindings stability. openfhe-python is at v1.3.0; test thoroughly on target platform (Debian Trixie / Ubuntu 24.04).

### Phase C: HE for 1:N Identification with Indexing

**Goal:** Search against a gallery of enrolled templates using HE.

**What to do:**
1. Implement SIMD-batched matching: pack multiple gallery templates into SIMD slots for parallel comparison
2. Implement encrypted gallery storage (optional, if threat model requires)
3. Add indexing/pruning to avoid scanning the full gallery:
   - Locality-Sensitive Hashing (LSH) on IrisCodes to create buckets
   - Only HE-match against templates in the same bucket
   - LSH operates on plaintext metadata (coarse hash), preserving privacy
4. Optimize rotation key management (generate only needed rotation distances)
5. Benchmark and tune: find the sweet spot between gallery size, latency, and parallelism

**Effort:** ~6-10 weeks
**Complexity:** High
**Protection gained:** Full 1:N identification with template protection
**Dependencies:** Phase B complete, performance baseline established

**Note:** Phase C may not be needed if EyeD primarily does 1:1 verification (user claims identity, system verifies). 1:N identification (who is this person?) is a harder problem and may be deferred indefinitely.

### Timeline Summary

```
Week 0-2:   Phase A (AES-at-rest, mTLS, NATS TLS)
Week 2-8:   Phase B (HE for 1:1 verification)
Week 8-18:  Phase C (HE for 1:N identification) -- optional
```

---

## 7. Risks and Mitigations

### Performance Risk: HE is Too Slow

**Risk:** HE matching adds 30-70ms per 1:1 comparison. For 1:N with large galleries, this could become seconds or minutes.

**Likelihood:** Low for 1:1, Medium for 1:N (>10K gallery).

**Mitigation:**
- 1:1 verification at 30-70ms is acceptable (the Open-IRIS pipeline itself takes ~43ms; HE roughly doubles the total)
- For 1:N, use LSH indexing to reduce candidate set before HE matching
- Consider GPU acceleration: OpenFHE has experimental CUDA support; TFHE-rs has production GPU backend
- Fallback: use HE only for the final match against top-K candidates from a plaintext pre-filter

### Complexity Risk: Key Management Burden

**Risk:** HE key management (generation, distribution, rotation, revocation) adds operational complexity. Evaluation keys are ~100-200MB per client, straining memory and network.

**Likelihood:** Medium.

**Mitigation:**
- Session-based keys: generate fresh HE keys per verification session, discard after use (eliminates key rotation problem, but increases latency by key generation time ~100ms)
- Persistent keys: generate per capture device, store secret key in secure element/TPM, transmit eval keys once and cache
- Compress evaluation keys using key-switching decomposition techniques (trade compute for size)
- Start with a single capture device deployment to validate key management before scaling

### Library Maturity Risk: OpenFHE in Production

**Risk:** OpenFHE is an academic library. While backed by DARPA and used in research, large-scale production deployments are limited.

**Likelihood:** Low-Medium.

**Mitigation:**
- OpenFHE is at v1.4.2 with active development and a NumFOCUS affiliation (same umbrella as NumPy, Pandas)
- The BFV operations we need (encrypt, ciphertext-plaintext multiply, rotate, decrypt) are the most basic and well-tested codepath
- Pin to a specific version, vendor the dependency, and maintain a comprehensive test suite
- SEAL is a fallback: both libraries implement BFV with compatible parameter sets. Migration cost is ~1-2 weeks

### Accuracy Risk: Does HE Change Match Accuracy?

**Risk:** HE might introduce errors that change match outcomes.

**Likelihood:** None (for BFV).

**Mitigation:** BFV performs exact integer arithmetic modulo t. For t=2, every operation is exact -- there is no approximation error. The Hamming distance computed under HE is identical to the plaintext Hamming distance, bit for bit. This is not a risk; it is a mathematical guarantee. (CKKS would introduce approximation error, which is why we do not use CKKS.)

### Regulatory Risk: Does HE Satisfy Compliance Requirements?

**Risk:** Regulators may not understand or accept HE as a sufficient protection measure.

**Likelihood:** Low (trend is positive).

**Mitigation:**
- HE is increasingly recognized in privacy regulations. NIST has published standards for HE parameter selection
- The combination of HE + AES-at-rest + mTLS provides defense in depth
- Document the cryptographic parameters and security proofs for auditors

---

## 8. Recommendation

### Primary Recommendation

**Adopt OpenFHE with BFV (t=2) for IrisCode template protection, following the phased roadmap.**

Justification:

1. **Feasibility is confirmed.** The algebraic trick (HD = Σx + Σy - 2·Σ(x·y)) maps cleanly to BFV's ciphertext-plaintext multiply + rotate-and-sum. Multiplicative depth of 1 is trivial for BFV. Published results (Yasuda et al., 2013) demonstrate 47ms total latency for 2048-bit iris codes on 2013 hardware; our 10,240-bit codes on modern hardware should achieve similar or better times.

2. **OpenFHE is the right library.** It has the best combination of BFV performance, Python bindings (for iris-engine), CMake build system (for C++ services), Docker support, and active development. SEAL is a viable alternative but lacks official Python bindings. TFHE-rs is architecturally wrong for batch Hamming distance.

3. **The overhead is acceptable.** A 30-70ms overhead for 1:1 verification roughly doubles the existing ~43ms pipeline latency. In a biometric verification scenario (user waits 1-2 seconds anyway for capture + feedback), this is imperceptible.

4. **Phase A should be immediate.** AES-at-rest and mTLS cost almost nothing to implement and provide immediate security value. They are prerequisites for any serious deployment, regardless of HE.

5. **Phase C is optional.** Most iris biometric deployments are 1:1 verification (boarding gates, access control). 1:N identification is a different product category. Defer Phase C until there is a concrete business requirement.

### What NOT To Do

- **Do not encrypt the gallery with HE** unless the threat model specifically requires it. Plaintext gallery + encrypted probe gives 90% of the security benefit at 1% of the storage cost.
- **Do not attempt HE on the raw iris image or DNN pipeline.** Running MobileNetV2+UNet++ inference under HE is computationally infeasible (would take hours per frame). HE is for the IrisCode matching step only.
- **Do not use CKKS for binary data.** CKKS is for approximate real-number arithmetic. IrisCodes are binary; BFV with t=2 gives exact results.
- **Do not use TFHE/gate-level schemes.** The per-gate overhead (~7ms) makes 10,240-bit Hamming distance impractical (~72 seconds).
- **Do not skip PAD.** HE protects templates; PAD protects against spoofing. They solve orthogonal problems. Both are needed.

### Decision Matrix

| Approach | Latency | Storage | Complexity | Security | Verdict |
|----------|---------|---------|------------|----------|---------|
| Plaintext + AES-at-rest | ~1ms match | 1.3 KB/template | Low | At-rest only | **Phase A (do now)** |
| HE probe + plaintext gallery | ~50ms match | 1.3 KB/template + 870KB probe | Medium | Strong (probe protected) | **Phase B (do next)** |
| HE probe + HE gallery | ~100ms match | 870 KB/template | High | Strongest | Defer unless required |
| Fully encrypted pipeline | Hours | N/A | Extreme | Theoretical max | **Do not pursue** |

---

## Appendix A: Key References

1. Yasuda, M. et al. (2013). "Packed Homomorphic Encryption Based on Ideal Lattices and Its Application to Biometrics." CD-ARES 2013.
   https://link.springer.com/chapter/10.1007/978-3-642-40588-4_5

2. OpenFHE Library (v1.4.2, 2025). Open-source FHE library.
   https://github.com/openfheorg/openfhe-development

3. Microsoft SEAL (v4.1, 2024). Homomorphic encryption library.
   https://github.com/microsoft/SEAL

4. TFHE-rs (v1.0.0, 2025). Pure Rust TFHE implementation by Zama.
   https://github.com/zama-ai/tfhe-rs

5. Cross-Platform FHE Benchmarking (ePrint 2025/473). Miran et al.
   https://eprint.iacr.org/2025/473

6. CSAIDE 2025 Benchmark Study. Performance Analysis of Leading HE Libraries.
   https://dl.acm.org/doi/10.1145/3729706.3729711

7. Review of HE for Privacy-Preserving Biometrics (2023). Sensors, 23(7), 3566.
   https://pmc.ncbi.nlm.nih.gov/articles/PMC10098691/

8. Bassit et al. (2022). "Hybrid biometric template protection." IET Biometrics.
   https://ietresearch.onlinelibrary.wiley.com/doi/full/10.1049/bme2.12075

9. Privacy-preserving iris authentication using FHE (2020). Multimedia Tools and Applications.
   https://link.springer.com/article/10.1007/s11042-020-08680-5

10. Homomorphic Encryption Security Standard.
    https://homomorphicencryption.org/standard/

---

## Appendix B: BFV Parameter Quick Reference

For copy-paste into OpenFHE setup code:

```
Scheme:              BFV
Polynomial degree:   N = 8192
Plaintext modulus:   t = 2
Security level:      HEStd_128_classic
Coefficient modulus: auto-selected by library (~218 bits for N=8192)
Multiplicative depth: 1 (only need one ciphertext-plaintext multiply)
Batch packing:       Coefficient packing (pack bits into polynomial coefficients)
Slots per ciphertext: 8192 binary values
Ciphertexts per IrisCode: 2 (8192 + 2048 bits, zero-padded)
```

```python
# OpenFHE Python pseudocode
import openfhe

params = openfhe.CCParamsBFVRNS()
params.SetPlaintextModulus(2)
params.SetMultiplicativeDepth(1)
params.SetSecurityLevel(openfhe.HEStd_128_classic)

cc = openfhe.GenCryptoContext(params)
cc.Enable(openfhe.PKE)
cc.Enable(openfhe.KEYSWITCH)
cc.Enable(openfhe.LEVELEDSHE)

keys = cc.KeyGen()
cc.EvalMultKeyGen(keys.secretKey)
cc.EvalRotateKeyGen(keys.secretKey, [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096])
```

---

*This report was produced for internal engineering evaluation. All performance numbers are estimates derived from published research and should be validated with benchmarks on EyeD's target hardware before implementation commitments are made.*
