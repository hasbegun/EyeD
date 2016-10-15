
#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QMap>

namespace Ui {
    class MainWindow;
}

class SharedImageBuffer;
class CameraView;
class QPushButton;

class MainWindow : public QMainWindow
{
    Q_OBJECT

    public:
        explicit MainWindow(QWidget *parent = 0);
        ~MainWindow();

    private:
        bool removeFromMapByTabIndex(QMap<int, int>& map, int tabIndex);
        void updateMapValues(QMap<int, int>& map, int tabIndex);
        void setTabCloseToolTips(QTabWidget *tabs, QString tooltip);
        Ui::MainWindow *ui;
        QPushButton *m_connectToCameraButton;
        QMap<int, int> m_deviceNumberMap;
        QMap<int, CameraView*> m_cameraViewMap;
        SharedImageBuffer *m_sharedImageBuffer;

    public slots:
        void connectToCamera();
        void disconnectCamera(int index);
        void showAboutDialog();
        void setFullScreen(bool enable);
};

#endif // MAINWINDOW_H
