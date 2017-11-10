/*
 */
#pragma once

#include <string>

namespace alk {
class TilePath {
public:
	std::string name;
	unsigned int zoom;
	unsigned long long x;
	unsigned long long y;
	std::string format;
	explicit TilePath();
	explicit TilePath(std::string n, std::string z, std::string x1, std::string y1, std::string fmt);
	std::string to_s();
};
}
