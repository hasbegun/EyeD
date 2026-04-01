cmake_minimum_required(VERSION 3.28)
project(iris-engine2 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# --- Build libiris as subdirectory (SMPC enabled, no tests/bench) ---
set(IRIS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(IRIS_ENABLE_BENCH OFF CACHE BOOL "" FORCE)
set(IRIS_ENABLE_FHE OFF CACHE BOOL "" FORCE)
set(IRIS_ENABLE_SMPC ON CACHE BOOL "" FORCE)
set(IRIS_ENABLE_COMPARISON OFF CACHE BOOL "" FORCE)
add_subdirectory(libiris)

# --- cpp-httplib (header-only HTTP server) ---
include(FetchContent)
FetchContent_Declare(
    httplib
    GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
    GIT_TAG        v0.18.3
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(httplib)

# --- nats.c (NATS client for distributed SMPC) ---
set(NATS_BUILD_STREAMING OFF CACHE BOOL "" FORCE)
set(NATS_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING_SAVED ${BUILD_TESTING})
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    nats_c
    GIT_REPOSITORY https://github.com/nats-io/nats.c.git
    GIT_TAG        v3.9.1
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(nats_c)
set(BUILD_TESTING ${BUILD_TESTING_SAVED} CACHE BOOL "" FORCE)

# --- libpq (PostgreSQL C client) ---
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBPQ REQUIRED IMPORTED_TARGET libpq)

# --- Service executable ---
add_executable(iris-engine2
    src/main.cpp
    src/db.cpp
    src/smpc.cpp
    src/smpc_distributed.cpp
    src/nats_client.cpp
    src/gallery.cpp
    src/routes_health.cpp
    src/routes_analyze.cpp
    src/routes_enroll.cpp
    src/routes_gallery.cpp
    src/routes_config.cpp
)

target_include_directories(iris-engine2 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(iris-engine2 PRIVATE
    iris
    httplib::httplib
    PkgConfig::LIBPQ
    nats_static
)

# Relax -Werror inherited from libiris for service code
target_compile_options(iris-engine2 PRIVATE -Wno-error)

# --- SMPC Participant binary ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/smpc-party")
    add_executable(smpc-party smpc-party/main.cpp)
    target_link_libraries(smpc-party PRIVATE iris nats_static)
    target_compile_options(smpc-party PRIVATE -Wno-error)
endif()

# --- Tests (only when tests/ directory is present) ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests")
    enable_testing()
    add_subdirectory(tests)
endif()
