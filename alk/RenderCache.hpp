
#pragma once

#include <mbgl/actor/actor_ref.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/storage/offline.hpp>
#include <mbgl/util/constants.hpp>
#include <mbgl/util/optional.hpp>

#include <vector>
#include <mutex>

namespace mbgl {

namespace util {
template <typename T> class Thread;
} // namespace util

class ResourceTransform;
}

namespace alk {

class RenderCache : public mbgl::FileSource {
public:
	RenderCache(const std::string& cachePath, uint64_t maximumCacheSize);
    ~RenderCache() override;

    std::unique_ptr<mbgl::AsyncRequest> request(const mbgl::Resource&, Callback) override;

    /*
     * Pause file request activity.
     *
     * If pause is called then no revalidation or network request activity
     * will occur.
     */
    void pause();

    /*
     * Resume file request activity.
     *
     * Calling resume will unpause the file source and process any tasks that
     * expired while the file source was paused.
     */
    void resume();

    void put(const mbgl::Resource&, const mbgl::Response&);

    class Impl;
private:
    const std::unique_ptr<mbgl::util::Thread<Impl>> impl;

    std::mutex cachedBaseURLMutex;
    std::string cachedBaseURL = mbgl::util::API_BASE_URL;

};

}
