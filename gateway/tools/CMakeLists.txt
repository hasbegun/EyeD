# Gateway tool binaries

# --- integration_test ---
add_executable(integration_test
    integration_test.cpp)
target_include_directories(integration_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
    ${CMAKE_BINARY_DIR}/proto-gen)
target_link_libraries(integration_test PRIVATE
    proto_gen
    pthread)

# --- ws_test ---
add_executable(ws_test
    ws_test.cpp)
target_include_directories(ws_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(ws_test PRIVATE
    Boost::system
    pthread)
