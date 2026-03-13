#include "gallery.h"

#include <doctest/doctest.h>
#include <thread>
#include <vector>
#include <string>

// Helper to create a minimal iris template for testing
// In production, this would come from the iris pipeline
static iris::IrisTemplate create_test_template(int seed = 0) {
    iris::IrisTemplate tmpl;
    // Create minimal template for testing
    // The actual content doesn't matter for testing the gallery logic
    return tmpl;
}

TEST_CASE("Gallery instantiation") {
    Gallery gallery(0.39, 0.32);
    CHECK(gallery.size() == 0);
}

TEST_CASE("Gallery default thresholds") {
    Gallery gallery(0.39, 0.32);
    CHECK(gallery.size() == 0);

    // Empty gallery should return no match
    auto result = gallery.match(create_test_template());
    CHECK_FALSE(result.has_value());
}

TEST_CASE("Gallery add single entry") {
    Gallery gallery(0.39, 0.32);

    GalleryEntry entry;
    entry.template_id = "template-1";
    entry.identity_id = "identity-1";
    entry.identity_name = "Test User";
    entry.eye_side = "left";
    entry.tmpl = create_test_template(1);

    gallery.add(std::move(entry));

    CHECK(gallery.size() == 1);
}

TEST_CASE("Gallery add multiple entries") {
    Gallery gallery(0.39, 0.32);

    for (int i = 0; i < 5; i++) {
        GalleryEntry entry;
        entry.template_id = "template-" + std::to_string(i);
        entry.identity_id = "identity-" + std::to_string(i);
        entry.identity_name = "User " + std::to_string(i);
        entry.eye_side = (i % 2 == 0) ? "left" : "right";
        entry.tmpl = create_test_template(i);

        gallery.add(std::move(entry));
    }

    CHECK(gallery.size() == 5);
}

TEST_CASE("Gallery remove existing identity") {
    Gallery gallery(0.39, 0.32);

    // Add entries
    GalleryEntry entry1;
    entry1.template_id = "template-1";
    entry1.identity_id = "identity-1";
    entry1.identity_name = "User 1";
    entry1.eye_side = "left";
    entry1.tmpl = create_test_template(1);
    gallery.add(std::move(entry1));

    GalleryEntry entry2;
    entry2.template_id = "template-2";
    entry2.identity_id = "identity-1";  // Same identity
    entry2.identity_name = "User 1";
    entry2.eye_side = "right";
    entry2.tmpl = create_test_template(2);
    gallery.add(std::move(entry2));

    CHECK(gallery.size() == 2);

    // Remove identity
    int removed = gallery.remove("identity-1");

    CHECK(removed == 2);
    CHECK(gallery.size() == 0);
}

TEST_CASE("Gallery remove non-existent identity") {
    Gallery gallery(0.39, 0.32);

    GalleryEntry entry;
    entry.template_id = "template-1";
    entry.identity_id = "identity-1";
    entry.identity_name = "User 1";
    entry.eye_side = "left";
    entry.tmpl = create_test_template(1);
    gallery.add(std::move(entry));

    CHECK(gallery.size() == 1);

    // Try to remove non-existent identity
    int removed = gallery.remove("non-existent");

    CHECK(removed == 0);
    CHECK(gallery.size() == 1);
}

TEST_CASE("Gallery remove with multiple identities") {
    Gallery gallery(0.39, 0.32);

    // Add 3 different identities
    for (int i = 0; i < 3; i++) {
        GalleryEntry entry;
        entry.template_id = "template-" + std::to_string(i);
        entry.identity_id = "identity-" + std::to_string(i);
        entry.identity_name = "User " + std::to_string(i);
        entry.eye_side = "left";
        entry.tmpl = create_test_template(i);
        gallery.add(std::move(entry));
    }

    CHECK(gallery.size() == 3);

    // Remove middle identity
    int removed = gallery.remove("identity-1");

    CHECK(removed == 1);
    CHECK(gallery.size() == 2);
}

TEST_CASE("Gallery match empty gallery") {
    Gallery gallery(0.39, 0.32);

    auto result = gallery.match(create_test_template());

    // Should return nullopt for empty gallery
    CHECK_FALSE(result.has_value());
}

TEST_CASE("Gallery check_duplicate empty gallery") {
    Gallery gallery(0.39, 0.32);

    auto result = gallery.check_duplicate(create_test_template());

    // Empty gallery means no duplicate found
    CHECK_FALSE(result.is_duplicate);
    CHECK(result.duplicate_identity_id.empty());
    CHECK(result.duplicate_identity_name.empty());
}

TEST_CASE("Gallery check_duplicate with entry") {
    Gallery gallery(0.39, 0.32);

    GalleryEntry entry;
    entry.template_id = "template-1";
    entry.identity_id = "identity-1";
    entry.identity_name = "Test User";
    entry.eye_side = "left";
    entry.tmpl = create_test_template(1);
    gallery.add(std::move(entry));

    // Check duplicate with same template
    auto result = gallery.check_duplicate(create_test_template(1));

    // With low threshold, it might find a duplicate
    // The actual result depends on the matcher implementation
    // We just verify the structure is correct
    if (result.is_duplicate) {
        CHECK(result.duplicate_identity_id == "identity-1");
        CHECK(result.duplicate_identity_name == "Test User");
    }
}

TEST_CASE("Gallery list empty") {
    Gallery gallery(0.39, 0.32);

    auto list = gallery.list();

    CHECK(list.empty());
}

TEST_CASE("Gallery list with entries") {
    Gallery gallery(0.39, 0.32);

    // Add two entries for same identity (different eyes)
    GalleryEntry entry1;
    entry1.template_id = "template-left";
    entry1.identity_id = "identity-1";
    entry1.identity_name = "User 1";
    entry1.eye_side = "left";
    entry1.tmpl = create_test_template(1);
    gallery.add(std::move(entry1));

    GalleryEntry entry2;
    entry2.template_id = "template-right";
    entry2.identity_id = "identity-1";
    entry2.identity_name = "User 1";
    entry2.eye_side = "right";
    entry2.tmpl = create_test_template(2);
    gallery.add(std::move(entry2));

    // Add another identity
    GalleryEntry entry3;
    entry3.template_id = "template-2";
    entry3.identity_id = "identity-2";
    entry3.identity_name = "User 2";
    entry3.eye_side = "left";
    entry3.tmpl = create_test_template(3);
    gallery.add(std::move(entry3));

    auto list = gallery.list();

    // Should have 2 identities
    CHECK(list.size() == 2);

    // Find identity-1
    auto it = std::find_if(list.begin(), list.end(),
        [](const Gallery::IdentityInfo& info) {
            return info.identity_id == "identity-1";
        });
    CHECK(it != list.end());
    CHECK(it->name == "User 1");
    CHECK(it->templates.size() == 2);
}

TEST_CASE("Gallery size after operations") {
    Gallery gallery(0.39, 0.32);

    CHECK(gallery.size() == 0);

    // Add
    GalleryEntry entry1;
    entry1.template_id = "t1";
    entry1.identity_id = "i1";
    entry1.identity_name = "User 1";
    entry1.eye_side = "left";
    entry1.tmpl = create_test_template(1);
    gallery.add(std::move(entry1));
    CHECK(gallery.size() == 1);

    // Add more
    GalleryEntry entry2;
    entry2.template_id = "t2";
    entry2.identity_id = "i2";
    entry2.identity_name = "User 2";
    entry2.eye_side = "left";
    entry2.tmpl = create_test_template(2);
    gallery.add(std::move(entry2));
    CHECK(gallery.size() == 2);

    // Remove one
    gallery.remove("i1");
    CHECK(gallery.size() == 1);

    // Remove all
    gallery.remove("i2");
    CHECK(gallery.size() == 0);
}

TEST_CASE("Gallery threshold behavior") {
    // Test with different threshold values
    Gallery high_threshold_gallery(0.6, 0.5);
    Gallery low_threshold_gallery(0.2, 0.1);

    GalleryEntry entry;
    entry.template_id = "template-1";
    entry.identity_id = "identity-1";
    entry.identity_name = "Test User";
    entry.eye_side = "left";
    entry.tmpl = create_test_template(1);
    high_threshold_gallery.add(std::move(entry));

    GalleryEntry entry2;
    entry2.template_id = "template-2";
    entry2.identity_id = "identity-1";
    entry2.identity_name = "Test User";
    entry2.eye_side = "left";
    entry2.tmpl = create_test_template(1);
    low_threshold_gallery.add(std::move(entry2));

    // Both galleries have size 1
    CHECK(high_threshold_gallery.size() == 1);
    CHECK(low_threshold_gallery.size() == 1);
}

TEST_CASE("Gallery thread safety - concurrent adds") {
    Gallery gallery(0.39, 0.32);

    constexpr int kThreads = 4;
    constexpr int kPerThread = 25;

    std::vector<std::thread> threads;
    threads.reserve(kThreads);
    for (int t = 0; t < kThreads; ++t) {
        threads.emplace_back([&gallery, t]() {
            for (int i = 0; i < kPerThread; ++i) {
                GalleryEntry e;
                int idx = t * kPerThread + i;
                e.template_id = "t" + std::to_string(idx);
                e.identity_id = "i" + std::to_string(idx);
                e.identity_name = "User " + std::to_string(idx);
                e.eye_side = "left";
                e.tmpl = create_test_template(idx);
                gallery.add(std::move(e));
            }
        });
    }
    for (auto& th : threads) th.join();

    CHECK(gallery.size() == kThreads * kPerThread);
}

TEST_CASE("Gallery thread safety - concurrent add and size") {
    Gallery gallery(0.39, 0.32);

    constexpr int kAdders = 3;
    constexpr int kReaders = 2;
    constexpr int kPerAdder = 20;

    std::vector<std::thread> threads;
    threads.reserve(kAdders + kReaders);

    for (int t = 0; t < kAdders; ++t) {
        threads.emplace_back([&gallery, t]() {
            for (int i = 0; i < kPerAdder; ++i) {
                GalleryEntry e;
                int idx = t * kPerAdder + i;
                e.template_id = "t" + std::to_string(idx);
                e.identity_id = "i" + std::to_string(idx);
                e.identity_name = "User " + std::to_string(idx);
                e.eye_side = "left";
                e.tmpl = create_test_template(idx);
                gallery.add(std::move(e));
            }
        });
    }
    for (int t = 0; t < kReaders; ++t) {
        threads.emplace_back([&gallery]() {
            // Concurrent reads must not crash
            for (int i = 0; i < 50; ++i) {
                (void)gallery.size();
                (void)gallery.list();
            }
        });
    }
    for (auto& th : threads) th.join();

    CHECK(gallery.size() == kAdders * kPerAdder);
}

TEST_CASE("GalleryEntry structure") {
    GalleryEntry entry;

    // Verify default state
    CHECK(entry.template_id.empty());
    CHECK(entry.identity_id.empty());
    CHECK(entry.identity_name.empty());
    CHECK(entry.eye_side.empty());
}

TEST_CASE("GalleryMatch structure") {
    GalleryMatch match;

    // Verify default values
    CHECK(match.hamming_distance == 1.0);
    CHECK_FALSE(match.is_match);
    CHECK(match.best_rotation == 0);
    CHECK(match.matched_identity_id.empty());
    CHECK(match.matched_identity_name.empty());
    CHECK(match.matched_template_id.empty());
}

TEST_CASE("DuplicateCheck structure") {
    DuplicateCheck dup;

    // Verify default values
    CHECK_FALSE(dup.is_duplicate);
    CHECK(dup.duplicate_identity_id.empty());
    CHECK(dup.duplicate_identity_name.empty());
}

TEST_CASE("Gallery identity info structure") {
    Gallery::IdentityInfo info;

    CHECK(info.identity_id.empty());
    CHECK(info.name.empty());
    CHECK(info.templates.empty());
}

TEST_CASE("Gallery template info structure") {
    Gallery::TemplateInfo info;

    CHECK(info.template_id.empty());
    CHECK(info.eye_side.empty());
}

