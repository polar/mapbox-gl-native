#pragma once

#include <mbgl/style/source.hpp>
#include <mbgl/util/geojson.hpp>
#include <mbgl/util/range.hpp>
#include <mbgl/util/constants.hpp>
#include <mbgl/actor/mailbox.hpp>

namespace mbgl {

class OverscaledTileID;
class CanonicalTileID;

namespace style {

using TileFunction = std::function<void(const CanonicalTileID&)>;

class CustomTileLoader;

class CustomVectorSource : public Source {
public:
    struct TileOptions {
        double tolerance = 0.375;
        uint16_t tileSize = util::tileSize;
        uint16_t buffer = 128;
    };

    struct Options {
        TileFunction fetchTileFunction;
        TileFunction cancelTileFunction;
        Range<uint8_t> zoomRange = { 0, 18};
        TileOptions tileOptions;
    };
public:
    CustomVectorSource(std::string id, CustomVectorSource::Options options);
    ~CustomVectorSource() final;
    void loadDescription(FileSource&) final;
    void setTileData(const CanonicalTileID&, const GeoJSON&);

    // Private implementation
    class Impl;
    const Impl& impl() const;
private:
    std::shared_ptr<Mailbox> mailbox;    
    std::unique_ptr<CustomTileLoader> loader;
};

template <>
inline bool Source::is<CustomVectorSource>() const {
    return getType() == SourceType::CustomVector;
}

} // namespace style
} // namespace mbgl
