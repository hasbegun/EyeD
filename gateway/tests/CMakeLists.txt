# Gateway unit tests

# --- doctest ---
include(FetchContent)
FetchContent_Declare(doctest
    GIT_REPOSITORY https://github.com/doctest/doctest.git
    GIT_TAG        v2.4.11
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(doctest)

# --- test_config ---
add_executable(test_config test_config.cpp)
target_include_directories(test_config PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_test(NAME test_config COMMAND test_config)

# --- test_breaker ---
add_executable(test_breaker
    test_breaker.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/breaker.cpp)
target_include_directories(test_breaker PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_test(NAME test_breaker COMMAND test_breaker)

# --- test_nats_client ---
add_executable(test_nats_client
    test_nats_client.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/nats_client.cpp)
target_include_directories(test_nats_client PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
    ${nats_c_SOURCE_DIR}/src)
target_link_libraries(test_nats_client PRIVATE nats_static nlohmann_json::nlohmann_json)
add_test(NAME test_nats_client COMMAND test_nats_client)

# --- test_grpc_server ---
add_executable(test_grpc_server
    test_grpc_server.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/grpc_server.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/nats_client.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/breaker.cpp)
target_include_directories(test_grpc_server PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
    ${CMAKE_BINARY_DIR}/proto-gen
    ${nats_c_SOURCE_DIR}/src)
target_link_libraries(test_grpc_server PRIVATE proto_gen nats_static nlohmann_json::nlohmann_json)
add_test(NAME test_grpc_server COMMAND test_grpc_server)

# --- test_http_server ---
add_executable(test_http_server
    test_http_server.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/http_server.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/nats_client.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/breaker.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ws_hub.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/signaling_hub.cpp)
target_include_directories(test_http_server PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
    ${nats_c_SOURCE_DIR}/src)
target_link_libraries(test_http_server PRIVATE nats_static nlohmann_json::nlohmann_json Boost::system pthread)
add_test(NAME test_http_server COMMAND test_http_server)

# --- test_ws_hub ---
add_executable(test_ws_hub
    test_ws_hub.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ws_hub.cpp)
target_include_directories(test_ws_hub PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(test_ws_hub PRIVATE nlohmann_json::nlohmann_json)
add_test(NAME test_ws_hub COMMAND test_ws_hub)

# --- test_signaling_hub ---
add_executable(test_signaling_hub
    test_signaling_hub.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/signaling_hub.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ws_hub.cpp)
target_include_directories(test_signaling_hub PRIVATE
    ${doctest_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(test_signaling_hub PRIVATE nlohmann_json::nlohmann_json)
add_test(NAME test_signaling_hub COMMAND test_signaling_hub)
