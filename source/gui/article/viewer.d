module gui.article.viewer;

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

import wikia.pubchem.conformer3d;

class MoleculeViewer : DrawingArea
{
    private:

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

    Conformer3D conformer;
    Camera camera;
    HoverState hover;
    void delegate() onClick;
    string backgroundName;
    double dragStartRotX, dragStartRotY;

    public:

    this(bool enableDrag = true)
    {
        addCssClass("molecule-viewer");
        setContentWidth(400);
        setContentHeight(300);
        hexpand = true;
        camera = Camera();

        setDrawFunc(&onDraw);

        if (enableDrag)
        {
            auto dragGesture = new gtk.gesture_drag.GestureDrag();
            dragGesture.connectDragBegin(&onDragBegin);
            dragGesture.connectDragUpdate(&onDragUpdate);
            addController(dragGesture);
        }

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

    void setBackgroundName(string name)
    {
        backgroundName = name;
        queueDraw();
    }

    void setConformer(Conformer3D conf)
    {
        conformer = conf;
        hover.clear();
        queueDraw();
    }

    void setBaseZoom(double z)
    {
        camera.baseZoom = z;
        camera.zoom = z;
        queueDraw();
    }

    void resetView()
    {
        camera.reset();
        queueDraw();
    }

    private void onDragBegin()
    {
        dragStartRotX = camera.rotationX;
        dragStartRotY = camera.rotationY;
    }

    private void onDragUpdate(double x, double y)
    {
        camera.rotationY = dragStartRotY + x * 0.01;
        camera.rotationX = dragStartRotX + y * 0.01;
        queueDraw();
    }

    private bool onScroll(double dx, double dy)
    {
        camera.zoomBy(1.0 - dy * 0.1);
        queueDraw();
        return true;
    }

    private void onMotion(double x, double y)
    {
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

    private void onLeave()
    {
        hover.clear();
        queueDraw();
    }


    private string formatBondTooltip(Bond3D bond)
    {
        int idx1 = conformer.indexOf(bond.aid1);
        int idx2 = conformer.indexOf(bond.aid2);

        if (idx1 < 0 || idx2 < 0)
            return "Bond";

        string bondType = bond.order == 1 ? "Single" :
            (bond.order == 2 ? "Double" : "Triple");
        return conformer.atoms[idx1].element.name~"-"~conformer.atoms[idx2].element.name~" "~bondType;
    }

    private void onDraw(DrawingArea, Context cr, int width, int height)
    {
        drawBackground(cr);

        drawBackgroundText(cr, backgroundName, width, height);

        drawGrid(cr, width, height);

        if (conformer is null || !conformer.isValid())
        {
            drawPlaceholder(cr, width, height);
            return;
        }

        drawMolecule(cr, conformer, camera, width, height, hover.atomId, hover.bondIdx);

        drawInfoText(cr, cast(int)conformer.atoms.length, cast(int)conformer.bonds.length, width, height);

        if (hover.tooltip !is null)
            drawTooltip(cr, hover.tooltip, hover.x, hover.y, width, height);
    }
}
