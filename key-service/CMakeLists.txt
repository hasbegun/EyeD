cmake_minimum_required(VERSION 3.16)
project(eyed-key-service VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- OpenFHE ---
find_package(OpenFHE REQUIRED)
if(OpenFHE_FOUND)
    message(STATUS "Found OpenFHE ${OpenFHE_VERSION}")
endif()

# --- nats.c (C client for NATS messaging) ---
include(FetchContent)

FetchContent_Declare(
    nats_c
    GIT_REPOSITORY https://github.com/nats-io/nats.c.git
    GIT_TAG        v3.8.2
    GIT_SHALLOW    TRUE
)
set(NATS_BUILD_STREAMING OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nats_c)

# --- nlohmann/json ---
FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

# --- key-service executable ---
add_executable(key-service
    src/main.cpp
    src/he_context.cpp
    src/handlers.cpp
)

target_include_directories(key-service PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${OpenFHE_INCLUDE}
    ${OpenFHE_INCLUDE}/third-party/include
    ${OpenFHE_INCLUDE}/core
    ${OpenFHE_INCLUDE}/pke
    ${OpenFHE_INCLUDE}/binfhe
)

target_link_libraries(key-service PRIVATE
    ${OpenFHE_LIBRARIES}
    nats
    nlohmann_json::nlohmann_json
)

# OpenFHE may need OpenMP
find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    target_link_libraries(key-service PRIVATE OpenMP::OpenMP_CXX)
endif()
