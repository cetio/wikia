module gui.article.infobox;

import std.conv : to;
import std.stdio : writeln;

import gtk.box;
import gtk.label;
import gtk.overlay;
import gtk.gesture_click;
import gtk.widget : Widget;
import gtk.types : Orientation, Align;

import gui.background : Background;
import wikia.pubchem;
import wikia.psychonaut : Dosage, DosageResult;
import gui.article.viewer;

class Infobox : Overlay
{
    private Label compoundNameLabel;
    private Label cidLabel;
    private Label formulaLabel;
    private Label weightLabel;
    private Label smilesLabel;
    private MoleculeViewer moleculeViewer;
    private Compound currentCompound;
    private Box chemicalSection;
    private Box dosageSection;
    private Box loadingDotsBox;
    private Box content;

    void delegate() onViewerClick;

    this()
    {
        super();
        addCssClass("infobox");
        valign = Align.Start;
        halign = Align.End;
        widthRequest = 80;
        hexpand = false;

        content = new Box(Orientation.Vertical, 0);
        content.addCssClass("infobox-content");

        compoundNameLabel = new Label("Select");
        compoundNameLabel.addCssClass("infobox-title");
        compoundNameLabel.wrap = true;
        compoundNameLabel.maxWidthChars = 10;
        compoundNameLabel.hexpand = true;
        content.append(compoundNameLabel);

        moleculeViewer = new MoleculeViewer(false);
        moleculeViewer.setContentWidth(88);
        moleculeViewer.setContentHeight(88);
        moleculeViewer.setBaseZoom(10.0);
        moleculeViewer.addCssClass("infobox-viewer-frame");

        GestureClick viewerClick = new GestureClick();
        viewerClick.connectReleased(&onViewerClicked);
        moleculeViewer.addController(viewerClick);

        content.append(moleculeViewer);

        chemicalSection = new Box(Orientation.Vertical, 0);
        cidLabel = new Label("--");
        formulaLabel = new Label("--");
        smilesLabel = new Label("--");
        weightLabel = new Label("--");
        buildChemicalSection();
        content.append(chemicalSection);

        loadingDotsBox = buildLoadingDots();
        loadingDotsBox.visible = false;
        content.append(loadingDotsBox);

        dosageSection = new Box(Orientation.Vertical, 0);
        dosageSection.visible = false;
        content.append(dosageSection);

        Background bg = new Background(
            6,      // maxSplotches
            120,    // msPerFrame
            10.0,   // spawnMargin
            25.0,   // minRadius
            65.0,   // maxRadius
            0.55,   // minAlpha
            0.85,   // maxAlpha
            "infobox-background", // cssClass
            true    // paintBase
        );
        bg.hexpand = true;
        bg.vexpand = true;
        setChild(bg);

        addOverlay(content);
        setMeasureOverlay(content, true);
        setClipOverlay(content, true);
    }

    @property MoleculeViewer getViewer()
    {
        return moleculeViewer;
    }

    void setCompound(Compound compound)
    {
        currentCompound = compound;
    }

    void setConformer(Conformer3D conformer)
    {
        moleculeViewer.setConformer(conformer);
    }

    void update(Compound compound, Conformer3D conformer, string name)
    {
        writeln("[Infobox] update called, name: ", name);
        if (conformer is null || compound is null)
        {
            writeln("[Infobox] Conformer or compound is null, returning");
            return;
        }

        compoundNameLabel.label = name;
        cidLabel.label = compound.cid > 0 ? compound.cid.to!string : "--";
        formulaLabel.label = compound.properties.formula.length > 0
            ? compound.properties.formula : "--";
        weightLabel.label = compound.properties.weight > 0
            ? compound.properties.weight.to!string : "--";
        smilesLabel.label = compound.smiles.length > 0
            ? compound.smiles : "--";
    }

    void showLoading()
    {
        clearBox(dosageSection);
        dosageSection.visible = false;
        loadingDotsBox.visible = true;
    }

    void hideLoading()
    {
        loadingDotsBox.visible = false;
    }

    void setDosage(DosageResult result)
    {
        writeln("[Infobox] setDosage called, ",
            result.dosages.length, " routes, fromSimilar=",
            result.fromSimilar);

        hideLoading();
        clearBox(dosageSection);

        if (result.dosages.length == 0)
        {
            dosageSection.visible = false;
            return;
        }

        Box hdrBox = new Box(Orientation.Horizontal, 4);
        hdrBox.addCssClass("infobox-section-header");
        hdrBox.halign = Align.Fill;

        Label hdr = new Label("Dosage");
        hdr.addCssClass("infobox-section-header-text");
        hdr.halign = Align.Start;
        hdr.hexpand = true;
        hdr.xalign = 0;
        hdrBox.append(hdr);

        if (result.fromSimilar && result.sourceName !is null)
        {
            Label sourceLabel = new Label(result.sourceName);
            sourceLabel.addCssClass("dosage-similar-warning");
            sourceLabel.halign = Align.End;
            sourceLabel.tooltipText = "Sourced from a similar compound";
            hdrBox.append(sourceLabel);
        }

        dosageSection.append(hdrBox);

        foreach (d; result.dosages)
        {
            Label routeLabel = new Label(d.route);
            routeLabel.addCssClass("dosage-route-header");
            routeLabel.halign = Align.Start;
            routeLabel.xalign = 0;
            dosageSection.append(routeLabel);

            appendRow(dosageSection, "Bioavail.", d.bioavailability);
            appendRow(dosageSection, "Threshold", d.threshold);
            appendRow(dosageSection, "Light", d.light);
            appendRow(dosageSection, "Common", d.common);
            appendRow(dosageSection, "Strong", d.strong);
            appendRow(dosageSection, "Heavy", d.heavy);
        }

        dosageSection.visible = true;
    }

    void reset()
    {
        compoundNameLabel.label = "Select";
        cidLabel.label = "--";
        formulaLabel.label = "--";
        weightLabel.label = "--";
        smilesLabel.label = "--";

        currentCompound = null;
        moleculeViewer.setConformer(null);
        hideLoading();
        clearBox(dosageSection);
        dosageSection.visible = false;
    }

    private void buildChemicalSection()
    {
        Label sectionHdr = new Label("Chemical");
        sectionHdr.addCssClass("infobox-section-header");
        sectionHdr.halign = Align.Fill;
        sectionHdr.xalign = 0;
        chemicalSection.append(sectionHdr);

        Label idHdr = new Label("Identifiers");
        idHdr.addCssClass("dosage-route-header");
        idHdr.halign = Align.Start;
        idHdr.xalign = 0;
        chemicalSection.append(idHdr);

        appendLabelRow(chemicalSection, "CID", cidLabel);
        appendLabelRow(chemicalSection, "Formula", formulaLabel);
        // appendLabelRow(chemicalSection, "SMILES", smilesLabel);

        Label propHdr = new Label("Properties");
        propHdr.addCssClass("dosage-route-header");
        propHdr.halign = Align.Start;
        propHdr.xalign = 0;
        chemicalSection.append(propHdr);

        appendLabelRow(chemicalSection, "Weight", weightLabel);
    }

    private void appendLabelRow(Box parent, string label, Label value)
    {
        Box rowBox = new Box(Orientation.Horizontal, 8);
        rowBox.addCssClass("infobox-row");

        Label labelWidget = new Label(label);
        labelWidget.addCssClass("infobox-label");
        labelWidget.halign = Align.Start;
        labelWidget.valign = Align.Start;

        value.addCssClass("infobox-value");
        value.halign = Align.End;
        value.hexpand = true;
        value.wrap = true;
        value.maxWidthChars = 8;

        rowBox.append(labelWidget);
        rowBox.append(value);
        parent.append(rowBox);
    }

    private void appendRow(Box parent, string label, string value)
    {
        if (value is null || value.length == 0)
            return;

        Box rowBox = new Box(Orientation.Horizontal, 8);
        rowBox.addCssClass("infobox-row");

        Label labelWidget = new Label(label);
        labelWidget.addCssClass("infobox-label");
        labelWidget.halign = Align.Start;
        labelWidget.valign = Align.Start;

        Label valueWidget = new Label(value);
        valueWidget.addCssClass("infobox-value");
        valueWidget.halign = Align.End;
        valueWidget.hexpand = true;
        valueWidget.wrap = true;
        valueWidget.maxWidthChars = 8;

        rowBox.append(labelWidget);
        rowBox.append(valueWidget);
        parent.append(rowBox);
    }

    private void clearBox(Box box)
    {
        Widget child = box.getFirstChild();
        while (child !is null)
        {
            Widget next = child.getNextSibling();
            box.remove(child);
            child = next;
        }
    }

    private Box buildLoadingDots()
    {
        Box dots = new Box(Orientation.Horizontal, 1);
        dots.addCssClass("loading-dots");
        dots.halign = Align.Center;
        dots.marginTop = 8;
        dots.marginBottom = 8;

        auto dot1 = new Label(".");
        dot1.addCssClass("dot");
        auto dot2 = new Label(".");
        dot2.addCssClass("dot");
        auto dot3 = new Label(".");
        dot3.addCssClass("dot");

        dots.append(dot1);
        dots.append(dot2);
        dots.append(dot3);
        return dots;
    }

    private void onViewerClicked(int nPress, double x, double y)
    {
        if (onViewerClick !is null)
            onViewerClick();
    }
}
