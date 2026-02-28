cmake_minimum_required(VERSION 3.25)
project(capture_device LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---- Dependencies ----
find_package(Protobuf REQUIRED)
find_package(OpenCV 4 REQUIRED COMPONENTS core imgcodecs imgproc videoio)
find_package(spdlog REQUIRED)

# gRPC — try CONFIG mode first (bookworm provides it), fall back to pkg-config
find_package(gRPC CONFIG QUIET)
if(NOT gRPC_FOUND)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GRPC REQUIRED IMPORTED_TARGET grpc++)
    # Find the grpc_cpp_plugin
    find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin REQUIRED)
endif()

# toml++ — header-only, single header downloaded to /usr/local/include
add_library(tomlplusplus INTERFACE)
target_include_directories(tomlplusplus INTERFACE /usr/local/include)

# ---- Proto code generation ----
set(PROTO_SRC_DIR "${CMAKE_SOURCE_DIR}/../proto")
set(PROTO_OUT_DIR "${CMAKE_BINARY_DIR}/proto-gen")
file(MAKE_DIRECTORY "${PROTO_OUT_DIR}")

# Determine protoc and grpc_cpp_plugin paths
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
    COMMENT "Generating C++ proto/gRPC stubs from capture.proto"
)

add_library(proto_gen STATIC
    "${PROTO_OUT_DIR}/capture.pb.cc"
    "${PROTO_OUT_DIR}/capture.grpc.pb.cc"
)
target_include_directories(proto_gen PUBLIC "${PROTO_OUT_DIR}")

if(gRPC_FOUND)
    target_link_libraries(proto_gen PUBLIC protobuf::libprotobuf gRPC::grpc++)
else()
    target_link_libraries(proto_gen PUBLIC protobuf::libprotobuf PkgConfig::GRPC)
endif()

# ---- Main executable ----
add_executable(capture_device
    src/main.cpp
    src/camera.cpp
    src/quality_gate.cpp
    src/client.cpp
)

target_include_directories(capture_device PRIVATE
    src
    "${PROTO_OUT_DIR}"
)

target_link_libraries(capture_device PRIVATE
    proto_gen
    ${OpenCV_LIBS}
    spdlog::spdlog
)

target_link_libraries(capture_device PRIVATE tomlplusplus)
