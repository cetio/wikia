module gui.conformer.camera;

import std.math;
import std.algorithm;

struct Camera
{
    double rotationX = 0.3;
    double rotationY = 0.4;
    double zoom = 40.0;
    double baseZoom = 40.0;

    double[2] project(double x, double y, double z)
    {
        double cosX = cos(rotationX), sinX = sin(rotationX);
        double cosY = cos(rotationY), sinY = sin(rotationY);

        double y1 = y * cosX - z * sinX;
        double z1 = y * sinX + z * cosX;

        double x2 = x * cosY + z1 * sinY;

        return [x2 * zoom, y1 * zoom];
    }

    void rotate(double deltaX, double deltaY)
    {
        rotationY += deltaX * 0.01;
        rotationX += deltaY * 0.01;
    }

    void zoomBy(double factor)
    {
        zoom *= factor;
        zoom = max(10.0, min(200.0, zoom));
    }

    void reset()
    {
        rotationX = 0.3;
        rotationY = 0.4;
        zoom = baseZoom;
    }
}
