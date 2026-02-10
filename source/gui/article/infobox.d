module gui.article.infobox;

import std.conv : to;
import std.math : isNaN;
import std.stdio : writeln;
import std.uni : toUpper;

import gtk.box;
import gtk.event_controller_motion;
import gtk.gesture_click;
import gtk.label;
import gtk.button;
import gtk.overlay;
import gtk.types : Align, Orientation;
import gtk.widget : Widget;

import gui.conformer.view;
import wikia.pubchem;
import wikia.psychonaut : Dosage, DosageResult;

class Infobox : Overlay
{
private:
    Box details;

public:
    Box subject;
    Compound compound;
    MoleculeView moleculeView;

    this(MoleculeView moleculeView, Compound compound)
    {
        super();

        this.moleculeView = moleculeView;
        this.compound = compound;

        addCssClass("infobox");
        valign = Align.Start;
        halign = Align.End;
        widthRequest = 80;
        hexpand = false;

        subject = new Box(Orientation.Vertical, 0);
        subject.addCssClass("infobox-subject");
        subject.heightRequest = 2;

        moleculeView.setContentHeight(88);
        moleculeView.setContentWidth(88);
        setupMView();

        details = new Box(Orientation.Vertical, 0);
        details.addCssClass("infobox-details");
        details.widthRequest = 240;

        Box secChemical = new Box(Orientation.Vertical, 0);
        secChemical.hexpand = true;
        secChemical.halign = Align.Fill;
        buildChemicalSection(secChemical);
        details.append(secChemical);

        details.append(buildLoadingDots());

        Box root = new Box(Orientation.Vertical, 0);
        root.append(subject);
        root.append(details);

        setChild(root);
    }

    final void setupMView()
    {
        moleculeView.setBaseZoom(10.0);
        moleculeView.addCssClass("Y");
        moleculeView.hexpand = false;
        moleculeView.vexpand = false;
        moleculeView.disableMotionControl();

        subject.append(moleculeView);
    }

    void setDosage(DosageResult dosage)
    {
        writeln("[Infobox] setDosage called, ",
            dosage.dosages.length, " routes, source=",
            dosage.source ? dosage.source.name : "primary");

        removeLoadingDots();

        if (dosage.dosages.length == 0)
            return;

        Box sec = new Box(Orientation.Vertical, 0);
        sec.hexpand = true;
        sec.halign = Align.Fill;

        Box secHeader = new Box(Orientation.Horizontal, 4);
        secHeader.addCssClass("infobox-section-header");
        secHeader.halign = Align.Fill;

        Label headerLabel = new Label("DOSAGE");
        headerLabel.halign = Align.Start;
        headerLabel.hexpand = true;
        headerLabel.xalign = 0;
        secHeader.append(headerLabel);

        if (dosage.source !is null)
        {
            Label sourceLabel = new Label(dosage.source.name);
            sourceLabel.addCssClass("dosage-similar-warning");
            sourceLabel.halign = Align.End;
            sourceLabel.tooltipText = "Sourced from a similar compound";
            secHeader.append(sourceLabel);
        }
        sec.append(secHeader);

        foreach (d; dosage.dosages)
        {
            Box route = new Box(Orientation.Vertical, 0);
            route.hexpand = true;
            route.halign = Align.Fill;
            appendRow(route, "Bioavail.", d.bioavailability);
            appendRow(route, "Threshold", d.threshold);
            appendRow(route, "Light", d.light);
            appendRow(route, "Common", d.common);
            appendRow(route, "Strong", d.strong);
            appendRow(route, "Heavy", d.heavy);

            sec.append(buildCollapsibleSubheading(d.route, route));
            sec.append(route);
        }

        details.append(sec);
    }

private:
    void buildChemicalSection(Box sec)
    {
        Label secHeader = new Label("CHEMICAL");
        secHeader.addCssClass("infobox-section-header");
        secHeader.halign = Align.Fill;
        secHeader.xalign = 0;
        sec.append(secHeader);

        Box identifiers = new Box(Orientation.Vertical, 0);
        identifiers.hexpand = true;
        identifiers.halign = Align.Fill;
        appendRow(identifiers, "CID", compound.cid > 0
            ? compound.cid.to!string : "--");
        appendRow(identifiers, "Formula", compound.properties.formula.length > 0
            ? compound.properties.formula : "--");
        sec.append(
            buildCollapsibleSubheading("Identifiers", identifiers)
        );
        sec.append(identifiers);

        Box properties = new Box(Orientation.Vertical, 0);
        properties.hexpand = true;
        properties.halign = Align.Fill;
        appendRow(properties, "Weight", compound.properties.weight > 0
            ? compound.properties.weight.to!string : "--");
        appendRow(properties, "Mass", !compound.properties.mass.isNaN && compound.properties.mass > 0
            ? compound.properties.mass.to!string : "--");
        appendRow(properties, "Charge", compound.properties.formula.length > 0
            ? compound.properties.charge.to!string : "--");
        appendRow(properties, "TPSA", !compound.properties.tpsa.isNaN
            ? compound.properties.tpsa.to!string : "--");
        appendRow(properties, "XLogP", !compound.properties.xlogp.isNaN
            ? compound.properties.xlogp.to!string : "--");
        sec.append(
            buildCollapsibleSubheading("Properties", properties)
        );
        sec.append(properties);
    }

    void appendRow(Box parent, string label, string value)
    {
        if (value is null || value.length == 0)
            return;

        Box rowBox = new Box(Orientation.Horizontal, 0);
        rowBox.addCssClass("infobox-row");
        rowBox.hexpand = true;
        rowBox.halign = Align.Fill;
        rowBox.homogeneous = true;

        Box leftBox = new Box(Orientation.Horizontal, 0);
        leftBox.hexpand = true;
        leftBox.halign = Align.Fill;
        Label labelWidget = new Label(label);
        labelWidget.addCssClass("infobox-label");
        labelWidget.halign = Align.End;
        labelWidget.valign = Align.Start;
        leftBox.append(labelWidget);

        Box rightBox = new Box(Orientation.Horizontal, 0);
        rightBox.hexpand = true;
        rightBox.halign = Align.Fill;
        rightBox.marginStart = 8;
        Label valueWidget = new Label(value);
        valueWidget.addCssClass("infobox-value");
        valueWidget.halign = Align.Start;
        valueWidget.valign = Align.Start;
        valueWidget.wrap = true;
        valueWidget.maxWidthChars = 12;
        rightBox.append(valueWidget);

        rowBox.append(leftBox);
        rowBox.append(rightBox);
        parent.append(rowBox);
    }

    void removeLoadingDots()
    {
        Widget child = details.getLastChild();
        if (child !is null)
        {
            auto box = cast(Box)child;
            if (box !is null && box.hasCssClass("loading-dots"))
                details.remove(box);
        }
    }

    Box buildLoadingDots()
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

    Label buildCollapsibleSubheading(string title, Box contentBox)
    {
        Label header = new Label(title.toUpper);
        header.addCssClass("dosage-route-header");
        header.halign = Align.Start;
        header.xalign = 0;

        contentBox.visible = false;

        GestureClick click = new GestureClick();
        click.connectReleased((int nPress, double x, double y) {
            contentBox.visible = !contentBox.visible;
            header.halign = contentBox.visible ? Align.Fill : Align.Start;
        });
        header.addController(click);

        auto motion = new EventControllerMotion();
        motion.connectMotion((double x, double y) {
            if (!header.hasCssClass("collapsible-hover"))
                header.addCssClass("collapsible-hover");
        });
        motion.connectLeave(() {
            header.removeCssClass("collapsible-hover");
        });
        header.addController(motion);

        return header;
    }
}
