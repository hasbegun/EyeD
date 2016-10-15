
#ifndef MATTOQIMAGE_H
#define MATTOQIMAGE_H

#include <QImage>

#include <opencv2/opencv.hpp>

QImage MatToQImage(const cv::Mat& mat);

#endif // MATTOQIMAGE_H
