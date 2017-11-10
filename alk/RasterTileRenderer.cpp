/*
 *
 */

#include <mbgl/util/run_loop.hpp>

#include <mbgl/gl/context.hpp>
#include <mbgl/gl/headless_frontend.hpp>
#include <mbgl/util/default_thread_pool.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/style/style.hpp>
#include <mbgl/util/tileset.hpp>
#include <mbgl/tile/tile_id.hpp>
#include <mbgl/renderer/tile_parameters.hpp>
#include <mbgl/tile/tile_loader.hpp>
#include <mbgl/tile/tile_observer.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/tile/raster_tile.hpp>
#include <chrono>

#include "RenderCache.hpp"
#include "RasterTileRenderer.hpp"

namespace alk {

RasterTileRenderer::RasterTileRenderer(
		std::string styleUrl_,
		const uint32_t width_,
		const uint32_t height_,
		double pixelRatio_,
		double bearing_,
		double pitch_,
		RenderCache& renderCache_,
        mbgl::FileSource& fileSource_)
	: styleUrl(styleUrl_),
	  width(width_),
	  height(height_),
	  pixelRatio(pixelRatio_),
	  bearing(bearing_),
	  pitch(pitch_),
	  renderCache(renderCache_),
	  fileSource(fileSource_),
	  threadPool(1),
	  frontend({ width, height }, pixelRatio,
	    		 fileSource, this->threadPool),
	  map(this->frontend,
			        mbgl::MapObserver::nullObserver(),
					this->frontend.getSize(),
					pixelRatio,
					fileSource,
					this->threadPool,
					mbgl::MapMode::Still) {

    if (styleUrl.find("://") == std::string::npos) {
    	styleUrl = std::string("file://") + styleUrl;
    }
    map.getStyle().loadURL(styleUrl);
    map.setBearing(bearing);
    map.setPitch(pitch);
    map.setDebug(mbgl::MapDebugOptions::TileBorders |
    		mbgl::MapDebugOptions::ParseStatus);

};

double RasterTileRenderer::getPixelRatio() {
	return pixelRatio;
}
double RasterTileRenderer::getBearing() {
	return bearing;
}
double RasterTileRenderer::getPitch() {
	return pitch;
}
RenderCache& RasterTileRenderer::getRenderCache() {
	return renderCache;
}
mbgl::FileSource& RasterTileRenderer::getFileSource() {
	return fileSource;
}

// http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
static void tile2lonlat(long long x, long long y, int zoom, double *lon, double *lat) {
	unsigned long long n = 1LL << zoom;
	*lon = 360.0 * x / n - 180.0;
	*lat = atan(sinh(M_PI * (1 - 2.0 * y / n))) * 180.0 / M_PI;
}

void RasterTileRenderer::renderTile(TilePath *path, std::function<void (const std::string data)> callback) {
	std::chrono::steady_clock::time_point begin =
			std::chrono::steady_clock::now();
	double lat = 0, lon = 0;
	tile2lonlat(path->x, path->y, path->zoom, &lon, &lat);
	map.setLatLngZoom( { lat, lon }, path->zoom);
	map.moveBy( { width / 2.0, height / 2.0 });
	std::cout << "Rendering.... " << path->to_s() << std::endl;
	frontend.render(map, [=] (mbgl::PremultipliedImage result) {
		std::chrono::steady_clock::time_point end =
				std::chrono::steady_clock::now();
		std::cout << "........Rendered "
				<< path->to_s()
				<< " in " << std::chrono::duration_cast<std::chrono::milliseconds>(
						end - begin).count() << "ms" << std::endl;
		auto data = mbgl::encodePNG(std::move(result));
		std::chrono::steady_clock::time_point end2 =
				std::chrono::steady_clock::now();
		std::cout << "Encoded "
				<< path->to_s()
				<< " in " << std::chrono::duration_cast<std::chrono::milliseconds>(
						end2 - end).count() << "ms" << std::endl;
		callback(data);
	});
}

}
