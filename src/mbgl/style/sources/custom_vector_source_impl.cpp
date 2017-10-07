#include <mbgl/style/sources/custom_vector_source_impl.hpp>
#include <mbgl/style/source_observer.hpp>

namespace mbgl {
namespace style {

CustomVectorSource::Impl::Impl(std::string id_,
                               const CustomVectorSource::Options options)
    : Source::Impl(SourceType::CustomVector, std::move(id_)),
      tileOptions(options.tileOptions),
      zoomRange(options.zoomRange),
      loaderRef({}) {
}

CustomVectorSource::Impl::Impl(const Impl& impl, ActorRef<CustomTileLoader> loaderRef_)
    : Source::Impl(impl),
    tileOptions(impl.tileOptions),
    zoomRange(impl.zoomRange),
    loaderRef(loaderRef_){
    
}

optional<std::string> CustomVectorSource::Impl::getAttribution() const {
    return {};
}

CustomVectorSource::TileOptions CustomVectorSource::Impl::getTileOptions() const {
    return tileOptions;
}

Range<uint8_t> CustomVectorSource::Impl::getZoomRange() const {
    return zoomRange;
}

optional<ActorRef<CustomTileLoader>> CustomVectorSource::Impl::getTileLoader() const {
    return loaderRef;
}

} // namespace style
} // namespace mbgl
