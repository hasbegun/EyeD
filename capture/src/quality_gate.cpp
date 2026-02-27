#include "quality_gate.h"

#include <cmath>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

float QualityGate::score(const cv::Mat& image) const {
    cv::Mat gray = image;
    if (image.channels() > 1) {
        cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    }

    cv::Mat gx, gy, mag;
    cv::Sobel(gray, gx, CV_32F, 1, 0, 3);
    cv::Sobel(gray, gy, CV_32F, 0, 1, 3);
    cv::magnitude(gx, gy, mag);

    const double mean_mag = cv::mean(mag)[0];
    // Normalize: max possible gradient magnitude is 255 * sqrt(2)
    return static_cast<float>(mean_mag / (255.0 * std::sqrt(2.0)));
}

std::vector<uchar> QualityGate::encode_jpeg(const cv::Mat& image) const {
    std::vector<uchar> buf;
    std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, cfg_.jpeg_quality};
    if (!cv::imencode(".jpg", image, buf, params)) {
        buf.clear();
    }
    return buf;
}
