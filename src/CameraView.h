
#ifndef CAMERAVIEW_H
#define CAMERAVIEW_H

//#include <QWidget>
#include <QtWidgets/QWidget>

#include "Structures.h"

namespace Ui {
    class CameraView;
}

class ProcessingThread;
class CaptureThread;
class SharedImageBuffer;
class ImageProcessingSettingsDialog;

class CameraView : public QWidget
{
    Q_OBJECT

    public:
        explicit CameraView(int deviceNumber, SharedImageBuffer *sharedImageBuffer, QWidget *parent = 0);
        ~CameraView();
        bool connectToCamera(bool dropFrame, int capThreadPrio, int procThreadPrio,
                             bool createProcThread, int width, int height);

    private:
        void stopCaptureThread();
        void stopProcessingThread();
        Ui::CameraView *ui;
        int m_deviceNumber;
        bool m_isCameraConnected;
        ProcessingThread *m_processingThread;
        CaptureThread *m_captureThread;
        SharedImageBuffer *m_sharedImageBuffer;
        ImageProcessingSettingsDialog *m_imageProcessingSettingsDialog;
        ImageProcessingFlags m_imageProcessingFlags;

    public slots:
        void setImageProcessingSettings();
        void newMouseData(MouseData mouseData);
        void updateMouseCursorPosLabel();
        void clearImageBuffer();

    private slots:
        void updateFrame(const QImage &frame);
        void updateProcessingThreadStats(ThreadStatisticsData statData);
        void updateCaptureThreadStats(ThreadStatisticsData statData);
        void handleContextMenuAction(QAction *action);

    signals:
        void newImageProcessingFlags(ImageProcessingFlags imageProcessingFlags);
        void setROI(QRect roi);
};

#endif // CAMERAVIEW_H
