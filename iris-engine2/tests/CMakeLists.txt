cmake_minimum_required(VERSION 3.28)

# --- Test configuration ---
enable_testing()

# --- doctest (header-only testing framework) ---
include(FetchContent)
FetchContent_Declare(
    doctest
    GIT_REPOSITORY https://github.com/doctest/doctest.git
    GIT_TAG        v2.4.11
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(doctest)

# --- Add test executables ---

# Test config
add_executable(test_config test_config.cpp)
target_link_libraries(test_config PRIVATE doctest_with_main iris)
target_include_directories(test_config PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test db (with mocked PostgreSQL)
add_executable(test_db test_db.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/db.cpp)
target_link_libraries(test_db PRIVATE doctest_with_main iris PkgConfig::LIBPQ)
target_include_directories(test_db PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test gallery (needs gallery.cpp + smpc.cpp + smpc_distributed.cpp + nats_client.cpp)
add_executable(test_gallery test_gallery.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/gallery.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/smpc.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/smpc_distributed.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/nats_client.cpp)
target_link_libraries(test_gallery PRIVATE doctest_with_main iris nats_static)
target_include_directories(test_gallery PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test SMPC integration
add_executable(test_smpc test_smpc.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/smpc.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/smpc_distributed.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/nats_client.cpp)
target_link_libraries(test_smpc PRIVATE doctest_with_main iris nats_static)
target_include_directories(test_smpc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test SMPC coordinator+participant (separate TU — no smpc_gallery.hpp conflict)
add_executable(test_smpc_coordinator test_smpc_coordinator.cpp)
target_link_libraries(test_smpc_coordinator PRIVATE doctest_with_main iris)
target_include_directories(test_smpc_coordinator PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# SMPC performance benchmarks (uses smpc_gallery.hpp — no coordinator conflict)
add_executable(bench_smpc bench_smpc.cpp)
target_link_libraries(bench_smpc PRIVATE doctest_with_main iris)
target_include_directories(bench_smpc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test SMPC sharded coordinator+participant (separate TU — no smpc_gallery.hpp conflict)
add_executable(test_smpc_sharded test_smpc_sharded.cpp)
target_link_libraries(test_smpc_sharded PRIVATE doctest_with_main iris)
target_include_directories(test_smpc_sharded PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test SMPC security features (TLS, audit, monitoring — separate TU)
add_executable(test_smpc_security test_smpc_security.cpp)
target_link_libraries(test_smpc_security PRIVATE doctest_with_main iris)
target_include_directories(test_smpc_security PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# SMPC integration tests (I1–I4, I10 — distributed protocol via InMemorySMPCBus)
add_executable(test_smpc_integration integration/smpc_integration.cpp)
target_link_libraries(test_smpc_integration PRIVATE doctest_with_main iris)
target_include_directories(test_smpc_integration PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Migration tests (migrate_templates, add_metadata_only, rollback)
add_executable(test_migration
    test_migration.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/smpc.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/smpc_distributed.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/nats_client.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/gallery.cpp
)
target_link_libraries(test_migration PRIVATE doctest_with_main iris nats)
target_include_directories(test_migration PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# --- Register tests with CTest ---
add_test(NAME test_config COMMAND test_config)
add_test(NAME test_db COMMAND test_db)
add_test(NAME test_gallery COMMAND test_gallery)
add_test(NAME test_smpc COMMAND test_smpc)
add_test(NAME test_smpc_coordinator COMMAND test_smpc_coordinator)
add_test(NAME test_smpc_sharded COMMAND test_smpc_sharded)
add_test(NAME test_smpc_security COMMAND test_smpc_security)
add_test(NAME test_smpc_integration COMMAND test_smpc_integration)
add_test(NAME test_migration COMMAND test_migration)
add_test(NAME bench_smpc COMMAND bench_smpc)

