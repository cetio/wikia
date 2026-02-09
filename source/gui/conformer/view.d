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
import gui.conformer.hit : HitResult, hitTest;
import gui.conformer.render;

import wikia.pubchem.compound : Compound;
import wikia.pubchem.conformer3d;

class MoleculeView : DrawingArea
{
package:
    struct HoverState
    {
        int atomId = -1;
        size_t bondIdx = size_t.max;
        string tooltip;
        double x, y;

        bool isValid() const => atomId != -1 || bondIdx != size_t.max;

        void clear()
        {
            atomId = -1;
            bondIdx = size_t.max;
            tooltip = null;
            x = y = 0;
        }
    }

    Compound compound;
    Camera camera;
    HoverState hover;
    double dragStartRotX;
    double dragStartRotY;
    bool motionControl;

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

        auto dragGesture = new gtk.gesture_drag.GestureDrag();
        dragGesture.connectDragBegin(&onDragBegin);
        dragGesture.connectDragUpdate(&onDragUpdate);
        addController(dragGesture);

        auto scrollController = new gtk.event_controller_scroll.EventControllerScroll(
            EventControllerScrollFlags.Vertical
        );
        scrollController.connectScroll(&onScroll);
        addController(scrollController);

        auto motionController = new gtk.event_controller_motion.EventControllerMotion();
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
        hover.clear();
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
        
        dragStartRotX = camera.rotationX;
        dragStartRotY = camera.rotationY;
    }

    void onDragUpdate(double x, double y)
    {
        if (!motionControl)
            return;
        
        camera.rotationY = dragStartRotY + x * 0.01;
        camera.rotationX = dragStartRotX + y * 0.01;
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
        {
            hover.clear();
            return;
        }

        hover.x = x;
        hover.y = y;

        int width = getAllocatedWidth();
        int height = getAllocatedHeight();
        HitResult ret = hitTest(x, y, width, height, conformer, camera);

        if (!ret.hit)
        {
            hover.clear();
            queueDraw();
            return;
        }

        if (ret.isAtom)
        {
            if (ret.atomId == hover.atomId)
                return;
            
            hover.atomId = ret.atomId;
            hover.bondIdx = size_t.max;
            int idx = conformer.indexOf(ret.atomId);
            if (idx >= 0)
                hover.tooltip = conformer.atoms[idx].element.name;
            queueDraw();
        }
        else
        {
            if (ret.bondIdx == hover.bondIdx)
                return;
            
            hover.atomId = -1;
            hover.bondIdx = ret.bondIdx;
            hover.tooltip = formatBondTooltip(conformer.bonds[ret.bondIdx]);
            queueDraw();
        }
    }

    void onLeave()
    {
        if (!motionControl)
            return;
        
        hover.clear();
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

    void onDraw(DrawingArea, Context cr, int width, int height)
    {
        drawBackground(cr);
        drawGrid(cr, width, height);
        drawBackgroundText(
            cr, 
            compound.name, 
            width, 
            height
        );

        if (hover.tooltip !is null)
        {
            drawTooltip(
                cr, 
                hover.tooltip, 
                hover.x, 
                hover.y, 
                width, 
                height
            );
        }

        if (compound.conformer3D is null || !compound.conformer3D.isValid())
            return;

        drawMolecule(
            cr, 
            compound.conformer3D, 
            camera, 
            width, 
            height, 
            hover.atomId, 
            hover.bondIdx
        );

        drawInfoText(
            cr, 
            cast(int)compound.conformer3D.atoms.length, 
            cast(int)compound.conformer3D.bonds.length, 
            height
        );
    }
}
