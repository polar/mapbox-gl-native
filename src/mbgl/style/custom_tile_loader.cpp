#include <mbgl/style/custom_tile_loader.hpp>

namespace mbgl {
namespace style {

CustomTileLoader::CustomTileLoader(const TileFunction& fetchTileFn, const TileFunction& cancelTileFn) {
    fetchTileFunction = fetchTileFn;
    cancelTileFunction = cancelTileFn;
}

void CustomTileLoader::fetchTile(const OverscaledTileID& tileID, ActorRef<SetTileDataFunction> callbackRef) {
    auto cachedTileData = dataCache.find(tileID.canonical);
    if (cachedTileData == dataCache.end()) {
        invokeTileFetch(tileID.canonical);
    } else {
        callbackRef.invoke(&SetTileDataFunction::operator(), *(cachedTileData->second));
    }
    auto tileCallbacks = tileCallbackMap.find(tileID.canonical);
    if (tileCallbacks == tileCallbackMap.end()) {
        auto tuple = std::make_tuple(tileID.overscaledZ, tileID.wrap, callbackRef);
        tileCallbackMap.insert({ tileID.canonical, std::vector<OverscaledIDFunctionTuple>(1, tuple) });
    }
    else {
        for(auto iter = tileCallbacks->second.begin(); iter != tileCallbacks->second.end(); iter++) {
            if(std::get<0>(*iter) == tileID.overscaledZ && std::get<1>(*iter) == tileID.wrap ) {
                std::get<2>(*iter) = callbackRef;
                return;
            }
        }
        tileCallbacks->second.emplace_back(std::make_tuple(tileID.overscaledZ, tileID.wrap, callbackRef));
    }
}

void CustomTileLoader::cancelTile(const OverscaledTileID& tileID) {
    if(tileCallbackMap.find(tileID.canonical) != tileCallbackMap.end()) {
        invokeTileCancel(tileID.canonical);
    }
}

void CustomTileLoader::removeTile(const OverscaledTileID& tileID) {
    auto tileCallbacks = tileCallbackMap.find(tileID.canonical);
    if (tileCallbacks == tileCallbackMap.end()) return;
    for(auto iter = tileCallbacks->second.begin(); iter != tileCallbacks->second.end(); iter++) {
        if(std::get<0>(*iter) == tileID.overscaledZ && std::get<1>(*iter) == tileID.wrap ) {
            tileCallbacks->second.erase(iter);
            break;
        }
    }
    if (tileCallbacks->second.size() == 0) {
        tileCallbackMap.erase(tileCallbacks);
        dataCache.erase(tileID.canonical);
    }
}

void CustomTileLoader::setTileData(const CanonicalTileID& tileID, const GeoJSON& data) {
    auto iter = tileCallbackMap.find(tileID);
    if (iter == tileCallbackMap.end()) return;
    dataCache[tileID] = std::make_unique<mapbox::geojson::geojson>(std::move(data));
    for(auto tuple : iter->second) {
        auto actor = std::get<2>(tuple);
        actor.invoke(&SetTileDataFunction::operator(), data);
    }
}

void CustomTileLoader::invokeTileFetch(const CanonicalTileID& tileID) {
    if (fetchTileFunction != nullptr) {
        fetchTileFunction(tileID);
    }
}

void CustomTileLoader::invokeTileCancel(const CanonicalTileID& tileID) {
    if (cancelTileFunction != nullptr) {
        cancelTileFunction(tileID);
    }
}

} // namespace style
} // namespace mbgl
