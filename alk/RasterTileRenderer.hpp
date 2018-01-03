#include <mbgl/map/map.hpp>
#include <mbgl/util/image.hpp>
#include <mbgl/util/run_loop.hpp>
#include <mbgl/util/default_thread_pool.hpp>
#include <mbgl/storage/file_source.hpp>
#include <thread>
#include <mutex>

#include <cstdlib>
#include <iostream>
#include <fstream>
#include <math.h>

#include "RenderCache.hpp"
#include "Frontend.hpp"
#include "TilePath.hpp"

#pragma once

namespace alk {

struct RenderStats {
	std::string id;
	std::chrono::system_clock::time_point renderStartTime;
	std::chrono::duration<double, std::milli> renderingCurrentTotalDuration;
	std::chrono::duration<double, std::milli> minimumRenderDuration;
	TilePath              minimumRenderTilePath;
	std::chrono::duration<double, std::milli> maximumRenderDuration;
	TilePath              maximumRenderTilePath;
	std::chrono::duration<double, std::milli> encodingCurrentTotalDuration;
	unsigned long long numberOfRequests;
};

class RasterTileRenderer {
public:
	explicit RasterTileRenderer(
			std::string id_,
			std::string styleUrl_,
			const uint32_t height_,
			const uint32_t width_,
			double pixelRatio_,
			double bearing_,
			double pitch_,
			RenderCache& renderCache_,
			mbgl::FileSource& fileSource_,
			std::mutex& renderMutex_,
			int renderThreads_);
	void renderTile(TilePath *path, std::function<void (const std::string data)> callback);
	double getPixelRatio();
	double getBearing();
	double getPitch();
	RenderCache& getRenderCache();
	mbgl::FileSource& getFileSource();
	RenderStats& getRenderStats();

protected:
	std::string id;
	std::string styleUrl;
    const uint32_t width;
    const uint32_t height;
    double pixelRatio;
    double bearing;
    double pitch;

private:
    RenderCache& renderCache;
    mbgl::FileSource& fileSource;
    std::mutex& renderMutex;
    mbgl::ThreadPool threadPool;
    Frontend frontend;
    mbgl::Map map;
    RenderStats renderStats;
};
};
