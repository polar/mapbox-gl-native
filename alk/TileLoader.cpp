
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
	      renderCache(&renderer_->getRenderCache())
	{
			assert(!this->request);
	}

void TileLoader::load(std::function<void (Tile&)> callback) {
		fromCacheOrRenderer(callback);
	}

void TileLoader::fromCacheOrRenderer(std::function<void (Tile&)> callback) {
	    assert(!request);

	    std::cerr << "Load from Cache " << tile.path->to_s() << std::endl;
	    resource.loadingMethod = mbgl::Resource::LoadingMethod::CacheOnly;
	    request = renderCache->request(resource, [this, callback](mbgl::Response res) {
	        request.reset();

	        if (res.error && res.error->reason == mbgl::Response::Error::Reason::NotFound) {
	            resource.priorModified = res.modified;
	            resource.priorExpires = res.expires;
	            resource.priorEtag = res.etag;
	            resource.priorData = res.data;
	        	std::cout << "Not Found in Cache " << tile.path->to_s() << std::endl;
	            loadFromRenderer(res, [this, callback] (Tile& tile_) {
	            	callback(tile_);
	            });
	        } else {
	        	std::cout << "Found in Cache " << tile.path->to_s() << std::endl;
	            loadFromCache(res);
		        callback(tile);
	        }
	    });
	}

void TileLoader::loadFromRenderer(mbgl::Response& response, std::function<void (Tile&)> callback) {
	rasterTileRenderer->renderTile(tile.path, [this, response, callback] (const std::string data) {
		mbgl::Timestamp begin = mbgl::util::now();
		// TODO:: Fix Expired Time
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
		renderCache->put(resource, resp);
		callback(tile);
	});
}

void TileLoader::loadFromCache(const mbgl::Response& res) {
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
