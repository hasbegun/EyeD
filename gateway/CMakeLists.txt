cmake_minimum_required(VERSION 3.25)
project(eyed-gateway VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# --- nats.c ---
FetchContent_Declare(nats_c
    GIT_REPOSITORY https://github.com/nats-io/nats.c.git
    GIT_TAG        v3.8.2
    GIT_SHALLOW    TRUE)
set(NATS_BUILD_STREAMING OFF CACHE BOOL "" FORCE)
set(NATS_BUILD_LIB_STATIC ON CACHE BOOL "" FORCE)
set(NATS_BUILD_LIB_SHARED OFF CACHE BOOL "" FORCE)
set(NATS_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nats_c)

# --- nlohmann/json (system) ---
find_package(nlohmann_json REQUIRED)

# --- gRPC + Protobuf (system) ---
find_package(Protobuf REQUIRED)
find_package(gRPC CONFIG QUIET)
if(NOT gRPC_FOUND)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GRPC REQUIRED IMPORTED_TARGET grpc++)
    find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin REQUIRED)
endif()

# --- Boost (Beast, Asio, System) ---
find_package(Boost REQUIRED COMPONENTS system)

# --- Proto code generation ---
set(PROTO_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../proto")
set(PROTO_OUT_DIR "${CMAKE_BINARY_DIR}/proto-gen")
file(MAKE_DIRECTORY "${PROTO_OUT_DIR}")

if(gRPC_FOUND)
    set(_GRPC_CPP_PLUGIN $<TARGET_FILE:gRPC::grpc_cpp_plugin>)
else()
    set(_GRPC_CPP_PLUGIN "${GRPC_CPP_PLUGIN}")
endif()

add_custom_command(
    OUTPUT
        "${PROTO_OUT_DIR}/capture.pb.cc"
        "${PROTO_OUT_DIR}/capture.pb.h"
        "${PROTO_OUT_DIR}/capture.grpc.pb.cc"
        "${PROTO_OUT_DIR}/capture.grpc.pb.h"
    COMMAND ${Protobuf_PROTOC_EXECUTABLE}
        --cpp_out="${PROTO_OUT_DIR}"
        --grpc_out="${PROTO_OUT_DIR}"
        --plugin=protoc-gen-grpc="${_GRPC_CPP_PLUGIN}"
        -I "${PROTO_SRC_DIR}"
        "${PROTO_SRC_DIR}/capture.proto"
    DEPENDS "${PROTO_SRC_DIR}/capture.proto"
    COMMENT "Generating C++ proto/gRPC stubs"
)

add_library(proto_gen STATIC
    "${PROTO_OUT_DIR}/capture.pb.cc"
    "${PROTO_OUT_DIR}/capture.grpc.pb.cc"
)
target_include_directories(proto_gen PUBLIC "${PROTO_OUT_DIR}")
if(gRPC_FOUND)
    target_link_libraries(proto_gen PUBLIC protobuf::libprotobuf gRPC::grpc++ gRPC::grpc++_reflection)
else()
    target_link_libraries(proto_gen PUBLIC protobuf::libprotobuf PkgConfig::GRPC)
endif()

# --- Gateway executable ---
add_executable(gateway
    src/main.cpp
    src/breaker.cpp
    src/nats_client.cpp
    src/grpc_server.cpp
    src/http_server.cpp
    src/ws_hub.cpp
    src/signaling_hub.cpp
)

target_include_directories(gateway PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${PROTO_OUT_DIR}
    ${nats_c_SOURCE_DIR}/src
)

target_link_libraries(gateway PRIVATE
    proto_gen
    nats_static
    nlohmann_json::nlohmann_json
    Boost::system
    pthread
)

# --- Unit Tests ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests")
    enable_testing()
    add_subdirectory(tests)
endif()

# --- Tools ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools")
    add_subdirectory(tools)
endif()
