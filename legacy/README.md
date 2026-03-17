# Legacy Components

This directory contains retired components that are no longer part of the active EyeD system.

## iris-engine (Retired March 2026)

**Status:** Retired in favor of iris-engine2

**Reason for retirement:**
- iris-engine was a Python-based implementation using Open-IRIS library
- Replaced by iris-engine2, a C++ implementation with better performance and native FHE support
- Build issues with Python dependencies and OpenFHE Python bindings
- iris-engine2 provides superior performance and maintainability

**Migration:**
- All services now use iris-engine2 (port 9510) as the default iris recognition engine
- client2 app simplified to remove engine selection UI
- docker-compose.yml updated to remove iris-engine service
- Integration tests now target iris-engine2

**Historical context:**
iris-engine served as the initial proof-of-concept for the EyeD biometric system, validating the architecture and FHE integration approach. The lessons learned from iris-engine directly informed the design of iris-engine2.

**Preservation:**
This code is preserved for reference and historical purposes. It should not be used in production.
