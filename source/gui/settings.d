module gui.settings;

import std.stdio : writeln;
import std.conv : to;
import std.algorithm : canFind;
import std.array : join;

import gtk.box;
import gtk.label;
import gtk.button;
import gtk.check_button;
import gtk.entry;
import gtk.stack;
import gtk.window;
import gtk.menu_button;
import gtk.popover;
import gtk.types : Orientation, Align;
import gtk.widget : Widget;

import infer.config;

class SettingsWindow : Window
{
private:
    Entry endpointEntry;
    Entry chatModelEntry;
    Entry embedModelEntry;
    Entry groupThreshEntry;
    Entry dedupeThreshEntry;
    CheckButton rabbitHolesCheck;
    CheckButton srcWikipediaCheck;
    CheckButton srcPsychonautCheck;
    MenuButton srcDropdown;
    Label srcDropdownLabel;
    Window parent;

    Button[] tabButtons;
    Stack contentStack;

    Box buildRow(string labelText, Widget field)
    {
        Box row = new Box(Orientation.Horizontal, 8);
        row.addCssClass("settings-row");
        row.hexpand = true;
        row.halign = Align.Fill;

        Label lbl = new Label(labelText);
        lbl.addCssClass("settings-label");
        lbl.halign = Align.Start;
        lbl.widthRequest = 140;
        row.append(lbl);

        field.hexpand = true;
        field.halign = Align.Fill;
        row.append(field);

        return row;
    }

    Box buildEntryRow(string labelText, Entry field)
    {
        field.addCssClass("settings-entry");
        return buildRow(labelText, field);
    }

    void selectTab(int index)
    {
        foreach (i, btn; tabButtons)
        {
            if (i == index)
                btn.addCssClass("settings-tab-active");
            else
                btn.removeCssClass("settings-tab-active");
        }

        final switch (index)
        {
            case 0: contentStack.visibleChildName = "inference"; break;
            case 1: contentStack.visibleChildName = "retrieval"; break;
            case 2: contentStack.visibleChildName = "style"; break;
        }
    }

    Box buildInferenceTab()
    {
        Box tab = new Box(Orientation.Vertical, 4);
        tab.addCssClass("settings-section");

        InferConfig cfg = config();

        endpointEntry = new Entry();
        endpointEntry.text = cfg.endpoint;
        tab.append(buildEntryRow("Endpoint", endpointEntry));

        chatModelEntry = new Entry();
        chatModelEntry.text = cfg.chatModel;
        tab.append(buildEntryRow("Chat Model", chatModelEntry));

        embedModelEntry = new Entry();
        embedModelEntry.text = cfg.embedModel;
        tab.append(buildEntryRow("Embed Model", embedModelEntry));

        groupThreshEntry = new Entry();
        groupThreshEntry.text = cfg.groupingThreshold.to!string;
        tab.append(buildEntryRow("Group Threshold", groupThreshEntry));

        dedupeThreshEntry = new Entry();
        dedupeThreshEntry.text = cfg.dedupeThreshold.to!string;
        tab.append(buildEntryRow("Dedup Threshold", dedupeThreshEntry));

        rabbitHolesCheck = new CheckButton();
        rabbitHolesCheck.label = "Auto resolve rabbit-holes";
        rabbitHolesCheck.active = cfg.autoResolveRabbitHoles;
        rabbitHolesCheck.marginTop = 8;
        tab.append(rabbitHolesCheck);

        return tab;
    }

    void updateDropdownLabel()
    {
        string[] active;
        if (srcWikipediaCheck.active) active ~= "Wikipedia";
        if (srcPsychonautCheck.active) active ~= "Psychonaut Wiki";
        srcDropdownLabel.label = active.length > 0 ? active.join(", ") : "None";
    }

    Box buildRetrievalTab()
    {
        Box tab = new Box(Orientation.Vertical, 4);
        tab.addCssClass("settings-section");

        InferConfig cfg = config();

        // Source dropdown
        srcDropdownLabel = new Label("");
        srcDropdownLabel.addCssClass("settings-dropdown-label");
        srcDropdownLabel.halign = Align.Start;
        srcDropdownLabel.hexpand = true;

        srcDropdown = new MenuButton();
        srcDropdown.addCssClass("settings-dropdown");
        srcDropdown.alwaysShowArrow = true;

        Popover pop = new Popover();
        pop.addCssClass("settings-dropdown-popover");
        Box popContent = new Box(Orientation.Vertical, 2);
        popContent.marginTop = 8;
        popContent.marginBottom = 8;
        popContent.marginStart = 8;
        popContent.marginEnd = 8;

        srcWikipediaCheck = new CheckButton();
        srcWikipediaCheck.label = "Wikipedia";
        srcWikipediaCheck.addCssClass("settings-dropdown-check");
        srcWikipediaCheck.active = cfg.enabledSources.canFind("wikipedia");
        srcWikipediaCheck.connectToggled(&updateDropdownLabel);
        popContent.append(srcWikipediaCheck);

        srcPsychonautCheck = new CheckButton();
        srcPsychonautCheck.label = "Psychonaut Wiki";
        srcPsychonautCheck.addCssClass("settings-dropdown-check");
        srcPsychonautCheck.active = cfg.enabledSources.canFind("psychonaut");
        srcPsychonautCheck.connectToggled(&updateDropdownLabel);
        popContent.append(srcPsychonautCheck);

        pop.setChild(popContent);
        srcDropdown.popover = pop;
        srcDropdown.child = srcDropdownLabel;

        updateDropdownLabel();
        tab.append(buildRow("Sources", srcDropdown));

        return tab;
    }

    static Box buildPlaceholderTab(string text)
    {
        Box tab = new Box(Orientation.Vertical, 0);
        tab.addCssClass("settings-section");
        tab.halign = Align.Center;
        tab.valign = Align.Center;
        tab.vexpand = true;

        Label placeholder = new Label(text);
        placeholder.addCssClass("settings-placeholder");
        tab.append(placeholder);
        return tab;
    }

public:
    this(Window parent)
    {
        super();
        this.parent = parent;
        if (parent !is null)
            setTransientFor(parent);
        setTitle("Settings");
        addCssClass("settings-window");

        Box root = new Box(Orientation.Vertical, 0);

        // Tab bar
        Box tabBar = new Box(Orientation.Horizontal, 0);
        tabBar.addCssClass("settings-tab-bar");
        tabBar.halign = Align.Fill;
        tabBar.hexpand = true;

        string[3] tabNames = ["Inference", "Retrieval", "Style"];
        foreach (i, name; tabNames)
        {
            Button tab = new Button();
            tab.label = name;
            tab.addCssClass("settings-tab");
            tab.connectClicked(((int idx) => () { selectTab(idx); })(cast(int)i));
            tabBar.append(tab);
            tabButtons ~= tab;
        }
        root.append(tabBar);

        // Content stack
        contentStack = new Stack();
        contentStack.hexpand = true;
        contentStack.vexpand = true;

        contentStack.addNamed(buildInferenceTab(), "inference");
        contentStack.addNamed(buildRetrievalTab(), "retrieval");
        contentStack.addNamed(buildPlaceholderTab("Style settings coming soon."), "style");
        contentStack.visibleChildName = "inference";

        root.append(contentStack);

        // Apply button
        Box footer = new Box(Orientation.Horizontal, 0);
        footer.halign = Align.End;
        footer.marginTop = 8;
        footer.marginEnd = 16;
        footer.marginBottom = 12;

        Button applyBtn = new Button();
        applyBtn.label = "Apply";
        applyBtn.addCssClass("settings-apply");
        applyBtn.connectClicked(&onApply);
        footer.append(applyBtn);
        root.append(footer);

        setChild(root);
        selectTab(0);
    }

    void setSizeFromParent()
    {
        int w = 1200;
        int h = 800;
        if (parent !is null)
        {
            int pw = parent.getAllocatedWidth();
            int ph = parent.getAllocatedHeight();
            if (pw > 0) w = pw;
            if (ph > 0) h = ph;
        }
        setDefaultSize(w / 3, h);
    }

    void open()
    {
        setSizeFromParent();
        present();
    }

    void onApply()
    {
        InferConfig cfg;
        cfg.endpoint = endpointEntry.text;
        cfg.chatModel = chatModelEntry.text;
        cfg.embedModel = embedModelEntry.text;
        cfg.autoResolveRabbitHoles = rabbitHolesCheck.active;

        try
            cfg.groupingThreshold = groupThreshEntry.text.to!float;
        catch (Exception e)
            cfg.groupingThreshold = 0.75;

        try
            cfg.dedupeThreshold = dedupeThreshEntry.text.to!float;
        catch (Exception e)
            cfg.dedupeThreshold = 0.92;

        string[] sources;
        if (srcWikipediaCheck.active) sources ~= "wikipedia";
        if (srcPsychonautCheck.active) sources ~= "psychonaut";
        cfg.enabledSources = sources;

        setConfig(cfg);
        writeln("[Settings] Config updated: endpoint=", cfg.endpoint,
            " chat=", cfg.chatModel, " embed=", cfg.embedModel,
            " rabbitHoles=", cfg.autoResolveRabbitHoles,
            " sources=", cfg.enabledSources);

        close();
    }
}
