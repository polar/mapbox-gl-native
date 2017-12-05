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

namespace alk {

class Map : public mbgl::Map {
public:
	explicit Map(mbgl::RendererFrontend&,
			mbgl::MapObserver&,
			mbgl::Size size,
        float pixelRatio,
		mbgl::FileSource&,
		mbgl::Scheduler&,
		mbgl::MapMode mapMode = mbgl::MapMode::Continuous);
~Map();
};

}
