module gui.conformer.render;

import std.math;
import std.conv : to;

import cairo.context : Context;
import cairo.types : FontSlant, FontWeight, TextExtents;

import gui.conformer.camera : Camera;

import wikia.pubchem.conformer3d;

double[3] getColor(Element elem)
{
    switch (cast(int)elem)
    {
        case 1:  return [1.0, 1.0, 1.0];  // H - White
        case 6:  return [0.3, 0.3, 0.3];  // C - Dark gray
        case 7:  return [0.2, 0.4, 1.0];  // N - Blue
        case 8:  return [1.0, 0.2, 0.2];  // O - Red
        case 9:  return [0.0, 0.9, 0.2];  // F - Green
        case 15: return [1.0, 0.5, 0.0]; // P - Orange
        case 16: return [1.0, 0.9, 0.2]; // S - Yellow
        case 17: return [0.0, 0.9, 0.0]; // Cl - Green
        case 35: return [0.6, 0.1, 0.1]; // Br - Dark red
        case 53: return [0.6, 0.0, 0.6]; // I - Purple
        default: return [0.7, 0.5, 0.7]; // Light purple
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

void drawMolecule(
    Context cr, 
    Conformer3D conformer, 
    Camera cam, 
    int width, 
    int height, 
    int hoveredAtomId, 
    size_t hoveredBondIdx
)
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

        double[2] proj1 = cam.project(conformer.atoms[idx1].x, conformer.atoms[idx1].y, conformer.atoms[idx1].z);
        double[2] proj2 = cam.project(conformer.atoms[idx2].x, conformer.atoms[idx2].y, conformer.atoms[idx2].z);

        bool isHovered;
        double lineWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);
        if (hoveredBondIdx != size_t.max)
        {
            Bond3D hb = conformer.bonds[hoveredBondIdx];
            isHovered = (hb.aid1 == bond.aid1 && hb.aid2 == bond.aid2)
                || (hb.aid1 == bond.aid2 && hb.aid2 == bond.aid1);
        }

        if (isHovered)
        {
            double[3] color1 = getColor(conformer.atoms[idx1].element);
            double[3] color2 = getColor(conformer.atoms[idx2].element);

            cr.setSourceRgb(
                (color1[0] + color2[0]) / 2.0,
                (color1[1] + color2[1]) / 2.0,
                (color1[2] + color2[2]) / 2.0
            );
            cr.setLineWidth(lineWidth + 4);
            cr.moveTo(centerX + proj1[0], centerY + proj1[1]);
            cr.lineTo(centerX + proj2[0], centerY + proj2[1]);
            cr.stroke();
        }

        cr.setLineWidth(lineWidth);
        cr.setSourceRgba(0.6, 0.6, 0.7, 0.8);
        cr.moveTo(centerX + proj1[0], centerY + proj1[1]);
        cr.lineTo(centerX + proj2[0], centerY + proj2[1]);
        cr.stroke();

        if (bond.order >= 2)
        {
            double dx = proj2[0] - proj1[0];
            double dy = proj2[1] - proj1[1];
            double len = sqrt(dx * dx + dy * dy);
            
            if (len > 0)
            {
                double nx = -dy / len * 3;
                double ny = dx / len * 3;

                cr.setLineWidth(1.5);
                cr.moveTo(centerX + proj1[0] + nx, centerY + proj1[1] + ny);
                cr.lineTo(centerX + proj2[0] + nx, centerY + proj2[1] + ny);
                cr.stroke();
            }
        }
    }

    foreach (atom; conformer.atoms)
    {
        double radius = getRadius(atom.element) * cam.zoom * 0.3;
        double[2] proj = cam.project(atom.x, atom.y, atom.z);
        double[3] color = getColor(atom.element);

        if (atom.aid == hoveredAtomId)
        {
            cr.arc(centerX + proj[0], centerY + proj[1], radius + 3, 0, 2 * PI);
            cr.setSourceRgb(color[0], color[1], color[2]);
            cr.setLineWidth(2);
            cr.stroke();
        }

        cr.setSourceRgb(color[0], color[1], color[2]);
        cr.arc(centerX + proj[0], centerY + proj[1], radius, 0, 2 * PI);
        cr.fillPreserve();
        cr.setSourceRgba(1, 1, 1, 0.3);
        cr.setLineWidth(1);
        cr.stroke();
    }
}

void drawInfoText(
    Context cr, 
    int atoms, 
    int bonds,
    int height
)
{
    cr.setSourceRgb(1, 1, 1);
    cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
    cr.setFontSize(11);
    cr.moveTo(10, height - 10);
    string info = "Atoms: "~atoms.to!string~"  Bonds: "~bonds.to!string;
    cr.showText(info);
}

void drawTooltip(
    Context cr, 
    string text, 
    double x, 
    double y, 
    int width,
    int height
)
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