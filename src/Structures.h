
#ifndef STRUCTURES_H
#define STRUCTURES_H

#include <QRect>

typedef struct
{
    int     smoothType;
    int     smoothParam1;
    int     smoothParam2;
    double  smoothParam3;
    double  smoothParam4;
    int     dilateNumberOfIterations;
    int     erodeNumberOfIterations;
    int     flipCode;
    double  cannyThreshold1;
    double  cannyThreshold2;
    int     cannyApertureSize;
    bool    cannyL2gradient;
    QString faceCascade;
    QString eyeCascade1;
    QString eyeCascade2;
} ImageProcessingSettings;

typedef struct
{
    bool grayscaleOn;
    bool smoothOn;
    bool dilateOn;
    bool erodeOn;
    bool flipOn;
    bool cannyOn;
    bool faceDetectOn;
    bool eyeDetectOn;
} ImageProcessingFlags;

typedef struct
{
    QRect selectionBox;
    bool leftButtonRelease;
    bool rightButtonRelease;
} MouseData;

typedef struct
{
    int averageFPS;
    int nFramesProcessed;
} ThreadStatisticsData;

#endif // STRUCTURES_H
