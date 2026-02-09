module gui.conformer.hit;

import std.math;
import std.algorithm;
import gui.conformer.camera : Camera;
import gui.conformer.render : getRadius;
import wikia.pubchem.conformer3d;

struct HitResult
{
    bool hit;
    bool isAtom;
    int atomId;
    size_t bondIdx;
}

HitResult hitTest(double mouseX, double mouseY, int width, int height, Conformer3D conformer, Camera cam)
{
    HitResult ret;
    ret.hit = false;

    if (conformer is null || !conformer.isValid())
        return ret;

    double centerX = width / 2.0;
    double centerY = height / 2.0;

    double mx = mouseX - centerX;
    double my = mouseY - centerY;

    double closestAtomDist = double.max;
    int hoveredAtomId = -1;

    foreach (atom; conformer.atoms)
    {
        double sx, sy;
        cam.project(atom.x, atom.y, atom.z, sx, sy);

        double dist = sqrt((sx - mx) * (sx - mx) + (sy - my) * (sy - my));
        double radius = getRadius(atom.element) * cam.zoom * 0.3;

        if (dist <= radius && dist < closestAtomDist)
        {
            hoveredAtomId = atom.aid;
            closestAtomDist = dist;
        }
    }

    if (hoveredAtomId != -1)
    {
        ret.hit = true;
        ret.isAtom = true;
        ret.atomId = hoveredAtomId;
        return ret;
    }

    double closestBondDist = double.max;
    size_t hoveredBondIdx = size_t.max;

    foreach (size_t i, bond; conformer.bonds)
    {
        int idx1 = conformer.indexOf(bond.aid1);
        int idx2 = conformer.indexOf(bond.aid2);

        if (idx1 < 0 || idx2 < 0)
            continue;

        double sx1, sy1, sx2, sy2;
        cam.project(conformer.atoms[idx1].x, conformer.atoms[idx1].y, conformer.atoms[idx1].z, sx1, sy1);
        cam.project(conformer.atoms[idx2].x, conformer.atoms[idx2].y, conformer.atoms[idx2].z, sx2, sy2);

        double dist = distanceToLineSegment(mx, my, sx1, sy1, sx2, sy2);
        double bondWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);

        if (dist <= bondWidth && dist < closestBondDist)
        {
            hoveredBondIdx = i;
            closestBondDist = dist;
        }
    }

    if (hoveredBondIdx != size_t.max)
    {
        ret.hit = true;
        ret.isAtom = false;
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

