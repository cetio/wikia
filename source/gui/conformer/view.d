module gui.conformer.view;

import std.math : abs;

import cairo.context : Context;
import cairo.types : TextExtents;
import gtk.drawing_area;
import gtk.event_controller_motion;
import gtk.event_controller_scroll;
import gtk.gesture_drag;
import gtk.types : EventControllerScrollFlags;

import gui.conformer.camera : Camera;
import gui.conformer.math : distanceMesh, bondHit, atomHit;
import gui.conformer.render;

import akashi.pubchem.compound : Compound;
import akashi.pubchem.conformer3d;

class MoleculeView : DrawingArea
{
package:
    Compound compound;
    Camera camera;
    double lastDragX;
    double lastDragY;
    bool motionControl;

    string tooltip;
    double mouseX = 0;
    double mouseY = 0;

    void delegate() onClick;

public:
    this()
    {
        addCssClass("molecule-viewer");
        setContentWidth(400);
        setContentHeight(300);
        hexpand = true;
        camera = Camera();

        setDrawFunc(&onDraw);

        GestureDrag dragGesture = new gtk.gesture_drag.GestureDrag();
        dragGesture.connectDragBegin(&onDragBegin);
        dragGesture.connectDragUpdate(&onDragUpdate);
        addController(dragGesture);

        EventControllerScroll scrollController = new gtk.event_controller_scroll.EventControllerScroll(
            EventControllerScrollFlags.Vertical
        );
        scrollController.connectScroll(&onScroll);
        addController(scrollController);

        EventControllerMotion motionController = new gtk.event_controller_motion.EventControllerMotion();
        motionController.connectMotion(&onMotion);
        motionController.connectLeave(&onLeave);
        addController(motionController);
    }

    bool enableMotionControl()
        => motionControl = true;
    
    bool disableMotionControl()
        => motionControl = false;
    
    void setCompound(Compound compound)
    {
        this.compound = compound;
        queueDraw();
    }

    void setBaseZoom(double val)
    {
        camera.baseZoom = val;
        camera.zoom = val;
        queueDraw();
    }

    void resetView()
    {
        camera.reset();
        queueDraw();
    }

private:
    void onDragBegin()
    {
        if (!motionControl)
            return;
        
        lastDragX = 0;
        lastDragY = 0;
    }

    void onDragUpdate(double x, double y)
    {
        if (!motionControl)
            return;
        
        double dx = x - lastDragX;
        double dy = y - lastDragY;
        lastDragX = x;
        lastDragY = y;

        camera.rotationY += dx * 0.01;
        camera.rotationX -= dy * 0.01;
        queueDraw();
    }

    bool onScroll(double dx, double dy)
    {
        if (!motionControl)
            return false;
        
        camera.zoomBy(1.0 - dy * 0.1);
        queueDraw();
        return true;
    }

    void onMotion(double x, double y)
    {
        if (!motionControl)
            return;
        
        Conformer3D conformer = compound.conformer3D;
        if (conformer is null || !conformer.isValid())
            return;

        int bondIdx = bondHit(this, x, y, getAllocatedWidth(), getAllocatedHeight());
        int atomIdx = atomHit(this, x, y, getAllocatedWidth(), getAllocatedHeight());

        if (mouseX != x || mouseY != y)
        {
            if (atomIdx >= 0)
                tooltip = conformer.atoms[atomIdx].element.name;
            else if (bondIdx >= 0)
                tooltip = formatBondTooltip(conformer.bonds[bondIdx]);

            queueDraw();
        }

        mouseX = x;
        mouseY = y;
    }

    void onLeave()
    {
        if (!motionControl)
            return;
        
        queueDraw();
    }

    string formatBondTooltip(Bond3D bond)
    {
        Conformer3D conformer = compound.conformer3D;
        int idx1 = conformer.indexOf(bond.aid1);
        int idx2 = conformer.indexOf(bond.aid2);

        if (idx1 < 0 || idx2 < 0)
            return "Bond";

        string bondType = bond.order == 1 ? "Single" :
            (bond.order == 2 ? "Double" : "Triple");
        return conformer.atoms[idx1].element.name~"-"~conformer.atoms[idx2].element.name~" "~bondType;
    }

    void onDraw(DrawingArea, Context ctx, int width, int height)
    {
        drawBackground(ctx);
        drawGrid(this, ctx);

        if (compound is null)
            return;

        drawBackgroundText(this, ctx);

        if (compound.conformer3D is null || !compound.conformer3D.isValid())
            return;

        drawMolecule(this, ctx);
        drawInfoText(this, ctx);

        if (tooltip != null)
        {
            drawTooltip(this, ctx);
            tooltip = null;
        }
    }
}
