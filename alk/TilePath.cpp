/*
 */
#include "TilePath.hpp"

#include <string>
#include <sstream>
namespace alk {

TilePath::TilePath() : name(""), zoom(0), x(0), y(0), format("") {};

TilePath::TilePath(std::string n, std::string z, std::string x1, std::string y1, std::string fmt) {
		name = n;
		zoom = atoi(z.c_str());
		x = atoi(x1.c_str());
		y = atoi(y1.c_str());
		format = fmt;
}

std::string TilePath::to_s() {
		std::ostringstream s;
		s << name << "/" << zoom << "/" << x << "/" << y << "." << format;
		return s.str();
}

}
