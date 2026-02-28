cmake_minimum_required(VERSION 3.16)
project(eyed-tools LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Homebrew on Apple Silicon / Intel
if(APPLE AND NOT DEFINED CMAKE_PREFIX_PATH)
    foreach(_prefix /opt/homebrew /usr/local)
        if(EXISTS "${_prefix}/opt/opencv/lib/cmake/opencv4")
            list(APPEND CMAKE_PREFIX_PATH "${_prefix}/opt/opencv")
            break()
        endif()
    endforeach()
endif()

find_package(OpenCV REQUIRED COMPONENTS core imgcodecs imgproc videoio)

add_executable(webcam-relay webcam-relay.cpp)
target_link_libraries(webcam-relay PRIVATE ${OpenCV_LIBS})

if(UNIX AND NOT APPLE)
    target_link_libraries(webcam-relay PRIVATE pthread)
endif()
