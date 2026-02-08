module gui.background;

import std.math : sin, cos, PI;
import std.typecons : Yes;
import std.random : uniform01, uniform, Random, unpredictableSeed;
import std.algorithm : min, max;

import gtk.drawing_area;
import cairo.context;
import glib.c.functions;

struct Splotch
{
    double x, y;
    double radius;
    double r, g, b;
    double alpha;
    int seed;
}

class Background : DrawingArea
{
    private double time = 0;
    private Random rng;
    private Splotch[] splotches;
    private enum maxSplotches = 40;
    private enum msPerFrame = 100;
    private enum spawnMargin = 50.0;
    private enum minRadius = 30.0;
    private enum maxRadius = 120.0;

    this()
    {
        rng = Random(unpredictableSeed);
        
        setDrawFunc(&drawBackground);
        addCssClass("homepage-background");
        
        g_timeout_add(msPerFrame, cast(GSourceFunc)&onFrame, cast(void*)this);
    }

    extern(C) static int onFrame(void* data)
    {
        Background self = cast(Background)data;
        self.time += 1.0;
        self.spawnSplotch();
        self.queueDraw();
        return 1;
    }

    private void spawnSplotch()
    {
        int width = getAllocatedWidth();
        int height = getAllocatedHeight();

        if (width <= 0 || height <= 0 || splotches.length >= maxSplotches)
            return;

        Splotch s;
        s.x = uniform(-spawnMargin, width + spawnMargin, rng);
        s.y = uniform(-spawnMargin, height + spawnMargin, rng);
        s.radius = uniform(minRadius, maxRadius, rng);

        // Random color from a palette (navy, baby blue, cyan, teal, soft purple)
        int colorChoice = uniform(0, 5, rng);
        switch (colorChoice)
        {
            case 0: // Navy
                s.r = 0.0; s.g = 0.2; s.b = 0.4;
                break;
            case 1: // Baby blue
                s.r = 0.70; s.g = 0.85; s.b = 1.0;
                break;
            case 2: // Cyan
                s.r = 0.4; s.g = 0.8; s.b = 1.0;
                break;
            case 3: // Teal
                s.r = 0.2; s.g = 0.6; s.b = 0.7;
                break;
            case 4: // Soft purple-blue
                s.r = 0.5; s.g = 0.6; s.b = 0.9;
                break;
            default:
                s.r = 0.70; s.g = 0.85; s.b = 1.0;
        }

        s.alpha = uniform(0.15, 0.35, rng);
        s.seed = uniform(0, 1000, rng);

        splotches ~= s;
    }

    private void drawBlob(Context cr, double cx, double cy, double baseRadius, int seed)
    {
        // Create irregular blob shape using multiple sine waves around circle
        int points = 32;
        double[32] angles;
        double[32] radii;

        foreach (i; 0..points)
        {
            angles[i] = i * 2.0 * PI / points;

            // Multiple overlapping sine waves for irregular edge
            double variation = 0;
            variation += sin(angles[i] * 3 + seed * 0.1) * 0.15;
            variation += cos(angles[i] * 5 + seed * 0.2) * 0.10;
            variation += sin(angles[i] * 7 + seed * 0.3) * 0.08;
            variation += cos(angles[i] * 2 + time * 0.05) * 0.05;

            radii[i] = baseRadius * (1.0 + variation);
        }

        // Draw smooth curve through points
        cr.moveTo(cx + radii[0] * cos(angles[0]), cy + radii[0] * sin(angles[0]));

        foreach (i; 0..points)
        {
            int next = (i + 1) % points;
            int next2 = (i + 2) % points;

            // Control points for smooth bezier
            double cp1x = cx + radii[i] * cos(angles[i]) + (radii[next] * cos(angles[next]) - radii[i] * cos(angles[i])) * 0.3;
            double cp1y = cy + radii[i] * sin(angles[i]) + (radii[next] * sin(angles[next]) - radii[i] * sin(angles[i])) * 0.3;

            double cp2x = cx + radii[next] * cos(angles[next]) - (radii[next2] * cos(angles[next2]) - radii[next] * cos(angles[next])) * 0.3;
            double cp2y = cy + radii[next] * sin(angles[next]) - (radii[next2] * sin(angles[next2]) - radii[next] * sin(angles[next])) * 0.3;

            cr.curveTo(cp1x, cp1y, cp2x, cp2y, cx + radii[next] * cos(angles[next]), cy + radii[next] * sin(angles[next]));
        }

        cr.closePath();
    }

    private void drawBackground(DrawingArea, Context cr, int width, int height)
    {
        // White base
        cr.setSourceRgb(1.0, 1.0, 1.0);
        cr.paint();

        // Draw all splotches with blending
        foreach (splotch; splotches)
        {
            cr.setSourceRgba(splotch.r, splotch.g, splotch.b, splotch.alpha);
            drawBlob(cr, splotch.x, splotch.y, splotch.radius, splotch.seed);
            cr.fill();
        }
    }
}
