
#ifndef PROCESSINGTHREAD_H
#define PROCESSINGTHREAD_H

#include <QThread>
#include <QTime>
#include <QQueue>
#include <QImage>

#include <opencv2/opencv.hpp>
#include <opencv2/objdetect.hpp>
#include "Structures.h"

using namespace cv;

class SharedImageBuffer;

class ProcessingThread : public QThread
{
    Q_OBJECT

    public:
        ProcessingThread(SharedImageBuffer *sharedImageBuffer, int deviceNumber);
        QRect getCurrentROI();
        void stop();

    private:
        void updateFPS(int);
        void resetROI();
        SharedImageBuffer *m_sharedImageBuffer;
        cv::Mat m_currentFrame;
        cv::Mat m_currentFrameGrayscale;
        cv::Rect m_currentROI;
        QImage m_frame;
        QTime m_t;
        QQueue<int> m_fps;
        QMutex m_doStopMutex;
        QMutex m_processingMutex;
        cv::Size m_frameSize;
        cv::Point m_framePoint;
        ImageProcessingFlags m_imgProcFlags;
        ImageProcessingSettings m_imgProcSettings;
        ThreadStatisticsData m_statsData;
        volatile bool m_doStop;
        int m_processingTime;
        int m_fpsSum;
        int m_sampleNumber;
        int m_deviceNumber;
        bool m_enableFrameProcessing;

        CascadeClassifier faceCascade;
        CascadeClassifier eyeCascade1;
        CascadeClassifier eyeCascade2;
        void initDetectCascades();

    protected:
        void run();

    public slots:
        void updateImageProcessingFlags(ImageProcessingFlags flags);
        void updateImageProcessingSettings(ImageProcessingSettings settings);
        void setROI(QRect roi);

    signals:
        void newFrame(const QImage& frame);
        void updateStatisticsInGUI(ThreadStatisticsData statData);
};

#endif // PROCESSINGTHREAD_H
