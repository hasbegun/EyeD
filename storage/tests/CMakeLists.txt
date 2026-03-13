cmake_minimum_required(VERSION 3.16)

enable_testing()

# --- doctest (header-only, consistent with iris-engine2 tests) ---
include(FetchContent)
FetchContent_Declare(
    doctest
    GIT_REPOSITORY https://github.com/doctest/doctest.git
    GIT_TAG        v2.4.11
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(doctest)

# --- test_config ---
add_executable(test_config test_config.cpp)
target_link_libraries(test_config PRIVATE doctest_with_main)
target_include_directories(test_config PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_test(NAME test_config COMMAND test_config)

# --- test_local_store ---
add_executable(test_local_store
    test_local_store.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/local_store.cpp)
target_link_libraries(test_local_store PRIVATE doctest_with_main)
target_include_directories(test_local_store PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_test(NAME test_local_store COMMAND test_local_store)

# --- test_archive_handler ---
add_executable(test_archive_handler
    test_archive_handler.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/archive_handler.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/local_store.cpp)
target_link_libraries(test_archive_handler PRIVATE
    doctest_with_main
    nlohmann_json::nlohmann_json)
target_include_directories(test_archive_handler PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_test(NAME test_archive_handler COMMAND test_archive_handler)

# --- test_retention_purger ---
add_executable(test_retention_purger
    test_retention_purger.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/retention_purger.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/local_store.cpp)
target_link_libraries(test_retention_purger PRIVATE doctest_with_main)
target_include_directories(test_retention_purger PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_test(NAME test_retention_purger COMMAND test_retention_purger)
