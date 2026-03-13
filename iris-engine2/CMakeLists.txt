cmake_minimum_required(VERSION 3.28)
project(iris-engine2 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# --- Build libiris as subdirectory (FHE enabled, no tests/bench) ---
set(IRIS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(IRIS_ENABLE_BENCH OFF CACHE BOOL "" FORCE)
set(IRIS_ENABLE_FHE ON CACHE BOOL "" FORCE)
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

# --- libpq (PostgreSQL C client) ---
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBPQ REQUIRED IMPORTED_TARGET libpq)

# --- Service executable ---
add_executable(iris-engine2
    src/main.cpp
    src/db.cpp
    src/fhe.cpp
    src/gallery.cpp
)

target_include_directories(iris-engine2 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(iris-engine2 PRIVATE
    iris
    httplib::httplib
    PkgConfig::LIBPQ
)

# Relax -Werror inherited from libiris for service code
target_compile_options(iris-engine2 PRIVATE -Wno-error)

# --- Tests (only when tests/ directory is present) ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests")
    enable_testing()
    add_subdirectory(tests)
endif()
