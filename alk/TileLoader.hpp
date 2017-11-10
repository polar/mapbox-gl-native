
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
	void loadFromCache(std::function<void (Tile&)> callback) ;
	void loadFromRendering(mbgl::Response& res, std::function<void (Tile&)> callback);
	void loadFromRendering(mbgl::Response& res) ;
	void loadedData(const mbgl::Response& res);
	Tile tile;
    mbgl::Resource resource;
    RasterTileRenderer* rasterTileRenderer;
    RenderCache* fileSource;
    std::unique_ptr<mbgl::AsyncRequest> request;
    std::function<void (Tile&)> dataCallback;
};


}
