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

# Test gallery (needs gallery.cpp + fhe.cpp for FHE-aware gallery)
add_executable(test_gallery test_gallery.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/gallery.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/fhe.cpp)
target_link_libraries(test_gallery PRIVATE doctest_with_main iris)
target_include_directories(test_gallery PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Test FHE integration
add_executable(test_fhe test_fhe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/fhe.cpp)
target_link_libraries(test_fhe PRIVATE doctest_with_main iris)
target_include_directories(test_fhe PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# --- Register tests with CTest ---
add_test(NAME test_config COMMAND test_config)
add_test(NAME test_db COMMAND test_db)
add_test(NAME test_gallery COMMAND test_gallery)
add_test(NAME test_fhe COMMAND test_fhe)

