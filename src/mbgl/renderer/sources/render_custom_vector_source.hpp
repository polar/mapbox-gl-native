#pragma once

#include <mbgl/renderer/render_source.hpp>
#include <mbgl/renderer/tile_pyramid.hpp>
#include <mbgl/style/sources/custom_vector_source_impl.hpp>
#include <mbgl/actor/actor.hpp>

namespace mbgl {

class RenderCustomVectorSource : public RenderSource {
public:
    RenderCustomVectorSource(Immutable<style::CustomVectorSource::Impl>);

    bool isLoaded() const final;

    void update(Immutable<style::Source::Impl>,
                const std::vector<Immutable<style::Layer::Impl>>&,
                bool needsRendering,
                bool needsRelayout,
                const TileParameters&) final;

    void startRender(PaintParameters&) final;
    void finishRender(PaintParameters&) final;

    std::vector<std::reference_wrapper<RenderTile>> getRenderTiles() final;

    std::unordered_map<std::string, std::vector<Feature>>
    queryRenderedFeatures(const ScreenLineString& geometry,
                          const TransformState& transformState,
                          const std::vector<const RenderLayer*>& layers,
                          const RenderedQueryOptions& options) const final;

    std::vector<Feature>
    querySourceFeatures(const SourceQueryOptions&) const final;

    void onLowMemory() final;
    void dumpDebugLogs() const final;
    
private:
    const style::CustomVectorSource::Impl& impl() const;

    TilePyramid tilePyramid;
};

template <>
inline bool RenderSource::is<RenderCustomVectorSource>() const {
    return baseImpl->type == SourceType::CustomVector;
}

} // namespace mbgl
