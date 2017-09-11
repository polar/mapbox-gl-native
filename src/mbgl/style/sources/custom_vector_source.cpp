#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/sources/custom_vector_source_impl.hpp>

namespace mbgl {
namespace style {

CustomVectorSource::CustomVectorSource(std::string id,
                                       const GeoJSONOptions options,
                                       FetchTileFunction fetchTileFn)
    : Source(makeMutable<CustomVectorSource::Impl>(std::move(id), options, fetchTileFn)) {
}

void CustomVectorSource::loadDescription(FileSource&) {
    loaded = true;
}

} // namespace style
} // namespace mbgl
