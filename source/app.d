module app;

import std.conv : to;
import std.string : strip;
import std.math : sin, cos, sqrt, PI;
import std.algorithm : min, max;

import gio.types : ApplicationFlags;
import gtk.application;
import gtk.application_window;
import gtk.header_bar;
import gtk.search_entry;
import gtk.popover;
import gtk.list_box;
import gtk.list_box_row;
import gtk.paned;
import gtk.scrolled_window;
import gtk.box;
import gtk.expander;
import gtk.frame;
import gtk.label;
import gtk.button;
import gtk.window;
import gtk.dialog;
import gtk.css_provider;
import gtk.style_context;
import gtk.style_provider;
import gtk.drawing_area;
import gtk.gesture_drag;
import gtk.gesture_click;
import gtk.event_controller_scroll;
import gtk.event_controller_motion;
import gtk.overlay;
import gtk.types : Orientation, Align, PolicyType, STYLE_PROVIDER_PRIORITY_APPLICATION;
import gtk.types : EventControllerScrollFlags;
import gdk.display;
import cairo.context;
import cairo.types : FontSlant, FontWeight, TextExtents;

import akashi.entrez.pubchem : PubChem;

immutable string GLOBAL_CSS = r"
.root-container {
    padding: 0;
    background: #f6f5f4;
    color: #2e3436;
}

.sidebar-scroll {
    background: #ffffff;
    border-right: 1px solid rgba(46, 52, 54, 0.10);
}

.sidebar {
    padding: 16px;
    min-width: 320px;
    background: transparent;
}

.property-section {
    background: #ffffff;
    border-radius: 12px;
    border: 1px solid rgba(46, 52, 54, 0.12);
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
}

.property-section-content {
    padding: 12px 12px 8px 12px;
}

.property-row {
    padding: 6px 0;
}

.property-label {
    font-weight: 600;
    color: rgba(46, 52, 54, 0.70);
}

.viewer {
    padding: 24px;
}

.viewer-controls {
    margin-bottom: 16px;
}

.viewer-frame {
    background: #ffffff;
    border-radius: 12px;
    border: 1px solid rgba(46, 52, 54, 0.12);
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
    padding: 24px;
}

.search-entry {
    min-width: 260px;
}

.suggestion-row {
    padding: 10px 12px;
}

.suggestion-secondary {
    color: rgba(46, 52, 54, 0.60);
    font-size: 0.95em;
}

.molecule-viewer {
    background: #1a1a2e;
    border-radius: 8px;
}
";

class MoleculeViewer : DrawingArea
{
    private PubChem.Conformer3D conformer;
    private double rotationX = 0.3;
    private double rotationY = 0.4; // 180 degrees + 0.4 to fix mirrored view
    private double zoom = 40.0;
    private double dragStartX, dragStartY;
    private double lastRotationX, lastRotationY;

    // Hover state
    private int hoveredAtomId = -1;
    private int hoveredBondIndex = -1;
    private string tooltipText = "";
    private double hoverX, hoverY;

    this()
    {
        addCssClass("molecule-viewer");
        setContentWidth(400);
        setContentHeight(400);
        hexpand = true;
        vexpand = true;

        setDrawFunc(&onDraw);

        auto dragGesture = new GestureDrag();
        dragGesture.connectDragBegin(&onDragBegin);
        dragGesture.connectDragUpdate(&onDragUpdate);
        addController(dragGesture);

        auto scrollController = new EventControllerScroll(
            EventControllerScrollFlags.Vertical
        );
        scrollController.connectScroll(&onScroll);
        addController(scrollController);
        
        auto motionController = new EventControllerMotion();
        motionController.connectMotion(&onMotion);
        motionController.connectLeave(&onLeave);
        addController(motionController);
    }

    void setConformer(PubChem.Conformer3D conf)
    {
        conformer = conf;
        clearHover();
        queueDraw();
    }

    void resetView()
    {
        rotationX = 0.3;
        rotationY = 0.4;
        zoom = 40.0;
        queueDraw();
    }

    private void onDragBegin(double x, double y)
    {
        dragStartX = x;
        dragStartY = y;
        lastRotationX = rotationX;
        lastRotationY = rotationY;
    }

    private void onDragUpdate(double offsetX, double offsetY)
    {
        rotationY = lastRotationY + offsetX * 0.01;
        rotationX = lastRotationX + offsetY * 0.01;
        queueDraw();
    }

    private bool onScroll(double dx, double dy)
    {
        zoom *= (1.0 - dy * 0.1);
        zoom = max(10.0, min(200.0, zoom));
        queueDraw();
        return true;
    }
    
    private void onMotion(double x, double y)
    {
        if (!conformer.isValid())
        {
            clearHover();
            return;
        }
        
        // Update hover position
        hoverX = x;
        hoverY = y;
        
        int width = getAllocatedWidth();
        int height = getAllocatedHeight();
        double centerX = width / 2.0;
        double centerY = height / 2.0;
        
        // Convert mouse coordinates to molecule coordinates
        double mx = x - centerX;
        double my = y - centerY;
        
        // Check atoms first (higher priority)
        int newHoveredAtomId = -1;
        double closestAtomDist = double.max;
        
        foreach (atom; conformer.atoms)
        {
            double sx, sy;
            project3D(atom.x, atom.y, atom.z, sx, sy);
            
            double dist = sqrt((sx - mx) * (sx - mx) + (sy - my) * (sy - my));
            double radius = getElementRadius(atom.element) * zoom * 0.3;
            
            if (dist <= radius && dist < closestAtomDist)
            {
                newHoveredAtomId = atom.aid;
                closestAtomDist = dist;
            }
        }
        
        // Check bonds if no atom is hovered
        int newHoveredBondIndex = -1;
        if (newHoveredAtomId == -1)
        {
            double closestBondDist = double.max;
            
            foreach (i, bond; conformer.bonds)
            {
                auto atom1 = conformer.getAtomById(bond.aid1);
                auto atom2 = conformer.getAtomById(bond.aid2);
                
                if (atom1 is null || atom2 is null)
                    continue;
                
                double sx1, sy1, sx2, sy2;
                project3D(atom1.x, atom1.y, atom1.z, sx1, sy1);
                project3D(atom2.x, atom2.y, atom2.z, sx2, sy2);
                
                // Distance from point to line segment
                double dist = distanceToLineSegment(mx, my, sx1, sy1, sx2, sy2);
                double bondWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);
                
                if (dist <= bondWidth && dist < closestBondDist)
                {
                    newHoveredBondIndex = cast(int)i;
                    closestBondDist = dist;
                }
            }
        }
        
        // Update hover state if changed
        if (newHoveredAtomId != hoveredAtomId || newHoveredBondIndex != hoveredBondIndex)
        {
            hoveredAtomId = newHoveredAtomId;
            hoveredBondIndex = newHoveredBondIndex;
            
            if (hoveredAtomId != -1)
            {
                auto atom = conformer.getAtomById(hoveredAtomId);
                if (atom !is null)
                    tooltipText = formatAtomTooltip(atom);
            }
            else if (hoveredBondIndex != -1)
            {
                auto bond = conformer.bonds[hoveredBondIndex];
                tooltipText = formatBondTooltip(bond);
            }
            else
                tooltipText = "";
            
            queueDraw();
        }
    }
    
    private void onLeave()
    {
        clearHover();
    }
    
    private void clearHover()
    {
        if (hoveredAtomId != -1 || hoveredBondIndex != -1)
        {
            hoveredAtomId = -1;
            hoveredBondIndex = -1;
            tooltipText = "";
            hoverX = hoverY = 0;
            queueDraw();
        }
    }
    
    private double distanceToLineSegment(double px, double py, double x1, double y1, double x2, double y2)
    {
        double dx = x2 - x1;
        double dy = y2 - y1;
        double lengthSquared = dx * dx + dy * dy;
        
        if (lengthSquared == 0)
            return sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));
        
        double t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / lengthSquared));
        double projectionX = x1 + t * dx;
        double projectionY = y1 + t * dy;
        
        return sqrt((px - projectionX) * (px - projectionX) + (py - projectionY) * (py - projectionY));
    }
    
    private string formatAtomTooltip(PubChem.Atom3D* atom)
    {
        return getElementName(atom.element);
    }
    
    private string formatBondTooltip(PubChem.Bond3D bond)
    {
        auto atom1 = conformer.getAtomById(bond.aid1);
        auto atom2 = conformer.getAtomById(bond.aid2);
        
        if (atom1 is null || atom2 is null)
            return "Bond";
        
        string bondType = bond.order == 1 ? "Single Bond" : (bond.order == 2 ? "Double Bond" : "Triple Bond");
        return getElementName(atom1.element)~"-"~getElementName(atom2.element)~" "~bondType;
    }
    
    private string getElementName(int element)
    {
        switch (element)
        {
            case 1: return "Hydrogen";
            case 6: return "Carbon";
            case 7: return "Nitrogen";
            case 8: return "Oxygen";
            case 9: return "Fluorine";
            case 15: return "Phosphorus";
            case 16: return "Sulfur";
            case 17: return "Chlorine";
            case 35: return "Bromine";
            case 53: return "Iodine";
            default: return "Element "~element.to!string;
        }
    }

    private void project3D(double x, double y, double z, out double sx, out double sy)
    {
        double cosX = cos(rotationX), sinX = sin(rotationX);
        double cosY = cos(rotationY), sinY = sin(rotationY);

        double y1 = y * cosX - z * sinX;
        double z1 = y * sinX + z * cosX;

        double x2 = x * cosY + z1 * sinY;

        sx = x2 * zoom;
        sy = y1 * zoom;
    }

    private void getElementColor(int element, out double r, out double g, out double b)
    {
        switch (element)
        {
            case 1:  r = 1.0; g = 1.0; b = 1.0; break; // H - white
            case 6:  r = 0.3; g = 0.3; b = 0.3; break; // C - dark gray
            case 7:  r = 0.2; g = 0.4; b = 1.0; break; // N - blue
            case 8:  r = 1.0; g = 0.2; b = 0.2; break; // O - red
            case 9:  r = 0.0; g = 0.9; b = 0.2; break; // F - green
            case 15: r = 1.0; g = 0.5; b = 0.0; break; // P - orange
            case 16: r = 1.0; g = 0.9; b = 0.2; break; // S - yellow
            case 17: r = 0.0; g = 0.9; b = 0.0; break; // Cl - green
            case 35: r = 0.6; g = 0.1; b = 0.1; break; // Br - dark red
            case 53: r = 0.6; g = 0.0; b = 0.6; break; // I - purple
            default: r = 0.7; g = 0.5; b = 0.7; break; // unknown
        }
    }

    private double getElementRadius(int element)
    {
        switch (element)
        {
            case 1:  return 0.3;  // H
            case 6:  return 0.5;  // C
            case 7:  return 0.5;  // N
            case 8:  return 0.5;  // O
            case 16: return 0.6;  // S
            case 17: return 0.6;  // Cl
            case 35: return 0.7;  // Br
            case 53: return 0.8;  // I
            default: return 0.5;
        }
    }

    private void onDraw(DrawingArea, Context cr, int width, int height)
    {
        // Gray background
        cr.setSourceRgb(0.2, 0.2, 0.2);
        cr.paint();
        
        // Draw gray grid lines
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

        if (!conformer.isValid())
        {
            cr.setSourceRgb(0.5, 0.5, 0.6);
            cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
            cr.setFontSize(14);
            cr.moveTo(width / 2.0 - 80, height / 2.0);
            cr.showText("Select a compound to view");
            return;
        }

        double centerX = width / 2.0;
        double centerY = height / 2.0;

        foreach (bond; conformer.bonds)
        {
            auto atom1 = conformer.getAtomById(bond.aid1);
            auto atom2 = conformer.getAtomById(bond.aid2);

            if (atom1 is null || atom2 is null)
                continue;

            double sx1, sy1, sx2, sy2;
            project3D(atom1.x, atom1.y, atom1.z, sx1, sy1);
            project3D(atom2.x, atom2.y, atom2.z, sx2, sy2);

            double lineWidth = bond.order == 1 ? 2.0 : (bond.order == 2 ? 3.0 : 4.0);
            
            // Check if this bond is hovered
            bool isHovered = false;
            if (hoveredBondIndex != -1)
            {
                auto hb = conformer.bonds[hoveredBondIndex];
                isHovered = (hb.aid1 == bond.aid1 && hb.aid2 == bond.aid2)
                    || (hb.aid1 == bond.aid2 && hb.aid2 == bond.aid1);
            }
            
            if (isHovered)
            {
                // Draw colored outline for hovered bond (mix of both atom colors)
                double r1, g1, b1, r2, g2, b2;
                getElementColor(atom1.element, r1, g1, b1);
                getElementColor(atom2.element, r2, g2, b2);
                
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
            project3D(atom.x, atom.y, atom.z, sx, sy);

            double r, g, b;
            getElementColor(atom.element, r, g, b);
            double radius = getElementRadius(atom.element) * zoom * 0.3;
            
            // Check if this atom is hovered
            bool isHovered = (atom.aid == hoveredAtomId);
            
            if (isHovered)
            {
                // Draw colored outline for hovered atom
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

        cr.setSourceRgb(1, 1, 1);
        cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
        cr.setFontSize(11);
        cr.moveTo(10, height - 10);
        string info = "Atoms: "~conformer.atoms.length.to!string
            ~"  Bonds: "~conformer.bonds.length.to!string;
        cr.showText(info);
        
        // Draw tooltip if hovering over an atom or bond
        if (tooltipText.length > 0)
        {
            cr.setSourceRgba(0, 0, 0, 0.8);
            cr.selectFontFace("Sans", FontSlant.Normal, FontWeight.Normal);
            cr.setFontSize(12);
            
            // Get text extents for tooltip background
            TextExtents extents;
            cr.textExtents(tooltipText, extents);
            
            // Add padding
            double padding = 8;
            double cornerRadius = 6;
            double tooltipWidth = extents.width + 2 * padding;
            double tooltipHeight = extents.height + 2 * padding;
            
            // Position tooltip above the hovered element
            double tooltipX = hoverX - tooltipWidth / 2;
            double tooltipY = hoverY - tooltipHeight - 15;
            
            // Keep tooltip within bounds
            if (tooltipX < 10) tooltipX = 10;
            if (tooltipX + tooltipWidth > width - 10) tooltipX = width - tooltipWidth - 10;
            if (tooltipY < 10) {
                // If no space above, place below
                tooltipY = hoverY + 15;
            }
            
            // Draw rounded rectangle background
            cr.moveTo(tooltipX + cornerRadius, tooltipY);
            cr.arc(tooltipX + tooltipWidth - cornerRadius, tooltipY + cornerRadius, 
                   cornerRadius, PI * 1.5, PI * 2);
            cr.arc(tooltipX + tooltipWidth - cornerRadius, tooltipY + tooltipHeight - cornerRadius, 
                   cornerRadius, 0, PI * 0.5);
            cr.arc(tooltipX + cornerRadius, tooltipY + tooltipHeight - cornerRadius, 
                   cornerRadius, PI * 0.5, PI);
            cr.arc(tooltipX + cornerRadius, tooltipY + cornerRadius, 
                   cornerRadius, PI, PI * 1.5);
            cr.closePath();
            
            // Fill background
            cr.setSourceRgba(1, 1, 1, 0.9);
            cr.fill();
            
            // Draw border
            cr.setSourceRgb(0, 0, 0);
            cr.setLineWidth(1);
            cr.stroke();
            
            // Draw tooltip text
            cr.setSourceRgb(0, 0, 0);
            cr.moveTo(tooltipX + padding, tooltipY + padding - extents.yBearing);
            cr.showText(tooltipText);
        }
    }
}

class PubChemWindow : gtk.application_window.ApplicationWindow
{
    private SearchEntry searchEntry;
    private Popover suggestionPopover;
    private ListBox suggestionList;
    private PubChem.Compound[] lastSuggestions;
    private MoleculeViewer moleculeViewer;
    private PubChem.Compound selectedCompound;
    private PubChem.Conformer3D selectedConformer;
    private Box sidebarBox;
    private Label compoundNameLabel;
    private Label cidLabel;
    private Label formulaLabel;
    private Label weightLabel;
    private Label smilesLabel;
    private Label atomCountLabel;
    private Label bondCountLabel;
    private Label conformerIdLabel;

    this(gtk.application.Application app)
    {
        super(app);
        setDefaultSize(1200, 800);
        setTitle("Akashi PubChem Viewer");

        auto root = new Box(Orientation.Vertical, 0);
        root.addCssClass("root-container");
        setChild(root);

        auto header = buildHeaderBar();
        setTitlebar(header);

        auto paned = buildMainPaned();
        root.append(paned);
    }

    private HeaderBar buildHeaderBar()
    {
        auto header = new HeaderBar();
        header.showTitleButtons = true;

        auto titleLabel = new Label("Akashi PubChem Viewer");
        header.titleWidget = titleLabel;

        searchEntry = new SearchEntry();
        searchEntry.placeholderText = "Search for a compound...";
        searchEntry.addCssClass("search-entry");
        searchEntry.connectActivate(&onSearchActivate);
        header.packStart(searchEntry);

        suggestionList = new ListBox();
        suggestionList.connectRowActivated(&onSuggestionActivated);

        suggestionPopover = new Popover();
        suggestionPopover.setParent(searchEntry);
        suggestionPopover.setChild(suggestionList);

        header.packEnd(createIconButton("view-refresh-symbolic", "Refresh"));
        header.packEnd(createIconButton("preferences-system-symbolic", "Preferences"));

        return header;
    }

    private Button createIconButton(string iconName, string tooltip)
    {
        auto button = new Button();
        button.iconName = iconName;
        button.tooltipText = tooltip;
        return button;
    }

    private Paned buildMainPaned()
    {
        auto paned = new Paned(Orientation.Horizontal);
        paned.position = 360;
        paned.positionSet = true;
        paned.setStartChild(buildSidebar());
        paned.setEndChild(buildViewer());
        return paned;
    }

    private ScrolledWindow buildSidebar()
    {
        sidebarBox = new Box(Orientation.Vertical, 12);
        sidebarBox.addCssClass("sidebar");
        
        // Basic Properties section
        auto basicExpander = new Expander("Basic Properties");
        basicExpander.addCssClass("property-section");
        auto basicBox = new Box(Orientation.Vertical, 4);
        basicBox.addCssClass("property-section-content");
        
        compoundNameLabel = new Label("--");
        compoundNameLabel.halign = Align.Start;
        compoundNameLabel.wrap = true;
        basicBox.append(buildPropertyRowWithLabel("Name", compoundNameLabel));
        
        cidLabel = new Label("--");
        cidLabel.halign = Align.Start;
        basicBox.append(buildPropertyRowWithLabel("CID", cidLabel));
        
        formulaLabel = new Label("--");
        formulaLabel.halign = Align.Start;
        basicBox.append(buildPropertyRowWithLabel("Formula", formulaLabel));
        
        weightLabel = new Label("--");
        weightLabel.halign = Align.Start;
        basicBox.append(buildPropertyRowWithLabel("Weight", weightLabel));
        
        basicExpander.setChild(basicBox);
        basicExpander.expanded = true;
        sidebarBox.append(basicExpander);
        
        // Structure section
        auto structExpander = new Expander("Structure");
        structExpander.addCssClass("property-section");
        auto structBox = new Box(Orientation.Vertical, 4);
        structBox.addCssClass("property-section-content");
        
        smilesLabel = new Label("--");
        smilesLabel.halign = Align.Start;
        smilesLabel.wrap = true;
        smilesLabel.maxWidthChars = 30;
        structBox.append(buildPropertyRowWithLabel("SMILES", smilesLabel));
        
        structExpander.setChild(structBox);
        structExpander.expanded = true;
        sidebarBox.append(structExpander);
        
        // 3D section
        auto _3DExpander = new Expander("3D Conformer");
        _3DExpander.addCssClass("property-section");
        auto _3DBox = new Box(Orientation.Vertical, 4);
        _3DBox.addCssClass("property-section-content");
        
        atomCountLabel = new Label("--");
        atomCountLabel.halign = Align.Start;
        _3DBox.append(buildPropertyRowWithLabel("Atoms", atomCountLabel));
        
        bondCountLabel = new Label("--");
        bondCountLabel.halign = Align.Start;
        _3DBox.append(buildPropertyRowWithLabel("Bonds", bondCountLabel));
        
        conformerIdLabel = new Label("--");
        conformerIdLabel.halign = Align.Start;
        _3DBox.append(buildPropertyRowWithLabel("Conformer ID", conformerIdLabel));
        
        _3DExpander.setChild(_3DBox);
        _3DExpander.expanded = true;
        sidebarBox.append(_3DExpander);

        auto scroller = new ScrolledWindow();
        scroller.addCssClass("sidebar-scroll");
        scroller.child = sidebarBox;
        scroller.setPolicy(PolicyType.Never, PolicyType.Automatic);
        return scroller;
    }
    
    private Box buildPropertyRowWithLabel(string labelText, Label valueLabel)
    {
        auto row = new Box(Orientation.Vertical, 2);
        row.addCssClass("property-row");

        auto label = new Label(labelText);
        label.addCssClass("property-label");
        label.halign = Align.Start;

        row.append(label);
        row.append(valueLabel);
        return row;
    }

    private Expander createPropertySection(string title)
    {
        auto expander = new Expander(title);
        expander.addCssClass("property-section");

        auto sectionBox = new Box(Orientation.Vertical, 4);
        sectionBox.addCssClass("property-section-content");
        sectionBox.append(buildPropertyRow("Label", "--"));
        sectionBox.append(buildPropertyRow("Value", "Pending"));

        expander.setChild(sectionBox);
        expander.expanded = true;
        return expander;
    }

    private Box buildPropertyRow(string labelText, string valueText)
    {
        auto row = new Box(Orientation.Vertical, 2);
        row.addCssClass("property-row");

        auto label = new Label(labelText);
        label.addCssClass("property-label");
        label.halign = Align.Start;
        auto value = new Label(valueText);
        value.halign = Align.Start;

        row.append(label);
        row.append(value);
        return row;
    }

    private Box buildViewer()
    {
        auto viewerBox = new Box(Orientation.Vertical, 0);
        viewerBox.addCssClass("viewer");
        viewerBox.vexpand = true;
        viewerBox.marginTop = 12;
        viewerBox.marginBottom = 12;
        viewerBox.marginStart = 12;
        viewerBox.marginEnd = 12;

        moleculeViewer = new MoleculeViewer();
        
        // Reset button at bottom right, occluding the viewer
        auto resetBtn = new Button();
        resetBtn.iconName = "view-refresh-symbolic";
        resetBtn.tooltipText = "Reset view";
        resetBtn.connectClicked(&onResetView);
        resetBtn.marginEnd = 8;
        resetBtn.marginBottom = 8;
        resetBtn.widthRequest = 36;
        resetBtn.heightRequest = 36;
        resetBtn.addCssClass("circular");
        resetBtn.halign = Align.End;
        resetBtn.valign = Align.End;
        
        // Create an overlay container
        auto overlay = new Overlay();
        overlay.setChild(moleculeViewer);
        overlay.addOverlay(resetBtn);
        
        viewerBox.append(overlay);
        return viewerBox;
    }
    
    private void onResetView()
    {
        if (moleculeViewer !is null)
            moleculeViewer.resetView();
    }

    private void onSearchActivate()
    {
        string text = searchEntry.text;
        if (text.length < 2)
        {
            if (suggestionPopover !is null)
                suggestionPopover.hide();
            return;
        }

        updateSuggestions(text);
    }

    private void updateSuggestions(string query)
    {
        PubChem.Compound[] compounds;
        try
        {
            compounds = PubChem.searchByName(query, 6);
        }
        catch (Exception)
        {
            compounds = [];
        }

        lastSuggestions = compounds;

        suggestionList.removeAll();

        if (compounds.length == 0)
        {
            if (suggestionPopover !is null)
                suggestionPopover.hide();
            return;
        }

        foreach (compound; compounds)
        {
            auto row = new ListBoxRow();

            auto rowBox = new Box(Orientation.Vertical, 2);
            rowBox.addCssClass("suggestion-row");

            string title = compound.iupacName.length ? compound.iupacName : ("CID "~compound.cid);
            auto titleLabel = new Label(title);
            titleLabel.halign = Align.Start;

            string detail = "CID "~compound.cid;
            if (compound.molecularFormula.length)
                detail ~= "  "~compound.molecularFormula;
            if (compound.molecularWeight > 0)
                detail ~= "  "~compound.molecularWeight.to!string;

            auto detailLabel = new Label(detail);
            detailLabel.addCssClass("suggestion-secondary");
            detailLabel.halign = Align.Start;

            rowBox.append(titleLabel);
            rowBox.append(detailLabel);
            row.setChild(rowBox);

            suggestionList.append(row);
        }

        if (suggestionPopover !is null)
            suggestionPopover.popup();
    }

    private void onSuggestionActivated(ListBoxRow row)
    {
        if (row is null)
            return;
        
        int index = row.getIndex();
        if (index < 0 || index >= lastSuggestions.length)
            return;
        
        selectedCompound = lastSuggestions[index];
        
        if (suggestionPopover !is null)
            suggestionPopover.hide();
        
        loadCompound3D(selectedCompound.cid);
    }
    
    private void loadCompound3D(string cid)
    {
        try
        {
            selectedConformer = PubChem.getConformer3D(cid);
            
            if (moleculeViewer !is null)
                moleculeViewer.setConformer(selectedConformer);
            
            updateSidebarInfo();
        }
        catch (Exception e)
        {
            // Handle error silently for now
        }
    }
    
    private void updateSidebarInfo()
    {
        if (compoundNameLabel !is null)
        {
            string name = selectedCompound.iupacName.length > 0 
                ? selectedCompound.iupacName : "Unknown";
            compoundNameLabel.label = name;
        }
        
        if (cidLabel !is null)
            cidLabel.label = selectedCompound.cid;
        
        if (formulaLabel !is null)
            formulaLabel.label = selectedCompound.molecularFormula;
        
        if (weightLabel !is null)
            weightLabel.label = selectedCompound.molecularWeight.to!string;
        
        if (smilesLabel !is null)
            smilesLabel.label = selectedCompound.canonicalSMILES;
        
        if (atomCountLabel !is null)
            atomCountLabel.label = selectedConformer.atoms.length.to!string;
        
        if (bondCountLabel !is null)
            bondCountLabel.label = selectedConformer.bonds.length.to!string;
        
        if (conformerIdLabel !is null)
            conformerIdLabel.label = selectedConformer.conformerId;
    }
}

class PubChemApp : gtk.application.Application
{
    this()
    {
        super("org.akashi.pubchem", ApplicationFlags.DefaultFlags);
        connectActivate(&onActivate);
    }

    private void applyCss()
    {
        auto provider = new CssProvider();
        provider.loadFromString(GLOBAL_CSS);
        StyleContext.addProviderForDisplay(Display.getDefault(), provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    private void onActivate()
    {
        applyCss();
        auto window = new PubChemWindow(this);
        window.present();
    }
}

void main(string[] args)
{
    auto app = new PubChemApp();
    app.run(args);
}