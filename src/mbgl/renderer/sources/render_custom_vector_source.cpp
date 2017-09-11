#include <mbgl/renderer/sources/render_custom_vector_source.hpp>
#include <mbgl/renderer/render_tile.hpp>
#include <mbgl/renderer/paint_parameters.hpp>
#include <mbgl/tile/geojson_tile.hpp>
#include <mbgl/util/logging.hpp>

#include <mbgl/algorithm/generate_clip_ids.hpp>
#include <mbgl/algorithm/generate_clip_ids_impl.hpp>

#include <mapbox/geojsonvt.hpp>

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

void RenderCustomVectorSource::setTileData(const CanonicalTileID& tileID,
                                           const style::FetchTileResult& result) {
    if (result.is<style::Error>()) {
        Log::Error(Event::Render, "FetchTile (%d, %d, %d) error: %s", tileID.z, tileID.x, tileID.y, result.get<style::Error>().message.c_str());
        return;
    }
    
    auto geoJSON = result.get<mapbox::geojson::geojson>();
    auto data = mapbox::geometry::feature_collection<int16_t>();
    if (geoJSON.is<FeatureCollection>() && !geoJSON.get<FeatureCollection>().empty()) {
        const GeoJSONOptions options = impl().getOptions();

        const double scale = util::EXTENT / options.tileSize;
        
        mapbox::geojsonvt::Options vtOptions;
        vtOptions.maxZoom = options.maxzoom;
        vtOptions.extent = util::EXTENT;
        vtOptions.buffer = std::round(scale * options.buffer);
        vtOptions.tolerance = scale * options.tolerance;
        auto geojsonVt = std::make_unique<mapbox::geojsonvt::GeoJSONVT>(geoJSON, vtOptions);
        data = geojsonVt->getTile(tileID.z, tileID.x, tileID.y).features;
    }
    for (auto const& item : tilePyramid.tiles) {
        if (item.first.canonical == tileID) {
            static_cast<GeoJSONTile*>(item.second.get())->updateData(data);
        }
    }
}

void RenderCustomVectorSource::update(Immutable<style::Source::Impl> baseImpl_,
                                 const std::vector<Immutable<Layer::Impl>>& layers,
                                 const bool needsRendering,
                                 const bool needsRelayout,
                                 const TileParameters& parameters) {
    std::swap(baseImpl, baseImpl_);

    enabled = needsRendering;

    auto fetchTile = impl().getFetchTileFunction();
    
    FetchTileCallback fetchTileCallback = std::bind(&RenderCustomVectorSource::setTileData, this, std::placeholders::_1, std::placeholders::_2);

    const GeoJSONOptions options = impl().getOptions();
    tilePyramid.update(layers,
                       needsRendering,
                       needsRelayout,
                       parameters,
                       SourceType::CustomVector,
                       util::tileSize,
                       { options.minzoom, options.maxzoom },
                       [&] (const OverscaledTileID& tileID) {
                           fetchTile(tileID.canonical, fetchTileCallback);
                           return std::make_unique<GeoJSONTile>(tileID, impl().id, parameters, mapbox::geometry::feature_collection<int16_t>());
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
