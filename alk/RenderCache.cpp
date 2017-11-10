

#include <mbgl/actor/actor_ref.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/storage/file_source_request.hpp>
#include <mbgl/storage/offline.hpp>
#include <mbgl/util/constants.hpp>
#include <mbgl/util/optional.hpp>
#include <mbgl/storage/offline_database.hpp>

#include <vector>
#include <mutex>
#include <string>

#include <mbgl/util/platform.hpp>
#include <mbgl/util/url.hpp>
#include <mbgl/util/thread.hpp>
#include <mbgl/util/work_request.hpp>
#include <iostream>

#include "RenderCache.hpp"

#pragma GCC diagnostic ignored "-Wunused-parameter"

namespace alk {

class RenderCache::Impl {
public:
    Impl(mbgl::ActorRef<Impl> self, const std::string& cachePath, uint64_t maximumCacheSize) {
        // Initialize the Database asynchronously so as to not block Actor creation.
        self.invoke(&Impl::initializeOfflineDatabase, cachePath, maximumCacheSize);
    }

    void initializeOfflineDatabase(std::string cachePath, uint64_t maximumCacheSize) {
        offlineDatabase = std::make_unique<mbgl::OfflineDatabase>(cachePath, maximumCacheSize);
    }

    void put(const mbgl::Resource& resource, const mbgl::Response& response) {
        offlineDatabase->put(resource, response);
        std::cout << "Put " << resource.url << std::endl;
    }

    void request(mbgl::AsyncRequest* req, mbgl::Resource resource, mbgl::ActorRef<mbgl::FileSourceRequest> ref) {
        auto callback = [ref] (const mbgl::Response& res) mutable {
            ref.invoke(&mbgl::FileSourceRequest::setResponse, res);
        };
        auto offlineResponse = offlineDatabase->get(resource);
        if (!offlineResponse) {
			// Ensure there's always a response that we can send, so the caller knows that
			// there's no optional data available in the cache, when it's the only place
			// we're supposed to load from.
			offlineResponse.emplace();
			offlineResponse->noContent = true;
			offlineResponse->error = std::make_unique<mbgl::Response::Error>(
					mbgl::Response::Error::Reason::NotFound, "Not found in offline database");
			callback(*offlineResponse);
        } else {
        	if (!offlineResponse->isUsable()) {
				// Don't return resources the server requested not to show when they're stale.
				// Even if we can't directly use the response, we may still use it to send a
				// conditional HTTP request, which is why we're saving it above.
				offlineResponse->error = std::make_unique<mbgl::Response::Error>(
						mbgl::Response::Error::Reason::NotFound, "Cached resource is unusable");
				callback(*offlineResponse);
        	} else {
				// Copy over the fields so that we can use them when making a refresh request.
				resource.priorModified = offlineResponse->modified;
				resource.priorExpires = offlineResponse->expires;
				resource.priorEtag = offlineResponse->etag;
				resource.priorData = offlineResponse->data;
				callback(*offlineResponse);
        	}
        }
    }

    void cancel(mbgl::AsyncRequest* req) {
        tasks.erase(req);
    }

private:
    std::unordered_map<mbgl::AsyncRequest*, std::unique_ptr<mbgl::AsyncRequest>> tasks;
    std::unique_ptr<mbgl::OfflineDatabase> offlineDatabase;
};

RenderCache::RenderCache(const std::string& cachePath, uint64_t maximumCacheSize) :
		impl(std::make_unique<mbgl::util::Thread<Impl>>("RenderCache", cachePath, maximumCacheSize)) {
}


RenderCache::~RenderCache() = default;

std::unique_ptr<mbgl::AsyncRequest> RenderCache::request(const mbgl::Resource& resource, Callback callback) {
    auto req = std::make_unique<mbgl::FileSourceRequest>(std::move(callback));

    req->onCancel([fs = impl->actor(), req = req.get()] () mutable { fs.invoke(&Impl::cancel, req); });

    impl->actor().invoke(&Impl::request, req.get(), resource, req->actor());

    return std::move(req);
}

void RenderCache::pause() {
    impl->pause();
}

void RenderCache::resume() {
    impl->resume();
}

void RenderCache::put(const mbgl::Resource& resource, const mbgl::Response& response) {
    impl->actor().invoke(&Impl::put, resource, response);
}

}
