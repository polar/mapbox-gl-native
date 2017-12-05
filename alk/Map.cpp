#include <mbgl/util/optional.hpp>
#include <mbgl/util/chrono.hpp>
#include <mbgl/map/map_observer.hpp>
#include <mbgl/map/mode.hpp>
#include <mbgl/util/noncopyable.hpp>
#include <mbgl/util/size.hpp>
#include <mbgl/annotation/annotation.hpp>
#include <mbgl/map/camera.hpp>
#include <mbgl/util/geometry.hpp>
#include <mbgl/map/map.hpp>
#include <iostream>

#include "Map.hpp"


namespace alk {

Map::Map(mbgl::RendererFrontend& frontend,
		mbgl::MapObserver& observer,
		mbgl::Size size,
    float pixelRatio,
	mbgl::FileSource& fileSource,
	mbgl::Scheduler& scheduler,
	mbgl::MapMode mapMode) :
			  mbgl::Map(frontend, observer, size, pixelRatio, fileSource, scheduler, mapMode) {
	std::cout << "Making new map!" << std::endl;

}

Map::~Map() {
	std::cout << "Map Gone!" << std::endl;
}

};
