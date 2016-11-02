#-------------------------------------------------
#
# Project created by QtCreator 2016-10-12T23:46:45
#
#-------------------------------------------------

QT       += core gui

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = EyeD
TEMPLATE = app

macx {
    OPENCV_PATH = /usr/local/opencv/3.1.0/osx
    LIBS += -L$$OPENCV_PATH/lib \
        -lopencv_core \
        -lopencv_imgproc \
        -lopencv_highgui \
        -lopencv_objdetect \
        -lopencv_video \
        -lopencv_videoio

    INCLUDEPATH += $$OPENCV_PATH/include

    TBB_PATH = /usr/local/opt/tbb
    LIBS += -L$$TBB_PATH/lib \
        -ltbb \
        -ltbbmalloc \
        -ltbbmalloc_proxy
    INCLUDEPATH += $$TBB_PATH/include
}

SOURCES += src/CameraConnectDialog.cpp\
           src/CameraView.cpp\
           src/CaptureThread.cpp\
           src/FrameLabel.cpp\
           src/ImageProcessingSettingsDialog.cpp\
           src/main.cpp\
           src/MainWindow.cpp\
           src/MatToQImage.cpp\
           src/ProcessingThread.cpp\
           src/SharedImageBuffer.cpp \
           src/ImageUtils.cpp \
    src/Faces.cpp

HEADERS  += src/Buffer.h\
            src/CameraConnectDialog.h\
            src/CameraView.h\
            src/CaptureThread.h\
            src/Config.h \
            src/FrameLabel.h\
            src/ImageProcessingSettingsDialog.h\
            src/MainWindow.h\
            src/MatToQImage.h\
            src/ProcessingThread.h\
            src/SharedImageBuffer.h\
            src/Structures.h \
            src/ImageUtils.h \
    src/Faces.h

FORMS    += src/CameraConnectDialog.ui\
            src/CameraView.ui\
            src/ImageProcessingSettingsDialog.ui\
            src/MainWindow.ui
