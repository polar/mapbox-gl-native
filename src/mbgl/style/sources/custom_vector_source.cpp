#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/sources/custom_vector_source_impl.hpp>
#include <mbgl/actor/scheduler.hpp>
#include <mbgl/tile/tile_id.hpp>

#include <tuple>
#include <map>

namespace mbgl {
namespace style {

class CustomTileLoader::Impl {
public:

    using OverscaledIDFunctionTuple = std::tuple<uint8_t, int16_t, ActorRef<SetTileDataFunction>>;

    Impl(TileFunction&& fetchTileFn, TileFunction&& cancelTileFn) {
        fetchTileFunction = std::move(fetchTileFn);
        cancelTileFunction = std::move(cancelTileFn);
    }

    void fetchTile(const OverscaledTileID& tileID, ActorRef<SetTileDataFunction> callbackRef) {
        auto cachedTileData = dataCache.find(tileID.canonical);
        if (cachedTileData == dataCache.end()) {
            fetchTileFunction(tileID.canonical);
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

    void cancelTile(const OverscaledTileID& tileID) {
        if(tileCallbackMap.find(tileID.canonical) != tileCallbackMap.end()) {
            cancelTileFunction(tileID.canonical);
        }
    }

    void removeTile(const OverscaledTileID& tileID) {
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

    void setTileData(const CanonicalTileID& tileID, const mapbox::geojson::geojson& data) {
        auto iter = tileCallbackMap.find(tileID);
        if (iter == tileCallbackMap.end()) return;
        dataCache[tileID] = std::make_unique<mapbox::geojson::geojson>(std::move(data));
        for(auto tuple : iter->second) {
            auto actor = std::get<2>(tuple);
            actor.invoke(&SetTileDataFunction::operator(), data);
        }
    }

private:
    TileFunction fetchTileFunction;
    TileFunction cancelTileFunction;
    std::unordered_map<CanonicalTileID, std::vector<OverscaledIDFunctionTuple>> tileCallbackMap;
    std::map<CanonicalTileID, std::unique_ptr<mapbox::geojson::geojson>> dataCache;
};

CustomTileLoader::CustomTileLoader(TileFunction fetchTileFn, TileFunction cancelTileFn)
    : impl(new CustomTileLoader::Impl(std::move(fetchTileFn), std::move(cancelTileFn))) {

}

CustomTileLoader::~CustomTileLoader() {
    delete impl;
    impl = nullptr;
}

void CustomTileLoader::fetchTile(const OverscaledTileID& tileID, ActorRef<SetTileDataFunction> callbackRef) {
    impl->fetchTile(tileID, callbackRef);
}

void CustomTileLoader::cancelTile(const OverscaledTileID& tileID) {
    impl->cancelTile(tileID);
}

void CustomTileLoader::setTileData(const CanonicalTileID& tileID, const mapbox::geojson::geojson& data) {
    impl->setTileData(tileID, data);
}

void CustomTileLoader::removeTile(const OverscaledTileID& tileID) {
    impl->removeTile(tileID);
}

CustomVectorSource::CustomVectorSource(std::string id,
                                       const CustomVectorSource::Options options)
    : Source(makeMutable<CustomVectorSource::Impl>(std::move(id), options)),
    mailbox(std::make_shared<Mailbox>(*Scheduler::GetCurrent())),
    loader(options.fetchTileFunction, options.cancelTileFunction) {
}

const CustomVectorSource::Impl& CustomVectorSource::impl() const {
    return static_cast<const CustomVectorSource::Impl&>(*baseImpl);
}
void CustomVectorSource::loadDescription(FileSource&) {
    baseImpl = makeMutable<CustomVectorSource::Impl>(impl(), ActorRef<CustomTileLoader>(loader, mailbox));
    loaded = true;
}

void CustomVectorSource::setTileData(const CanonicalTileID& tileID,
                                     const mapbox::geojson::geojson& data) {
    loader.setTileData(tileID, data);
}

} // namespace style
} // namespace mbgl
