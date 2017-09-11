#include <mbgl/style/sources/custom_vector_source_impl.hpp>

#include <mbgl/style/source_observer.hpp>
#include <mbgl/tile/geojson_tile.hpp>
#include <mbgl/tile/vector_tile.hpp>
#include <mbgl/util/tile_cover.hpp>

namespace mbgl {
namespace style {

CustomVectorSource::Impl::Impl(std::string id_,
                               const GeoJSONOptions options_,
                               FetchTileFunction fetchTileFn_)
    : Source::Impl(SourceType::CustomVector, std::move(id_)),
      options(options_),
      fetchTileFn(fetchTileFn_) {
}

optional<std::string> CustomVectorSource::Impl::getAttribution() const {
    return {};
}

GeoJSONOptions CustomVectorSource::Impl::getOptions() const {
    return options;
}

FetchTileFunction CustomVectorSource::Impl::getFetchTileFunction() const {
    return fetchTileFn;
}

} // namespace style
} // namespace mbgl
