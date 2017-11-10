
#include <mbgl/tile/tile_observer.hpp>
#include <mbgl/storage/file_source.hpp>
#include <chrono>
#include "RasterTileRenderer.hpp"
#include "Tile.hpp"
#include "TileLoader.hpp"

#pragma GCC diagnostic ignored "-Wunused-parameter"

namespace alk {

TileLoader::TileLoader(TilePath* tilePath_, RasterTileRenderer* renderer_) :
		  tile(tilePath_),
	      resource(mbgl::Resource::tile(
	        "/data/{z}/{x}/{y}.png",
	        renderer_->getPixelRatio(),
	        tile.path->x,
	        tile.path->y,
	        tile.path->zoom,
	        mbgl::Tileset::Scheme::XYZ,
	        mbgl::Resource::LoadingMethod::CacheOnly)),
			rasterTileRenderer(renderer_),
	      fileSource(&renderer_->getRenderCache())
	{
			assert(!this->request);
	}

void TileLoader::load(std::function<void (Tile&)> callback) {
		loadFromCache(callback);
	}
void TileLoader::loadFromCache(std::function<void (Tile&)> callback) {
	    assert(!request);

	    std::cerr << "Load from Cache " << tile.path->to_s() << std::endl;
	    resource.loadingMethod = mbgl::Resource::LoadingMethod::CacheOnly;
	    request = fileSource->request(resource, [this, callback](mbgl::Response res) {
	        request.reset();

	        if (res.error && res.error->reason == mbgl::Response::Error::Reason::NotFound) {
	            // When the cache-only request could not be satisfied, don't treat it as an error.
	            // A cache lookup could still return data, _and_ an error, in particular when we were
	            // able to find the data, but it is expired and the Cache-Control headers indicated that
	            // we aren't allowed to use expired responses. In this case, we still get the data which
	            // we can use in our conditional network request.
	            resource.priorModified = res.modified;
	            resource.priorExpires = res.expires;
	            resource.priorEtag = res.etag;
	            resource.priorData = res.data;
	        	std::cout << "Not Found in Cache " << tile.path->to_s() << std::endl;
	            loadFromRendering(res, [this, callback] (Tile& tile_) {
	            	callback(tile_);
	            });
	        } else {
	        	std::cout << "Found in Cache " << tile.path->to_s() << std::endl;
	            loadedData(res);
		        callback(tile);
	        }
	    });
	}

void TileLoader::loadFromRendering(mbgl::Response& response, std::function<void (Tile&)> callback) {
	rasterTileRenderer->renderTile(tile.path, [this, response, callback] (const std::string data) {
		mbgl::Timestamp begin = mbgl::util::now();
		// TODO:: FIx Expired Time
		tile.setMetadata(begin, begin + std::chrono::hours(30));
		// We make shared pointer to the data, because the put will be an async task.
		auto d = std::make_shared<const std::string>(data);
		tile.setData(d);
		mbgl::Response resp;
		resp.noContent = false;
		resp.data = d;
		resp.mustRevalidate = false;
		// This is an async task that will be executing on another thread.
		// It will release the shared object;
		fileSource->put(resource, resp);
		callback(tile);
	});
}

void TileLoader::loadFromRendering(mbgl::Response& res) {
	}

void TileLoader::loadedData(const mbgl::Response& res) {
	    if (res.error && res.error->reason != mbgl::Response::Error::Reason::NotFound) {
	        tile.setError(std::make_exception_ptr(std::runtime_error(res.error->message)));
	    } else if (res.notModified) {
	        resource.priorExpires = res.expires;
	        // Do not notify the tile; when we get this message, it already has the current
	        // version of the data.
	        tile.setMetadata(res.modified, res.expires);
	    } else {
	        resource.priorModified = res.modified;
	        resource.priorExpires = res.expires;
	        resource.priorEtag = res.etag;
	        tile.setMetadata(res.modified, res.expires);
	        if (!res.noContent) {
	        	tile.setData(res.data);
	        }
	    }
	}
}
