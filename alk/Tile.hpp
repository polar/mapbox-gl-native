

#include <mbgl/tile/tile_observer.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/tile/raster_tile.hpp>
#include <chrono>
#include "TilePath.hpp"

#pragma once

namespace alk {

class Tile : public mbgl::Tile {
public:
	Tile(TilePath* path_);
	~Tile();
    void setData(std::shared_ptr<const std::string> data);
    void setError(std::exception_ptr);
    void setMetadata(std::experimental::optional<mbgl::Timestamp> modified,
    		std::experimental::optional<mbgl::Timestamp> expires);
    void cancel();
    void upload(mbgl::gl::Context&);
    mbgl::Bucket* getBucket(const mbgl::style::Layer::Impl&) const;
	TilePath* path;
	std::shared_ptr<const std::string> data;
};

}


