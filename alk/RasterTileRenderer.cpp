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
        mbgl::FileSource& fileSource_,
		int renderThreads_)
	: styleUrl(styleUrl_),
	  width(width_),
	  height(height_),
	  pixelRatio(pixelRatio_),
	  bearing(bearing_),
	  pitch(pitch_),
	  renderCache(renderCache_),
	  fileSource(fileSource_),
	  threadPool(renderThreads_),
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

// Something is off with the lat lon placement. Seems to require a 512 size with a pixel ratio of 1.

// http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
static void tile2lonlat(double x, double y, int zoom, double *lon, double *lat) {
	unsigned long long n = 1LL << zoom;
	*lon = 360.0 * x / n - 180.0;
	*lat = atan(sinh(M_PI * (1 - 2.0 * y / n))) * 180.0 / M_PI;
}

// Something is off. The maps do not line up in the CartoCam. This may be because of the data
// in the Vector Tiles.
// In an effort to find out why.
// The following is taken from dotnet/Libraries/ALK.Utilities/TileSystem.cs
//  However, yields the same answer as above, but may come up with longitude of -inf, which terminal faults.
/*
static uint MapSize(int levelOfDetail, int tileWidth)
        {
            return (uint)tileWidth << levelOfDetail;
        }

static double Clip(double n, double minValue, double maxValue)
        {
            return std::min(std::max(n, minValue), maxValue);
        }

static void PixelXYToLatLong(double pixelX, double pixelY, int levelOfDetail, int tileWidth, double& latitude, double& longitude)
        {
            double mapSize = MapSize(levelOfDetail, tileWidth);
            double x = (Clip(pixelX, 0, mapSize - 1) / mapSize) - 0.5;
            double y = 0.5 - (Clip(pixelY, 0, mapSize - 1) / mapSize);

            latitude = 90 - 360 * atan(exp(-y * 2 * M_PI)) / M_PI;
            longitude = 360 * x;
        }

static void TileXYToPixelXY(double tileX, double tileY, int tileWidth, int& pixelX, int& pixelY)
        {
            pixelX = tileX * tileWidth;
            pixelY = tileY * tileWidth;
        }

static void TileXYToLatLong(double tileX, double tileY, int levelOfDetail, int tileWidth, double& latitude, double& longitude)
        {
            int pixelX, pixelY;
            TileXYToPixelXY(tileX, tileY, tileWidth,  pixelX, pixelY);
            PixelXYToLatLong(pixelX, pixelY, levelOfDetail, tileWidth, latitude, longitude);
        }
*/

void RasterTileRenderer::renderTile(TilePath *path, std::function<void (const std::string data)> callback) {
	std::chrono::steady_clock::time_point begin =
			std::chrono::steady_clock::now();
	double lat = 0, lon = 0;
	// The x,y integers in this calculation gets us the NW corner, but we need to set the center.
	// The center is 0.5+x, 0.5+y.
	tile2lonlat(path->x + 0.5, path->y + 0.5, path->zoom, &lon, &lat);
	std::cout << "Rendering.... " << path->to_s() << " at " << lon << ", " << lat << std::endl;
	map.setLatLngZoom( { lat, lon }, path->zoom);
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
