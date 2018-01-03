
#include <mbgl/tile/tile_observer.hpp>
#include <mbgl/storage/file_source.hpp>
#include "RasterTileRenderer.hpp"
#include "RenderCache.hpp"
#include "Tile.hpp"

#pragma once

namespace alk {

class TileLoader {
public:
	TileLoader(TilePath *tilePath_, RasterTileRenderer* renderer_);
	void load(std::function<void (Tile&)> callback);
private:
	void fromCacheOrRenderer(std::function<void (Tile&)> callback) ;
	void loadFromRenderer(mbgl::Response& res, std::function<void (Tile&)> callback);
	void loadFromCache(const mbgl::Response& res);
	Tile tile;
    mbgl::Resource resource;
    RasterTileRenderer* rasterTileRenderer;
    RenderCache* renderCache;
    std::unique_ptr<mbgl::AsyncRequest> request;
    std::function<void (Tile&)> dataCallback;
};


}
