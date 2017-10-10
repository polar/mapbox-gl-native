#pragma once

#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/tile/tile_id.hpp>
#include <mbgl/util/geojson.hpp>
#include <mbgl/actor/actor_ref.hpp>

#include <map>

namespace mbgl {
namespace style {

using SetTileDataFunction = std::function<void(const GeoJSON&)>;

class CustomTileLoader : private util::noncopyable {
public:

    using OverscaledIDFunctionTuple = std::tuple<uint8_t, int16_t, ActorRef<SetTileDataFunction>>;

    CustomTileLoader(const TileFunction& fetchTileFn, const TileFunction& cancelTileFn);

    void fetchTile(const OverscaledTileID& tileID, ActorRef<SetTileDataFunction> callbackRef);
    void cancelTile(const OverscaledTileID& tileID);

    void removeTile(const OverscaledTileID& tileID);
    void setTileData(const CanonicalTileID& tileID, const GeoJSON& data);

private:
    TileFunction fetchTileFunction;
    TileFunction cancelTileFunction;
    std::unordered_map<CanonicalTileID, std::vector<OverscaledIDFunctionTuple>> tileCallbackMap;
    std::map<CanonicalTileID, std::unique_ptr<GeoJSON>> dataCache;
};

} // namespace style
} // namespace mbgl
