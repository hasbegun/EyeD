
#ifndef IMAGEPROCESSINGSETTINGSDIALOG_H
#define IMAGEPROCESSINGSETTINGSDIALOG_H

#include <QDialog>

#include "Structures.h"

namespace Ui {
class ImageProcessingSettingsDialog;
}

class QAbstractButton;

class ImageProcessingSettingsDialog : public QDialog
{
    Q_OBJECT

    public:
        explicit ImageProcessingSettingsDialog(QWidget *parent = 0);
        ~ImageProcessingSettingsDialog();
        void updateDialogSettingsFromStored();

    private:
        Ui::ImageProcessingSettingsDialog *ui;
        ImageProcessingSettings m_imageProcessingSettings;

    public slots:
        void resetAllDialogToDefaults();
        void updateStoredSettingsFromDialog();

    private slots:
        void resetSmoothDialogToDefaults();
        void resetDilateDialogToDefaults();
        void resetErodeDialogToDefaults();
        void resetFlipDialogToDefaults();
        void resetCannyDialogToDefaults();
        void validateDialog();
        void smoothTypeChange(QAbstractButton *button);

    signals:
        void newImageProcessingSettings(ImageProcessingSettings settings);
};

#endif // IMAGEPROCESSINGSETTINGSDIALOG_H
