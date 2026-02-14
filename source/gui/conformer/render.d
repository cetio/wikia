module gui.conformer.render;

import std.math;
import std.algorithm : clamp, sort;
import std.conv : to;

import cairo.context : Context;
import cairo.types : FontSlant, FontWeight, TextExtents;

import gui.conformer.camera : Camera;
import gui.conformer.math : distanceMesh;
import gui.conformer.view : MoleculeView;

import akashi.pubchem.conformer3d;

private struct DrawCmd
{
    Bond3D[] bonds;
    double depth;
    int idx;
}

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

void drawBackground(Context ctx)
{
    ctx.setSourceRgb(0.2, 0.2, 0.2);
    ctx.paint();
}

void drawGrid(MoleculeView view, Context ctx)
{
    ctx.setSourceRgba(0.5, 0.5, 0.5, 0.3);
    ctx.setLineWidth(1);
    double gridSize = 20.0;
    for (double x = 0; x < view.getAllocatedWidth(); x += gridSize)
    {
        ctx.moveTo(x, 0);
        ctx.lineTo(x, view.getAllocatedHeight());
    }
    
    for (double y = 0; y < view.getAllocatedHeight(); y += gridSize)
    {
        ctx.moveTo(0, y);
        ctx.lineTo(view.getAllocatedWidth(), y);
    }
    ctx.stroke();
}

void drawBackgroundText(MoleculeView view, Context ctx)
{
    if (view.compound.name is null)
        return;

    ctx.selectFontFace("Sans", FontSlant.Normal, FontWeight.Bold);
    ctx.setFontSize(120);
    TextExtents extents;
    ctx.textExtents(view.compound.name, extents);

    double textX = (view.getAllocatedWidth() - extents.width) / 2.0;
    double textY = (view.getAllocatedHeight() + extents.height) / 2.0;

    ctx.setSourceRgba(1, 1, 1, 0.08);
    ctx.moveTo(textX, textY);
    ctx.showText(view.compound.name);
}

void drawMolecule(MoleculeView view, Context ctx)
{
    Conformer3D conformer = view.compound.conformer3D;
    if (conformer is null || !conformer.isValid())
        return;

    double centerX = view.getAllocatedWidth() / 2.0;
    double centerY = view.getAllocatedHeight() / 2.0;

    double[int] distances = distanceMesh(
        view, view.mouseX, view.mouseY,
        view.getAllocatedWidth(), view.getAllocatedHeight()
    );

    double[] px = new double[conformer.atoms.length];
    double[] py = new double[conformer.atoms.length];
    double[] pz = new double[conformer.atoms.length];
    double[] ar = new double[conformer.atoms.length];

    foreach (i, atom; conformer.atoms)
    {
        double[2] proj = view.camera.project(atom.x, atom.y, atom.z);
        px[i] = centerX + proj[0];
        py[i] = centerY + proj[1];
        pz[i] = view.camera.depth(atom.x, atom.y, atom.z);

        double base = getRadius(atom.element) * view.camera.zoom * 0.3;
        double dist = distances.get(cast(int)i, double.max);
        ar[i] = base * clamp(1.02 + 0.02 * (20.0 - dist), 1.0, 1.30);
    }

    DrawCmd[] cmds = new DrawCmd[conformer.atoms.length];
    foreach (i; 0..conformer.atoms.length)
        cmds[i] = DrawCmd(null, pz[i], cast(int)i);

    // Sort the atoms by depth for occlusion and then we add the bonds so that the bonds occlude properly.
    // If we render the bonds before the atoms, they will always be occluded.
    // If we render the bonds after the atoms, they will occlude the atoms.
    // We don't need to do more distance calculations if we just use the depth we already calculated for atoms.
    cmds.sort!((DrawCmd a, DrawCmd b) => a.depth < b.depth);
    foreach (bond; conformer.bonds)
    {
        foreach (ref cmd; cmds)
        {
            int idx1 = conformer.indexOf(bond.aid1);
            int idx2 = conformer.indexOf(bond.aid2);

            if (idx1 == cmd.idx || idx2 == cmd.idx)
            {
                cmd.bonds ~= bond;
                break;
            }
        }
    }

    foreach (cmd; cmds)
    {
        foreach (bond; cmd.bonds)
        {
            int idx1 = conformer.indexOf(bond.aid1);
            int idx2 = conformer.indexOf(bond.aid2);

            double w = fmin(ar[idx1], ar[idx2]);
            double dx = px[idx2] - px[idx1];
            double dy = py[idx2] - py[idx1];
            double len = sqrt(dx * dx + dy * dy);
            if (len == 0)
                continue;

            double nx = -dy / len;
            double ny = dx / len;

            ctx.setSourceRgba(0.6, 0.6, 0.7, 1);

            if (bond.order == 1)
            {
                ctx.setLineWidth(w);
                ctx.moveTo(px[idx1], py[idx1]);
                ctx.lineTo(px[idx2], py[idx2]);
                ctx.stroke();
            }
            else if (bond.order == 2)
            {
                double offset = w * 0.55;
                ctx.setLineWidth(w * 0.45);
                ctx.moveTo(px[idx1] + nx * offset, py[idx1] + ny * offset);
                ctx.lineTo(px[idx2] + nx * offset, py[idx2] + ny * offset);
                ctx.stroke();
                ctx.moveTo(px[idx1] - nx * offset, py[idx1] - ny * offset);
                ctx.lineTo(px[idx2] - nx * offset, py[idx2] - ny * offset);
                ctx.stroke();
            }
            else
            {
                double offset = w * 0.75;
                ctx.setLineWidth(w * 0.35);
                ctx.moveTo(px[idx1], py[idx1]);
                ctx.lineTo(px[idx2], py[idx2]);
                ctx.stroke();
                ctx.moveTo(px[idx1] + nx * offset, py[idx1] + ny * offset);
                ctx.lineTo(px[idx2] + nx * offset, py[idx2] + ny * offset);
                ctx.stroke();
                ctx.moveTo(px[idx1] - nx * offset, py[idx1] - ny * offset);
                ctx.lineTo(px[idx2] - nx * offset, py[idx2] - ny * offset);
                ctx.stroke();
            }
        }

        double[3] color = getColor(conformer.atoms[cmd.idx].element);

        ctx.setSourceRgb(color[0], color[1], color[2]);
        ctx.moveTo(px[cmd.idx] + ar[cmd.idx], py[cmd.idx]);
        ctx.arc(px[cmd.idx], py[cmd.idx], ar[cmd.idx], 0, 2 * PI);
        ctx.fill();

        ctx.setSourceRgba(1, 1, 1, 1);
        ctx.setLineWidth(1);
        ctx.moveTo(px[cmd.idx] + ar[cmd.idx], py[cmd.idx]);
        ctx.arc(px[cmd.idx], py[cmd.idx], ar[cmd.idx], 0, 2 * PI);
        ctx.stroke();
    }
}

void drawInfoText(MoleculeView view, Context ctx)
{
    Conformer3D conformer = view.compound.conformer3D;
    if (conformer is null || !conformer.isValid())
        return;
    
    ctx.setSourceRgb(1, 1, 1);
    ctx.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
    ctx.setFontSize(11);
    ctx.moveTo(10, view.getAllocatedHeight() - 10);
    ctx.showText(
        "Atoms: "~conformer.atoms.length.to!string~"  Bonds: "~conformer.bonds.length.to!string
    );
}

void drawTooltip(MoleculeView view, Context ctx)
{
    if (view.tooltip == null)
        return;

    ctx.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
    ctx.setFontSize(12);
    TextExtents extents;
    ctx.textExtents(view.tooltip, extents);

    double paddingX = 8;
    double boxWidth = extents.width + paddingX * 2;
    double boxHeight = 24;
    double boxX = view.mouseX + 15;
    double boxY = view.mouseY - boxHeight - 5;

    if (boxX + boxWidth > view.getAllocatedWidth())
        boxX = view.mouseX - boxWidth - 15;
    if (boxY < 0)
        boxY = view.mouseY + 15;

    ctx.setSourceRgba(0, 0, 0, 0.85);
    ctx.rectangle(boxX, boxY, boxWidth, boxHeight);
    ctx.fill();

    ctx.setSourceRgb(1, 1, 1);
    ctx.rectangle(boxX, boxY, boxWidth, boxHeight);
    ctx.setLineWidth(1);
    ctx.stroke();

    ctx.setSourceRgb(1, 1, 1);
    double textY = boxY + boxHeight / 2.0 + extents.height / 2.0 - 1;
    ctx.moveTo(boxX + paddingX, textY);
    ctx.showText(view.tooltip);
}