#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/custom_tile_loader.hpp>
#include <mbgl/style/sources/custom_vector_source_impl.hpp>
#include <mbgl/actor/scheduler.hpp>
#include <mbgl/tile/tile_id.hpp>

#include <tuple>
#include <map>

namespace mbgl {
namespace style {

CustomVectorSource::CustomVectorSource(std::string id,
                                       const CustomVectorSource::Options options)
    : Source(makeMutable<CustomVectorSource::Impl>(std::move(id), options)),
    mailbox(std::make_shared<Mailbox>(*Scheduler::GetCurrent())),
    loader(std::make_unique<CustomTileLoader>(options.fetchTileFunction, options.cancelTileFunction)) {
}

CustomVectorSource::~CustomVectorSource() = default;

const CustomVectorSource::Impl& CustomVectorSource::impl() const {
    return static_cast<const CustomVectorSource::Impl&>(*baseImpl);
}

void CustomVectorSource::loadDescription(FileSource&) {
    baseImpl = makeMutable<CustomVectorSource::Impl>(impl(), ActorRef<CustomTileLoader>(*loader, mailbox));
    loaded = true;
}

void CustomVectorSource::setTileData(const CanonicalTileID& tileID,
                                     const GeoJSON& data) {
    loader->setTileData(tileID, data);
}

} // namespace style
} // namespace mbgl
