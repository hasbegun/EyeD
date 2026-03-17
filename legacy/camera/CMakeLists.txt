cmake_minimum_required(VERSION 3.2.3)

project(EyeD)

set(PROJECT_NAME            "EyeD")
set(PROJECT_VERSION         "1.0.0")
set(PROJECT_AUTHOR_NAME     "I.C")
set(PROJECT_AUTHOR_EMAIL    "hasbegun@gmail.com")
set(PROJECT_AUTHOR_WEBSITE  "www.eyedentiscan.com")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Find includes in corresponding build directories
set(CMAKE_INCLUDE_CURRENT_DIR ON)
# Instruct CMake to run moc automatically when needed.
set(CMAKE_AUTOMOC ON)

#######
# TBB #
#######
find_package(TBB)
include_directories(${TBB_INCLUDE_DIRS})
add_definitions(${TBB_DEFINITIONS})

########
# Qt 5 #
########
find_package(Qt5Widgets REQUIRED)

##########
# OpenCV #
##########
set(OpenCV_STATIC OFF)
find_package(OpenCV REQUIRED)
include_directories(${OpenCV_INCLUDE_DIRS})

###############
# Application #
###############
add_subdirectory(src)
