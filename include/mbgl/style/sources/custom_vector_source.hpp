#pragma once

#include <mbgl/style/source.hpp>
#include <mbgl/style/sources/geojson_source.hpp>
#include <mbgl/util/geo.hpp>
#include <mbgl/util/geojson.hpp>
#include <mbgl/util/variant.hpp>

namespace mbgl {
namespace style {

struct Error { std::string message; };

using FetchTileResult = variant<
    mapbox::geojson::geojson,
    Error>;

using FetchTileCallback = std::function<void(const CanonicalTileID& tileID, const FetchTileResult&)>;
using FetchTileFunction = std::function<void(const CanonicalTileID&, FetchTileCallback)>;

class CustomVectorSource : public Source {
public:
    CustomVectorSource(std::string id,
                       GeoJSONOptions options,
                       FetchTileFunction fetchTile);

    void loadDescription(FileSource&) final;

    // Private implementation
    class Impl;
    const Impl& impl() const;
};

template <>
inline bool Source::is<CustomVectorSource>() const {
    return getType() == SourceType::CustomVector;
}

} // namespace style
} // namespace mbgl
