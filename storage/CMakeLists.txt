cmake_minimum_required(VERSION 3.16)
project(eyed-storage VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

# --- nats.c (FetchContent: small repo, ~1.5MB) ---
FetchContent_Declare(nats_c
    GIT_REPOSITORY https://github.com/nats-io/nats.c.git
    GIT_TAG        v3.8.2
    GIT_SHALLOW    TRUE)
set(NATS_BUILD_STREAMING OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nats_c)

# --- nlohmann/json (system package: nlohmann-json3-dev on ubuntu:22.04) ---
find_package(nlohmann_json REQUIRED)

# --- cpp-httplib — vendored single header (downloaded by Dockerfile via curl).
# Falls back to FetchContent for non-Docker/local builds.
set(HTTPLIB_VENDOR_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/vendor/httplib/httplib.h")
if(EXISTS "${HTTPLIB_VENDOR_HEADER}")
    message(STATUS "cpp-httplib: using vendored header at ${HTTPLIB_VENDOR_HEADER}")
    add_library(httplib_vendor INTERFACE)
    target_include_directories(httplib_vendor INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/vendor/httplib")
    add_library(httplib::httplib ALIAS httplib_vendor)
else()
    message(STATUS "cpp-httplib: vendored header not found, using FetchContent")
    FetchContent_Declare(httplib
        GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
        GIT_TAG        v0.18.3
        GIT_SHALLOW    TRUE)
    FetchContent_MakeAvailable(httplib)
endif()

# OpenSSL — required by cpp-httplib for HTTPS; also needed by nats.c
find_package(OpenSSL REQUIRED)

# --- Storage executable ---
add_executable(storage
    src/main.cpp
    src/local_store.cpp
    src/archive_handler.cpp
    src/retention_purger.cpp
)

target_include_directories(storage PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(storage PRIVATE
    nats
    nlohmann_json::nlohmann_json
    httplib::httplib
    OpenSSL::SSL
    OpenSSL::Crypto
)

# --- Tests (only when tests/ directory is present) ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests")
    enable_testing()
    add_subdirectory(tests)
endif()
