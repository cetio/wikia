module gui.conformer.math;

import std.math;
import std.algorithm;
import std.array;
import gui.conformer.camera;
import gui.conformer.render : getRadius;
import gui.conformer.view : MoleculeView;
import akashi.pubchem.conformer3d;

double[int] distanceMesh(MoleculeView view, double mouseX, double mouseY, int width, int height)
{
    double[int] distances;

    if (view.compound is null || view.compound.conformer3D is null || !view.compound.conformer3D.isValid())
        return distances;

    Conformer3D conformer = view.compound.conformer3D;
    Camera cam = view.camera;

    mouseX -= (width / 2.0);
    mouseY -= (height / 2.0);

    foreach (i, atom; conformer.atoms)
    {
        double[2] proj = cam.project(atom.x, atom.y, atom.z);
        
        double dist = sqrt((proj[0] - mouseX) * (proj[0] - mouseX) + (proj[1] - mouseY) * (proj[1] - mouseY));
        distances[cast(int)i] = dist;
    }

    return distances;
}

int atomHit(MoleculeView view, double mouseX, double mouseY, int width, int height)
{
    if (view.compound is null || view.compound.conformer3D is null || !view.compound.conformer3D.isValid())
        return -1;

    Conformer3D conformer = view.compound.conformer3D;
    Camera cam = view.camera;

    mouseX -= (width / 2.0);
    mouseY -= (height / 2.0);

    double closestAtomDist = double.max;
    int hoveredAtomIdx = -1;
    foreach (i, atom; conformer.atoms)
    {
        double[2] proj = cam.project(atom.x, atom.y, atom.z);
        
        double dist = sqrt((proj[0] - mouseX) * (proj[0] - mouseX) + (proj[1] - mouseY) * (proj[1] - mouseY));
        double radius = getRadius(atom.element) * cam.zoom * 0.3;

        if (dist <= radius && dist < closestAtomDist)
        {
            hoveredAtomIdx = cast(int)i;
            closestAtomDist = dist;
        }
    }

    return hoveredAtomIdx;
}

int bondHit(MoleculeView view, double mouseX, double mouseY, int width, int height)
{
    if (view.compound is null || view.compound.conformer3D is null || !view.compound.conformer3D.isValid())
        return -1;

    Conformer3D conformer = view.compound.conformer3D;
    Camera cam = view.camera;

    mouseX -= (width / 2.0);
    mouseY -= (height / 2.0);

    double closestBondDist = double.max;
    int hoveredBondIdx = -1;
    foreach (i, bond; conformer.bonds)
    {
        int idx1 = conformer.indexOf(bond.aid1);
        int idx2 = conformer.indexOf(bond.aid2);

        if (idx1 < 0 || idx2 < 0)
            continue;

        double[2] proj1 = cam.project(conformer.atoms[idx1].x, conformer.atoms[idx1].y, conformer.atoms[idx1].z);
        double[2] proj2 = cam.project(conformer.atoms[idx2].x, conformer.atoms[idx2].y, conformer.atoms[idx2].z);

        double dist = distanceToLineSegment(mouseX, mouseY, proj1[0], proj1[1], proj2[0], proj2[1]);
        double bondWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);

        if (dist <= bondWidth && dist < closestBondDist)
        {
            hoveredBondIdx = cast(int)i;
            closestBondDist = dist;
        }
    }

    return hoveredBondIdx;
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
