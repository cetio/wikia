module gui.conformer.render;

import std.math;
import std.conv : to;

import cairo.context : Context;
import cairo.types : FontSlant, FontWeight, TextExtents;

import gui.conformer.camera : Camera;

import wikia.pubchem.conformer3d;

void getColor(Element elem, out double r, out double g, out double b)
{
    switch (cast(int)elem)
    {
        case 1:  r = 1.0; g = 1.0; b = 1.0; break;  // H - White
        case 6:  r = 0.3; g = 0.3; b = 0.3; break;  // C - Dark gray
        case 7:  r = 0.2; g = 0.4; b = 1.0; break;  // N - Blue
        case 8:  r = 1.0; g = 0.2; b = 0.2; break;  // O - Red
        case 9:  r = 0.0; g = 0.9; b = 0.2; break;  // F - Green
        case 15: r = 1.0; g = 0.5; b = 0.0; break; // P - Orange
        case 16: r = 1.0; g = 0.9; b = 0.2; break; // S - Yellow
        case 17: r = 0.0; g = 0.9; b = 0.0; break; // Cl - Green
        case 35: r = 0.6; g = 0.1; b = 0.1; break; // Br - Dark red
        case 53: r = 0.6; g = 0.0; b = 0.6; break; // I - Purple
        default: r = 0.7; g = 0.5; b = 0.7; break; // Light purple
    }
}

double getRadius(Element elem)
{
    switch (cast(int)elem)
    {
        case 1:  return 0.3;  // H
        case 6:  return 0.5;  // C
        case 7:  return 0.5;  // N
        case 8:  return 0.5;  // O
        case 16: return 0.6; // S
        case 17: return 0.6; // Cl
        case 35: return 0.7; // Br
        case 53: return 0.8; // I
        default: return 0.5;
    }
}

void drawBackground(Context cr)
{
    cr.setSourceRgb(0.2, 0.2, 0.2);
    cr.paint();
}

void drawGrid(Context cr, int width, int height)
{
    cr.setSourceRgba(0.5, 0.5, 0.5, 0.3);
    cr.setLineWidth(1);
    double gridSize = 20.0;
    for (double x = 0; x < width; x += gridSize)
    {
        cr.moveTo(x, 0);
        cr.lineTo(x, height);
    }
    
    for (double y = 0; y < height; y += gridSize)
    {
        cr.moveTo(0, y);
        cr.lineTo(width, y);
    }
    cr.stroke();
}

void drawBackgroundText(Context cr, string name, int width, int height)
{
    if (name is null)
        return;

    cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Bold);
    cr.setFontSize(120);
    TextExtents extents;
    cr.textExtents(name, extents);

    double textX = (width - extents.width) / 2.0;
    double textY = (height + extents.height) / 2.0;

    cr.setSourceRgba(1, 1, 1, 0.08);
    cr.moveTo(textX, textY);
    cr.showText(name);
}

void drawMolecule(Context cr, Conformer3D conformer, Camera cam, int width, int height, 
                  int hoveredAtomId, size_t hoveredBondIdx)
{
    if (conformer is null || !conformer.isValid())
        return;

    double centerX = width / 2.0;
    double centerY = height / 2.0;

    foreach (bond; conformer.bonds)
    {
        int idx1 = conformer.indexOf(bond.aid1);
        int idx2 = conformer.indexOf(bond.aid2);

        if (idx1 < 0 || idx2 < 0)
            continue;

        double sx1, sy1, sx2, sy2;
        cam.project(conformer.atoms[idx1].x, conformer.atoms[idx1].y, conformer.atoms[idx1].z, sx1, sy1);
        cam.project(conformer.atoms[idx2].x, conformer.atoms[idx2].y, conformer.atoms[idx2].z, sx2, sy2);

        double lineWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);

        bool isHovered = false;
        if (hoveredBondIdx != size_t.max)
        {
            Bond3D hb = conformer.bonds[hoveredBondIdx];
            isHovered = (hb.aid1 == bond.aid1 && hb.aid2 == bond.aid2)
                || (hb.aid1 == bond.aid2 && hb.aid2 == bond.aid1);
        }

        if (isHovered)
        {
            double r1, g1, b1, r2, g2, b2;
            getColor(conformer.atoms[idx1].element, r1, g1, b1);
            getColor(conformer.atoms[idx2].element, r2, g2, b2);

            double avgR = (r1 + r2) / 2.0;
            double avgG = (g1 + g2) / 2.0;
            double avgB = (b1 + b2) / 2.0;

            cr.setLineWidth(lineWidth + 4);
            cr.setSourceRgb(avgR, avgG, avgB);
            cr.moveTo(centerX + sx1, centerY + sy1);
            cr.lineTo(centerX + sx2, centerY + sy2);
            cr.stroke();
        }

        cr.setLineWidth(lineWidth);
        cr.setSourceRgba(0.6, 0.6, 0.7, 0.8);
        cr.moveTo(centerX + sx1, centerY + sy1);
        cr.lineTo(centerX + sx2, centerY + sy2);
        cr.stroke();

        if (bond.order >= 2)
        {
            double dx = sx2 - sx1;
            double dy = sy2 - sy1;
            double len = sqrt(dx * dx + dy * dy);
            if (len > 0)
            {
                double nx = -dy / len * 3;
                double ny = dx / len * 3;

                cr.setLineWidth(1.5);
                cr.moveTo(centerX + sx1 + nx, centerY + sy1 + ny);
                cr.lineTo(centerX + sx2 + nx, centerY + sy2 + ny);
                cr.stroke();
            }
        }
    }

    foreach (atom; conformer.atoms)
    {
        double sx, sy;
        cam.project(atom.x, atom.y, atom.z, sx, sy);

        double r, g, b;
        getColor(atom.element, r, g, b);
        double radius = getRadius(atom.element) * cam.zoom * 0.3;

        bool isHovered = (atom.aid == hoveredAtomId);

        if (isHovered)
        {
            cr.arc(centerX + sx, centerY + sy, radius + 3, 0, 2 * PI);
            cr.setSourceRgb(r, g, b);
            cr.setLineWidth(2);
            cr.stroke();
        }

        cr.arc(centerX + sx, centerY + sy, radius, 0, 2 * PI);
        cr.setSourceRgb(r, g, b);
        cr.fillPreserve();
        cr.setSourceRgba(1, 1, 1, 0.3);
        cr.setLineWidth(1);
        cr.stroke();
    }
}

void drawInfoText(Context cr, int atoms, int bonds, int width, int height)
{
    cr.setSourceRgb(1, 1, 1);
    cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
    cr.setFontSize(11);
    cr.moveTo(10, height - 10);
    string info = "Atoms: "~atoms.to!string~"  Bonds: "~bonds.to!string;
    cr.showText(info);
}

void drawTooltip(Context cr, string text, double x, double y, int width, int height)
{
    if (text is null)
        return;

    cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
    cr.setFontSize(12);
    TextExtents extents;
    cr.textExtents(text, extents);

    double paddingX = 8;
    double boxWidth = extents.width + paddingX * 2;
    double boxHeight = 24;
    double boxX = x + 15;
    double boxY = y - boxHeight - 5;

    if (boxX + boxWidth > width)
        boxX = x - boxWidth - 15;
    if (boxY < 0)
        boxY = y + 15;

    cr.setSourceRgba(0, 0, 0, 0.85);
    cr.rectangle(boxX, boxY, boxWidth, boxHeight);
    cr.fill();

    cr.setSourceRgb(1, 1, 1);
    cr.rectangle(boxX, boxY, boxWidth, boxHeight);
    cr.setLineWidth(1);
    cr.stroke();

    cr.setSourceRgb(1, 1, 1);
    double textY = boxY + boxHeight / 2.0 + extents.height / 2.0 - 1;
    cr.moveTo(boxX + paddingX, textY);
    cr.showText(text);
}

void drawPlaceholder(Context cr, int width, int height)
{
    cr.setSourceRgb(0.5, 0.5, 0.6);
    cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
    cr.setFontSize(14);
    cr.moveTo(width / 2.0 - 80, height / 2.0);
    cr.showText("Select a compound to view");
}
