/*
 */
#include "TileHandler.hpp"

#include <mbgl/util/run_loop.hpp>
#include <proxygen/httpserver/RequestHandler.h>
#include <proxygen/httpserver/ResponseBuilder.h>
#include <proxygen/lib/utils/URL.h>
#include <memory>
#include <iostream>
#include <regex>
#include <string>

#include "Tile.hpp"
#include "TileLoader.hpp"

using namespace proxygen;

namespace alk {

TileHandler::TileHandler(
		mbgl::util::RunLoop* loop_,
		RasterTileRenderer* rasterTileRenderer_) :
				loop(loop_),
				rasterTileRenderer(rasterTileRenderer_) {
}

void TileHandler::onRequest(std::unique_ptr<HTTPMessage>  headers ) noexcept {
  request_ = std::move(headers);
  url_ = proxygen::URL(request_->getURL());
  std::cout << url_.getUrl() << std::endl;
  std::string path = url_.getPath();
  std::smatch m;
  // Try to match /data/{z}/{x}/{y}.png
  std::regex pathMatch("/([^/]*)/([0-9]+)/([0-9]+)/([0-9]+)(.(png|jpg))?");
  if (std::regex_match(path, m, pathMatch)) {
	  tilePath_ = new TilePath(m[1],m[2],m[3],m[4],m[6]);
  } else {
	  // This approach matches ALK style /data?x={x}&y={y}&z={z}
	  auto q = url_.getQuery();
	  std::string x,y,z;
	  if(std::regex_search(q, m, std::regex("x=([0-9]+)"))) {
		  x = m[1];
	  }
	  if(std::regex_search(q, m, std::regex("y=([0-9]+)"))) {
		  y = m[1];
	  }
	  if(std::regex_search(q, m, std::regex("z=([0-9]+)"))) {
		  z = m[1];
	  }
	  if (x != "" && y != "" && z != "") {
		  // We always assume png here.
		  tilePath_ = new TilePath(url_.getPath(), z, x, y, "png");
	  } else {
		  // tilePath_ is null
	  }
  }
}

void TileHandler::onBody(std::unique_ptr<folly::IOBuf> body) noexcept {
  if (body_) {
    body_->prependChain(std::move(body));
  } else {
    body_ = std::move(body);
  }
}

void TileHandler::onEOM() noexcept {
  ResponseBuilder resp(downstream_);
  if (tilePath_ != NULL) {
	  TileLoader loader(tilePath_, rasterTileRenderer);
	  pending = true;
	  loader.load([this, &resp] (Tile& tile) {
		  try {
			  if (tile.data) {
				  resp.status(200, "OK");
				  resp.body(*tile.data);
			  } else {
				  resp.status(500, "Internal Render Error");
			  }
		  } catch (std::exception& e) {
			  resp.status(500, "Internal Render Error");
		  }
		  pending = false;
	  });
	  // This bit of code ensures that the loop will get run once
	  // after the loader sets this up on a thread ensuring execution
	  // of the callback.
	  while(pending)  {
		  loop->runOnce();
	  }
	  resp.sendWithEOM();
  } else {
	  resp.status(404, "Not Found: Bad Tile Address");
	  resp.sendWithEOM();
  }
}

void TileHandler::onUpgrade(UpgradeProtocol /*protocol*/) noexcept {
  // handler doesn't support upgrades
}

void TileHandler::requestComplete() noexcept {
  delete tilePath_;
  delete this;
}

void TileHandler::onError(ProxygenError /*err*/) noexcept {
	delete tilePath_;
	delete this;
}

}
