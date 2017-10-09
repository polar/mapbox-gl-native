#pragma once

#include <mbgl/style/source_impl.hpp>
#include <mbgl/style/sources/custom_vector_source.hpp>
#include <mbgl/style/custom_tile_loader.hpp>
#include <mbgl/actor/actor_ref.hpp>

namespace mbgl {
namespace style {

class CustomVectorSource::Impl : public Source::Impl {
public:
    Impl(std::string id, CustomVectorSource::Options options);
    Impl(const Impl&, ActorRef<CustomTileLoader>);

    optional<std::string> getAttribution() const final;

    CustomVectorSource::TileOptions getTileOptions() const;
    Range<uint8_t> getZoomRange() const;
    optional<ActorRef<CustomTileLoader>> getTileLoader() const;

private:
    CustomVectorSource::TileOptions tileOptions;
    Range<uint8_t> zoomRange;
    optional<ActorRef<CustomTileLoader>> loaderRef;
};

} // namespace style
} // namespace mbgl
