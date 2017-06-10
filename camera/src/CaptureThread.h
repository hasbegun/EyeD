
#ifndef CAPTURETHREAD_H
#define CAPTURETHREAD_H

#include <QThread>
#include <QTime>
#include <QQueue>

#include <opencv2/opencv.hpp>

#include "Structures.h"

class SharedImageBuffer;

class CaptureThread : public QThread
{
    Q_OBJECT

    public:
        CaptureThread(SharedImageBuffer *sharedImageBuffer, int deviceNumber, bool dropFrameIfBufferFull, int width, int height);
        void stop();
        bool connectToCamera();
        bool disconnectCamera();
        bool isCameraConnected();
        int getInputSourceWidth();
        int getInputSourceHeight();

    private:
        void updateFPS(int);
        SharedImageBuffer *m_sharedImageBuffer;
        cv::VideoCapture m_cap;
        cv::Mat m_grabbedFrame;
        QTime m_t;
        QMutex m_doStopMutex;
        QQueue<int> m_fps;
        ThreadStatisticsData m_statsData;
        volatile bool m_doStop;
        int m_captureTime;
        int m_sampleNumber;
        int m_fpsSum;
        bool m_dropFrameIfBufferFull;
        int m_deviceNumber;
        int m_width;
        int m_height;

    protected:
        void run();

    signals:
        void updateStatisticsInGUI(ThreadStatisticsData statData);
};

#endif // CAPTURETHREAD_H
