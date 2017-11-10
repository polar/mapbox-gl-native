#include <mbgl/gl/headless_frontend.hpp>
#include <mbgl/renderer/renderer.hpp>
#include <mbgl/renderer/update_parameters.hpp>
#include <mbgl/map/map.hpp>
#include <mbgl/map/transform_state.hpp>
#include <mbgl/storage/file_source.hpp>
#include <mbgl/util/run_loop.hpp>

namespace alk {

class Frontend : public mbgl::HeadlessFrontend {
public:
	Frontend(mbgl::Size size_, float pixelRatio_, mbgl::FileSource& fileSource_, mbgl::Scheduler& scheduler_);
	void render(mbgl::Map& map, std::function<void (const mbgl::PremultipliedImage)> callback);
};

}
