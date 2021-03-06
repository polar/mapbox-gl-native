/*
 */
#include <folly/Memory.h>
#include <folly/io/async/EventBaseManager.h>
#include <proxygen/httpserver/HTTPServer.h>
#include <proxygen/httpserver/RequestHandlerFactory.h>
#include <unistd.h>
#include <mbgl/util/run_loop.hpp>
#include <mbgl/storage/default_file_source.hpp>
#include <mbgl/actor/scheduler.hpp>
#include <map>
#include <thread>
#include <mutex>
#include <chrono>
#include <regex>

#include <boost/program_options.hpp>

#include "RenderCache.hpp"
#include "TileHandler.hpp"
#include "StatsHandler.hpp"
#include "SourcesFileSource.hpp"
#include "SourcesDefaultFileSource.hpp"
#include "SourcesSpecLoader.hpp"

using namespace proxygen;

using folly::EventBase;
using folly::EventBaseManager;
using folly::SocketAddress;

using Protocol = HTTPServer::Protocol;
using namespace alk;

namespace po = boost::program_options;

class Entry {
public:
	mbgl::util::RunLoop* loop;
	RasterTileRenderer * renderer;
};

std::mutex g_gl_render_mutex;

class TileHandlerFactory : public RequestHandlerFactory {
 public:
	TileHandlerFactory(std::string serverName_,
			std::chrono::system_clock::time_point begin_,
			std::map<std::thread::id, Entry *>& renderers_,
			std::string styleUrl_,
			unsigned int tileSize_,
			RenderCache& rasterCache_,
			mbgl::FileSource& fileSource_,
			int renderThreads_) :
			serverName(serverName_),
			beginTime(begin_),
			styleUrl(styleUrl_),
			tileSize(tileSize_),
		    rendererLoops(renderers_),
			rasterCache(rasterCache_),
			fileSource(fileSource_),
			renderThreads(renderThreads_){}
  void onServerStart(folly::EventBase* /*evb*/) noexcept override {
  }

  void onServerStop() noexcept override {
  }

  RequestHandler* onRequest(RequestHandler* h, HTTPMessage* msg) noexcept override {
	  std::smatch base_match;
      auto res = std::regex_search(msg->getURL(), base_match, std::regex("/stats"));
	  if (res) {
		  return onStatsRequest(h, msg);
	  }
	  return onTileRequest(h, msg);
  }

  RequestHandler* onStatsRequest(RequestHandler *, HTTPMessage *) noexcept {
	  std::vector<RenderStats> renderers;
	  for(auto rl: rendererLoops) {
		  renderers.push_back(rl.second->renderer->getRenderStats());
	  }
	  return new StatsHandler(serverName, beginTime, renderers);
  }

  RequestHandler* onTileRequest(RequestHandler*, HTTPMessage*) noexcept {
	  auto tid = std::this_thread::get_id();
	  std::stringstream id;
	  id << tid;
	  std::string sid = id.str();
	  Entry *entry = rendererLoops[tid];
	  if (entry == NULL) {
		  entry = new Entry();
		  entry->loop = new mbgl::util::RunLoop(mbgl::util::RunLoop::Type::New);
		  entry->renderer = new RasterTileRenderer(
				  sid,
				  styleUrl,
				  tileSize,
				  tileSize,
				  tileSize < 512 ? 1.0 : 2.0, // pixelRatio
				  0.0,
				  0.0,
				  rasterCache,
				  fileSource,
				  g_gl_render_mutex,
				  this->renderThreads);
		  rendererLoops[tid] = entry;
	  }
    return new TileHandler(entry->loop, entry->renderer);
  }

 private:
  std::string serverName;
  std::chrono::system_clock::time_point beginTime;
  std::string styleUrl;
  unsigned int tileSize;
  std::map<std::thread::id, Entry *>& rendererLoops;
  RenderCache& rasterCache;
  mbgl::FileSource& fileSource;
  int renderThreads;
};

int main(int argc, char* argv[]) {
	std::string style_url;
	unsigned int server_threads = 1;
	unsigned int render_threads = 4;
	std::string raster_cache_file = "raster.cache";
	std::string vector_cache_file = "vector.cache";
	std::string sources_map_file = "";
	std::string asset_root = ".";
	std::string serverName = "ALK Raster Render Server";
	unsigned int raster_cache_limit = 1024;
	unsigned int vector_cache_limit = 1024;
	unsigned int http_port = 11000;
	unsigned int tile_size = 512;
	std::string bind_address = "0.0.0.0";

    po::options_description desc("Allowed options");
    desc.add_options()
    	("name,n", po::value(&serverName)->value_name("server name"), "Server Name")
		("style,s", po::value(&style_url)->required()->value_name("url"), "Mapbox Stylesheet URL")
		("tile-size,z", po::value(&tile_size)->value_name("integer")->default_value(512), "TileSize (256,512)")
		("port,p", po::value(&http_port)->value_name("integer")->default_value(http_port), "Http Port")
		("bind,b", po::value(&bind_address)->value_name("IP Address")->default_value(bind_address), "IP Address to which to bind server.")
		("server-threads,t", po::value(&server_threads)->value_name("integer")->default_value(server_threads), "Number of Server Threads")
		("render-threads,T", po::value(&render_threads)->value_name("integer")->default_value(render_threads), "Number of Render Threads per Server Thread")
		("raster-cache,r", po::value(&raster_cache_file)->value_name("sqlite3")->default_value(raster_cache_file), "Raster Tile Cache File")
		("raster-cache-limit,R", po::value(&raster_cache_limit)->value_name("Mb")->default_value(raster_cache_limit), "Raster Cache Limit")
		("vector-cache,v", po::value(&vector_cache_file)->value_name("sqlite3")->default_value(vector_cache_file), "Vector Tile Cache File")
		("vector-cache-limit,V", po::value(&vector_cache_limit)->value_name("Mb")->default_value(vector_cache_limit), "Vector Cache Limit")
		("asset-root,a", po::value(&asset_root)->value_name("directory")->default_value(asset_root), "Directory to which asset:// URLs will resolve")
		("sources-map,m", po::value(&sources_map_file)->value_name("path")->default_value(sources_map_file),"Name of MbTilesSource URL Map")
    ;

    try {
        po::variables_map vm;
        po::store(po::parse_command_line(argc, argv, desc), vm);
        po::notify(vm);
        if (tile_size != 256 && tile_size != 512) {
        	throw std::runtime_error("Tile Size must be 256 or 512");
        }
    } catch(std::exception& e) {
        std::cout << "Error: " << e.what() << std::endl << desc;
        exit(1);
    }
  mbgl::DefaultFileSource vectorCache(vector_cache_file, asset_root, vector_cache_limit * 1024*1024);
  SourcesSpec specs = SourcesSpec();
  if (sources_map_file != "") {
	  SourcesSpecLoader loader(sources_map_file);
	  specs = loader.get();
  }
  SourcesFileSource sources(specs);
  SourcesDefaultFileSource fileSource(sources, vectorCache);

  RenderCache rasterCache(raster_cache_file, raster_cache_limit * 1024*1024);
  std::map<std::thread::id, Entry *> renderers;
  std::vector<HTTPServer::IPConfig> IPs = {
    {SocketAddress(bind_address, http_port, true), Protocol::HTTP}
  };

  if (server_threads <= 0) {
    server_threads = sysconf(_SC_NPROCESSORS_ONLN);
    CHECK(server_threads > 0);
  }

  HTTPServerOptions options;
  options.threads = static_cast<size_t>(server_threads);
  options.idleTimeout = std::chrono::milliseconds(60000);
  options.shutdownOn = {SIGINT, SIGTERM};
  options.enableContentCompression = false;
  std::chrono::system_clock::time_point begin =
			std::chrono::system_clock::now();
  options.handlerFactories = RequestHandlerChain()
      .addThen<TileHandlerFactory>(serverName, begin, renderers, style_url, tile_size, rasterCache, fileSource, render_threads)
      .build();
  options.h2cEnabled = true;

  HTTPServer server(std::move(options));
  server.bind(IPs);

  // Start HTTPServer mainloop in a separate thread
  std::thread t([&] () {
	  server.start();
  });

  t.join();
  return 0;
}
