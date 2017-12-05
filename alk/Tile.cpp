
#include <mbgl/tile/tile_observer.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/tile/raster_tile.hpp>
#include <chrono>

#include "RasterTileRenderer.hpp"
#include "Tile.hpp"

#pragma GCC diagnostic ignored "-Wunused-parameter"

namespace alk {

Tile::Tile(TilePath* path_) : mbgl::Tile(mbgl::OverscaledTileID(path_->zoom, path_->x, path_->y)), path(path_) {}

Tile::~Tile() {
	//std::cout << "Tile " << path->to_s() << " deleted. data.use_count = " <<
	//		data.use_count() << "." << std::endl;
}

void Tile::cancel() {
	std::cout << "Cancel called" << std::endl;
	}

void Tile::setError(std::exception_ptr err) {
	    loaded = true;
	    observer->onTileError(*this, err);
	}

void Tile::setMetadata(std::experimental::optional<mbgl::Timestamp> modified_,
			std::experimental::optional<mbgl::Timestamp> expires_) {
	    modified = modified_;
	    expires = expires_;
	}

void Tile::setData(std::shared_ptr<const std::string> data_) {
	    pending = true;
	    data = data_;
	    observer->onTileChanged(*this);
	}

mbgl::Bucket* Tile::getBucket(const mbgl::style::Layer::Impl& layer) const {
		std::cout << "getBucket!!" << std::endl;
	    return nullptr;
	}

void Tile::upload(mbgl::gl::Context& context) {
		std::cout << "UPLOAD TILE" << std::endl;
	}

}
