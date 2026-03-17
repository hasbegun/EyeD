
#ifndef SHAREDIMAGEBUFFER_H
#define SHAREDIMAGEBUFFER_H

#include <QHash>
#include <QSet>
#include <QWaitCondition>
#include <QMutex>

#include <opencv2/opencv.hpp>

#include "Buffer.h"

class SharedImageBuffer
{
    public:
        SharedImageBuffer();
        void add(int deviceNumber, Buffer<cv::Mat> *imageBuffer, bool sync = false);
        Buffer<cv::Mat>* getByDeviceNumber(int deviceNumber);
        void removeByDeviceNumber(int deviceNumber);
        void sync(int deviceNumber);
        void wakeAll();
        void setSyncEnabled(bool enable);
        bool isSyncEnabledForDeviceNumber(int deviceNumber);
        bool getSyncEnabled();
        bool containsImageBufferForDeviceNumber(int deviceNumber);

    private:
        QHash<int, Buffer<cv::Mat>*> m_imageBufferMap;
        QSet<int> m_syncSet;
        QWaitCondition m_wc;
        QMutex m_mutex;
        int m_nArrived;
        bool m_doSync;
};

#endif // SHAREDIMAGEBUFFER_H
