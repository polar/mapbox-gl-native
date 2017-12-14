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
#include <thread>
#include <mutex>
#include <cfloat>

#include "RenderCache.hpp"
#include "RasterTileRenderer.hpp"

namespace alk {

/**
 * @classdesc
 *
 * This class renders (width x height) tiles at the given pixel ratio.
 * Specifying 256 x 256 and pixel ratio of 2 yields 512 x 512 tiles.
 * The pixel ratio does not affect vector tile rendering vector styling.
 * Vector tiles are always rendered in a 512 x 512 space regardless of
 * pixel ratio. Pixel ratio doesn't seem to matter for vector tiles as
 * the features are given dimensions that relate to only the zoom level.
 * The pixel ratio governs the sprites and raster tiles included in the style.
 * That is, pixel ratio of 2 adds "@2x" to any sprites URL in the style.
 *
 * @param {string}       styleUrl_   This is the url of the style.
 *                            http::/tiles-dev.alk.com/styles/default/styles.json
 *                            ./style.json  (for file)
 * @param {uint32_t}     width_       The width of the resultant tile.
 * @param {uint32_t}     height_      The height of the resultant tile.
 * @param {double}       pixelRatio_  The pixel ratio, (1 or 2).
 * @param {double}       bearing_     The camera bearing.
 * @param {double}       pitch_       The camera pitch.
 * @param {RenderCache&} renderCache_ This is the file source for storing rendered
 *                                    raster tiles.
 * @param {mbgl::FileSource&} fileSource_  This is the file source for caching
 *                                         things gotten from the network, such as
 *                                         vector tiles, styles, sprites, etc.
 * @param {std::mutex&} renderMutex_ This is the mutex with which to protect the
 *                                   rendering around the GL library, which seems
 *                                   to not be thread safe. It has thread safe
 *                                   render threads, but the library in general is
 *                                   not thread safe we use this around rendering, yet
 *                                   allow threads for HTTP requests.
 * @param {ThreadPool} renderThreads This is a thread pool that the GL renderer may use.
 *
 * For normal applications, use 256,256,1.
 */
RasterTileRenderer::RasterTileRenderer(
		std::string styleUrl_,
		const uint32_t width_,
		const uint32_t height_,
		double pixelRatio_,
		double bearing_,
		double pitch_,
		RenderCache& renderCache_,
        mbgl::FileSource& fileSource_,
		std::mutex& renderMutex_,
		int renderThreads_)
	: styleUrl(styleUrl_),
	  width(width_),
	  height(height_),
	  pixelRatio(pixelRatio_),
	  bearing(bearing_),
	  pitch(pitch_),
	  renderCache(renderCache_),
	  fileSource(fileSource_),
	  renderMutex(renderMutex_),
	  threadPool(renderThreads_),
	  frontend({ width_, height_ }, pixelRatio_,
	    		 fileSource, this->threadPool),
	  map(this->frontend,
			        mbgl::MapObserver::nullObserver(),
					// Height and width doesn't matter much here for rendering as
					// it always seems to render enough.
					{width_, height_}, // This really doesn't matter.
					// pixelRatio here governs what is downloaded from the styles, such as sprites @2x
					// and raster tiles from the internet.
					pixelRatio_,
					fileSource,
					this->threadPool,
					// We need Static or Tile.
					// Not yet sure what the difference is.
					mbgl::MapMode::Tile) {

    if (styleUrl.find("://") == std::string::npos) {
    	styleUrl = std::string("file://") + styleUrl;
    }
    map.getStyle().loadURL(styleUrl);
    map.setBearing(bearing);
    map.setPitch(pitch);
    //map.setDebug(mbgl::MapDebugOptions::TileBorders |
    //		mbgl::MapDebugOptions::ParseStatus);

	std::chrono::steady_clock::time_point begin =
			std::chrono::steady_clock::now();
    renderStats.renderStartTime = begin;
    renderStats.minimumRenderDuration = std::chrono::duration<double, std::milli>::min();
    renderStats.maximumRenderDuration = std::chrono::duration<double, std::milli>::max();
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

RenderStats& RasterTileRenderer::getRenderStats() {
	return renderStats;
}

// http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
static void tile2lonlat(double x, double y, int zoom, double *lon, double *lat) {
	unsigned long long n = 1LL << zoom;
	*lon = 360.0 * x / n - 180.0;
	*lat = atan(sinh(M_PI * (1 - 2.0 * y / n))) * 180.0 / M_PI;
}

void RasterTileRenderer::renderTile(TilePath *path, std::function<void (const std::string data)> callback) {
	std::chrono::steady_clock::time_point begin =
			std::chrono::steady_clock::now();
	double lat = 0, lon = 0;
	// The x,y integers in this calculation gets us the NW corner, but we need to set the center.
	// The center is 0.5+x, 0.5+y.
	tile2lonlat(path->x + 0.5, path->y + 0.5, path->zoom, &lon, &lat);
	std::cout << "Rendering.... " << path->to_s() << " at " << lon << ", " << lat << std::endl;

	// Vector tiles (z,x,y) render in a 512 space, but we want double the feature characteristics.
	// So we back off the zoom 1, which may render 4-8 more vector tiles.
	if (width < 512) {
		map.setLatLngZoom( { lat, lon }, path->zoom < 1 ? 0 : path->zoom - 1.0);
	} else {
		map.setLatLngZoom( { lat, lon }, path->zoom);
	}
	// The GL library is not thread safe beyond its own render threads.
	// We lock against all other RasterTileRenders here.
	renderMutex.lock();
	frontend.render(map, [=] (mbgl::PremultipliedImage result) {
		// We are done with GL Rendering.
		renderMutex.unlock();
		std::chrono::steady_clock::time_point end =
				std::chrono::steady_clock::now();
		std::chrono::duration<double, std::milli> duration = end - begin;
		renderStats.numberOfRequests++;
		if (duration < renderStats.minimumRenderDuration) {
			renderStats.minimumRenderDuration = duration;
			renderStats.mimimumRenderTilePath = *path;
		}
		if (duration > renderStats.maximumRenderDuration) {
			renderStats.maximumRenderDuration = duration;
			renderStats.maximumRenderTilePath = *path;
		}
		renderStats.renderingCurrentTotalDuration += duration;
		std::cout << "........Rendered "
				<< path->to_s()
				<< " in " << std::chrono::duration_cast<std::chrono::milliseconds>(end-begin).count() << "ms" << std::endl;
		auto data = mbgl::encodePNG(std::move(result));
		std::chrono::steady_clock::time_point end2 =
				std::chrono::steady_clock::now();

		std::chrono::duration<double, std::milli> encDuration = end2 - end;
		renderStats.encodingCurrentTotalDuration += encDuration;
		std::cout << "Encoded "
				<< path->to_s()
				<< " in " << std::chrono::duration_cast<std::chrono::milliseconds>(
						end2 - end).count() << "ms" << std::endl;
		callback(data);
	});
}

}
