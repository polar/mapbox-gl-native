#include <mbgl/gl/headless_frontend.hpp>
#include <mbgl/gl/headless_backend.hpp>
#include <mbgl/renderer/renderer.hpp>
#include <mbgl/renderer/update_parameters.hpp>
#include <mbgl/map/map.hpp>
#include <mbgl/map/transform_state.hpp>
#include <mbgl/util/run_loop.hpp>
#include <mbgl/storage/file_source.hpp>
#include "Frontend.hpp"

namespace alk {

Frontend::Frontend(mbgl::Size size_, float pixelRatio_, mbgl::FileSource& fileSource_, mbgl::Scheduler& scheduler_) :
    mbgl::HeadlessFrontend(size_, pixelRatio_, fileSource_, scheduler_) {

}

void Frontend::render(mbgl::Map& map, std::function<void (const mbgl::PremultipliedImage)> callback) {

    map.renderStill([this, callback](std::exception_ptr error) {
        if (error) {
            std::rethrow_exception(error);
        } else {
        	mbgl::PremultipliedImage result = readStillImage();
            callback(std::move(result));
        }
    });
}

}
