#pragma once

// Units are fractions of a leaf's width. +y points down the page.
// A developable cylinder preserves arc length; its axis is the perpendicular
// bisector of the corner-to-finger vector, corrected by half the bend arc.
struct CurlFold {
    float nx, ny, axisX, axisY, radius;
};
struct CurlPoint {
    float x, y, z, nx, ny, nz;
};
extern "C" {
CurlFold CurlMakeFold(float width, float height, float progress, float cornerY, float fingerY, float velocity);
CurlPoint CurlProject(float x, float y, CurlFold fold);
}
