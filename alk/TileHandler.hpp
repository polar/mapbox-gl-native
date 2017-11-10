/*
 */
#pragma once

#include <folly/Memory.h>
#include <mbgl/util/run_loop.hpp>
#include <proxygen/httpserver/RequestHandler.h>
#include <proxygen/lib/utils/URL.h>
#include <memory>

#include "RasterTileRenderer.hpp"
#include "TilePath.hpp"

namespace proxygen {
class ResponseHandler;
}

namespace alk {

class TileHandler : public proxygen::RequestHandler {
 public:
  explicit TileHandler(
			mbgl::util::RunLoop* loop_,
			RasterTileRenderer* rasterTileRenderer_);

  void onRequest(std::unique_ptr<proxygen::HTTPMessage> headers)
      noexcept override;

  void onBody(std::unique_ptr<folly::IOBuf> body) noexcept override;

  void onEOM() noexcept override;

  void onUpgrade(proxygen::UpgradeProtocol proto) noexcept override;

  void requestComplete() noexcept override;

  void onError(proxygen::ProxygenError err) noexcept override;

 private:
  mbgl::util::RunLoop* loop;
  RasterTileRenderer* rasterTileRenderer;
  std::unique_ptr<proxygen::HTTPMessage> request_;
  std::unique_ptr<folly::IOBuf> body_;
  proxygen::URL url_;
  TilePath *tilePath_ = nullptr;
  bool pending = false;
};

}
