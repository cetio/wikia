module gui.background;

import std.math : sin, cos, PI;
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
    
    // Configuration
    private int maxSplotches = 40;
    private int msPerFrame = 100;
    private double spawnMargin = 50.0;
    private double minRadius = 30.0;
    private double maxRadius = 120.0;
    private double minAlpha = 0.15;
    private double maxAlpha = 0.35;
    private string cssClass = "home-background";

    this(int maxSplotches = 40, 
        int msPerFrame = 100, 
        double spawnMargin = 50.0,
        double minRadius = 30.0, 
        double maxRadius = 120.0,
        double minAlpha = 0.15, 
        double maxAlpha = 0.35,
        string cssClass = "home-background"
    )
    {
        this.maxSplotches = maxSplotches;
        this.msPerFrame = msPerFrame;
        this.spawnMargin = spawnMargin;
        this.minRadius = minRadius;
        this.maxRadius = maxRadius;
        this.minAlpha = minAlpha;
        this.maxAlpha = maxAlpha;
        this.cssClass = cssClass;
        this.rng = Random(unpredictableSeed);
        
        setDrawFunc(&drawBackground);
        addCssClass(this.cssClass);
        
        g_timeout_add(this.msPerFrame, cast(GSourceFunc)&onFrame, cast(void*)this);
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

        switch (uniform(0, 5, rng))
        {
            // Navy
            case 0:
                s.r = 0.0; 
                s.g = 0.2; 
                s.b = 0.4;
                break;
            // Baby blue
            case 1:
                s.r = 0.70; 
                s.g = 0.85; 
                s.b = 1.0;
                break;
            // Cyan
            case 2:
                s.r = 0.4; 
                s.g = 0.8; 
                s.b = 1.0;
                break;
            // Teal
            case 3:
                s.r = 0.2; 
                s.g = 0.6; 
                s.b = 0.7;
                break;
            // Soft purple-blue
            case 4:
                s.r = 0.5; 
                s.g = 0.6; 
                s.b = 0.9;
                break;
            default:
                s.r = 0.70; 
                s.g = 0.85; 
                s.b = 1.0;
        }

        s.alpha = uniform(minAlpha, maxAlpha, rng);
        s.seed = uniform(0, 1000, rng);

        splotches ~= s;
    }

    private void drawBlob(Context ctx, double cx, double cy, double baseRadius, int seed)
    {
        // Create irregular blob shape using multiple sine waves around circle.
        int points = 32;
        double[32] angles;
        double[32] radii;

        foreach (i; 0..points)
        {
            angles[i] = i * 2.0 * PI / points;

            // Multiple overlapping sine waves for irregular edge.
            double variation = 0;
            variation += sin(angles[i] * 3 + seed * 0.1) * 0.15;
            variation += cos(angles[i] * 5 + seed * 0.2) * 0.10;
            variation += sin(angles[i] * 7 + seed * 0.3) * 0.08;
            variation += cos(angles[i] * 2 + time * 0.05) * 0.05;

            radii[i] = baseRadius * (1.0 + variation);
        }

        // Draw smooth curve through points.
        ctx.moveTo(cx + radii[0] * cos(angles[0]), cy + radii[0] * sin(angles[0]));

        foreach (i; 0..points)
        {
            int next = (i + 1) % points;
            int next2 = (i + 2) % points;

            // Control points for smooth bezier.
            double[2] cp1 = [
                cx + radii[i] * cos(angles[i]) + 
                        (radii[next] * cos(angles[next]) - radii[i] * cos(angles[i])) * 0.3,
                cy + radii[i] * sin(angles[i]) + 
                        (radii[next] * sin(angles[next]) - radii[i] * sin(angles[i])) * 0.3
            ];

            double[2] cp2 = [
                cx + radii[next] * cos(angles[next]) - 
                        (radii[next2] * cos(angles[next2]) - radii[next] * cos(angles[next])) * 0.3,
                cy + radii[next] * sin(angles[next]) - 
                        (radii[next2] * sin(angles[next2]) - radii[next] * sin(angles[next])) * 0.3
            ];

            ctx.curveTo(
                cp1[0], cp1[1], 
                cp2[0], cp2[1], 
                cx + radii[next] * cos(angles[next]), 
                cy + radii[next] * sin(angles[next])
            );
        }

        ctx.closePath();
    }

    private void drawBackground(DrawingArea, Context ctx, int width, int height)
    {
        ctx.setSourceRgb(1.0, 1.0, 1.0);
        ctx.paint();

        foreach (splotch; splotches)
        {
            ctx.setSourceRgba(splotch.r, splotch.g, splotch.b, splotch.alpha);
            drawBlob(ctx, splotch.x, splotch.y, splotch.radius, splotch.seed);
            ctx.fill();
        }
    }
}
