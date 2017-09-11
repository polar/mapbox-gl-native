#pragma once

#include <mbgl/style/source_impl.hpp>
#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/tile/tile_id.hpp>

namespace mbgl {
namespace style {

class CustomVectorSource::Impl : public Source::Impl {
public:
    Impl(std::string id,
         GeoJSONOptions options,
         FetchTileFunction fetchTileFn);

    optional<std::string> getAttribution() const final;

    GeoJSONOptions getOptions() const;
    FetchTileFunction getFetchTileFunction() const;

private:
    GeoJSONOptions options;
    FetchTileFunction fetchTileFn;
};

} // namespace style
} // namespace mbgl
