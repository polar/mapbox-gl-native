#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/sources/custom_vector_source_impl.hpp>
#include <mbgl/actor/scheduler.hpp>

namespace mbgl {
namespace style {

class CustomTileLoader::Impl {
public:
    Impl(TileFunction&& fetchTileFn, TileFunction&& cancelTileFn) {
        fetchTileFunction = std::move(fetchTileFn);
        cancelTileFunction = std::move(cancelTileFn);
    }

    void fetchTile(const CanonicalTileID& tileID, ActorRef<SetTileDataFunction> callbackRef) {
        fetchTileFunction(tileID);
        auto insertResult = tileCallbackMap.insert({tileID, callbackRef});
        if (insertResult.second == false) {
            insertResult.first->second = callbackRef;
        }
    }

    void cancelTile(const CanonicalTileID& tileID) {
        if(tileCallbackMap.find(tileID) != tileCallbackMap.end())
            cancelTileFunction(tileID);
    }

    void removeTile(const CanonicalTileID& tileID) {
        tileCallbackMap.erase(tileID);
    }

    void setTileData(const CanonicalTileID& tileID, const mapbox::geojson::geojson& data) {
        auto iter = tileCallbackMap.find(tileID);
        if (iter == tileCallbackMap.end()) return;
        iter->second.invoke(&SetTileDataFunction::operator(), tileID, data);
    }

private:
    TileFunction fetchTileFunction;
    TileFunction cancelTileFunction;
    std::unordered_map<CanonicalTileID, ActorRef<SetTileDataFunction>> tileCallbackMap;
};


CustomTileLoader::CustomTileLoader(TileFunction&& fetchTileFn, TileFunction&& cancelTileFn)
    : impl(new CustomTileLoader::Impl(std::move(fetchTileFn), std::move(cancelTileFn))) {

}

CustomTileLoader::~CustomTileLoader() {
    delete impl;
    impl = nullptr;
}

void CustomTileLoader::fetchTile(const CanonicalTileID& tileID, ActorRef<SetTileDataFunction> callbackRef) {
    impl->fetchTile(tileID, callbackRef);
}

void CustomTileLoader::cancelTile(const CanonicalTileID& tileID) {
    impl->cancelTile(tileID);
}

void CustomTileLoader::setTileData(const CanonicalTileID& tileID, const mapbox::geojson::geojson& data) {
    impl->setTileData(tileID, data);
}

void CustomTileLoader::removeTile(const CanonicalTileID& tileID) {
    impl->removeTile(tileID);
}

CustomVectorSource::CustomVectorSource(std::string id,
                                       const GeoJSONOptions options,
                                       TileFunction fetchTileFn,
                                       TileFunction cancelTileFn)
    : Source(makeMutable<CustomVectorSource::Impl>(std::move(id), options)),
    mailbox(std::make_shared<Mailbox>(*Scheduler::GetCurrent())),
    loader(std::move(fetchTileFn), std::move(cancelTileFn)) {
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
