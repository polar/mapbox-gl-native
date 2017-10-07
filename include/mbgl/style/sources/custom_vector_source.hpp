#pragma once

#include <mbgl/style/source.hpp>
#include <mbgl/util/geojson.hpp>
#include <mbgl/util/range.hpp>
#include <mbgl/util/constants.hpp>
#include <mbgl/actor/actor_ref.hpp>

namespace mbgl {

class OverscaledTileID;
class CanonicalTileID;

namespace style {

using SetTileDataFunction = std::function<void(const mapbox::geojson::geojson&)>;
using TileFunction = std::function<void(const CanonicalTileID&)>;

class CustomTileLoader : private util::noncopyable {
public:
    CustomTileLoader(TileFunction fetchTileFn, TileFunction cancelTileFn);
    ~CustomTileLoader();

    void fetchTile(const OverscaledTileID& tileID, ActorRef<SetTileDataFunction> callbackRef);
    void cancelTile(const OverscaledTileID& tileID);
    void removeTile(const OverscaledTileID& tileID);

    void setTileData(const CanonicalTileID& tileID, const mapbox::geojson::geojson& data);

private:
    class Impl;
    Impl* impl = nullptr;
};

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

    void loadDescription(FileSource&) final;
    void setTileData(const CanonicalTileID&, const mapbox::geojson::geojson&);

    // Private implementation
    class Impl;
    const Impl& impl() const;
private:
    std::shared_ptr<Mailbox> mailbox;
    CustomTileLoader loader;

};

template <>
inline bool Source::is<CustomVectorSource>() const {
    return getType() == SourceType::CustomVector;
}

} // namespace style
} // namespace mbgl
