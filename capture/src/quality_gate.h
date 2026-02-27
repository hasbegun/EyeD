#pragma once

#include <vector>

#include <opencv2/core.hpp>

struct QualityConfig {
    float threshold    = 0.30f;
    int   jpeg_quality = 85;
};

class QualityGate {
public:
    explicit QualityGate(const QualityConfig& cfg) : cfg_(cfg) {}

    // Sobel score in [0.0, 1.0]. Higher = sharper.
    float score(const cv::Mat& image) const;

    bool passes(float s) const { return s >= cfg_.threshold; }

    // JPEG-encode the image. Returns empty vector on failure.
    std::vector<uchar> encode_jpeg(const cv::Mat& image) const;

private:
    QualityConfig cfg_;
};
