#include <mbgl/text/place_symbols.hpp>
#include <mbgl/renderer/buckets/symbol_bucket.hpp>
#include <mbgl/layout/symbol_layout.hpp>
#include <mbgl/renderer/placement_state.hpp>

namespace mbgl {

    void updateOpacity(SymbolInstance& symbolInstance, OpacityState& opacityState, float targetOpacity, TimePoint& opacityUpdateTime, CollisionFadeTimes& collisionFadeTimes) {
        if (symbolInstance.isDuplicate) {
            opacityState.opacity = 0;
            opacityState.targetOpacity = 0;
        } else {
            if (opacityState.targetOpacity != targetOpacity) {
                collisionFadeTimes.latestStart = opacityUpdateTime;
            }
            float increment = collisionFadeTimes.fadeDuration != Duration::zero() ?
                ((opacityUpdateTime - opacityState.time) / collisionFadeTimes.fadeDuration) :
                1;
            opacityState.opacity = std::fmax(0, std::fmin(1, opacityState.opacity + (opacityState.targetOpacity == 1 ? increment : -increment)));
            opacityState.targetOpacity = targetOpacity;
            opacityState.time = opacityUpdateTime;
        }
    }

    void updateOpacities(SymbolBucket& bucket, SymbolLayout& symbolLayout, CollisionFadeTimes& collisionFadeTimes) {

        if (bucket.hasTextData()) bucket.text.opacityVertices.clear();
        if (bucket.hasIconData()) bucket.icon.opacityVertices.clear();

        // TODO
        // bucket.fadeStartTime = Date.now()
        TimePoint fadeStartTime = Clock::now();

        for (SymbolInstance& symbolInstance : symbolLayout.symbolInstances) {
            if (symbolInstance.hasText) {
                auto targetOpacity = symbolInstance.placedText ? 1.0 : 0.0;
                bool initialHidden = symbolInstance.textOpacityState.opacity == 0 && symbolInstance.textOpacityState.targetOpacity == 0;
                updateOpacity(symbolInstance, symbolInstance.textOpacityState, targetOpacity, fadeStartTime, collisionFadeTimes);
                bool nowHidden = symbolInstance.textOpacityState.opacity == 0 && symbolInstance.textOpacityState.targetOpacity == 0;

                if (initialHidden != nowHidden) {
                    // TODO mark placed symbols as hidden so that they don't need to be projected at render time
                }

                auto opacityVertex = SymbolOpacityAttributes::vertex(symbolInstance.textOpacityState.targetOpacity, symbolInstance.textOpacityState.opacity);
                for (size_t i = 0; i < symbolInstance.glyphQuads.size(); i++) {
                    bucket.text.opacityVertices.emplace_back(opacityVertex);
                    bucket.text.opacityVertices.emplace_back(opacityVertex);
                    bucket.text.opacityVertices.emplace_back(opacityVertex);
                    bucket.text.opacityVertices.emplace_back(opacityVertex);
                }
            }

            if (symbolInstance.hasIcon) {
                auto targetOpacity = symbolInstance.placedIcon ? 1.0 : 0.0;
                updateOpacity(symbolInstance, symbolInstance.iconOpacityState, targetOpacity, fadeStartTime, collisionFadeTimes);
                auto opacityVertex = SymbolOpacityAttributes::vertex(1.0, 1.0); // TODO
                if (symbolInstance.iconQuad) {
                    bucket.icon.opacityVertices.emplace_back(opacityVertex);
                    bucket.icon.opacityVertices.emplace_back(opacityVertex);
                    bucket.icon.opacityVertices.emplace_back(opacityVertex);
                    bucket.icon.opacityVertices.emplace_back(opacityVertex);
                }
            }
        }

        // TODO update vertex buffers
    }
} // namespace mbgl
