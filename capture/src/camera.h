#pragma once

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>

struct CameraConfig {
    std::string source         = "directory"; // "directory" | "webcam"
    std::string image_dir      = "/data/Iris/CASIA1";
    std::string device         = "/dev/video0"; // device path or stream URL
    int         width          = 640;
    int         height         = 480;
    int         frame_rate_fps = 30;
    std::string eye_side       = "left";
    bool        is_nir         = false;
};

class Camera {
public:
    explicit Camera(const CameraConfig& cfg);

    // Blocks until next frame is due (rate limiting), then returns it.
    // Returns false on permanent failure (e.g. empty directory, camera lost).
    bool next_frame(cv::Mat& out_image, uint64_t& out_timestamp_us);

    const std::string& eye_side() const { return cfg_.eye_side; }
    bool is_nir() const { return cfg_.is_nir; }
    bool is_available() const;

private:
    CameraConfig cfg_;

    // Directory mode
    std::vector<std::string> image_paths_;
    std::size_t dir_index_ = 0;
    std::chrono::steady_clock::time_point last_frame_time_{};
    std::chrono::microseconds frame_interval_us_{};

    // Webcam mode
    cv::VideoCapture cap_;

    void load_directory_images();
    bool capture_from_directory(cv::Mat& out, uint64_t& ts);
    bool capture_from_webcam(cv::Mat& out, uint64_t& ts);
};
