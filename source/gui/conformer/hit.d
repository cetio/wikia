module gui.conformer.hit;

import std.math;
import std.algorithm;
import gui.conformer.camera;
import gui.conformer.render : getRadius;
import wikia.pubchem.conformer3d;

struct HitResult
{
    int atomIdx = -1;
    int bondIdx = -1;

    bool isValid() const 
        => atomIdx > -1 || bondIdx > -1;
}

HitResult hitTest(
    double mouseX, 
    double mouseY, 
    int width, 
    int height, 
    Conformer3D conformer, 
    Camera cam
)
{
    HitResult ret;

    if (conformer is null || !conformer.isValid())
        return ret;

    double centerX = width / 2.0;
    double centerY = height / 2.0;

    double mx = mouseX - centerX;
    double my = mouseY - centerY;

    double closestAtomDist = double.max;
    int hoveredAtomIdx = -1;

    foreach (i, atom; conformer.atoms)
    {
        double[2] proj = cam.project(atom.x, atom.y, atom.z);
        
        double dist = sqrt((proj[0] - mx) * (proj[0] - mx) + (proj[1] - my) * (proj[1] - my));
        double radius = getRadius(atom.element) * cam.zoom * 0.3;

        if (dist <= radius && dist < closestAtomDist)
        {
            hoveredAtomIdx = cast(int)i;
            closestAtomDist = dist;
        }
    }

    if (hoveredAtomIdx != -1)
    {
        ret.atomIdx = hoveredAtomIdx;
        return ret;
    }

    double closestBondDist = double.max;
    int hoveredBondIdx = -1;

    foreach (size_t i, bond; conformer.bonds)
    {
        int idx1 = conformer.indexOf(bond.aid1);
        int idx2 = conformer.indexOf(bond.aid2);

        if (idx1 < 0 || idx2 < 0)
            continue;

        double[2] proj1 = cam.project(conformer.atoms[idx1].x, conformer.atoms[idx1].y, conformer.atoms[idx1].z);
        double[2] proj2 = cam.project(conformer.atoms[idx2].x, conformer.atoms[idx2].y, conformer.atoms[idx2].z);

        double dist = distanceToLineSegment(mx, my, proj1[0], proj1[1], proj2[0], proj2[1]);
        double bondWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);

        if (dist <= bondWidth && dist < closestBondDist)
        {
            hoveredBondIdx = cast(int)i;
            closestBondDist = dist;
        }
    }

    if (hoveredBondIdx != -1)
    {
        ret.bondIdx = hoveredBondIdx;
    }

    return ret;
}

double distanceToLineSegment(double px, double py, double x1, double y1, double x2, double y2)
{
    double dx = x2 - x1;
    double dy = y2 - y1;
    double lengthSquared = dx * dx + dy * dy;

    if (lengthSquared == 0)
        return sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));

    double t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / lengthSquared));
    double projectionX = x1 + t * dx;
    double projectionY = y1 + t * dy;

    return sqrt((px - projectionX) * (px - projectionX) + (py - projectionY) * (py - projectionY));
}

