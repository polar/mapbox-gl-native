#include <mbgl/renderer/sources/render_custom_vector_source.hpp>
#include <mbgl/renderer/render_tile.hpp>
#include <mbgl/renderer/paint_parameters.hpp>
#include <mbgl/tile/custom_tile.hpp>

#include <mbgl/algorithm/generate_clip_ids.hpp>
#include <mbgl/algorithm/generate_clip_ids_impl.hpp>

namespace mbgl {

using namespace style;

RenderCustomVectorSource::RenderCustomVectorSource(Immutable<style::CustomVectorSource::Impl> impl_)
    : RenderSource(impl_) {
    tilePyramid.setObserver(this);
}

const style::CustomVectorSource::Impl& RenderCustomVectorSource::impl() const {
    return static_cast<const style::CustomVectorSource::Impl&>(*baseImpl);
}

bool RenderCustomVectorSource::isLoaded() const {
    return tilePyramid.isLoaded();
}

void RenderCustomVectorSource::update(Immutable<style::Source::Impl> baseImpl_,
                                 const std::vector<Immutable<Layer::Impl>>& layers,
                                 const bool needsRendering,
                                 const bool needsRelayout,
                                 const TileParameters& parameters) {
    std::swap(baseImpl, baseImpl_);

    enabled = needsRendering;

    auto tileLoader = impl().getTileLoader();
    if (!tileLoader) {
        return;
    }

    tilePyramid.update(layers,
                       needsRendering,
                       needsRelayout,
                       parameters,
                       SourceType::CustomVector,
                       util::tileSize,
                       impl().getZoomRange(),
                       [&] (const OverscaledTileID& tileID) {
                           return std::make_unique<CustomTile>(tileID, impl().id, parameters, impl().getTileOptions(), *tileLoader);
                       });
}

void RenderCustomVectorSource::startRender(PaintParameters& parameters) {
    parameters.clipIDGenerator.update(tilePyramid.getRenderTiles());
    tilePyramid.startRender(parameters);
}

void RenderCustomVectorSource::finishRender(PaintParameters& parameters) {
    tilePyramid.finishRender(parameters);
}

std::vector<std::reference_wrapper<RenderTile>> RenderCustomVectorSource::getRenderTiles() {
    return tilePyramid.getRenderTiles();
}

std::unordered_map<std::string, std::vector<Feature>>
RenderCustomVectorSource::queryRenderedFeatures(const ScreenLineString& geometry,
                                           const TransformState& transformState,
                                           const std::vector<const RenderLayer*>& layers,
                                           const RenderedQueryOptions& options) const {
    return tilePyramid.queryRenderedFeatures(geometry, transformState, layers, options);
}

std::vector<Feature> RenderCustomVectorSource::querySourceFeatures(const SourceQueryOptions& options) const {
    return tilePyramid.querySourceFeatures(options);
}

void RenderCustomVectorSource::onLowMemory() {
    tilePyramid.onLowMemory();
}

void RenderCustomVectorSource::dumpDebugLogs() const {
    tilePyramid.dumpDebugLogs();
}

} // namespace mbgl
